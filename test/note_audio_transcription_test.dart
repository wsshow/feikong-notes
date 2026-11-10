import 'dart:async';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/services/speech_transcription_service.dart';
import 'package:fknotes/widgets/note_audio_transcription_sheet.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Writer writer;
  late _Transcriptions driver;
  late NoteAsset asset;

  setUp(() {
    final now = DateTime.utc(2026, 8, 27);
    asset = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.audio,
      storageKey: 'notes/audio/voice.wav',
      originalName: 'voice.wav',
      displayName: '语音笔记',
      byteLength: 32,
      mimeType: 'audio/wav',
      durationMs: 25000,
      createdAt: now,
      updatedAt: now,
    );
    writer = _Writer();
    driver = _Transcriptions();
  });

  Future<void> openEditor(
    WidgetTester tester, {
    String? transcript,
    bool private = false,
    int revision = 1,
  }) async {
    asset = asset.copyWith(transcript: transcript);
    writer.note = Note.newDraft(isPrivate: private).copyWith(
      title: '原有标题',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('原有正文\n')
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
      revision: revision,
    );
    await tester.pumpWidget(
      _app(
        NoteQuillEditorPage(
          initialNote: writer.note,
          writerLoader: () async => writer,
          transcriptionDriver: driver,
          resolveAssetPath: (_) => '/managed/voice.wav',
          autosaveDelay: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTranscription(WidgetTester tester) async {
    final menu = find.byKey(ValueKey('note-audio-actions-${asset.id.value}'));
    final gesture = await tester.startGesture(tester.getCenter(menu));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('修改标题'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
    await tester.tap(find.text('语音识别'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteAudioTranscriptionSheet), findsOneWidget);
  }

  testWidgets('first tap starts recognition after saving a new draft', (
    tester,
  ) async {
    await openEditor(tester, revision: 0);
    await openTranscription(tester);
    expect(driver.starts, 1);
    expect(writer.note.revision, 1);
    expect(writer.writes, 1);
    expect(driver.job!.assetId, asset.id);
    expect(driver.job!.filePath, asset.storageKey);
    expect(find.text('正在识别语音'), findsOneWidget);
    final original = writer.note.document.toDelta().toJson();
    await driver.finish('这是语音识别的结果');
    await tester.pumpAndSettle();
    expect(find.text('这是语音识别的结果'), findsOneWidget);
    expect(writer.note.assets.single.transcript, '这是语音识别的结果');
    expect(writer.note.assets.single.transcriptionEngine, 'test-sensevoice');
    expect(writer.note.assets.single.transcribedAt, isNotNull);
    expect(writer.note.searchText, contains('这是语音识别的结果'));
    expect(writer.note.document.toDelta().toJson(), original);
  });

  testWidgets(
    'closing the sheet keeps recognition running and preserves later edits',
    (tester) async {
      await openEditor(tester);
      await openTranscription(tester);
      await tester.tap(find.byKey(const Key('close-audio-transcription')));
      await tester.pumpAndSettle();
      expect(driver.job!.isRunning, isTrue);
      await tester.enterText(
        find.byKey(const Key('quill-note-title')),
        '识别期间的新标题',
      );
      final editor = tester.widget<NoteQuillEditor>(
        find.byType(NoteQuillEditor),
      );
      editor.controller.quillController.replaceText(0, 0, '刚输入的正文\n', null);
      await driver.finish('后台转写');
      await tester.pumpAndSettle();
      expect(writer.note.title, '识别期间的新标题');
      expect(writer.note.document.project().plainText, contains('刚输入的正文'));
      expect(writer.note.assets.single.transcript, '后台转写');
      await openTranscription(tester);
      expect(driver.starts, 1);
      expect(find.text('后台转写'), findsOneWidget);
    },
  );

  testWidgets(
    'cached transcript is copied only on request and can be transcribed again',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openEditor(tester, transcript: '之前的识别文字');
      await openTranscription(tester);
      expect(driver.starts, 0);
      expect(copied, isEmpty);
      await tester.tap(find.byKey(const Key('copy-audio-transcription')));
      await tester.pumpAndSettle();
      expect(copied, ['之前的识别文字']);
      expect(find.text('转写文字已复制'), findsOneWidget);
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      expect(driver.starts, 1);
      driver.progress('正在处理的部分文字', .5);
      await tester.pumpAndSettle();
      expect(find.text('正在处理的部分文字'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
    },
  );

  testWidgets('unsaved draft failure prevents starting a background job', (
    tester,
  ) async {
    await openEditor(tester, revision: 0);
    writer.fail = true;
    await openTranscription(tester);
    expect(driver.starts, 0);
    expect(find.text('暂时无法开始识别，请确认笔记已保存后重试'), findsOneWidget);
  });

  for (final entry in {
    TranscriptionFailure.fileMissing: '音频文件不存在或已被移除',
    TranscriptionFailure.busy: '正在使用本地推理资源',
  }.entries) {
    testWidgets('${entry.key} is explained without native error details', (
      tester,
    ) async {
      await openEditor(tester);
      await openTranscription(tester);
      driver.fail(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('/private/path'), findsNothing);
    });
  }

  testWidgets('missing model is actionable without starting or downloading', (
    tester,
  ) async {
    driver.available = false;
    await openEditor(tester);
    await openTranscription(tester);
    expect(find.text('需要离线识别模型'), findsOneWidget);
    expect(find.text('管理模型'), findsOneWidget);
    expect(driver.starts, 0);
    expect(writer.writes, 0);
  });
  testWidgets(
    'cancellation and empty speech preserve the previous transcript',
    (tester) async {
      await openEditor(tester, transcript: '已经保存');
      await openTranscription(tester);
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-audio-transcription')));
      await tester.pumpAndSettle();
      expect(find.text('已取消转写'), findsOneWidget);
      expect(writer.note.assets.single.transcript, '已经保存');
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      driver.fail(TranscriptionFailure.noSpeech);
      await tester.pumpAndSettle();
      expect(find.text('未识别到清晰语音，请检查录音后重试'), findsOneWidget);
      expect(find.text('已经保存'), findsOneWidget);
      expect(find.textContaining('/private/path'), findsNothing);
      expect(writer.writes, 0);
    },
  );

  testWidgets(
    'save failure keeps the result for copying without caching it as saved',
    (tester) async {
      await openEditor(tester, transcript: '旧转写');
      await openTranscription(tester);
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      writer.fail = true;
      await driver.finish('尚未保存的新转写');
      await tester.pumpAndSettle();
      expect(find.text('转写文字尚未保存，可复制文字或重试'), findsOneWidget);
      expect(find.text('尚未保存的新转写'), findsOneWidget);
      expect(writer.note.assets.single.transcript, '旧转写');
      final editor = tester.widget<NoteQuillEditor>(
        find.byType(NoteQuillEditor),
      );
      expect(editor.controller.asset(asset.id)!.transcript, '旧转写');
      writer.fail = false;
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      await driver.finish('重试完成');
      await tester.pumpAndSettle();
      expect(writer.note.assets.single.transcript, '重试完成');
    },
  );

  for (final removed in [true, false]) {
    testWidgets(
      'late transcript rejects ${removed ? 'removed' : 'replaced'} audio',
      (tester) async {
        await openEditor(tester);
        await openTranscription(tester);
        final controller = tester
            .widget<NoteQuillEditor>(find.byType(NoteQuillEditor))
            .controller;
        if (removed) {
          controller.removeAsset(asset.id);
        } else {
          controller.updateAsset(
            asset.copyWith(storageKey: 'notes/audio/new.wav'),
          );
        }
        await driver.finish('过期结果');
        await tester.pumpAndSettle();
        expect(driver.job!.status, TranscriptionStatus.failed);
        expect(writer.writes, 0);
        expect(controller.asset(asset.id)!.transcript, isNull);
      },
    );
  }

  testWidgets(
    'private recognition stays private and registration is released on disposal',
    (tester) async {
      await openEditor(tester, private: true);
      final id = writer.note.id;
      await openTranscription(tester);
      expect(driver.job!.privateSpace, isTrue);
      await driver.finish('隐私转写');
      await tester.pumpAndSettle();
      expect(writer.note.isPrivate, isTrue);
      expect(writer.note.assets.single.transcript, '隐私转写');
      expect(driver.sinks[id], isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(driver.sinks[id], isNull);
    },
  );

  testWidgets('cannot cancel while the transcript save is committing', (
    tester,
  ) async {
    await openEditor(tester);
    await openTranscription(tester);
    writer.gate = Completer<void>();
    final saving = driver.finish('保存中的文字');
    await tester.pump();
    await tester.pump();
    expect(find.text('正在保存转写'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('cancel-audio-transcription')),
          )
          .onPressed,
      isNull,
    );
    writer.gate!.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(driver.job!.status, TranscriptionStatus.completed);
  });

  testWidgets(
    'model management can return to recognition on a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      driver.available = false;
      var managed = 0;
      var starts = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => NoteAudioTranscriptionSheet(
                    driver: driver,
                    noteId: NoteId.generate(),
                    asset: asset,
                    onStart: () async => starts++,
                    onManageModels: () async {
                      managed++;
                      driver.available = true;
                    },
                  ),
                ),
              ),
            ),
          ),
          locale: const Locale('en'),
          scale: 2,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('start-audio-transcription')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-audio-transcription')));
      await tester.pumpAndSettle();
      expect(managed, 1);
      expect(starts, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('zh'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    quill.FlutterQuillLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

final class _Writer implements NoteEditorWriter {
  late Note note;
  bool fail = false;
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<Note> create(Note value) => update(value);
  @override
  Future<Note> update(Note value) async {
    writes++;
    await gate?.future;
    if (fail) throw StateError('Disk full');
    if (value.revision != note.revision) throw StateError('Stale revision');
    return note = value.copyWith(revision: value.revision + 1);
  }

  @override
  Future<void> deletePermanently(Note value) async {}
}

final class _Transcriptions extends ChangeNotifier
    implements NoteTranscriptionDriver {
  bool available = true;
  int starts = 0;
  TranscriptionJob? job;
  final Map<NoteId, NoteTranscriptSink> sinks = {};
  @override
  Future<bool> isModelAvailable() async => available;
  @override
  TranscriptionJob? jobFor(String storageKey) =>
      job?.filePath == storageKey ? job : null;
  @override
  void registerEditor(NoteId id, NoteTranscriptSink sink) => sinks[id] = sink;
  @override
  void unregisterEditor(NoteId id, NoteTranscriptSink sink) {
    if (sinks[id] == sink) sinks.remove(id);
  }

  @override
  Future<Note> writeTranscript(NoteTranscriptResult result) =>
      sinks[result.noteId]!(result);

  @override
  Future<void> start({
    required NoteId noteId,
    required NoteAsset attachment,
    bool privateSpace = false,
    int? speakerCount,
  }) async {
    if (job?.isRunning == true) return;
    starts++;
    job = TranscriptionJob(
      key: '$starts',
      noteId: noteId,
      assetId: attachment.id,
      filePath: attachment.storageKey,
      privateSpace: privateSpace,
      status: TranscriptionStatus.recognizing,
      progress: .2,
    );
    notifyListeners();
  }

  void progress(String text, double value) {
    job!.partialText = text;
    job!.progress = value;
    notifyListeners();
  }

  Future<void> finish(String text) async {
    final current = job!;
    current.partialText = text;
    current.status = TranscriptionStatus.saving;
    notifyListeners();
    try {
      await sinks[current.noteId]!(
        NoteTranscriptResult(
          noteId: current.noteId,
          assetId: current.assetId,
          storageKey: current.filePath,
          transcript: text,
          engine: 'test-sensevoice',
          at: DateTime.utc(2026, 8, 27),
          privateSpace: current.privateSpace,
        ),
      );
      current.status = TranscriptionStatus.completed;
    } catch (_) {
      current.status = TranscriptionStatus.failed;
      current.failure = TranscriptionFailure.saving;
    }
    notifyListeners();
  }

  void fail(TranscriptionFailure failure) {
    job!.status = TranscriptionStatus.failed;
    job!.failure = failure;
    job!.errorMessage = 'native error /private/path';
    notifyListeners();
  }

  @override
  void cancel(String storageKey) {
    if (job!.status == TranscriptionStatus.saving) return;
    job!.status = TranscriptionStatus.canceled;
    notifyListeners();
  }
}
