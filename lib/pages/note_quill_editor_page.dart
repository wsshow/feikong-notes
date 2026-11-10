import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:quill_native_bridge/quill_native_bridge.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import 'package:fknotes_harness/fknotes_harness.dart';
import '../agent/agent_service.dart';
import '../agent/editor_agent_driver.dart';
import '../services/local_chat_note_context_builder.dart';
import '../widgets/agent_permission_sheet.dart';
export '../agent/editor_agent_driver.dart' show NoteInlineAssistantDriver;
import '../debug/app_diagnostics.dart';
import '../editor/note_assistant_editing.dart';
import '../editor/note_editor_controller.dart';
import '../editor/note_outline.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../models/local_llm.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../models/note_share.dart';
import '../models/note_semantic_projection.dart';
import '../services/file_storage_service.dart';
import '../services/incoming_share_service.dart';
import '../services/kokoro_tts_model_service.dart';
import '../services/language_model_service.dart';
import '../services/local_model_manager.dart';
import '../services/note_edit_guard.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../services/note_audio_playback_service.dart';
import '../services/note_audio_recording_service.dart';
import '../services/note_asset_import_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/note_database_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_repository.dart';
import '../services/note_reminder_service.dart';
import '../services/note_watermark_service.dart';
import '../services/ocr_service.dart';
import '../services/speech_transcription_service.dart';
import '../services/speech_model_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_attachment_title_sheet.dart';
import '../widgets/note_image_ocr_sheet.dart';
import '../widgets/note_audio_transcription_sheet.dart';
import '../widgets/note_inline_assistant_composer.dart';
import '../widgets/private_cloud_ai_notice.dart';
import '../widgets/note_external_image_drop.dart';
import '../widgets/note_quill_editor.dart';
import '../widgets/note_file_reference_picker.dart';
import '../widgets/note_outline_sheet.dart';
import '../widgets/note_read_aloud_bar.dart';
import '../widgets/note_recording_bar.dart';
import '../widgets/note_tags_editor_sheet.dart';
import '../widgets/note_reminder_sheet.dart';
import '../widgets/note_reminder_indicator.dart';
import '../widgets/note_video_player_page.dart';
import 'model_management_page.dart';
import 'note_share_composer_page.dart';
import '../widgets/app_icon.dart';

abstract interface class NoteEditorWriter {
  Future<Note> create(Note note);

  Future<Note> update(Note note);

  Future<void> deletePermanently(Note note);
}

final class RepositoryNoteEditorWriter implements NoteEditorWriter {
  RepositoryNoteEditorWriter(this.repository, {FileStorageService? storage})
    : storage = storage ?? FileStorageService.instance;

  final NoteRepository repository;
  final FileStorageService storage;

  @override
  Future<Note> create(Note note) => repository.create(note);

  @override
  Future<Note> update(Note note) => repository.update(note);

  @override
  Future<void> deletePermanently(Note note) async {
    await repository.deletePermanently(note.id);
    for (final asset in note.assets) {
      for (final key in [asset.storageKey, asset.previewStorageKey]) {
        try {
          await storage.deleteFile(key);
        } on FileSystemException {
          // The database deletion is authoritative. Orphan cleanup can retry
          // when a platform file handle is released.
        }
      }
    }
  }
}

typedef NoteEditorWriterLoader = Future<NoteEditorWriter> Function();

final class PickedNoteImage {
  const PickedNoteImage({required this.bytes, required this.originalName});

  final Uint8List bytes;
  final String originalName;
}

final class PickedNoteVideo {
  const PickedNoteVideo({
    required this.file,
    required this.originalName,
    this.durationMs,
  });

  final File file;
  final String originalName;
  final int? durationMs;
}

typedef NoteImagePicker = Future<PickedNoteImage?> Function(ImageSource source);
typedef NoteImageTextRecognizer = Future<OcrResult> Function(String imagePath);
typedef NoteVideoPicker = Future<PickedNoteVideo?> Function(ImageSource source);
typedef NoteImageAssetImporter =
    Future<NoteAsset> Function(Uint8List bytes, {required String originalName});
typedef NoteAudioAssetImporter =
    Future<NoteAsset> Function(
      File source, {
      required String originalName,
      required String displayName,
      required int durationMs,
    });
typedef NoteVideoAssetImporter =
    Future<NoteAsset> Function(
      File source, {
      required String originalName,
      int? durationMs,
    });
typedef NoteReadAloudAvailabilityChecker = Future<bool> Function();
typedef NoteLanguageModelAvailabilityChecker = Future<bool> Function();

/// The result returned when the note editor closes.
///
/// [completed] distinguishes the explicit toolbar action from system or
/// header back navigation so callers can return through intermediate routes.
final class NoteEditorRouteResult {
  const NoteEditorRouteResult({required this.note, required this.completed});

  final Note? note;
  final bool completed;
}

/// The clean-slate Delta editor route.
///
/// The page never converts its document to Markdown. Quill owns selection,
/// input, undo and formatting; persistence receives a validated snapshot only
/// after the debounce window or immediately before the route closes.
final class NoteQuillEditorPage extends StatefulWidget {
  const NoteQuillEditorPage({
    this.initialNote,
    this.writerLoader,
    this.reminders,
    this.importImage,
    this.importAudio,
    this.importVideo,
    this.pickImage,
    this.pickVideo,
    this.pickFileReferences,
    this.locateForWatermark,
    this.watermarkImage,
    this.resolveImage,
    this.resolveAssetPath,
    this.recognizeImageText,
    this.readAloud,
    this.readAloudAvailabilityChecker,
    this.inlineAssistantDriver,
    this.audioRecordingDriver,
    this.audioPlaybackDriver,
    this.transcriptionDriver,
    this.languageModelAvailabilityChecker,
    this.now,
    this.autosaveDelay = const Duration(milliseconds: 700),
    super.key,
  });

  final Note? initialNote;
  final NoteEditorWriterLoader? writerLoader;
  final NoteReminderDriver? reminders;
  final NoteImageAssetImporter? importImage;
  final NoteAudioAssetImporter? importAudio;
  final NoteVideoAssetImporter? importVideo;
  final NoteImagePicker? pickImage;
  final NoteVideoPicker? pickVideo;
  final Future<List<NoteFileReference>?> Function()? pickFileReferences;
  final NoteWatermarkLocationProvider? locateForWatermark;
  final NoteImageWatermarker? watermarkImage;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteImageTextRecognizer? recognizeImageText;
  final NoteReadAloudDriver? readAloud;
  final NoteReadAloudAvailabilityChecker? readAloudAvailabilityChecker;
  final NoteInlineAssistantDriver? inlineAssistantDriver;
  final NoteAudioRecordingDriver? audioRecordingDriver;
  final NoteAudioPlaybackDriver? audioPlaybackDriver;
  final NoteTranscriptionDriver? transcriptionDriver;
  final NoteLanguageModelAvailabilityChecker? languageModelAvailabilityChecker;
  final DateTime Function()? now;
  final Duration autosaveDelay;

  @override
  State<NoteQuillEditorPage> createState() => _NoteQuillEditorPageState();
}

final class _NoteQuillEditorPageState extends State<NoteQuillEditorPage>
    with WidgetsBindingObserver {
  late Note _note;
  bool _reminderPending = false;
  int _countedContentRevision = -1;
  int _bodyCharacterCount = 0;
  late final NoteEditorController _editor;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _editorFocusNode;
  late final NoteImageAssetImporter _importImage;
  late final NoteAudioAssetImporter _importAudio;
  late final NoteVideoAssetImporter _importVideo;
  late final NoteEditorWriterLoader _writerLoader;
  late final NoteImagePicker _pickImage;
  late final NoteVideoPicker _pickVideo;
  late final NoteWatermarkLocationProvider _locateForWatermark;
  late final NoteImageWatermarker _watermarkImage;
  late final NoteReadAloudDriver _readAloud;
  late final NoteInlineAssistantDriver _inlineAssistant;
  late final NoteAudioRecordingDriver _audioRecorder;
  late final NoteAudioPlaybackDriver _audioPlayback;
  late final NoteTranscriptionDriver _transcriptions;
  late final NoteTranscriptSink _transcriptSink;
  late final TextEditingController _inlineAssistantController;
  late final FocusNode _inlineAssistantFocusNode;
  late List<String> _tags;

  Timer? _autosaveTimer;
  Future<void> _saveTail = Future<void>.value();
  Future<void>? _imageImport;
  Future<void>? _audioImport;
  Future<void>? _videoImport;
  StreamSubscription<double>? _recordingAmplitudeSubscription;
  Timer? _recordingTimer;
  _EditorSaveState _saveState = _EditorSaveState.enabled;
  var _dirtyVersion = 0;
  var _savedVersion = 0;
  late String _observedTitle;
  var _importingImage = false;
  var _importingVideo = false;
  var _pickingFileReferences = false;
  var _actionPending = false;
  var _closing = false;
  var _outlineOpen = false;
  var _readAloudStarting = false;
  var _readAloudRequestId = 0;
  final _bodyEditorKey = GlobalKey<quill.QuillEditorState>();
  final _editorScrollController = ScrollController();
  var _allowPop = false;
  var _inlineAssistantOpen = false;
  var _inlinePrivateCloudNotice = false;
  var _inlineAssistantCheckingModel = false;
  var _inlineAssistantLoading = false;
  var _inlineAssistantGenerating = false;
  var _inlineAssistantRunId = 0;
  String _inlineAssistantOutput = '';
  String? _inlineAssistantError;
  NoteAssistantInsertionSession? _inlineAssistantSession;
  _InlineAssistantMetadataSession? _inlineAssistantMetadataSession;
  NoteInlineAssistantTarget _inlineAssistantTarget =
      NoteInlineAssistantTarget.cursor;
  _NoteRecordingState _recordingState = _NoteRecordingState.idle;
  Duration _recordingElapsed = Duration.zero;
  List<double> _recordingAmplitudes = List<double>.filled(18, .06);
  final Stopwatch _recordingClock = Stopwatch();
  var _recordingRunId = 0;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  bool get _recordingVisible => _recordingState != _NoteRecordingState.idle;
  bool get _readAloudVisible => _readAloudStarting || _readAloud.isActive;

  bool get _supportsCameraCapture =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.initialNote ?? Note.newDraft(now: _now);
    NoteEditGuard.instance.register(_note.id, this);
    _tags = [..._note.tags];
    _importImage =
        widget.importImage ?? NoteAssetImportService.instance.importImageBytes;
    _importAudio =
        widget.importAudio ?? NoteAssetImportService.instance.importAudioFile;
    _importVideo =
        widget.importVideo ?? NoteAssetImportService.instance.importVideoFile;
    _writerLoader =
        widget.writerLoader ??
        () async => RepositoryNoteEditorWriter(
          await NoteDatabaseService.instance.repository,
        );
    _pickImage = widget.pickImage ?? _pickImageFromDevice;
    _pickVideo = widget.pickVideo ?? _pickVideoFromDevice;
    _locateForWatermark =
        widget.locateForWatermark ??
        NoteWatermarkService.instance.currentLocation;
    _watermarkImage =
        widget.watermarkImage ??
        NoteWatermarkService.instance.applyLocationWatermark;
    _readAloud = widget.readAloud ?? NoteReadAloudService.instance;
    _inlineAssistant = widget.inlineAssistantDriver ?? HarnessEditorDriver();
    _audioRecorder =
        widget.audioRecordingDriver ?? LocalNoteAudioRecordingDriver();
    _audioPlayback =
        widget.audioPlaybackDriver ?? LocalNoteAudioPlaybackDriver();
    _transcriptions =
        widget.transcriptionDriver ?? SpeechTranscriptionService.instance;
    _transcriptSink = _saveAudioTranscript;
    _transcriptions.registerEditor(_note.id, _transcriptSink);
    _recordingAmplitudeSubscription = _audioRecorder.amplitudes.listen(
      _onRecordingAmplitude,
    );
    _inlineAssistantController = TextEditingController();
    _inlineAssistantFocusNode = FocusNode();
    _readAloud.addListener(_onReadAloudChanged);
    _observedTitle = _note.title;
    _titleController = TextEditingController(text: _note.title)
      ..addListener(_onTitleChanged);
    _titleFocusNode = FocusNode();
    _editorFocusNode = FocusNode();
    _editor = NoteEditorController(
      document: _note.document,
      assets: _note.assets,
      importImage: _importClipboardImage,
      discardImportedAsset: _deleteAssetFiles,
    )..addListener(_markDirty);
    _saveState = _note.revision == 0
        ? _EditorSaveState.enabled
        : _EditorSaveState.saved;
  }

  void _onTitleChanged() {
    final value = _titleController.text;
    if (value == _observedTitle) return;
    _observedTitle = value;
    _markDirty();
  }

  void _onReadAloudChanged() {
    if (mounted) {
      setState(() {
        if (_readAloud.isActive ||
            _readAloud.status == ReadAloudStatus.failed) {
          _readAloudStarting = false;
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_recordingState == _NoteRecordingState.recording) {
        unawaited(_pauseOrResumeRecording());
      }
      unawaited(_persistLatest());
      if (_note.isPrivate) {
        unawaited(_audioPlayback.stop());
        if (_readAloudVisible) unawaited(_stopReadAloud());
      }
    }
  }

  void _markDirty() {
    if (!mounted) return;
    _dirtyVersion++;
    if (_saveState != _EditorSaveState.saving) {
      _saveState = _EditorSaveState.pending;
    }
    _autosaveTimer?.cancel();
    if (!_closing) {
      _autosaveTimer = Timer(widget.autosaveDelay, () {
        unawaited(_persistLatest());
      });
    }
    setState(() {});
  }

  Future<bool> _persistLatest() {
    _autosaveTimer?.cancel();
    final operation = _saveTail.then((_) => _persistCurrent());
    _saveTail = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> _persistCurrent() async {
    if (_dirtyVersion == _savedVersion) return true;
    final targetVersion = _dirtyVersion;
    if (mounted) setState(() => _saveState = _EditorSaveState.saving);
    try {
      final candidate = _currentSnapshot(updatedAt: _now);
      final previous = _note;

      if (candidate.revision == 0 && candidate.isMeaningfullyEmpty) {
        _savedVersion = targetVersion;
      } else {
        final writer = await _writerLoader();
        _note = candidate.revision == 0
            ? await writer.create(candidate)
            : await writer.update(candidate);
        _savedVersion = targetVersion;
        await _discardRemovedAssetFiles(previous, _note);
      }
      if (mounted) {
        setState(() {
          _saveState = _dirtyVersion == _savedVersion
              ? _EditorSaveState.saved
              : _EditorSaveState.pending;
        });
      }
      return true;
    } catch (error, stackTrace) {
      AppDiagnostics.error(
        AppLogCategory.editor,
        'note_autosave_failed',
        data: {
          'revision': _note.revision,
          'dirtyVersion': _dirtyVersion,
          'savedVersion': _savedVersion,
          'assetCount': _editor.assets.length,
        },
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _saveState = _EditorSaveState.failed);
      return false;
    }
  }

  Future<void> _discardRemovedAssetFiles(Note previous, Note current) async {
    final retained = current.assetsById;
    for (final asset in previous.assets) {
      final replacement = retained[asset.id];
      if (replacement == null ||
          replacement.storageKey != asset.storageKey ||
          replacement.previewStorageKey != asset.previewStorageKey) {
        await _deleteAssetFilesBestEffort(asset);
      }
    }
  }

  Note _currentSnapshot({DateTime? updatedAt}) {
    final snapshot = _editor.snapshot();
    final coverId = _note.coverAttachmentId;
    final retainedCover =
        coverId != null && snapshot.assets.any((asset) => asset.id == coverId);
    return _note.copyWith(
      title: _titleController.text.trim(),
      document: snapshot.document,
      tags: _tags,
      assets: snapshot.assets,
      coverAttachmentId: retainedCover ? coverId : null,
      updatedAt: updatedAt ?? _note.updatedAt,
    );
  }

  Future<void> _showOutline() async {
    if (_outlineOpen || _closing) return;
    _outlineOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final entry = await AppOverlay.bottomSheet<NoteOutlineEntry>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: .68,
          child: NoteOutlineSheet(controller: _editor),
        ),
      );
      if (entry == null || !mounted || _closing) return;
      final controller = _editor.quillController;
      final offset = entry.offset.clamp(0, controller.document.length - 1);
      // Outline navigation moves the caret without reopening the keyboard.
      controller.skipRequestKeyboard = true;
      controller.updateSelection(
        TextSelection.collapsed(offset: offset),
        quill.ChangeSource.local,
      );
      controller.skipRequestKeyboard = false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_editorScrollController.hasClients) return;
      final render = _bodyEditorKey
          .currentState
          ?.editableTextKey
          .currentState
          ?.renderEditor;
      if (render == null) return;
      final caret = render.getLocalRectForCaret(controller.selection.extent);
      final target = RenderAbstractViewport.of(
        render,
      ).getOffsetToReveal(render, .12, rect: caret).offset;
      final position = _editorScrollController.position;
      await _editorScrollController.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _outlineOpen = false;
    }
  }

  Future<void> _startReadAloud() async {
    if (_readAloudVisible || _closing || _recordingVisible) return;
    final requestId = ++_readAloudRequestId;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _readAloudStarting = true);
    try {
      if (_readAloud.status == ReadAloudStatus.failed) await _readAloud.stop();
      if (!await _ensureReadAloudAvailable(requestId) ||
          !mounted ||
          _closing ||
          requestId != _readAloudRequestId) {
        return;
      }
      final text = NoteSemanticProjection.fromNote(
        _currentSnapshot(),
      ).speechText();
      if (text.trim().isEmpty) {
        AppFeedback.show(context, context.l10n.noteReadAloudFailed);
        return;
      }
      await _readAloud.speak(text);
    } catch (_) {
      if (!mounted || requestId != _readAloudRequestId) return;
      AppFeedback.error(
        context,
        _readAloud.errorMessage ?? context.l10n.noteReadAloudFailed,
      );
    } finally {
      if (mounted && requestId == _readAloudRequestId) {
        setState(() => _readAloudStarting = false);
      }
    }
  }

  Future<void> _stopReadAloud() async {
    // A canceled model check must not start speech after it eventually returns.
    _readAloudRequestId++;
    if (mounted) setState(() => _readAloudStarting = false);
    try {
      await _readAloud.stop();
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.noteReadAloudFailed);
    }
  }

  Future<bool> _ensureReadAloudAvailable(int requestId) async {
    final checker = widget.readAloudAvailabilityChecker;
    if (checker != null) return checker();
    final model = await KokoroTtsModelService.instance.inspect();
    if (!mounted || requestId != _readAloudRequestId) return false;
    if (model.installed) return true;
    if (!mounted) return false;
    final openModels = await AppOverlay.dialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.offlineReadAloudModelRequired),
        content: Text(context.l10n.readAloudModelDownloadDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.maybeLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.manageModels),
          ),
        ],
      ),
    );
    if (openModels == true && mounted && requestId == _readAloudRequestId) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const ModelManagementPage(
            focusModelId: KokoroTtsModelService.modelId,
          ),
        ),
      );
    }
    return false;
  }

  bool get _inlineAssistantBusy =>
      _inlineAssistantCheckingModel ||
      _inlineAssistantLoading ||
      _inlineAssistantGenerating;

  bool get _inlineAssistantSelectionAvailable {
    final selection = _editor.quillController.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _toggleInlineAssistant() {
    if (_inlineAssistantBusy) return;
    if (_inlineAssistantOpen) {
      _closeInlineAssistant();
      return;
    }
    final target = _inlineAssistantSelectionAvailable
        ? NoteInlineAssistantTarget.selection
        : NoteInlineAssistantTarget.cursor;
    // Defer ownership to the new field as it attaches, keeping the old input
    // connection alive until focus transfers in that same frame.
    _inlineAssistantFocusNode.requestFocus();
    setState(() {
      _inlineAssistantOpen = true;
      _inlineAssistantTarget = target;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
    });
    unawaited(_refreshInlinePrivacyNotice());
  }

  Future<void> _refreshInlinePrivacyNotice() async {
    if (!_note.isPrivate || _inlineAssistant is! HarnessEditorDriver) return;
    final driver = _inlineAssistant;
    try {
      final profile = await driver.service.profiles.get(
        await driver.service.profiles.selectedId(),
      );
      if (mounted) setState(() => _inlinePrivateCloudNotice = profile.isRemote);
    } catch (_) {
      // Submission reports configuration errors through the existing UI.
    }
  }

  void _changeInlineAssistantTarget(NoteInlineAssistantTarget target) {
    if (_inlineAssistantBusy ||
        (target == NoteInlineAssistantTarget.selection &&
            !_inlineAssistantSelectionAvailable)) {
      return;
    }
    _inlineAssistantFocusNode.requestFocus();
    setState(() => _inlineAssistantTarget = target);
  }

  void _closeInlineAssistant() {
    if (_inlineAssistantBusy) return;
    _inlineAssistantRunId++;
    _editorFocusNode.requestFocus();
    setState(() {
      _inlineAssistantOpen = false;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
    });
  }

  Future<void> _submitInlineAssistant(
    String rawInstruction, {
    NoteInlineAssistantTarget? target,
  }) async {
    final instruction = rawInstruction.trim();
    if (instruction.isEmpty || _inlineAssistantBusy) return;
    final requestedTarget =
        target ??
        (_inlineAssistantTarget == NoteInlineAssistantTarget.cursor &&
                _requestsNoteMetadata(instruction)
            ? NoteInlineAssistantTarget.metadata
            : _inlineAssistantTarget);
    _inlineAssistantController.text = instruction;
    FocusManager.instance.primaryFocus?.unfocus();
    final runId = ++_inlineAssistantRunId;
    final availabilityChecker = widget.languageModelAvailabilityChecker;
    final shouldCheckAvailability =
        availabilityChecker != null || widget.inlineAssistantDriver == null;
    setState(() {
      _inlineAssistantTarget = requestedTarget;
      _inlineAssistantCheckingModel = shouldCheckAvailability;
      _inlineAssistantLoading = !shouldCheckAvailability;
      _inlineAssistantGenerating = false;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
    });

    try {
      if (shouldCheckAvailability) {
        final available =
            await (availabilityChecker?.call() ??
                _ensureLanguageModelAvailable());
        if (!mounted || runId != _inlineAssistantRunId) return;
        if (!available) {
          setState(() => _inlineAssistantCheckingModel = false);
          return;
        }
        setState(() {
          _inlineAssistantCheckingModel = false;
          _inlineAssistantLoading = true;
        });
      }

      if (_inlineAssistant case final HarnessEditorDriver driver) {
        final profile = await driver.service.profiles.get(
          await driver.service.profiles.selectedId(),
        );
        if (!mounted || runId != _inlineAssistantRunId) return;
        final note = _currentSnapshot();
        setState(
          () => _inlinePrivateCloudNotice = note.isPrivate && profile.isRemote,
        );
        final grant = await prepareAgentTask(
          context,
          service: driver.service,
          profile: profile,
          skillId: 'editor',
          editor: true,
          notes: [
            LocalChatNoteContextBuilder.fromNote(
              note,
              untitledLabel: context.l10n.untitled,
            ),
          ],
        );
        if (!mounted || runId != _inlineAssistantRunId) return;
        if (grant == null) {
          setState(() => _inlineAssistantLoading = false);
          return;
        }
        driver.configure(
          profile: profile,
          scope: grant.scope,
          limits: grant.limits,
          note: note,
          instruction: instruction,
        );
      }
      await _inlineAssistant.load();
      if (!mounted || runId != _inlineAssistantRunId) return;

      final anchor = _editor.captureAssistantAnchor();
      final editTarget =
          requestedTarget == NoteInlineAssistantTarget.selection &&
              !anchor.hasSelection
          ? NoteInlineAssistantTarget.currentLine
          : requestedTarget;
      if (_inlineAssistantTarget != editTarget) {
        setState(() => _inlineAssistantTarget = editTarget);
      }
      final metadataTarget = editTarget == NoteInlineAssistantTarget.metadata;
      final session = metadataTarget
          ? null
          : _editor.beginAssistantInsertion(anchor: anchor, target: editTarget);
      _inlineAssistantSession = session;
      final languageCode = Localizations.localeOf(context).languageCode;
      final projection = NoteSemanticProjection.fromNote(_currentSnapshot());
      final scope = switch (editTarget) {
        NoteInlineAssistantTarget.selection => NoteAssistantScope.selection,
        NoteInlineAssistantTarget.currentLine =>
          NoteAssistantScope.currentBlock,
        NoteInlineAssistantTarget.cursor ||
        NoteInlineAssistantTarget.document ||
        NoteInlineAssistantTarget.metadata => NoteAssistantScope.fullNote,
      };
      final source = switch (editTarget) {
        NoteInlineAssistantTarget.selection => anchor.selectedText,
        NoteInlineAssistantTarget.currentLine => anchor.currentLineText,
        NoteInlineAssistantTarget.cursor ||
        NoteInlineAssistantTarget.document ||
        NoteInlineAssistantTarget.metadata => projection.assistantSource(
          languageCode: languageCode,
        ),
      };
      final request = NoteAssistantPromptBuilder.build(
        action: NoteAssistantAction.custom(instruction),
        maxSourceCharacters:
            _inlineAssistant is HarnessEditorDriver &&
                _inlineAssistant.profile.isRemote
            ? (_inlineAssistant.profile.capabilities.contextTokens -
                      _inlineAssistant.limits.maxOutputTokens -
                      3000)
                  .clamp(
                    256,
                    _inlineAssistant.profile.capabilities.contextTokens,
                  )
            : NoteAssistantPromptBuilder.maxInputCharacters,
        onDevice:
            _inlineAssistant is! HarnessEditorDriver ||
            !(_inlineAssistant).profile.isRemote,
        title: _titleController.text.trim(),
        content: source,
        tags: _tags,
        scope: scope,
        languageCode: languageCode,
        outputMode: switch (editTarget) {
          NoteInlineAssistantTarget.cursor =>
            NoteAssistantOutputMode.insertAtCursor,
          NoteInlineAssistantTarget.metadata =>
            NoteAssistantOutputMode.updateMetadata,
          _ => NoteAssistantOutputMode.replaceTarget,
        },
        cursorContext: editTarget == NoteInlineAssistantTarget.cursor
            ? anchor.currentLineText
            : '',
      );
      setState(() {
        _inlineAssistantLoading = false;
        _inlineAssistantGenerating = true;
      });

      final rawOutput = StringBuffer();
      var appliedOutput = '';
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final event in _inlineAssistant.generate(request)) {
        if (!mounted || runId != _inlineAssistantRunId) return;
        switch (event) {
          case LocalLlmTextDelta():
            if (event.reasoning) continue;
            if (event.replace) rawOutput.clear();
            rawOutput.write(event.text);
            final now = DateTime.now();
            if (now.difference(lastPaint) < const Duration(milliseconds: 70)) {
              continue;
            }
            final visible = LocalLlmOutputFilter.visibleText(
              rawOutput.toString(),
            );
            if (metadataTarget) continue;
            if (visible.trim().isEmpty || visible == appliedOutput) continue;
            if (!_editor.updateAssistantInsertion(session!, visible)) {
              throw StateError(context.l10n.noteChangedRetryAssistant);
            }
            appliedOutput = visible;
            lastPaint = now;
            setState(() => _inlineAssistantOutput = visible);
          case LocalLlmGenerationCompleted():
            final visible = LocalLlmOutputFilter.visibleText(
              rawOutput.toString(),
            ).trim();
            if (metadataTarget) {
              if (visible.isEmpty) {
                throw StateError(context.l10n.assistantNoOutput);
              }
              final update = NoteAssistantMetadataUpdate.tryParse(visible);
              if (update == null) {
                throw StateError(context.l10n.inlineAssistantInvalidMetadata);
              }
              if (!_applyInlineAssistantMetadata(update)) {
                throw StateError(context.l10n.inlineAssistantNoMetadataChanges);
              }
            } else if (visible.isNotEmpty && visible != appliedOutput) {
              if (!_editor.updateAssistantInsertion(session!, visible)) {
                throw StateError(context.l10n.noteChangedRetryAssistant);
              }
              appliedOutput = visible;
            }
            if (session != null) _editor.finishAssistantInsertion(session);
            setState(() {
              _inlineAssistantOutput = visible;
              _inlineAssistantLoading = false;
              _inlineAssistantGenerating = false;
              if (visible.isEmpty) {
                _inlineAssistantError = context.l10n.assistantNoOutput;
              }
            });
        }
      }
      if (mounted &&
          runId == _inlineAssistantRunId &&
          _inlineAssistantGenerating) {
        if (session != null) _editor.finishAssistantInsertion(session);
        setState(() {
          _inlineAssistantLoading = false;
          _inlineAssistantGenerating = false;
          _inlineAssistantError = context.l10n.generationIncomplete;
        });
      }
    } catch (error) {
      if (!mounted || runId != _inlineAssistantRunId) return;
      final session = _inlineAssistantSession;
      if (session != null && _inlineAssistantOutput.trim().isEmpty) {
        _editor.revertAssistantInsertion(session);
        _inlineAssistantSession = null;
      } else if (session != null) {
        _editor.finishAssistantInsertion(session);
      }
      setState(() {
        _inlineAssistantCheckingModel = false;
        _inlineAssistantLoading = false;
        _inlineAssistantGenerating = false;
        _inlineAssistantError = error is HarnessException
            ? context.l10n.agentError(error.code)
            : error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  bool _applyInlineAssistantMetadata(NoteAssistantMetadataUpdate update) {
    final beforeTitle = _titleController.text;
    final beforeTags = List<String>.of(_tags);
    final nextTitle = update.title ?? beforeTitle;
    final nextTags = update.tags ?? beforeTags;
    if (nextTitle == beforeTitle && _sameTags(nextTags, beforeTags)) {
      return false;
    }
    _inlineAssistantMetadataSession = _InlineAssistantMetadataSession(
      beforeTitle: beforeTitle,
      beforeTags: beforeTags,
      appliedTitle: nextTitle,
      appliedTags: nextTags,
    );
    if (nextTitle != beforeTitle) {
      _titleController.value = TextEditingValue(
        text: nextTitle,
        selection: TextSelection.collapsed(offset: nextTitle.length),
      );
    }
    if (!_sameTags(nextTags, beforeTags)) {
      _tags = List<String>.of(nextTags);
      _markDirty();
    }
    return true;
  }

  Future<void> _stopInlineAssistant() async {
    _inlineAssistantRunId++;
    try {
      await _inlineAssistant.cancel();
    } catch (_) {
      // The generation stream may already have reached its terminal event.
    }
    if (!mounted) return;
    final session = _inlineAssistantSession;
    if (session != null) _editor.finishAssistantInsertion(session);
    setState(() {
      _inlineAssistantCheckingModel = false;
      _inlineAssistantLoading = false;
      _inlineAssistantGenerating = false;
      if (_inlineAssistantOutput.trim().isEmpty) {
        _inlineAssistantSession = null;
        _inlineAssistantOpen = false;
      }
    });
  }

  void _undoInlineAssistant() {
    final session = _inlineAssistantSession;
    if (session != null && !_editor.revertAssistantInsertion(session)) {
      AppFeedback.show(context, context.l10n.noteChangedRetryAssistant);
      return;
    }
    final metadataSession = _inlineAssistantMetadataSession;
    if (metadataSession != null &&
        (_titleController.text != metadataSession.appliedTitle ||
            !_sameTags(_tags, metadataSession.appliedTags))) {
      AppFeedback.show(context, context.l10n.noteChangedRetryAssistant);
      return;
    }
    if (metadataSession != null) {
      if (_titleController.text != metadataSession.beforeTitle) {
        _titleController.value = TextEditingValue(
          text: metadataSession.beforeTitle,
          selection: TextSelection.collapsed(
            offset: metadataSession.beforeTitle.length,
          ),
        );
      }
      if (!_sameTags(_tags, metadataSession.beforeTags)) {
        _tags = List<String>.of(metadataSession.beforeTags);
        _markDirty();
      }
    }
    _inlineAssistantFocusNode.requestFocus();
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
    });
  }

  void _continueInlineAssistant() {
    _inlineAssistantFocusNode.requestFocus();
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
      _inlineAssistantController.clear();
      _inlineAssistantTarget = NoteInlineAssistantTarget.cursor;
    });
  }

  void _retryInlineAssistant() {
    final instruction = _inlineAssistantController.text;
    final session = _inlineAssistantSession;
    if (session != null) _editor.revertAssistantInsertion(session);
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantMetadataSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
    });
    unawaited(_submitInlineAssistant(instruction));
  }

  Future<bool> _ensureLanguageModelAvailable() async {
    final agent = AgentService.instance;
    if ((await agent.profiles.get(
      await agent.profiles.selectedId(),
    )).isRemote) {
      return true;
    }
    final models = LanguageModelService.instance;
    final selectedId = await models.selectedModelId();
    final installed = await models.inspect(selectedId);
    if (installed.installed) return true;
    if (!mounted) return false;
    final downloadSize =
        '${(models.downloadSizeBytes(selectedId) / 1073741824).toStringAsFixed(1)} GB';
    final openModels = await AppOverlay.dialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.localLanguageModelRequired),
        content: Text(
          context.l10n.localLanguageModelDownloadDescription(
            localizedModelName(
              context.l10n,
              LocalModelManager.instance.modelOf(selectedId),
            ),
            downloadSize,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.maybeLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.manageModels),
          ),
        ],
      ),
    );
    if (openModels != true || !mounted) return false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelManagementPage(focusModelId: selectedId),
      ),
    );
    if (!mounted) return false;
    final currentId = await models.selectedModelId();
    return (await models.inspect(currentId)).installed;
  }

  Future<void> _openShareComposer() async {
    await _imageImport;
    if (!mounted) return;
    final draft = NoteShareDraft.fromNote(_currentSnapshot());
    if (!draft.hasContent) {
      AppFeedback.show(context, context.l10n.noteHasNoShareableContent);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => NoteShareComposerPage(draft: draft)),
    );
  }

  Future<void> _editTags() async {
    final tags = await AppOverlay.inputSheet<List<String>>(
      context: context,
      builder: (_) => NoteTagsEditorSheet(initialTags: _tags),
    );
    if (tags == null || !mounted || _sameTags(tags, _tags)) return;
    _tags = tags;
    _markDirty();
  }

  Future<bool> _updatePersistedMetadata(
    Note Function(Note note) change, {
    bool allowDraft = false,
  }) async {
    if (_actionPending) return false;
    _actionPending = true;
    if (mounted) setState(() {});
    try {
      await _imageImport;
      if (!await _persistLatest() || (_note.revision == 0 && !allowDraft)) {
        if (mounted && _saveState == _EditorSaveState.failed) {
          AppFeedback.error(context, context.l10n.saveFailedStorage);
        }
        return false;
      }
      // Metadata and autosaves share one queue, so a slow native reminder
      // update cannot race a newer document snapshot or erase its deadline.
      final operation = _saveTail.then((_) async {
        final writer = await _writerLoader();
        final candidate = change(_note).copyWith(updatedAt: _now);
        _note = _note.revision == 0
            ? await writer.create(candidate)
            : await writer.update(candidate);
      });
      _saveTail = operation.catchError((Object _) {});
      await operation;
      if (mounted) {
        setState(
          () => _saveState = _dirtyVersion == _savedVersion
              ? _EditorSaveState.saved
              : _EditorSaveState.pending,
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _saveState = _EditorSaveState.failed);
        AppFeedback.error(context, context.l10n.saveFailedStorage);
      }
      return false;
    } finally {
      _actionPending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _togglePinned() async {
    await _updatePersistedMetadata(
      (note) => note.copyWith(isPinned: !note.isPinned),
    );
  }

  Future<void> _editReminder() async {
    if (_reminderPending || _actionPending) return;
    _reminderPending = true;
    _titleFocusNode.unfocus();
    _editorFocusNode.unfocus();
    try {
      final selected = await AppOverlay.bottomSheet<NoteReminderSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            NoteReminderSheet(initialTime: _note.reminderAt, now: widget.now),
      );
      if (selected == null || !mounted) return;
      final reminders = widget.reminders ?? NoteReminderService.instance;
      if (selected.at != null) {
        final access = await reminders.requestAccess();
        if (!mounted) return;
        if (access != NoteReminderAccess.ready) {
          AppFeedback.error(context, switch (access) {
            NoteReminderAccess.notificationsDisabled =>
              context.l10n.reminderNotificationsDisabled,
            NoteReminderAccess.exactAlarmDisabled =>
              context.l10n.reminderExactDisabled,
            _ => context.l10n.reminderUnsupported,
          });
          return;
        }
        // Permission settings may have stayed open until after the chosen time.
        if (!selected.at!.isAfter(_now)) {
          AppFeedback.error(context, context.l10n.reminderChooseFuture);
          return;
        }
      }
      final previous = _note.reminderAt;
      if (!await _updatePersistedMetadata(
        (note) => note.copyWith(reminderAt: selected.at),
        allowDraft: true,
      )) {
        return;
      }
      if (selected.at != null) {
        var scheduled = false;
        try {
          scheduled = await reminders.schedule(_note.id);
        } catch (_) {
          /* Roll back below. */
        }
        if (!scheduled) {
          await _updatePersistedMetadata(
            (note) => note.copyWith(reminderAt: previous),
          );
          if (mounted) {
            AppFeedback.error(context, context.l10n.reminderScheduleFailed);
          }
          return;
        }
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.reminderScheduleFailed);
      }
    } finally {
      _reminderPending = false;
    }
  }

  Future<void> _deleteNote() async {
    if (_note.revision == 0) {
      final confirmed = await _confirmDestructiveAction(
        title: context.l10n.discardNoteQuestion,
        description: context.l10n.discardNoteDescription,
        actionLabel: context.l10n.discardNote,
      );
      if (!confirmed || !mounted) return;
      setState(() => _actionPending = true);
      await _imageImport;
      await _discardUnsavedAssets();
      if (mounted) await _leaveEditor(null);
      return;
    }

    final confirmed = await _confirmDestructiveAction(
      title: context.l10n.deletePermanentlyQuestion,
      description: context.l10n.deletePermanentlyDescription,
      actionLabel: context.l10n.deletePermanently,
    );
    if (!confirmed || !mounted) return;
    setState(() => _actionPending = true);
    try {
      await _imageImport;
      if (!await _persistLatest()) return;
      final writer = await _writerLoader();
      await writer.deletePermanently(_note);
      if (mounted) await _leaveEditor(null);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.toolActionFailed(context.l10n.deletePermanently),
        );
      }
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String description,
    required String actionLabel,
  }) async =>
      await AppOverlay.bottomSheet<bool>(
        context: context,
        useSafeArea: true,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(color: context.appColors.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.appColors.danger,
                      ),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> _leaveEditor(Note? result) async {
    if (!mounted) return;
    _autosaveTimer?.cancel();
    setState(() {
      _closing = true;
      _allowPop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  void _handleMenuAction(_QuillEditorMenuAction action) {
    switch (action) {
      case _QuillEditorMenuAction.readAloud:
        unawaited(_startReadAloud());
      case _QuillEditorMenuAction.share:
        unawaited(_openShareComposer());
      case _QuillEditorMenuAction.tags:
        unawaited(_editTags());
      case _QuillEditorMenuAction.reminder:
        unawaited(_editReminder());
      case _QuillEditorMenuAction.pin:
        unawaited(_togglePinned());
      case _QuillEditorMenuAction.save:
        unawaited(_persistLatest());
      case _QuillEditorMenuAction.delete:
        unawaited(_deleteNote());
    }
  }

  Future<NoteAsset?> _importClipboardImage(Uint8List bytes) async {
    try {
      final asset = await _importImage(bytes, originalName: context.l10n.image);
      _editorFocusNode.unfocus();
      return asset;
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.image),
        );
      }
      return null;
    }
  }

  Future<void> _showImageSourceSheet() async {
    if (_importingImage || _importingVideo) return;
    final source = await AppOverlay.bottomSheet<_ImageImportSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.addToNote,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ImageSourceAction(
                      key: const Key('quill-pick-gallery-image'),
                      icon: Icons.photo_library_outlined,
                      label: context.l10n.image,
                      onTap: () => Navigator.pop(
                        sheetContext,
                        _ImageImportSource.gallery,
                      ),
                    ),
                  ),
                  if (_supportsCameraCapture) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImageSourceAction(
                        key: const Key('quill-take-photo'),
                        icon: Icons.photo_camera_outlined,
                        label: context.l10n.camera,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          _ImageImportSource.camera,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_supportsCameraCapture) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ImageSourceAction(
                        key: const Key('quill-take-watermarked-photo'),
                        icon: Icons.add_location_alt_outlined,
                        label: context.l10n.watermarkCamera,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          _ImageImportSource.watermarkCamera,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    NoteWatermarkLocation? watermarkLocation;
    if (source == _ImageImportSource.watermarkCamera) {
      watermarkLocation = await _chooseWatermarkLocation();
      if (watermarkLocation == null || !mounted) return;
    }
    final operation = _pickAndInsertImage(
      source,
      watermarkLocation: watermarkLocation,
    );
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<NoteWatermarkLocation?> _chooseWatermarkLocation() =>
      AppOverlay.bottomSheet<NoteWatermarkLocation>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => _WatermarkLocationSheet(
          locate: _locateForWatermark,
          now: widget.now ?? DateTime.now,
        ),
      );

  Future<void> _pickAndInsertImage(
    _ImageImportSource source, {
    NoteWatermarkLocation? watermarkLocation,
  }) async {
    setState(() => _importingImage = true);
    NoteAsset? imported;
    try {
      final selected = await _pickImage(source.imageSource);
      if (selected == null || !mounted) return;
      final bytes = watermarkLocation == null
          ? selected.bytes
          : await _watermarkImage(selected.bytes, watermarkLocation);
      imported = await _importImage(
        bytes,
        originalName: watermarkLocation == null
            ? selected.originalName
            : 'watermark-'
                  '${watermarkLocation.capturedAt.microsecondsSinceEpoch}.jpg',
      );
      if (!mounted) {
        await _deleteAssetFiles(imported);
        return;
      }
      _editor.insertAsset(imported);
      _editorFocusNode.unfocus();
    } catch (_) {
      if (imported != null) await _deleteAssetFiles(imported);
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.image),
        );
      }
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  Future<void> _showVideoSourceSheet() async {
    if (_importingImage || _importingVideo) return;
    final source = await AppOverlay.bottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.addToNote,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ImageSourceAction(
                      key: const Key('quill-pick-gallery-video'),
                      icon: Icons.video_library_outlined,
                      label: context.l10n.chooseVideo,
                      onTap: () =>
                          Navigator.pop(sheetContext, ImageSource.gallery),
                    ),
                  ),
                  if (_supportsCameraCapture) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImageSourceAction(
                        key: const Key('quill-record-video'),
                        icon: Icons.videocam_outlined,
                        label: context.l10n.recordVideo,
                        onTap: () =>
                            Navigator.pop(sheetContext, ImageSource.camera),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final operation = _pickAndInsertVideo(source);
    _videoImport = operation;
    await operation;
    if (identical(_videoImport, operation)) _videoImport = null;
  }

  Future<void> _pickAndInsertVideo(ImageSource source) async {
    setState(() => _importingVideo = true);
    NoteAsset? imported;
    try {
      final selected = await _pickVideo(source);
      if (selected == null || !mounted) return;
      imported = await _importVideo(
        selected.file,
        originalName: selected.originalName,
        durationMs: selected.durationMs,
      );
      if (!mounted) {
        await _deleteAssetFiles(imported);
        return;
      }
      _editor.insertAsset(imported);
      _editorFocusNode.unfocus();
    } catch (_) {
      if (imported != null) await _deleteAssetFiles(imported);
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.video),
        );
      }
    } finally {
      if (mounted) setState(() => _importingVideo = false);
    }
  }

  Future<void> _handleDroppedImages(
    NoteDroppedImageBatch batch,
    int documentOffset,
  ) async {
    final operation = (_imageImport ?? Future<void>.value()).then(
      (_) => _importDroppedImages(batch, documentOffset),
    );
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<void> _importDroppedImages(
    NoteDroppedImageBatch batch,
    int documentOffset,
  ) async {
    if (batch.images.isEmpty) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.onlyImagesCanBeDropped);
      }
      return;
    }
    setState(() => _importingImage = true);
    var insertionOffset = documentOffset;
    var importFailures = 0;
    try {
      for (final image in batch.images) {
        NoteAsset? imported;
        try {
          imported = await _importImage(
            image.bytes,
            originalName: image.originalName,
          );
          if (!mounted) {
            await _deleteAssetFilesBestEffort(imported);
            return;
          }
          _editor.insertAssetAt(imported, insertionOffset);
          insertionOffset += 2;
          imported = null;
        } catch (_) {
          importFailures++;
          if (imported != null) await _deleteAssetFilesBestEffort(imported);
        }
      }
      if (!mounted) return;
      _editorFocusNode.unfocus();
      if (batch.rejectedCount > 0) {
        AppFeedback.error(context, context.l10n.droppedImagesRejected);
      } else if (importFailures > 0) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.image),
        );
      }
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  static Future<PickedNoteImage?> _pickImageFromDevice(
    ImageSource source,
  ) async {
    final selected = await ImagePicker().pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (selected == null) return null;
    final byteLength = await selected.length();
    if (byteLength <= 0 || byteLength > 20 * 1024 * 1024) {
      throw const FormatException('图片文件为空或超过 20 MB');
    }
    return PickedNoteImage(
      bytes: await selected.readAsBytes(),
      originalName: selected.name,
    );
  }

  static Future<PickedNoteVideo?> _pickVideoFromDevice(
    ImageSource source,
  ) async {
    final selected = await ImagePicker().pickVideo(source: source);
    if (selected == null) return null;
    final byteLength = await selected.length();
    if (byteLength <= 0 || byteLength > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('视频文件为空或超过 2 GB');
    }
    final file = File(selected.path);
    int? durationMs;
    final metadataReader = VideoPlayerController.file(file);
    try {
      await metadataReader.initialize();
      durationMs = metadataReader.value.duration.inMilliseconds;
    } catch (_) {
      // Duration is optional. A platform decoder can still play the managed
      // file later even when metadata probing is unavailable during import.
    } finally {
      await metadataReader.dispose();
    }
    return PickedNoteVideo(
      file: file,
      originalName: selected.name,
      durationMs: durationMs,
    );
  }

  Future<void> _deleteAssetFiles(NoteAsset asset) async {
    await FileStorageService.instance.deleteFile(asset.storageKey);
    await FileStorageService.instance.deleteFile(asset.previewStorageKey);
  }

  Future<void> _insertFileReferences() async {
    if (_pickingFileReferences || _closing) return;
    _pickingFileReferences = true;
    // An unfocused editor may still hold its initial or a previous caret.
    // Only an active body selection expresses an intentional insertion point.
    final selection = _editorFocusNode.hasFocus
        ? _editor.quillController.selection
        : null;
    _editorFocusNode.unfocus();
    try {
      final references =
          await (widget.pickFileReferences?.call() ??
              showNoteFileReferencePicker(context));
      if (!mounted || _closing || references == null || references.isEmpty) {
        return;
      }
      _editor.quillController.updateSelection(
        selection ??
            TextSelection.collapsed(
              offset: _editor.quillController.document.length - 1,
            ),
        quill.ChangeSource.local,
      );
      _editor.insertFileReferences(references);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.fmErrorOperation);
    } finally {
      _pickingFileReferences = false;
    }
  }

  void _openAsset(NoteAsset asset) {
    if (asset.kind == NoteAssetKind.file && mounted) {
      unawaited(
        IncomingShareService.openAttachment(asset).catchError((Object _) {
          if (mounted) {
            AppFeedback.error(context, context.l10n.incomingShareOpenFailed);
          }
        }),
      );
      return;
    }
    if (asset.kind != NoteAssetKind.video || !mounted) return;
    final filePath = (widget.resolveAssetPath ?? _resolveManagedAssetPath)(
      asset,
    );
    if (filePath == null || filePath.isEmpty) {
      AppFeedback.error(context, context.l10n.videoPlaybackFailed);
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NoteVideoPlayerPage(
            filePath: filePath,
            title: asset.displayTitle,
          ),
        ),
      ),
    );
  }

  NoteAsset? _currentAudioAsset(NoteAttachmentId id, String storageKey) {
    if (!mounted) return null;
    for (final asset in _editor.snapshot().assets) {
      if (asset.id == id &&
          asset.storageKey == storageKey &&
          asset.kind == NoteAssetKind.audio) {
        return asset;
      }
    }
    return null;
  }

  Future<void> _showAudioTranscription(NoteAsset source) async {
    if (!mounted || _closing) return;
    final current = _currentAudioAsset(source.id, source.storageKey);
    if (current == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await AppOverlay.bottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder: (_) => NoteAudioTranscriptionSheet(
        driver: _transcriptions,
        noteId: _note.id,
        asset: current,
        onStart: () async {
          final asset = _currentAudioAsset(current.id, current.storageKey);
          if (asset == null || _closing) throw StateError('音频已被移除');
          // A background job must never target an unpersisted draft or file.
          if (_note.revision == 0) _markDirty();
          if (!await _persistLatest()) throw StateError('笔记尚未保存');
          if (!mounted || _closing) return;
          if (_currentAudioAsset(current.id, current.storageKey) == null) {
            throw StateError('音频已被移除');
          }
          await _transcriptions.start(
            noteId: _note.id,
            attachment: asset,
            privateSpace: _note.isPrivate,
          );
        },
        onManageModels: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => const ModelManagementPage(
              focusModelId: SpeechModelService.modelId,
            ),
          ),
        ),
      ),
    );
  }

  Future<Note> _saveAudioTranscript(NoteTranscriptResult result) {
    final operation = _saveTail.then((_) async {
      if (!mounted || _allowPop) {
        _transcriptions.unregisterEditor(_note.id, _transcriptSink);
        return _transcriptions.writeTranscript(result);
      }
      final current = _currentAudioAsset(result.assetId, result.storageKey);
      if (current == null ||
          result.noteId != _note.id ||
          result.privateSpace != _note.isPrivate) {
        throw StateError('目标音频附件已发生变化');
      }
      _editor.updateAsset(
        current.copyWith(
          transcript: result.transcript,
          transcriptionEngine: result.engine,
          transcribedAt: result.at,
          updatedAt: result.at,
        ),
      );
      _autosaveTimer?.cancel();
      // Use the editor's save queue so background recognition cannot create a
      // competing repository revision or overwrite unsaved body/title edits.
      if (!await _persistCurrent()) {
        final latest = _currentAudioAsset(result.assetId, result.storageKey);
        if (latest?.transcript == result.transcript) {
          _editor.updateAsset(
            latest!.copyWith(
              transcript: current.transcript,
              transcriptionEngine: current.transcriptionEngine,
              transcribedAt: current.transcribedAt,
            ),
          );
        }
        throw StateError('无法保存转写');
      }
      return _note;
    });
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _copyImage(NoteAsset asset) async {
    try {
      final bridge = QuillNativeBridge();
      if (!await bridge.isSupported(
        QuillNativeBridgeFeature.copyImageToClipboard,
      )) {
        if (mounted) {
          AppFeedback.show(context, context.l10n.imageCopyUnavailable);
        }
        return;
      }
      final path = FileStorageService.instance.absolutePath(asset.storageKey);
      await bridge.copyImageToClipboard(await File(path).readAsBytes());
      if (mounted) AppFeedback.success(context, context.l10n.imageCopied);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.imageCopyFailed);
    }
  }

  Future<void> _showImageActions(NoteAsset requestedAsset) async {
    final current = _editor.asset(requestedAsset.id);
    if (current == null || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await AppOverlay.bottomSheet<_ImageAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const AppIcon(Icons.edit_outlined),
              title: Text(context.l10n.renameAttachment),
              onTap: () => Navigator.pop(sheetContext, _ImageAction.rename),
            ),
            ListTile(
              key: const Key('recognize-image-text'),
              leading: const AppIcon(Icons.document_scanner_rounded),
              title: Text(context.l10n.imageOcrAction),
              onTap: () => Navigator.pop(sheetContext, _ImageAction.ocr),
            ),
            ListTile(
              key: const Key('replace-image-from-gallery'),
              leading: const AppIcon(Icons.photo_library_outlined),
              title: Text(context.l10n.replaceFromGallery),
              onTap: () => Navigator.pop(sheetContext, _ImageAction.gallery),
            ),
            ListTile(
              key: const Key('replace-image-from-camera'),
              leading: const AppIcon(Icons.photo_camera_outlined),
              title: Text(context.l10n.replaceWithCamera),
              onTap: () => Navigator.pop(sheetContext, _ImageAction.camera),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ImageAction.rename:
        await _renameImage(current);
      case _ImageAction.ocr:
        await _showImageOcr(current);
      case _ImageAction.gallery:
        await _replaceImage(current, ImageSource.gallery);
      case _ImageAction.camera:
        await _replaceImage(current, ImageSource.camera);
    }
  }

  NoteAsset? _currentOcrAsset(NoteAsset source) {
    if (!mounted || _closing) return null;
    // Removed embeds can remain in the undo asset index. Only the current
    // document graph is authoritative; replacement also preserves the asset ID.
    for (final asset in _editor.snapshot().assets) {
      if (asset.id == source.id &&
          asset.kind == NoteAssetKind.image &&
          asset.storageKey == source.storageKey) {
        return asset;
      }
    }
    return null;
  }

  Future<void> _showImageOcr(NoteAsset source) async {
    final current = _currentOcrAsset(source);
    if (current == null) return;
    await AppOverlay.bottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      builder: (_) => NoteImageOcrSheet(
        initialText: current.ocrText,
        recognizeText: () => _recognizeImageText(current),
        saveText: (text) => _saveImageOcr(current, text),
      ),
    );
  }

  Future<OcrResult> _recognizeImageText(NoteAsset source) async {
    final l10n = context.l10n;
    if (_currentOcrAsset(source) == null) {
      return OcrResult.failed(l10n.imageOcrSourceChanged);
    }
    try {
      final path = (widget.resolveAssetPath ?? _resolveManagedAssetPath)(
        source,
      );
      if (path == null) return OcrResult.failed(l10n.originalFileMissing);
      final result =
          await (widget.recognizeImageText ??
              OcrService.instance.recognizeText)(path);
      // Native errors are not user-facing (and may contain device paths).
      return result.didFail ? OcrResult.failed(l10n.imageOcrFailed) : result;
    } catch (_) {
      return OcrResult.failed(l10n.imageOcrFailed);
    }
  }

  Future<NoteImageOcrSaveStatus> _saveImageOcr(
    NoteAsset source,
    String text,
  ) async {
    final current = _currentOcrAsset(source);
    if (current == null) return NoteImageOcrSaveStatus.imageChanged;
    _editor.updateAsset(current.copyWith(ocrText: text, updatedAt: _now));
    final saved = await _persistLatest();
    final latest = _currentOcrAsset(source);
    if (latest == null) return NoteImageOcrSaveStatus.imageChanged;
    if (!saved) {
      // Keep the recognized text in the sheet for copying/retrying, but don't
      // present a failed save as a cached result on the next opening.
      if (latest.ocrText == text) {
        _editor.updateAsset(latest.copyWith(ocrText: current.ocrText));
      }
      return NoteImageOcrSaveStatus.failed;
    }
    return NoteImageOcrSaveStatus.saved;
  }

  Future<void> _renameImage(NoteAsset requestedAsset) async {
    final result = await showNoteAttachmentTitleSheet(
      context,
      initialValue: requestedAsset.displayTitle,
      fieldKey: const Key('image-attachment-title'),
    );
    if (result == null || !mounted) return;
    final current = _editor.asset(requestedAsset.id);
    if (current == null) return;
    _editor.updateAsset(
      current.copyWith(displayName: result.displayName, updatedAt: _now),
    );
  }

  Future<void> _replaceImage(
    NoteAsset requestedAsset,
    ImageSource source,
  ) async {
    if (_importingImage) return;
    final operation = _replaceImageFiles(requestedAsset, source);
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<void> _replaceImageFiles(
    NoteAsset requestedAsset,
    ImageSource source,
  ) async {
    setState(() => _importingImage = true);
    NoteAsset? imported;
    try {
      final selected = await _pickImage(source);
      if (selected == null || !mounted) return;
      imported = await _importImage(
        selected.bytes,
        originalName: selected.originalName,
      );
      if (!mounted) {
        await _deleteAssetFiles(imported);
        return;
      }
      final current = _editor.asset(requestedAsset.id);
      if (current == null) {
        await _deleteAssetFiles(imported);
        return;
      }
      final replacement = NoteAsset(
        id: current.id,
        kind: NoteAssetKind.image,
        storageKey: imported.storageKey,
        originalName: imported.originalName,
        displayName: current.displayName,
        byteLength: imported.byteLength,
        mimeType: imported.mimeType,
        previewStorageKey: imported.previewStorageKey,
        createdAt: current.createdAt,
        updatedAt: _now,
      );
      _editor.updateAsset(replacement);
      if (!await _persistLatest()) {
        _editor.updateAsset(current);
        await _deleteAssetFilesBestEffort(imported);
        if (mounted) {
          AppFeedback.error(context, context.l10n.imageReplaceFailed);
        }
        return;
      }
    } catch (_) {
      if (imported != null) await _deleteAssetFilesBestEffort(imported);
      if (mounted) {
        AppFeedback.error(context, context.l10n.imageReplaceFailed);
      }
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  Future<void> _showImageDetails(NoteAsset requestedAsset) async {
    final asset = _editor.asset(requestedAsset.id);
    if (asset == null || !mounted) return;
    final imageProvider = (widget.resolveImage ?? _resolveManagedImage)(asset);
    final formatter = DateFormat.yMMMd(context.l10n.localeName).add_Hm();
    await AppOverlay.bottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: (MediaQuery.sizeOf(sheetContext).height * .78).clamp(
          420.0,
          680.0,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          children: [
            Text(
              context.l10n.imageDetails,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            if (imageProvider != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: ColoredBox(
                  color: context.appColors.surfaceMuted,
                  child: Image(
                    image: imageProvider,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            if (imageProvider != null) const SizedBox(height: 18),
            _ImageDetailRow(
              label: context.l10n.fileName,
              value: asset.originalName,
            ),
            _ImageDetailRow(label: context.l10n.type, value: asset.mimeType),
            _ImageDetailRow(
              label: context.l10n.size,
              value: _formatBytes(asset.byteLength),
            ),
            _ImageDetailRow(
              label: context.l10n.created,
              value: formatter.format(asset.createdAt.toLocal()),
            ),
            _ImageDetailRow(
              label: context.l10n.updated,
              value: formatter.format(asset.updatedAt.toLocal()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewOriginalImage(NoteAsset requestedAsset) async {
    final asset = _editor.asset(requestedAsset.id);
    if (asset == null || !mounted) return;
    final imageProvider = (widget.resolveImage ?? _resolveManagedImage)(asset);
    if (imageProvider == null) {
      AppFeedback.error(context, context.l10n.originalFileMissing);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => _OriginalImageViewer(
          imageProvider: imageProvider,
          title: asset.displayTitle,
        ),
      ),
    );
  }

  Future<void> _deleteAssetFilesBestEffort(NoteAsset asset) async {
    try {
      await _deleteAssetFiles(asset);
    } catch (_) {
      // Persistence is authoritative; abandoned files can be reclaimed by a
      // later storage cleanup if the platform still has an open handle.
    }
  }

  void _onRecordingAmplitude(double amplitude) {
    if (!mounted || _recordingState != _NoteRecordingState.recording) return;
    setState(() {
      _recordingAmplitudes = [
        ..._recordingAmplitudes.skip(1),
        amplitude.clamp(.06, 1.0),
      ];
    });
  }

  Future<void> _startRecording() async {
    if (_recordingVisible || _actionPending || _closing) return;
    final runId = ++_recordingRunId;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_readAloudVisible) await _stopReadAloud();
    if (!mounted || runId != _recordingRunId) return;
    setState(() {
      _recordingState = _NoteRecordingState.preparing;
      _recordingElapsed = Duration.zero;
      _recordingAmplitudes = List<double>.filled(18, .06);
    });
    try {
      await _audioRecorder.start();
      if (!mounted || runId != _recordingRunId) {
        await _audioRecorder.cancel();
        return;
      }
      _recordingClock
        ..reset()
        ..start();
      _startRecordingTimer();
      setState(() => _recordingState = _NoteRecordingState.recording);
    } on NoteMicrophonePermissionDenied {
      _resetRecordingUi();
      await _showMicrophonePermissionDialog();
    } catch (error) {
      await _audioRecorder.cancel();
      _resetRecordingUi();
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingStartFailed(_readableError(error)),
        );
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recordingClock.isRunning) return;
      setState(() => _recordingElapsed = _recordingClock.elapsed);
    });
  }

  Future<void> _pauseOrResumeRecording() async {
    try {
      if (_recordingState == _NoteRecordingState.recording) {
        await _audioRecorder.pause();
        _recordingClock.stop();
        _recordingTimer?.cancel();
        _recordingElapsed = _recordingClock.elapsed;
        if (mounted) {
          setState(() => _recordingState = _NoteRecordingState.paused);
        }
      } else if (_recordingState == _NoteRecordingState.paused) {
        await _audioRecorder.resume();
        _recordingClock.start();
        _startRecordingTimer();
        if (mounted) {
          setState(() => _recordingState = _NoteRecordingState.recording);
        }
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingStartFailed(_readableError(error)),
        );
      }
    }
  }

  Future<void> _finishRecording() async {
    if (_recordingState != _NoteRecordingState.recording &&
        _recordingState != _NoteRecordingState.paused) {
      return;
    }
    _recordingElapsed = _recordingClock.elapsed;
    final runId = _recordingRunId;
    _recordingClock.stop();
    _recordingTimer?.cancel();
    setState(() => _recordingState = _NoteRecordingState.saving);
    final operation = _saveRecording(runId);
    _audioImport = operation;
    await operation;
    if (identical(_audioImport, operation)) _audioImport = null;
  }

  Future<void> _saveRecording(int runId) async {
    File? temporaryFile;
    NoteAsset? imported;
    try {
      final recording = await _audioRecorder.stop();
      temporaryFile = File(recording.path);
      if (!mounted || runId != _recordingRunId) return;
      final timestamp = _now;
      final local = timestamp.toLocal();
      final originalName = 'recording-${timestamp.microsecondsSinceEpoch}.m4a';
      final displayName = context.l10n.voiceNoteDefaultTitle(
        '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}',
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}',
      );
      imported = await _importAudio(
        temporaryFile,
        originalName: originalName,
        displayName: displayName,
        durationMs: _recordingElapsed.inMilliseconds,
      );
      if (!mounted || runId != _recordingRunId) {
        await _deleteAssetFiles(imported);
        return;
      }
      _editor.insertAsset(imported);
      _resetRecordingUi();
      _editorFocusNode.unfocus();
    } catch (error) {
      if (imported != null) await _deleteAssetFiles(imported);
      await _audioRecorder.cancel();
      _resetRecordingUi();
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingSaveFailed(_readableError(error)),
        );
      }
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recordingVisible || _recordingState == _NoteRecordingState.saving) {
      return;
    }
    _recordingRunId++;
    _recordingClock.stop();
    _recordingTimer?.cancel();
    try {
      await _audioRecorder.cancel();
    } finally {
      _resetRecordingUi();
    }
  }

  void _resetRecordingUi() {
    _recordingClock
      ..stop()
      ..reset();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (!mounted) return;
    setState(() {
      _recordingState = _NoteRecordingState.idle;
      _recordingElapsed = Duration.zero;
      _recordingAmplitudes = List<double>.filled(18, .06);
    });
  }

  Future<void> _showMicrophonePermissionDialog() async {
    if (!mounted) return;
    final openSettings = await AppOverlay.dialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.microphonePermissionRequired),
        content: Text(context.l10n.microphonePermissionDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.openSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) await permissions.openAppSettings();
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _readableError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state: |StateError: |Exception: )'),
    '',
  );

  Future<void> _requestClose({bool completed = false}) async {
    if (_closing) return;
    setState(() => _closing = true);
    if (_inlineAssistantBusy) await _stopInlineAssistant();
    if (!mounted) return;
    if (_recordingState == _NoteRecordingState.saving) {
      await _audioImport;
    } else if (_recordingVisible) {
      final discard = await _confirmDestructiveAction(
        title: context.l10n.discardRecordingQuestion,
        description: context.l10n.discardRecordingDescription,
        actionLabel: context.l10n.discard,
      );
      if (!discard || !mounted) {
        if (mounted) setState(() => _closing = false);
        return;
      }
      await _cancelRecording();
    }
    if (!mounted) return;
    await _imageImport;
    await _videoImport;
    var saved = await _persistLatest();
    if (!mounted) return;

    if (!saved) {
      final action = await AppOverlay.dialog<_FailedSaveAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.autosaveFailedShort),
          content: Text(context.l10n.saveFailedStorage),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.keepEditing),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.discard),
              child: Text(context.l10n.discardDraft),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.retry),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == _FailedSaveAction.retry) {
        saved = await _persistLatest();
      } else if (action == _FailedSaveAction.discard) {
        await _discardUnsavedAssets();
        saved = true;
      }
      if (!saved) {
        setState(() => _closing = false);
        return;
      }
    }

    // Drain any transcript write that arrived while the close/save UI awaited.
    // Unregister synchronously before allowing the route to pop; later results
    // use the repository (or the next editor) instead of this disposed draft.
    while (true) {
      final tail = _saveTail;
      await tail;
      if (identical(tail, _saveTail)) break;
    }
    if (!mounted) return;
    _transcriptions.unregisterEditor(_note.id, _transcriptSink);
    final result = NoteEditorRouteResult(
      note: _note.revision == 0 ? null : _note,
      completed: completed,
    );
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _discardUnsavedAssets() async {
    final persistedIds = _note.revision == 0
        ? <NoteAttachmentId>{}
        : _note.assets.map((asset) => asset.id).toSet();
    for (final asset in _editor.assets) {
      if (!persistedIds.contains(asset.id)) await _deleteAssetFiles(asset);
    }
  }

  String _saveLabel(BuildContext context) => switch (_saveState) {
    _EditorSaveState.enabled => context.l10n.autosaveEnabled,
    _EditorSaveState.pending => context.l10n.autosavePending,
    _EditorSaveState.saving => context.l10n.autosaving,
    _EditorSaveState.saved => context.l10n.autosavedLocally,
    _EditorSaveState.failed => context.l10n.autosaveFailedShort,
  };

  IconData get _saveIcon => switch (_saveState) {
    _EditorSaveState.enabled => Icons.offline_pin_outlined,
    _EditorSaveState.pending => Icons.schedule_rounded,
    _EditorSaveState.saving => Icons.sync_rounded,
    _EditorSaveState.saved => Icons.check_circle_outline_rounded,
    _EditorSaveState.failed => Icons.error_outline_rounded,
  };

  Color get _saveColor => _saveState == _EditorSaveState.failed
      ? context.appColors.danger
      : context.appColors.muted;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // An open action menu owns a local history entry. Dismiss it before
      // starting the editor's asynchronous save-and-leave flow.
      if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
        Navigator.pop(context);
        return;
      }
      unawaited(_requestClose());
    },
    child: Scaffold(
      backgroundColor: context.appColors.paperPrimary,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: context.appColors.paperPrimary,
          child: AbsorbPointer(
            absorbing: _actionPending,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: Container(
                    key: const Key('quill-editor-surface'),
                    color: context.appComponents.usesJournalEditor
                        ? null
                        : context.appColors.paperPrimary,
                    decoration: context.appComponents.usesJournalEditor
                        ? BoxDecoration(
                            color: context.appColors.surface,
                            image: const DecorationImage(
                              image: AssetImage(
                                EditorialJournalTokens.paperTextureAsset,
                              ),
                              fit: BoxFit.cover,
                              opacity: .16,
                              filterQuality: FilterQuality.low,
                            ),
                          )
                        : null,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: TextField(
                            key: const Key('quill-note-title'),
                            controller: _titleController,
                            focusNode: _titleFocusNode,
                            readOnly:
                                _recordingVisible ||
                                _inlineAssistantMetadataSession != null,
                            maxLines: 1,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(200),
                            ],
                            onSubmitted: (_) => _editorFocusNode.requestFocus(),
                            style: AppTypography.editorTitle.copyWith(
                              fontFamily:
                                  context.appComponents.displayFontFamily,
                              fontFamilyFallback:
                                  context
                                      .appComponents
                                      .displayFontFamilyFallback ??
                                  AppTypography.fallback,
                              color: context.appColors.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: context.l10n.newNote,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                        _buildMetadata(context),
                        Expanded(child: _buildBodyEditor(context)),
                      ],
                    ),
                  ),
                ),
                if (_importingImage || _importingVideo)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: context.appColors.accent,
                    backgroundColor: context.appColors.accentSoft,
                  ),
                if (_inlineAssistantOpen &&
                    _inlinePrivateCloudNotice &&
                    !_recordingVisible)
                  const PrivateCloudAiNotice(),
                if (_recordingVisible) ...[
                  if (!context.appComponents.usesFloatingNavigationDock)
                    _buildRecordingBar(),
                ] else if (_inlineAssistantOpen)
                  NoteInlineAssistantComposer(
                    controller: _inlineAssistantController,
                    focusNode: _inlineAssistantFocusNode,
                    loading: _inlineAssistantLoading,
                    generating: _inlineAssistantGenerating,
                    hasResult:
                        (_inlineAssistantSession != null ||
                            _inlineAssistantMetadataSession != null) &&
                        _inlineAssistantOutput.trim().isNotEmpty,
                    resultLabel: _inlineAssistantMetadataSession != null
                        ? context.l10n.inlineAssistantMetadataUpdated
                        : context.l10n.inlineAssistantWritten,
                    target: _inlineAssistantTarget,
                    selectionAvailable: _inlineAssistantSelectionAvailable,
                    error: _inlineAssistantError,
                    onSubmit: (value, target) => unawaited(
                      _submitInlineAssistant(value, target: target),
                    ),
                    onTargetChanged: _changeInlineAssistantTarget,
                    onStop: () => unawaited(_stopInlineAssistant()),
                    onRetry: _retryInlineAssistant,
                    onUndo: _undoInlineAssistant,
                    onContinue: _continueInlineAssistant,
                    onClose: _closeInlineAssistant,
                  )
                else
                  NoteQuillToolbar(
                    controller: _editor,
                    onOpenAssistant: _toggleInlineAssistant,
                    onInsertFileReferences: () =>
                        unawaited(_insertFileReferences()),
                    onInsertImage: _showImageSourceSheet,
                    onInsertVideo: _showVideoSourceSheet,
                    onRecordAudio: () => unawaited(_startRecording()),
                    onDone: _closing
                        ? null
                        : () => unawaited(_requestClose(completed: true)),
                    assistantTooltip: context.l10n.writeWithAi,
                    imageTooltip: context.l10n.image,
                    videoTooltip: context.l10n.video,
                    recordTooltip: context.l10n.record,
                    doneLabel: context.l10n.finishEditing,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBodyEditor(BuildContext context) {
    final recordingFloats =
        _recordingVisible && context.appComponents.usesFloatingNavigationDock;
    final recordingContentPadding = recordingFloats
        ? NoteRecordingBar.floatingScrollClearance(context)
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          // Read-aloud retains its compact viewport. Recording instead lets
          // content travel behind the dock and pads only the scrollable tail.
          padding: EdgeInsets.only(
            bottom: _readAloudVisible
                ? NoteReadAloudBar.heightFor(context) + 24
                : 0,
          ),
          child: NoteQuillEditor(
            key: const Key('quill-note-body'),
            editorKey: _bodyEditorKey,
            scrollController: _editorScrollController,
            controller: _editor,
            focusNode: _editorFocusNode,
            autofocus: _note.revision == 0,
            resolveImage: widget.resolveImage ?? _resolveManagedImage,
            resolveAssetPath:
                widget.resolveAssetPath ?? _resolveManagedAssetPath,
            audioPlayback: _audioPlayback,
            onOpenAsset: _openAsset,
            onTranscribeAudio: (asset) =>
                unawaited(_showAudioTranscription(asset)),
            onCopyImage: _copyImage,
            onEditImage: _showImageActions,
            onViewImageOriginal: _viewOriginalImage,
            onShowImageDetails: _showImageDetails,
            onDropImages: _handleDroppedImages,
            placeholder: context.l10n.noteStartHint,
            bottomContentPadding: recordingContentPadding,
            readOnly:
                _inlineAssistantBusy ||
                _inlineAssistantSession != null ||
                _recordingVisible,
          ),
        ),
        if (_readAloudVisible)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: NoteReadAloudBar(
                status: _readAloudStarting
                    ? ReadAloudStatus.generating
                    : _readAloud.status,
                onStop: () => unawaited(_stopReadAloud()),
              ),
            ),
          ),
        if (recordingFloats)
          Positioned(left: 0, right: 0, bottom: 0, child: _buildRecordingBar()),
      ],
    );
  }

  Widget _buildRecordingBar() => NoteRecordingBar(
    preparing: _recordingState == _NoteRecordingState.preparing,
    saving: _recordingState == _NoteRecordingState.saving,
    paused: _recordingState == _NoteRecordingState.paused,
    elapsed: _recordingElapsed,
    amplitudes: _recordingAmplitudes,
    onCancel: _recordingState == _NoteRecordingState.saving
        ? null
        : () => unawaited(_cancelRecording()),
    onPauseOrResume:
        _recordingState == _NoteRecordingState.recording ||
            _recordingState == _NoteRecordingState.paused
        ? () => unawaited(_pauseOrResumeRecording())
        : null,
    onFinish:
        _recordingState == _NoteRecordingState.recording ||
            _recordingState == _NoteRecordingState.paused
        ? () => unawaited(_finishRecording())
        : null,
  );

  int get _characterCount {
    if (_countedContentRevision != _editor.contentRevision) {
      // Count visible body characters, excluding whitespace and attachment
      // placeholders. Avoid snapshots/Delta validation on header rebuilds.
      final text = _editor.quillController.document.toPlainText().replaceAll(
        RegExp(r'[\s\uFFFC]'),
        '',
      );
      _bodyCharacterCount = text.characters.length;
      _countedContentRevision = _editor.contentRevision;
    }
    return _bodyCharacterCount;
  }

  Widget _buildMetadata(BuildContext context) {
    final locale = context.l10n.localeName;
    final updated = _note.updatedAt.toLocal();
    final date = updated.year == _now.toLocal().year
        ? DateFormat.MMMd(locale)
        : DateFormat.yMMMd(locale);
    final style = TextStyle(
      color: context.appColors.subtle,
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w400,
    );
    final separator = SizedBox(
      height: 12,
      child: VerticalDivider(
        width: 20,
        thickness: 0.5,
        color: context.appColors.line,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          key: const Key('quill-editor-metadata'),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: DefaultTextStyle(
              style: style,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    date.add_Hm().format(updated),
                    key: const Key('quill-note-updated-time'),
                  ),
                  separator,
                  Text(
                    context.l10n.characterCount(_characterCount),
                    key: const Key('quill-note-character-count'),
                  ),
                  if (_note.reminderAt case final time?) ...[
                    separator,
                    NoteReminderIndicator(
                      key: const Key('editor-note-reminder'),
                      at: time,
                      now: widget.now,
                      textColor: context.appColors.subtle,
                      onTap: () => unawaited(_editReminder()),
                    ),
                  ],
                  if (_tags.isNotEmpty) ...[
                    separator,
                    Tooltip(
                      message: context.l10n.editTags,
                      child: InkWell(
                        key: const Key('quill-edit-tags'),
                        onTap: _inlineAssistantMetadataSession == null
                            ? _editTags
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            minWidth: 48,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < _tags.length && index < 2;
                                index++
                              ) ...[
                                if (index > 0) const Text(' · '),
                                Text(
                                  '#${_tags[index]}',
                                  key: ValueKey(
                                    'quill-note-tag-${_tags[index]}',
                                  ),
                                ),
                              ],
                              if (_tags.length > 2)
                                Text(' +${_tags.length - 2}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
    decoration: BoxDecoration(
      color: context.appColors.paperPrimary,
      border: context.appComponents.usesJournalEditor
          ? Border(
              bottom: BorderSide(
                color: context.appColors.line.withValues(alpha: .75),
              ),
            )
          : null,
    ),
    child: Row(
      children: [
        IconButton(
          key: const Key('quill-editor-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _closing ? null : _requestClose,
          style: IconButton.styleFrom(fixedSize: const Size.square(48)),
          icon: const AppIcon(Icons.arrow_back_rounded, size: 22),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            key: const Key('quill-save-status'),
            onTap: _saveState == _EditorSaveState.failed
                ? () => unawaited(_persistLatest())
                : null,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Row(
                key: ValueKey(_saveState),
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(_saveIcon, size: 14, color: _saveColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _saveLabel(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _saveColor,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_closing || _actionPending || _saveState == _EditorSaveState.saving)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...[
          IconButton(
            key: const Key('quill-note-outline'),
            tooltip: context.l10n.noteOutline,
            onPressed: _recordingVisible ? null : _showOutline,
            style: IconButton.styleFrom(fixedSize: const Size.square(48)),
            icon: const AppIcon(Icons.toc_rounded, size: 21),
          ),
          AppAnchoredMenuButton<_QuillEditorMenuAction>(
            key: const Key('quill-editor-more'),
            tooltip: context.l10n.moreNoteActions,
            enabled: !_recordingVisible,
            icon: const AppIcon(Icons.more_vert_rounded),
            onSelected: _handleMenuAction,
            actions: _menuActions(context),
          ),
        ],
      ],
    ),
  );

  List<AppMenuAction<_QuillEditorMenuAction>> _menuActions(
    BuildContext context,
  ) => [
    AppMenuAction(
      value: _QuillEditorMenuAction.readAloud,
      icon: Icons.volume_up_outlined,
      label: context.l10n.readNoteAloud,
      enabled: !_readAloudVisible,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.share,
      icon: Icons.ios_share_rounded,
      label: context.l10n.shareNoteAsImage,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.tags,
      icon: Icons.label_outline_rounded,
      label: context.l10n.tags,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.pin,
      icon: Icons.push_pin_outlined,
      label: _note.isPinned ? context.l10n.unpin : context.l10n.pin,
      selected: _note.isPinned,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.reminder,
      icon: Icons.alarm_outlined,
      label: _note.reminderAt == null
          ? context.l10n.setNoteReminder
          : context.l10n.editNoteReminder,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.save,
      icon: Icons.save_outlined,
      label: context.l10n.save,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.delete,
      icon: Icons.delete_outline_rounded,
      label: _note.revision == 0
          ? context.l10n.discardNote
          : context.l10n.deletePermanently,
      destructive: true,
    ),
  ];

  ImageProvider _resolveManagedImage(NoteAsset asset) => FileImage(
    File(FileStorageService.instance.absolutePath(asset.storageKey)),
  );

  String _resolveManagedAssetPath(NoteAsset asset) =>
      FileStorageService.instance.absolutePath(asset.storageKey);

  Future<void> _disposeAudioRecorder() async {
    await _recordingAmplitudeSubscription?.cancel();
    _recordingAmplitudeSubscription = null;
    await _audioRecorder.dispose();
  }

  @override
  void dispose() {
    _readAloudRequestId++;
    NoteEditGuard.instance.release(_note.id, this);
    _transcriptions.unregisterEditor(_note.id, _transcriptSink);
    WidgetsBinding.instance.removeObserver(this);
    _inlineAssistantRunId++;
    if (_inlineAssistantBusy) unawaited(_inlineAssistant.cancel());
    _autosaveTimer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_disposeAudioRecorder());
    _audioPlayback.dispose();
    _readAloud.removeListener(_onReadAloudChanged);
    if (_readAloud.isActive) unawaited(_readAloud.stop());
    _titleController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _inlineAssistantController.dispose();
    _inlineAssistantFocusNode.dispose();
    _editor.dispose();
    super.dispose();
  }
}

enum _EditorSaveState { enabled, pending, saving, saved, failed }

enum _NoteRecordingState { idle, preparing, recording, paused, saving }

enum _FailedSaveAction { keepEditing, retry, discard }

enum _QuillEditorMenuAction {
  readAloud,
  share,
  tags,
  pin,
  reminder,
  save,
  delete,
}

enum _ImageImportSource {
  gallery(ImageSource.gallery),
  camera(ImageSource.camera),
  watermarkCamera(ImageSource.camera);

  const _ImageImportSource(this.imageSource);

  final ImageSource imageSource;
}

enum _ImageAction { rename, ocr, gallery, camera }

final class _InlineAssistantMetadataSession {
  _InlineAssistantMetadataSession({
    required this.beforeTitle,
    required List<String> beforeTags,
    required this.appliedTitle,
    required List<String> appliedTags,
  }) : beforeTags = List.unmodifiable(beforeTags),
       appliedTags = List.unmodifiable(appliedTags);

  final String beforeTitle;
  final List<String> beforeTags;
  final String appliedTitle;
  final List<String> appliedTags;
}

bool _sameTags(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _requestsNoteMetadata(String instruction) {
  final normalized = instruction.toLowerCase();
  final mentionsMetadata = RegExp(
    r'(标题|题目|标签|title|tags?|rename)',
  ).hasMatch(normalized);
  final requestsChange = RegExp(
    r'(生成|拟定|取名|命名|修改|更新|添加|加上|整理|generate|suggest|create|update|change|rename|add)',
  ).hasMatch(normalized);
  return mentionsMetadata && requestsChange;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

final class _OriginalImageViewer extends StatelessWidget {
  const _OriginalImageViewer({
    required this.imageProvider,
    required this.title,
  });

  final ImageProvider imageProvider;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appColors.canvas,
    appBar: AppBar(
      backgroundColor: context.appColors.canvas,
      foregroundColor: context.appColors.ink,
      surfaceTintColor: Colors.transparent,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          minScale: .75,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Image(
              key: const Key('note-original-image'),
              image: imageProvider,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(
                child: AppIcon(
                  Icons.broken_image_outlined,
                  color: context.appColors.muted,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ImageDetailRow extends StatelessWidget {
  const _ImageDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: context.appColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

enum _WatermarkLocationMode { current, manual }

final class _WatermarkLocationSheet extends StatefulWidget {
  const _WatermarkLocationSheet({required this.locate, required this.now});

  final NoteWatermarkLocationProvider locate;
  final DateTime Function() now;

  @override
  State<_WatermarkLocationSheet> createState() =>
      _WatermarkLocationSheetState();
}

final class _WatermarkLocationSheetState
    extends State<_WatermarkLocationSheet> {
  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocusNode = FocusNode();
  _WatermarkLocationMode _mode = _WatermarkLocationMode.current;
  NoteWatermarkLocation? _currentLocation;
  NoteWatermarkLocationFailure? _failure;
  var _loading = true;
  var _showManualError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCurrentLocation());
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final location = await widget.locate();
      if (!mounted) return;
      setState(() {
        _currentLocation = location;
        _loading = false;
      });
    } on NoteWatermarkLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failure = NoteWatermarkLocationFailure.unavailable;
        _loading = false;
      });
    }
  }

  void _selectMode(_WatermarkLocationMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _showManualError = false;
    });
    if (mode == _WatermarkLocationMode.manual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _manualFocusNode.requestFocus();
      });
    }
  }

  void _confirm() {
    if (_mode == _WatermarkLocationMode.current) {
      final location = _currentLocation;
      if (location != null) Navigator.pop(context, location);
      return;
    }
    final placeName = normalizeNoteWatermarkPlaceName(_manualController.text);
    if (placeName == null) {
      setState(() => _showManualError = true);
      return;
    }
    Navigator.pop(
      context,
      NoteWatermarkLocation(placeName: placeName, capturedAt: widget.now()),
    );
  }

  String _failureMessage(BuildContext context) => switch (_failure) {
    NoteWatermarkLocationFailure.serviceDisabled =>
      context.l10n.locationServiceDisabled,
    NoteWatermarkLocationFailure.permissionDenied =>
      context.l10n.locationPermissionRequired,
    NoteWatermarkLocationFailure.permissionDeniedForever =>
      context.l10n.locationPermissionPermanentlyDenied,
    NoteWatermarkLocationFailure.unavailable ||
    null => context.l10n.locationUnavailable,
  };

  Widget _buildCurrentLocation(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 104,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.locatingForWatermark),
            ],
          ),
        ),
      );
    }
    final location = _currentLocation;
    if (location != null) {
      final placeName = location.normalizedPlaceName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                Icons.location_on_outlined,
                color: context.appColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (placeName != null) ...[
                      Text(
                        context.l10n.detectedLocation,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: context.appColors.muted),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      placeName ?? context.l10n.locationNameUnavailable,
                      key: const Key('watermark-detected-location'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.appColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (location.coordinateSummary case final coordinate?) ...[
                      const SizedBox(height: 5),
                      Text(
                        coordinate,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('watermark-location-retry'),
              onPressed: _loadCurrentLocation,
              icon: const AppIcon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.retry),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _failureMessage(context),
          key: const Key('watermark-location-error'),
          style: TextStyle(color: context.appColors.danger, height: 1.45),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('watermark-location-retry'),
              onPressed: _loadCurrentLocation,
              icon: const AppIcon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.retry),
            ),
            if (_failure ==
                NoteWatermarkLocationFailure.permissionDeniedForever)
              TextButton(
                key: const Key('watermark-open-settings'),
                onPressed: permissions.openAppSettings,
                child: Text(context.l10n.openSettings),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final manualNameReady =
        normalizeNoteWatermarkPlaceName(_manualController.text) != null;
    final canContinue = _mode == _WatermarkLocationMode.current
        ? _currentLocation != null
        : manualNameReady;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.watermarkLocationTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.watermarkLocationDescription,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.appColors.muted),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _WatermarkLocationModeButton(
                    key: const Key('watermark-use-current-location'),
                    selected: _mode == _WatermarkLocationMode.current,
                    icon: Icons.my_location_rounded,
                    label: context.l10n.useCurrentLocation,
                    onPressed: () =>
                        _selectMode(_WatermarkLocationMode.current),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WatermarkLocationModeButton(
                    key: const Key('watermark-use-manual-location'),
                    selected: _mode == _WatermarkLocationMode.manual,
                    icon: Icons.edit_location_alt_outlined,
                    label: context.l10n.enterLocationManually,
                    onPressed: () => _selectMode(_WatermarkLocationMode.manual),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Container(
                key: ValueKey(_mode),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(color: context.appColors.line),
                ),
                child: _mode == _WatermarkLocationMode.current
                    ? _buildCurrentLocation(context)
                    : TextField(
                        key: const Key('watermark-manual-location-field'),
                        controller: _manualController,
                        focusNode: _manualFocusNode,
                        maxLength: 80,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: context.l10n.customLocationName,
                          hintText: context.l10n.customLocationHint,
                          errorText: _showManualError
                              ? context.l10n.locationNameRequired
                              : null,
                          prefixIcon: AppIcon(
                            Icons.place_outlined,
                            color: context.appColors.accent,
                          ),
                        ),
                        onChanged: (_) => setState(() {
                          _showManualError = false;
                        }),
                        onSubmitted: (_) => _confirm(),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('watermark-location-confirm'),
                    onPressed: canContinue ? _confirm : null,
                    icon: const AppIcon(Icons.photo_camera_outlined, size: 19),
                    label: Text(context.l10n.continueToCamera),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }
}

final class _WatermarkLocationModeButton extends StatelessWidget {
  const _WatermarkLocationModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      foregroundColor: selected
          ? context.appColors.ink
          : context.appColors.muted,
      backgroundColor: selected
          ? context.appColors.accentSoft
          : Colors.transparent,
      side: BorderSide(
        color: selected ? context.appColors.accent : context.appColors.line,
      ),
    ),
    icon: AppIcon(icon, size: 19),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

final class _ImageSourceAction extends StatelessWidget {
  const _ImageSourceAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: Material(
      color: context.appColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, color: context.appColors.accent),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
