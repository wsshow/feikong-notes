import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/pages/file_manager_page.dart';
import 'package:fknotes/models/library_file.dart';
import 'package:fknotes/pages/file_preview_page.dart';
import 'package:fknotes/providers/file_library_controller.dart';
import 'package:fknotes/services/file_library_store.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/app_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FileLibraryStore store;
  late FileLibraryController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-manager-ui');
    store = FileLibraryStore(rootPath: root.path);
    controller = FileLibraryController(store: store);
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await root.delete(recursive: true);
  });
  XFile file(String name) => XFile.fromData(
    Uint8List.fromList([65, 66, 67]),
    name: name,
    path: '/source/$name',
  );
  Future<void> tapIo(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (var i = 0; i < 200 && controller.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.busy, false);
    });
    await tester.pumpAndSettle();
  }

  Widget app(
    Widget child, {
    double scale = 1,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh'),
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(AppThemeCatalog.defaultStyle, brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );

  testWidgets(
    'imports files, searches, previews, selects and restores from trash',
    (tester) async {
      await tester.pumpWidget(
        app(
          FileManagerPage(
            controller: controller,
            pickFiles: () async => [file('meeting.txt'), file('slides.pptx')],
            previewBuilder: (entry, store) => Scaffold(
              appBar: AppBar(title: Text(entry.name)),
              body: const Text('Preview'),
            ),
          ),
        ),
      );
      await tester.runAsync(() => controller.load());
      await tester.pumpAndSettle();
      await tapIo(tester, find.byKey(const Key('file-manager-import-button')));
      await tester.pumpAndSettle();
      expect(find.text('meeting.txt'), findsOneWidget);
      expect(find.text('slides.pptx'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('file-manager-search')),
        'meeting',
      );
      await tester.pumpAndSettle();
      expect(find.text('slides.pptx'), findsNothing);
      await tapIo(tester, find.text('meeting.txt'));
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final entry = controller.entries.singleWhere(
        (e) => e.name == 'meeting.txt',
      );
      await tester.longPress(find.text('meeting.txt'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await tapIo(tester, find.text('移入回收站'));
      await tester.pumpAndSettle();
      expect(controller.isTrashed(controller.byId[entry.id]!), true);
      await tapIo(tester, find.byKey(const ValueKey('file-location-trash')));
      await tester.pumpAndSettle();
      await tapIo(tester, find.text('meeting.txt'));
      await tester.pumpAndSettle();
      await tapIo(tester, find.text('恢复'));
      await tester.pumpAndSettle();
      expect(controller.isTrashed(controller.byId[entry.id]!), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch write passes all selected file formats into one note', (
    tester,
  ) async {
    final entries = await tester.runAsync(
      () async => [
        await store.importFile(file('计划.pdf')),
        await store.importFile(file('素材.custom')),
      ],
    );
    await tester.runAsync(() => controller.load());
    List<LibraryFile>? selected;
    await tester.pumpWidget(
      app(
        FileManagerPage(
          controller: controller,
          onWriteNote: (files) async {
            selected = files;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('素材.custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划.pdf'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('记一笔'));
      // Writing refreshes the index without setting controller.busy. Queue a
      // read after that refresh so real file IO finishes before settling frames.
      await controller.load();
    });
    await tester.pumpAndSettle();
    expect(selected!.map((file) => file.id).toList(), [
      entries![1].id,
      entries[0].id,
    ]);
    expect(find.text('已选择 2 项'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'search hands its keyboard to the folder form and gets it back on cancel',
    (tester) async {
      await tester.pumpWidget(app(FileManagerPage(controller: controller)));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('file-manager-search'));
      await tester.enterText(search, '保留搜索');
      await tester.pump();
      expect(tester.testTextInput.isVisible, true);
      tester.testTextInput.log.clear();
      await tester.tap(find.byTooltip('新建文件夹'));
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.testTextInput.isVisible, true);
        expect(
          tester.testTextInput.log.where(
            (call) => call.method == 'TextInput.hide',
          ),
          isEmpty,
        );
      }
      final form = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('file-name-input')),
          matching: find.byType(EditableText),
        ),
      );
      expect(form.focusNode.hasFocus, true);
      tester.testTextInput.log.clear();
      await tester.tap(find.text('取消'));
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.testTextInput.isVisible, true);
        expect(
          tester.testTextInput.log.where(
            (call) => call.method == 'TextInput.hide',
          ),
          isEmpty,
        );
      }
      final source = tester.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(source.focusNode.hasFocus, true);
      expect(source.controller.text, '保留搜索');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folder creation and system back navigate the hierarchy', (
    tester,
  ) async {
    final folder = await tester.runAsync(() => store.createFolder('Projects'));
    await tester.runAsync(
      () => store.importFile(file('notes.txt'), parentId: folder!.id),
    );
    await tester.runAsync(() => controller.load());
    await tester.pumpWidget(app(FileManagerPage(controller: controller)));
    await tester.pumpAndSettle();
    await tapIo(tester, find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.folderId, isNull);
    expect(find.text('notes.txt'), findsNothing);
    await tapIo(tester, find.byTooltip('新建文件夹'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.byKey(const Key('file-name-input')), 'Archive');
    await tapIo(tester, find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'top back returns home in one tap from nested folders and search',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await store.createFolder('Projects');
        final child = await store.createFolder('Reports', parentId: folder.id);
        final nested = await store.createFolder('2026', parentId: child.id);
        await store.importFile(file('notes.txt'), parentId: nested.id);
        await controller.load();
      });
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FileManagerPage(controller: controller),
                  ),
                ),
                child: const Text('Open files from home'),
              ),
            ),
          ),
        ),
      );
      await tapIo(tester, find.text('Open files from home'));
      for (final name in ['Projects', 'Reports', '2026']) {
        await tapIo(tester, find.text(name));
      }
      await tester.enterText(
        find.byKey(const Key('file-manager-search')),
        'notes',
      );
      await tester.pumpAndSettle();
      expect(find.text('notes.txt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('file-manager-back')));
      await tester.pumpAndSettle();
      expect(find.byType(FileManagerPage), findsNothing);
      expect(find.text('Open files from home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('more menu omits retry; failed loading can still be retried', (
    tester,
  ) async {
    await tester.pumpWidget(app(FileManagerPage(controller: controller)));
    await tester.pumpAndSettle();
    final menu = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(AppAnchoredMenuButton<String>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await File('${root.path}/index.json').writeAsString('invalid index');
      await controller.load();
    });
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await tester.runAsync(() => File('${root.path}/index.json').delete());
    await tapIo(tester, find.text('重试'));
    expect(find.text('重试'), findsNothing);
    expect(controller.error, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow screens, dark mode and large text keep list and grid usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () =>
            store.importFile(file('a-very-long-filename-for-a-document.docx')),
      );
      await tester.runAsync(() => controller.load());
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          app(
            FileManagerPage(controller: controller),
            scale: scale,
            brightness: Brightness.dark,
          ),
        );
        await tester.runAsync(() => controller.load());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tapIo(tester, find.byKey(const Key('file-manager-view')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tapIo(tester, find.byTooltip('新建文件夹'));
      tester.view.viewInsets = FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tapIo(tester, find.text('取消'));
    },
  );

  testWidgets(
    'grid cards give images full-width previews and keep file information together',
    (tester) async {
      final entries = await tester.runAsync(
        () async => [
          await store.importFile(XFile('assets/brand/fknotes_mark.png')),
          await store.importFile(file('a-document-with-a-long-filename.xml')),
        ],
      );
      await tester.runAsync(() => controller.load());
      controller.toggleGrid();
      await tester.pumpWidget(app(FileManagerPage(controller: controller)));
      await tester.pumpAndSettle();
      for (final entry in entries!) {
        final card = tester.getRect(
          find.byKey(ValueKey('library-file-${entry.id}')),
        );
        final preview = tester.getRect(
          find.byKey(ValueKey('file-grid-preview-${entry.id}')),
        );
        final title = tester.getRect(
          find.byKey(ValueKey('file-grid-name-${entry.id}')),
        );
        final metadata = tester.getRect(
          find.byKey(ValueKey('file-grid-metadata-${entry.id}')),
        );
        final menu = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey('library-file-${entry.id}')),
            matching: find.byType(AppAnchoredMenuButton<String>),
          ),
        );
        expect(preview.width, closeTo(card.width, 1));
        expect(preview.height, greaterThan(80));
        expect(title.top - preview.bottom, inInclusiveRange(10, 14));
        expect(metadata.top - title.bottom, inInclusiveRange(4, 8));
        expect(menu.bottom, lessThanOrEqualTo(preview.bottom));
      }
      final thumbnail = tester.widget<Image>(
        find.byKey(ValueKey('file-grid-thumbnail-${entries.first.id}')),
      );
      expect(thumbnail.fit, BoxFit.cover);
      final image = thumbnail.image as ResizeImage;
      expect(image.width, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Office files offer system preview without sending content online',
    (tester) async {
      final entry = await tester.runAsync(
        () => store.importFile(file('deck.pptx')),
      );
      await tester.pumpWidget(
        app(
          FilePreviewPage(entry: entry!, store: store),
          locale: const Locale('en'),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Open this format with a compatible app'),
        findsOneWidget,
      );
      expect(find.text('Open with another app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
