import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/speech_transcription_service.dart';
import 'app_icon.dart';
import 'editor_context_menu.dart';

final class NoteAudioTranscriptionSheet extends StatefulWidget {
  const NoteAudioTranscriptionSheet({
    required this.driver,
    required this.noteId,
    required this.asset,
    required this.onStart,
    required this.onManageModels,
    super.key,
  });

  final NoteTranscriptionDriver driver;
  final NoteId noteId;
  final NoteAsset asset;
  final Future<void> Function() onStart;
  final Future<void> Function() onManageModels;

  @override
  State<NoteAudioTranscriptionSheet> createState() =>
      _NoteAudioTranscriptionSheetState();
}

final class _NoteAudioTranscriptionSheetState
    extends State<NoteAudioTranscriptionSheet> {
  bool _starting = false;
  bool _needsModel = false;
  bool _copying = false;
  bool _copyFailed = false;
  String? _error;
  String? _copyMessage;

  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  TranscriptionJob? get _job {
    final job = widget.driver.jobFor(widget.asset.storageKey);
    return job?.noteId == widget.noteId && job?.assetId == widget.asset.id
        ? job
        : null;
  }

  String get _text {
    final job = _job;
    if (job != null && job.partialText.trim().isNotEmpty) {
      return job.partialText.trim();
    }
    return widget.asset.transcript?.trim() ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active && _job == null && _text.isEmpty) unawaited(_start());
    });
  }

  Future<void> _start() async {
    if (!_active || _starting || _job?.isRunning == true) return;
    setState(() {
      _starting = true;
      _error = null;
      _copyMessage = null;
    });
    try {
      final installed = await widget.driver.isModelAvailable();
      if (!_active) return;
      setState(() => _needsModel = !installed);
      if (installed) await widget.onStart();
    } catch (_) {
      if (_active) {
        setState(() => _error = context.l10n.audioTranscriptStartFailed);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _manageModels() async {
    if (_starting) return;
    await widget.onManageModels();
    if (_active) await _start();
  }

  Future<void> _copy() async {
    if (_copying || _text.isEmpty) return;
    final l10n = context.l10n;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: _text));
      if (_active) {
        setState(() {
          _copyMessage = l10n.transcriptCopied;
          _copyFailed = false;
        });
      }
    } catch (_) {
      if (_active) {
        setState(() {
          _copyMessage = l10n.audioTranscriptCopyFailed;
          _copyFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.driver,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final l10n = context.l10n;
    final job = _job;
    final running = job?.isRunning == true;
    final busy = _starting || running;
    final needsModel =
        _needsModel || job?.failure == TranscriptionFailure.modelMissing;
    final text = _text;
    final status =
        _error ??
        (needsModel
            ? l10n.offlineSpeechModelRequired
            : switch (job?.status) {
                TranscriptionStatus.preparing => l10n.preparingTranscription,
                TranscriptionStatus.decoding => l10n.decodingAudio,
                TranscriptionStatus.diarizing => l10n.identifyingSpeakers,
                TranscriptionStatus.recognizing => l10n.recognizingSpeech,
                TranscriptionStatus.saving => l10n.savingTranscript,
                TranscriptionStatus.completed => l10n.completed,
                TranscriptionStatus.canceled => l10n.transcriptionCanceled,
                TranscriptionStatus.failed => switch (job?.failure) {
                  TranscriptionFailure.noSpeech => l10n.noClearSpeechRecognized,
                  TranscriptionFailure.fileMissing =>
                    l10n.audioTranscriptFileMissing,
                  TranscriptionFailure.saving => l10n.audioTranscriptSaveFailed,
                  TranscriptionFailure.busy => l10n.localInferenceInUse,
                  _ => l10n.transcriptionFailed,
                },
                null =>
                  _starting
                      ? l10n.preparingTranscription
                      : text.isEmpty
                      ? l10n.noTranscript
                      : '',
              });
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.recognizeAudio,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('close-audio-transcription'),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              l10n.audioTranscriptionDescription,
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (text.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .38,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    key: const Key('audio-transcription-result'),
                    contextMenuBuilder: buildAppEditableTextContextMenu,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
              ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _starting ? null : job?.progress.clamp(0, 1),
                minHeight: 2,
              ),
            ],
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const Key('audio-transcription-status'),
                    style: TextStyle(
                      color:
                          _error != null ||
                              job?.status == TranscriptionStatus.failed
                          ? context.appColors.danger
                          : context.appColors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            if (running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.backgroundTranscriptionHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.muted,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (running)
                  OutlinedButton(
                    key: const Key('cancel-audio-transcription'),
                    onPressed: job?.status == TranscriptionStatus.saving
                        ? null
                        : () => widget.driver.cancel(widget.asset.storageKey),
                    child: Text(l10n.cancel),
                  )
                else
                  OutlinedButton(
                    key: const Key('start-audio-transcription'),
                    onPressed: busy
                        ? null
                        : needsModel
                        ? _manageModels
                        : _start,
                    child: Text(
                      needsModel
                          ? l10n.manageModels
                          : text.isEmpty
                          ? l10n.recognizeAudio
                          : l10n.transcribeAgain,
                    ),
                  ),
                FilledButton(
                  key: const Key('copy-audio-transcription'),
                  onPressed: _copying || text.isEmpty ? null : _copy,
                  child: Text(l10n.copyAll),
                ),
              ],
            ),
            if (_copyMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _copyMessage!,
                    style: TextStyle(
                      color: _copyFailed
                          ? context.appColors.danger
                          : context.appColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
