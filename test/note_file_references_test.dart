import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_semantic_projection.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/app_overlay.dart';
import 'package:fknotes/widgets/note_file_reference_card.dart';
import 'package:fknotes/widgets/note_file_reference_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FileLibraryStore store;

  setUpAll(() async {
    final font = await rootBundle.load(
      'assets/fonts/source_han_serif/SourceHanSerifCN-VF.otf',
    );
    await (FontLoader('Roboto')..addFont(Future.value(font))).load();
    await (FontLoader(
      'Source Han Serif CN',
    )..addFont(Future.value(font))).load();
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('note-file-references');
    store = FileLibraryStore(rootPath: root.path);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<LibraryFile> file(String name, {String? parentId}) => store.importFile(
    XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: name,
      path: '/source/$name',
    ),
    parentId: parentId,
  );
  NoteFileReference reference(LibraryFile file) =>
      NoteFileReference(fileId: file.id, name: file.name, size: file.size);

  Widget app(
    Widget child, {
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(AppThemeStyle.editorialJournal, brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('项目资料')),
      body: child,
    ),
  );

  Future<void> settleIo(WidgetTester tester) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (attempt > 5 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  test(
    'group insertion survives snapshots, undo and redo without attachment copies',
    () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('正文'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final ref = NoteFileReference(
        fileId: NoteAttachmentId.generate().value,
        name: '草案.unknown',
        size: 8,
      );
      controller.insertFileReferences([ref]);
      expect(controller.snapshot().assets, isEmpty);
      final first = controller.snapshot().document;
      expect(first.toJsonString(), contains(ref.fileId));
      final projection = NoteSemanticProjection.fromNote(
        Note.newDraft().copyWith(document: first),
      );
      expect(projection.bodyText, '正文');
      expect(projection.assistantSource(), contains('文件引用：草案.unknown'));
      controller.quillController.undo();
      expect(
        controller.snapshot().document.toJsonString(),
        isNot(contains(ref.fileId)),
      );
      controller.quillController.redo();
      expect(controller.snapshot().document, first);
      controller.removeEmbedAt(0);
      expect(
        controller.snapshot().document.toJsonString(),
        isNot(contains(ref.fileId)),
      );
    },
  );

  testWidgets(
    'compact card expands all files with current names and unavailable references',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = await tester.runAsync(
        () async => [
          await file('活动策划.pdf'),
          await file('预算表.xlsx'),
          await file('参考照片.png'),
          await file('早期草稿.zip'),
        ],
      );
      final references = files!.map(reference).toList();
      await tester.runAsync(() async {
        await store.rename(files.first.id, '活动策划 · 定稿.pdf');
        await store.trash({files.last.id});
      });
      await tester.pumpWidget(
        app(
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '把灵感和资料放在一起，慢慢写成一份完整的计划。',
                  style: TextStyle(fontSize: 17, height: 1.8),
                ),
                const SizedBox(height: 16),
                NoteFileReferenceCard(
                  references: references,
                  store: store,
                  previewBuilder: (entry, _) => Scaffold(
                    appBar: AppBar(title: Text(entry.name)),
                    body: const Text('文件预览'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NoteFileReferenceCard), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      await tester.tap(find.byKey(const Key('note-file-reference-open')));
      await settleIo(tester);
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(find.text('活动策划 · 定稿.pdf'), findsOneWidget);
      expect(find.text('文件已移除或在回收站'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(ValueKey('note-file-reference-${files.last.id}')),
            )
            .enabled,
        false,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/note_file_references.png'),
      );
      await tester.tap(find.text('活动策划 · 定稿.pdf'));
      await settleIo(tester);
      expect(find.text('文件预览'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settleIo(tester);
      expect(find.byKey(const Key('note-file-reference-list')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await store.restore({files.last.id});
        await store.fileFor(files[1]).delete();
      });
      await tester.tap(find.byKey(const Key('note-file-reference-open')));
      await settleIo(tester);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(ValueKey('note-file-reference-${files.last.id}')),
            )
            .enabled,
        true,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(ValueKey('note-file-reference-${files[1].id}')),
            )
            .enabled,
        false,
      );
    },
  );

  testWidgets(
    'picker keeps multiple selections across search and directories',
    (tester) async {
      final files = await tester.runAsync(() async {
        final folder = await store.createFolder('项目');
        return [
          await file('计划.docx'),
          await file('明细.xlsx', parentId: folder.id),
          await file('隐藏.zip'),
        ];
      });
      await tester.runAsync(() => store.trash({files!.last.id}));
      List<NoteFileReference>? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AppOverlay.bottomSheet<List<NoteFileReference>>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => NoteFileReferencePicker(store: store),
                );
              },
              child: const Text('选择文件'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择文件'));
      await settleIo(tester);
      expect(find.text('隐藏.zip'), findsNothing);
      await tester.tap(find.text('明细.xlsx'));
      await tester.enterText(
        find.byKey(const Key('file-reference-search')),
        '计划',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('计划.docx'));
      await tester.pump();
      expect(find.text('引用所选文件（2）'), findsOneWidget);
      tester.testTextInput.hide();
      await tester.tap(find.byKey(const Key('file-reference-submit')));
      await settleIo(tester);
      expect(result!.map((file) => file.fileId).toList(), [
        files![1].id,
        files[0].id,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker imports arbitrary files, selects the batch and supports large dark text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppOverlay.bottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => NoteFileReferencePicker(
                  store: store,
                  pickFiles: () async => [
                    XFile.fromData(
                      Uint8List.fromList([1]),
                      name: '模型.custom',
                      path: '/source/模型.custom',
                    ),
                    XFile.fromData(
                      Uint8List.fromList([2]),
                      name: '会议录音.wav',
                      path: '/source/会议录音.wav',
                    ),
                  ],
                ),
              ),
              child: const Text('选择文件'),
            ),
          ),
          scale: 1.8,
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.text('选择文件'));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('file-reference-import')));
      await settleIo(tester);
      expect(find.text('模型.custom'), findsOneWidget);
      expect(find.text('会议录音.wav'), findsOneWidget);
      expect(find.text('引用所选文件（2）'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('file-reference-submit')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
