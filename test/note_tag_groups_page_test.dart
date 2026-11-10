import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_tag_groups_page.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/navigation_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('groups every note by tag and keeps an untagged group', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shared = _note('跨组笔记', tags: const ['工作', '项目']);
    final work = _note('工作记录', tags: const ['工作']);
    final untagged = _note('随手记');
    final store = _TagStore([shared, work, untagged]);
    final controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
    await controller.initialize();
    Note? openedNote;

    await tester.pumpWidget(
      _TestApp(
        child: NoteTagGroupsPage(
          controller: controller,
          onOpenNote: (note) async => openedNote = note,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tag-group-工作')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-group-项目')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-group-未标签')), findsOneWidget);
    expect(find.byType(TagOutlineIcon), findsNWidgets(3));
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    expect(find.text('2 条笔记'), findsOneWidget);

    expect(
      find.byKey(ValueKey('tag-note-工作-${shared.id.value}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('tag-note-项目-${shared.id.value}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('tag-note-未标签-${untagged.id.value}')),
      findsNothing,
    );
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(3));
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-group-notes-工作')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-groups-surface')), findsOneWidget);
    expect(
      find.byKey(ValueKey('tag-note-card-工作-${shared.id.value}')),
      findsNothing,
      reason: '紧凑展开态不应为每条笔记重复套卡片',
    );
    expect(
      find.byKey(ValueKey('tag-note-time-工作-${shared.id.value}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('tag-note-summary-工作-${shared.id.value}')),
      findsOneWidget,
    );

    final groupHeader = find.byKey(const ValueKey('tag-group-工作'));
    final noteRow = find.byKey(ValueKey('tag-note-工作-${shared.id.value}'));
    expect(
      find.descendant(of: groupHeader, matching: noteRow),
      findsNothing,
      reason: '展开后的笔记应当位于标签头下方，而非嵌套进交互头部',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey('tag-note-summary-工作-${shared.id.value}')),
          )
          .maxLines,
      1,
    );

    await tester.tap(noteRow);
    await tester.pumpAndSettle();
    expect(openedNote?.id, shared.id);

    await tester.tap(find.byKey(const ValueKey('tag-group-项目')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('tag-note-项目-${shared.id.value}')),
      findsOneWidget,
    );
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('tag-note-工作-${shared.id.value}')),
      findsNothing,
    );
  });

  testWidgets('reopening tag groups starts collapsed without losing notes', (
    tester,
  ) async {
    final note = _note('工作记录', tags: const ['工作']);
    final store = _TagStore([note]);
    final controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NoteTagGroupsPage(
                    controller: controller,
                    onOpenNote: (_) async {},
                  ),
                ),
              ),
              child: const Text('打开标签'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开标签'));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('tag-note-工作-${note.id.value}'));
    expect(row, findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-group-工作')));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开标签'));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(find.text('1 条笔记'), findsOneWidget);
  });

  testWidgets('compact group surface follows the selected theme profile', (
    tester,
  ) async {
    final note = _note('工作记录', tags: const ['工作']);
    final store = _TagStore([note]);
    final controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
    await controller.initialize();

    Future<RoundedRectangleBorder> pumpStyle(AppThemeStyle style) async {
      await tester.pumpWidget(
        _TestApp(
          style: style,
          child: NoteTagGroupsPage(
            controller: controller,
            onOpenNote: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.widget<Material>(
        find.byKey(const ValueKey('tag-groups-surface')),
      );
      return surface.shape! as RoundedRectangleBorder;
    }

    final quietShape = await pumpStyle(AppThemeStyle.paper);
    expect(quietShape.side.style, BorderStyle.none);
    expect(
      quietShape.borderRadius,
      BorderRadius.circular(AppRadii.quiet.large),
    );

    final sunnyShape = await pumpStyle(AppThemeStyle.sunnyGrowth);
    expect(sunnyShape.side.width, AppComponentTheme.cloud.surfaceBorderWidth);
    expect(
      sunnyShape.borderRadius,
      BorderRadius.circular(AppRadii.cloud.large),
    );

    final editorialShape = await pumpStyle(AppThemeStyle.editorialJournal);
    expect(
      editorialShape.side.width,
      AppComponentTheme.editorial.surfaceBorderWidth,
    );
    expect(
      editorialShape.borderRadius,
      BorderRadius.circular(AppRadii.editorial.large),
    );
  });
}

Note _note(String title, {List<String> tags = const []}) {
  final now = DateTime.now();
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromPlainText('$title 正文'),
    tags: tags,
    revision: 1,
    createdAt: now,
    updatedAt: now,
  );
}

final class _TagStore implements NoteLibraryStore {
  _TagStore(this.notes);

  final List<Note> notes;

  @override
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) async => List.of(notes);

  @override
  Future<Note> update(Note note) async => note;

  @override
  Future<void> deletePermanently(Note note) async {}
}

final class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.style = AppThemeStyle.editorialJournal,
  });

  final Widget child;
  final AppThemeStyle style;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: buildAppTheme(style, Brightness.light),
    home: child,
  );
}
