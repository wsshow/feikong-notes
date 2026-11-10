import 'dart:async';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/services/ocr_service.dart';
import 'package:fknotes/widgets/note_image_ocr_sheet.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Writer writer;
  late NoteAsset asset;

  setUp(() {
    final now = DateTime.utc(2026, 8, 27);
    asset = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/ocr.png',
      originalName: 'ocr.png',
      byteLength: 10,
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    writer = _Writer();
  });

  Future<void> openEditor(
    WidgetTester tester,
    NoteImageTextRecognizer recognize, {
    NoteAsset? initialAsset,
    bool missingPath = false,
  }) async {
    final image = initialAsset ?? asset;
    writer.note = Note.newDraft().copyWith(
      title: '图片 OCR',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('原有正文\n')
          ..insert(NoteEmbed.attachment(image.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [image],
      revision: 1,
    );
    await tester.pumpWidget(
      _app(
        NoteQuillEditorPage(
          initialNote: writer.note,
          writerLoader: () async => writer,
          recognizeImageText: recognize,
          resolveImage: (_) => null,
          resolveAssetPath: (_) => missingPath ? null : '/managed/original.png',
          autosaveDelay: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openOcr(WidgetTester tester) async {
    final editor = tester.widget<NoteQuillEditor>(find.byType(NoteQuillEditor));
    unawaited(editor.onEditImage!(editor.controller.asset(asset.id)!));
    await tester.pumpAndSettle();
    expect(find.text('修改标题'), findsOneWidget);
    expect(find.byKey(const Key('replace-image-from-gallery')), findsOneWidget);
    expect(find.byKey(const Key('replace-image-from-camera')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recognize-image-text')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'OCR uses the original image, saves metadata and copies on demand',
    (tester) async {
      final paths = <String>[];
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
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
      await openEditor(tester, (path) async {
        paths.add(path);
        return OcrResult.recognized('  中文 OCR\nEnglish 123  ');
      });
      final original = writer.note!.document.toDelta().toJson();
      await openOcr(tester);
      await tester.pumpAndSettle();

      expect(paths, ['/managed/original.png']);
      expect(find.text('中文 OCR\nEnglish 123'), findsOneWidget);
      expect(writer.note!.assets.single.ocrText, '中文 OCR\nEnglish 123');
      expect(writer.note!.searchText, contains('English 123'));
      expect(writer.note!.document.toDelta().toJson(), original);
      expect(clipboard, isEmpty);
      await tester.tap(find.byKey(const Key('copy-image-ocr')));
      await tester.pumpAndSettle();
      expect(clipboard, ['中文 OCR\nEnglish 123']);
      expect(find.text('识别文字已复制'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-image-ocr')));
      await tester.pumpAndSettle();
      await openOcr(tester);
      await tester.pumpAndSettle();
      expect(
        paths,
        hasLength(1),
        reason: 'Reopening uses the saved OCR result.',
      );
      expect(find.text('中文 OCR\nEnglish 123'), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-image-ocr')));
      await tester.pumpAndSettle();
      expect(paths, hasLength(2));
    },
  );

  testWidgets('recognition is single flight and retry recovers from no text', (
    tester,
  ) async {
    final pending = Completer<OcrResult>();
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
      return calls == 1 ? pending.future : OcrResult.recognized('重试成功');
    });
    await openOcr(tester);
    expect(find.text('正在识别…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('retry-image-ocr')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('copy-image-ocr')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('retry-image-ocr')));
    await tester.pump();
    expect(calls, 1);
    pending.complete(const OcrResult.noText());
    await tester.pumpAndSettle();
    expect(find.text('未识别到清晰文字'), findsOneWidget);
    expect(writer.writes, 0);
    await tester.tap(find.byKey(const Key('retry-image-ocr')));
    await tester.pumpAndSettle();
    expect(writer.note!.assets.single.ocrText, '重试成功');
  });

  for (final failure in [
    OcrResult.failed('native error /private/path'),
    const OcrResult.noText(),
  ]) {
    testWidgets('${failure.status} preserves cached OCR text', (tester) async {
      var calls = 0;
      await openEditor(tester, (_) async {
        calls++;
        return failure;
      }, initialAsset: asset.copyWith(ocrText: '已保存的文字'));
      await openOcr(tester);
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.byKey(const Key('retry-image-ocr')));
      await tester.pumpAndSettle();
      expect(find.text('已保存的文字'), findsOneWidget);
      expect(writer.note!.assets.single.ocrText, '已保存的文字');
      expect(writer.writes, 0);
      expect(
        find.text(failure.didFail ? '文字识别暂时不可用，请重试' : '未识别到清晰文字'),
        findsOneWidget,
      );
      expect(find.textContaining('/private/path'), findsNothing);
    });
  }

  testWidgets(
    'save failure keeps result available and retries without rerunning OCR',
    (tester) async {
      var calls = 0;
      await openEditor(tester, (_) async {
        calls++;
        return OcrResult.recognized('等待保存');
      }, initialAsset: asset.copyWith(ocrText: '之前的文字'));
      writer.fail = true;
      await openOcr(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retry-image-ocr')));
      await tester.pumpAndSettle();
      expect(find.text('识别文字尚未保存，请重试'), findsOneWidget);
      expect(find.text('等待保存'), findsOneWidget);
      expect(writer.note!.assets.single.ocrText, '之前的文字');
      final editor = tester.widget<NoteQuillEditor>(
        find.byType(NoteQuillEditor),
      );
      expect(editor.controller.asset(asset.id)!.ocrText, '之前的文字');
      writer.fail = false;
      await tester.tap(find.byKey(const Key('retry-image-ocr')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(writer.note!.assets.single.ocrText, '等待保存');
      expect(find.text('识别文字尚未保存，请重试'), findsNothing);
    },
  );

  testWidgets('clipboard failure is visible in the sheet and can be retried', (
    tester,
  ) async {
    var failCopy = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && failCopy) {
          throw PlatformException(code: 'unavailable');
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
    await openEditor(
      tester,
      (_) async => const OcrResult.noText(),
      initialAsset: asset.copyWith(ocrText: '复制这段文字'),
    );
    await openOcr(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-image-ocr')));
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    expect(find.text('识别文字已复制'), findsNothing);
    failCopy = false;
    await tester.tap(find.byKey(const Key('copy-image-ocr')));
    await tester.pumpAndSettle();
    expect(find.text('识别文字已复制'), findsOneWidget);
    expect(find.text('复制失败，请重试'), findsNothing);
    expect(writer.writes, 0);
  });

  testWidgets('missing original path does not call OCR', (tester) async {
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
      return const OcrResult.noText();
    }, missingPath: true);
    await openOcr(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const Key('image-ocr-status')), findsOneWidget);
    expect(find.text('未识别到清晰文字'), findsNothing);
    expect(writer.writes, 0);
  });

  for (final change in ['replaced', 'removed', 'dismissed', 'disposed']) {
    testWidgets('late OCR result is ignored after image/sheet is $change', (
      tester,
    ) async {
      final pending = Completer<OcrResult>();
      await openEditor(tester, (_) => pending.future);
      await openOcr(tester);
      final editor = tester.widget<NoteQuillEditor>(
        find.byType(NoteQuillEditor),
      );
      switch (change) {
        case 'replaced':
          editor.controller.updateAsset(
            asset.copyWith(storageKey: 'notes/images/replacement.png'),
          );
        case 'removed':
          editor.controller.removeAsset(asset.id);
        case 'dismissed':
          await tester.tap(find.byKey(const Key('close-image-ocr')));
          await tester.pump();
        case 'disposed':
          await tester.pumpWidget(const SizedBox());
      }
      pending.complete(OcrResult.recognized('不能写入旧图片'));
      await tester.pumpAndSettle();
      expect(writer.writes, 0);
      if (change == 'replaced' || change == 'removed') {
        expect(find.text('图片已更改或删除，请重新打开 OCR'), findsOneWidget);
        expect(editor.controller.asset(asset.id)!.ocrText, isNull);
      } else {
        expect(find.byType(NoteImageOcrSheet), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'OCR results and actions remain scrollable on a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => NoteImageOcrSheet(
                    initialText: List.filled(
                      100,
                      'Long English and 中文 text',
                    ).join('\n'),
                    recognizeText: () async => const OcrResult.noText(),
                    saveText: (_) async => NoteImageOcrSaveStatus.saved,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
          locale: const Locale('en'),
          scale: 2,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('copy-image-ocr')));
      await tester.pumpAndSettle();
      expect(find.text('Copy all'), findsOneWidget);
      expect(find.text('Recognize again'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('copy-image-ocr'))).height,
        greaterThanOrEqualTo(48),
      );
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
  Note? note;
  int writes = 0;
  bool fail = false;

  @override
  Future<Note> create(Note value) => update(value);

  @override
  Future<Note> update(Note value) async {
    writes++;
    if (fail) throw StateError('Disk full');
    return note = value.copyWith(revision: value.revision + 1);
  }

  @override
  Future<void> deletePermanently(Note value) async => note = null;
}
