import 'dart:async';

import 'package:fknotes/app.dart';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_calendar_page.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/pages/quill_home_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/widgets/app_update_coordinator.dart';
import 'package:fknotes/widgets/navigation_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late _HomeStore store;
  late NoteLibraryController controller;

  setUp(() {
    final base = DateTime.utc(2026, 7, 23, 8);
    store = _HomeStore([
      _note('较早置顶', updatedAt: base, pinned: true),
      _note('最新笔记', updatedAt: base.add(const Duration(hours: 2))),
    ]);
    controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
  });

  testWidgets('home is the single note-library destination', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
          noteLoader: store.get,
          assistantBuilder: (context, onOpenNote) =>
              _testAssistant(context, onOpenNote, store.notes.last),
        ),
      ),
    );
    await _pump(tester);

    expect(find.byType(NoteLibraryPage), findsOneWidget);
    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-list')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-navigation')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('quill-home-assistant')), findsOneWidget);
    expect(
      find.byKey(const Key('delta-library-open-calendar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('delta-library-open-tag-groups')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('delta-library-open-settings')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delta-library-select-notes')), findsNothing);
    expect(find.byType(TagOutlineIcon), findsOneWidget);
    expect(find.byType(SettingsOutlineIcon), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    expect(find.byIcon(Icons.hexagon_outlined), findsNothing);
    expect(find.text('最新笔记'), findsOneWidget);
    expect(find.text('较早置顶'), findsOneWidget);
    final newNoteSize = tester.getSize(
      find.byKey(const Key('quill-home-new-note')),
    );
    expect(newNoteSize.height, 52);
    expect(newNoteSize.width, greaterThan(200));
  });

  testWidgets('calendar opens full screen and returns home after a search', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);
    await controller.search('最新');
    await _pump(tester);
    expect(controller.query, '最新');
    await tester.tap(find.byKey(const Key('delta-library-open-calendar')));
    await _pump(tester);
    expect(controller.query, isEmpty);
    expect(find.byType(NoteCalendarPage), findsOneWidget);
    expect(find.byKey(const Key('calendar-month-view')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byKey(const Key('calendar-view-year')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('calendar-back-home')));
    await tester.pumpAndSettle();
    expect(find.byType(NoteCalendarPage), findsNothing);
    expect(find.byType(NoteLibraryPage), findsOneWidget);
    expect(find.text('最新笔记'), findsOneWidget);
  });

  testWidgets('settings opens as a full-screen page', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-open-settings')));
    await _pump(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('settings-back')), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('本地优先'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('纸短情长'), findsOneWidget);
    final page = find.byKey(const Key('settings-page'));
    final settingsBackground = tester.widget<Scaffold>(page).backgroundColor;
    final homeBackground = tester
        .widget<Scaffold>(
          find.descendant(
            of: find.byType(NoteLibraryPage, skipOffstage: false),
            matching: find.byType(Scaffold, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        .backgroundColor;
    expect(settingsBackground, homeBackground);
    final summary = tester.widget<Container>(
      find.byKey(const Key('settings-data-summary')),
    );
    final summaryDecoration = summary.decoration! as BoxDecoration;
    expect(summaryDecoration.color, settingsBackground);
    expect(summaryDecoration.borderRadius, isNotNull);
    expect(summaryDecoration.border, isNull);
    // A soft lower shadow and a tight contact shadow separate white surfaces.
    expect(summaryDecoration.boxShadow, [
      BoxShadow(
        color: AppPalette.paperLight.shadow.withValues(alpha: .06),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
      BoxShadow(
        color: AppPalette.paperLight.shadow.withValues(alpha: .04),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ]);
    // The data overview is the only raised surface; settings actions stay flat.
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(of: page, matching: find.byType(DecoratedBox)),
          )
          .where(
            (box) =>
                box.decoration is BoxDecoration &&
                ((box.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                    false),
          ),
      hasLength(1),
    );
    expect(
      tester
          .widgetList<Material>(
            find.descendant(of: page, matching: find.byType(Material)),
          )
          .every((material) => material.elevation == 0),
      isTrue,
    );
    final exportRow = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '导出完整备份'),
    );
    expect(exportRow.leading, isNull);
    expect(
      tester
          .widgetList<ListTile>(
            find.descendant(of: page, matching: find.byType(ListTile)),
          )
          .every((row) => row.leading == null),
      isTrue,
    );
    expect(exportRow.contentPadding, EdgeInsets.zero);
    expect(
      tester
          .widgetList<Divider>(
            find.descendant(of: page, matching: find.byType(Divider)),
          )
          .every((divider) => divider.indent == null || divider.indent == 0),
      isTrue,
    );
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('导出完整备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.text('云同步'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-back')));
    await _pump(tester);
    expect(find.byType(NoteLibraryPage), findsOneWidget);
  });

  testWidgets('editorial settings use layered paper sections', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
        child: QuillHomePage(
          controller: controller,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);
    await tester.tap(find.byKey(const Key('delta-library-open-settings')));
    await _pump(tester);

    final page = find.byKey(const Key('settings-page'));
    final summary = tester.widget<Container>(
      find.byKey(const Key('settings-data-summary')),
    );
    final decoration = summary.decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.editorialJournalLight.surface);
    expect(decoration.border, isNotNull);
    expect(summary.foregroundDecoration, isNull);
    expect(
      tester
          .widgetList<Material>(
            find.descendant(of: page, matching: find.byType(Material)),
          )
          .any((material) => material.elevation > 0),
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, '导出完整备份'))
          .contentPadding,
      const EdgeInsets.symmetric(horizontal: 16),
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'flat settings stays scrollable with large ${locale.languageCode} text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final l10n = lookupAppLocalizations(locale);
        await tester.pumpWidget(
          _TestApp(
            locale: locale,
            child: QuillHomePage(
              controller: controller,
              dataSizeLoader: () async => 2048,
              editorBuilder: _testEditor,
              updateSupported: true,
              updateChecker: (_) async => AppUpdateCheckResult.latest,
            ),
          ),
        );
        await _pump(tester);
        await tester.tap(find.byKey(const Key('delta-library-open-settings')));
        await _pump(tester);
        expect(tester.takeException(), isNull);
        final list = find.descendant(
          of: find.byKey(const Key('settings-list')),
          matching: find.byType(Scrollable),
        );
        final update = find.byKey(const Key('check-for-updates'));
        await tester.scrollUntilVisible(update, 350, scrollable: list);
        await tester.ensureVisible(update);
        await tester.pumpAndSettle();
        await tester.tap(update);
        await _pump(tester);
        expect(find.text(l10n.latestVersionInstalled), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await _pump(tester);
        expect(find.byType(NoteLibraryPage), findsOneWidget);
      },
    );
  }

  testWidgets('update check reports progress, failure and latest inline', (
    tester,
  ) async {
    final result = Completer<AppUpdateCheckResult>();
    var attempts = 0;
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
          updateSupported: true,
          updateChecker: (_) {
            attempts += 1;
            return attempts == 1
                ? result.future
                : Future.value(AppUpdateCheckResult.latest);
          },
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-open-settings')));
    await _pump(tester);
    final updateRow = find.byKey(const Key('check-for-updates'));
    await tester.scrollUntilVisible(
      updateRow,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(
      tester.element(updateRow),
      alignment: 0.5,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(updateRow);
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    expect(
      find.descendant(
        of: updateRow,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    result.complete(AppUpdateCheckResult.failed);
    await _pump(tester);
    expect(find.text('暂时无法检查更新，请稍后再试'), findsOneWidget);
    expect(find.byKey(const Key('app-update-sheet')), findsNothing);

    await tester.tap(updateRow);
    await _pump(tester);
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant destination opens the local assistant route', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
          noteLoader: store.get,
          assistantBuilder: (context, onOpenNote) =>
              _testAssistant(context, onOpenNote, store.notes.last),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('quill-home-assistant')));
    await _pump(tester);
    expect(find.text('全新 Delta 本地助手'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-assistant-source')));
    await _pump(tester);
    expect(find.text('编辑 最新笔记'), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await _pump(tester);
  });

  testWidgets('new-note action converges on the Delta editor', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    await tester.pumpAndSettle();
    expect(find.text('新的 Delta 笔记'), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await _pump(tester);
    expect(find.byType(NoteLibraryPage), findsOneWidget);
  });

  testWidgets('returning from a new note keeps the search keyboard closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search')));
    await tester.pump();
    expect(_searchEditable(tester).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await tester.pumpAndSettle();

    expect(_searchEditable(tester).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('bulk selection hides the unique creation action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.longPress(
      find.byKey(ValueKey('delta-note-${store.notes.first.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delta-library-selection-header')), findsOne);
    expect(find.byKey(const Key('quill-home-new-note')), findsNothing);
    expect(find.byKey(const Key('quill-home-navigation')), findsNothing);

    await tester.tap(find.byKey(const Key('delta-library-exit-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-navigation')), findsNothing);
  });
}

Widget _testEditor(BuildContext context, Note? note) => Scaffold(
  body: Center(
    child: TextButton(
      key: const Key('close-test-editor'),
      onPressed: () => Navigator.pop(context),
      child: Text(note == null ? '新的 Delta 笔记' : '编辑 ${note.title}'),
    ),
  ),
);

Widget _testAssistant(
  BuildContext context,
  Future<void> Function(LocalChatNoteContext source) onOpenNote,
  Note sourceNote,
) => Scaffold(
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('全新 Delta 本地助手'),
        TextButton(
          key: const Key('open-assistant-source'),
          onPressed: () => onOpenNote(
            LocalChatNoteContext(
              noteId: sourceNote.id,
              title: sourceNote.title,
              scope: LocalChatNoteScope.fullNote,
              content: 'Delta 正文',
              updatedAt: DateTime.utc(2026, 7, 23),
            ),
          ),
          child: const Text('打开来源'),
        ),
      ],
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

EditableText _searchEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('delta-library-search')),
        matching: find.byType(EditableText),
      ),
    );

final class _HomeStore implements NoteLibraryStore {
  _HomeStore(this.notes);

  final List<Note> notes;

  Future<Note?> get(NoteId id) async {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) async => notes
      .where((note) => note.searchText.contains(query))
      .toList(growable: false);

  @override
  Future<Note> update(Note note) async {
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

Note _note(String title, {required DateTime updatedAt, bool pinned = false}) =>
    Note(
      id: NoteId.generate(),
      title: title,
      document: NoteDocument.fromPlainText('Delta 正文'),
      isPinned: pinned,
      revision: 1,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

final class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.locale = const Locale('zh'),
    this.theme,
  });

  final Widget child;
  final Locale locale;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AppLocaleController(observePlatform: false),
      ),
      ChangeNotifierProvider(
        create: (_) => AppLockController(observeLifecycle: false),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      theme: theme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}
