import 'dart:convert';
import 'dart:typed_data';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/providers/editorial_material_controller.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/editorial_paper_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _PageLibraryStore store;
  late NoteLibraryController controller;
  late EditorialMaterialController materials;

  setUp(() {
    store = _PageLibraryStore([
      _note(
        '格式笔记',
        document: Delta()
          ..insert('加粗正文', {'bold': true})
          ..insert('\n'),
      ),
      _note('普通笔记', document: Delta()..insert('可搜索内容\n')),
    ]);
    controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
    materials = EditorialMaterialController()..loading = false;
    addTearDown(materials.dispose);
  });

  testWidgets('renders one lightweight, searchable note list', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-list')), findsOneWidget);
    expect(find.text('非空笔记'), findsOneWidget);
    expect(find.text('2 条笔记'), findsOneWidget);
    expect(find.text('格式笔记'), findsOneWidget);
    expect(find.text('加粗正文'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    final firstTile = tester.widget<Material>(
      find.byKey(ValueKey('delta-note-${store.notes.first.id.value}')),
    );
    expect(firstTile.color, Colors.transparent);
    expect(firstTile.shape, isNull);
    expect(
      find.byKey(const Key('delta-ribbon-timeline-preview')),
      findsNothing,
    );
    expect(find.byKey(const Key('delta-library-constellation')), findsNothing);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets('keeps reminder, tags and time on one row at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = _imageAsset('photo.png');
      final note = _note(
        '带提醒的图片笔记',
        document: Delta()
          ..insert(NoteEmbed.attachment(image.id).toDeltaData())
          ..insert('\n'),
        assets: [image],
        tags: const ['这是很长的标签', '第二个标签'],
      ).copyWith(reminderAt: DateTime.now().add(const Duration(days: 1)));
      store.notes
        ..clear()
        ..add(note);
      await tester.pumpWidget(
        _TestApp(
          child: NoteLibraryPage(
            materialController: materials,
            controller: controller,
            resolveImage: (_) => MemoryImage(_onePixelPng),
          ),
        ),
      );
      await _pump(tester);
      final time = find.byKey(ValueKey('delta-note-time-${note.id.value}'));
      final tags = find.byKey(ValueKey('delta-note-tags-${note.id.value}'));
      final reminder = find.byKey(
        ValueKey('delta-note-reminder-${note.id.value}'),
      );
      expect(
        (tester.getCenter(time).dy - tester.getCenter(reminder).dy).abs(),
        lessThan(2),
      );
      expect(
        (tester.getCenter(tags).dy - tester.getCenter(reminder).dy).abs(),
        lessThan(2),
      );
      expect(
        tester.getTopLeft(reminder).dx,
        greaterThan(tester.getTopLeft(tags).dx),
      );
      expect(tester.takeException(), isNull);
      await tester.longPress(
        find.byKey(ValueKey('delta-note-${note.id.value}')),
      );
      await _pump(tester);
      expect(tester.takeException(), isNull);
      store.notes[0] = note.copyWith(reminderAt: DateTime.utc(2020));
      await controller.refresh();
      await _pump(tester);
      expect(reminder, findsNothing);
      expect(tags, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('debounces full-text search without replacing newer input', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('delta-library-search')),
      '可搜索',
    );
    await tester.pump(const Duration(milliseconds: 219));
    expect(find.text('格式笔记'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await _pump(tester);
    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.text('格式笔记'), findsNothing);

    await tester.tap(find.byKey(const Key('delta-library-clear-shelf-search')));
    await _pump(tester);
    expect(find.text('格式笔记'), findsOneWidget);
  });

  testWidgets('cards omit trailing menus and long press starts bulk actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final first = store.notes.first;
    final firstCard = find.byKey(ValueKey('delta-note-${first.id.value}'));
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

    await tester.longPress(firstCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('delta-library-selection-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('delta-library-selection-actions')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('delta-library-pin-selected')));
    await _pump(tester);
    expect(store.notes.first.isPinned, isTrue);
    expect(
      find.byKey(const Key('delta-library-selection-actions')),
      findsNothing,
    );
  });

  testWidgets('long press exposes bottom bulk actions and confirms deletion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final first = store.notes.first;
    await tester.longPress(
      find.byKey(ValueKey('delta-note-${first.id.value}')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('delta-library-selection-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('delta-library-selection-actions')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('quill-home-new-note')), findsNothing);

    await tester.tap(find.byKey(const Key('delta-library-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除这 1 篇笔记？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delta-library-confirm-delete')));
    await _pump(tester);

    expect(store.notes, hasLength(1));
    expect(store.notes.single.id, isNot(first.id));
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
  });

  testWidgets('shows a bounded image thumbnail on the card right edge', (
    tester,
  ) async {
    var imageResolutionCount = 0;
    final image = _imageAsset('photo.png');
    store.notes
      ..clear()
      ..add(
        _note(
          '图片笔记',
          document: Delta()
            ..insert(NoteEmbed.attachment(image.id).toDeltaData())
            ..insert('\n'),
          assets: [image],
          tags: const ['工作', '项目', '收集箱'],
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
          resolveImage: (_) {
            imageResolutionCount += 1;
            return MemoryImage(_onePixelPng);
          },
        ),
      ),
    );
    await _pump(tester);

    expect(find.text('图片笔记'), findsOneWidget);
    final thumbnail = find.byKey(
      ValueKey('delta-note-thumbnail-${store.notes.single.id.value}'),
    );
    expect(thumbnail, findsOneWidget);
    expect(tester.getSize(thumbnail), const Size.square(72));
    final card = find.byKey(
      ValueKey('delta-note-${store.notes.single.id.value}'),
    );
    expect(
      (tester.getCenter(thumbnail).dy - tester.getCenter(card).dy).abs(),
      lessThan(1),
    );
    final time = find.byKey(
      ValueKey('delta-note-time-${store.notes.single.id.value}'),
    );
    final tags = find.byKey(
      ValueKey('delta-note-tags-${store.notes.single.id.value}'),
    );
    expect(find.text('工作 · 项目 +1'), findsOneWidget);
    expect(
      (tester.getCenter(time).dy - tester.getCenter(tags).dy).abs(),
      lessThan(2),
    );
    expect(tester.getCenter(tags).dx, greaterThan(tester.getCenter(time).dx));
    expect(imageResolutionCount, greaterThan(0));
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
  });

  testWidgets('places audio and video signals beside the card time', (
    tester,
  ) async {
    final audio = _asset(NoteAssetKind.audio, 'voice.m4a');
    final video = _asset(NoteAssetKind.video, 'clip.mp4');
    store.notes
      ..clear()
      ..add(
        _note(
          '媒体笔记',
          document: Delta()
            ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
            ..insert('\n')
            ..insert(NoteEmbed.attachment(video.id).toDeltaData())
            ..insert('\n'),
          assets: [audio, video],
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final noteId = store.notes.single.id.value;
    expect(find.byKey(ValueKey('delta-note-audio-$noteId')), findsOneWidget);
    expect(find.byKey(ValueKey('delta-note-video-$noteId')), findsOneWidget);
  });

  testWidgets('empty state starts a note from the single primary action', (
    tester,
  ) async {
    store.notes.clear();
    var createCount = 0;
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
          onCreateNote: () => createCount += 1,
        ),
      ),
    );
    await _pump(tester);

    expect(find.text('还没有笔记'), findsOneWidget);
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    expect(createCount, 1);
  });

  testWidgets('returning from an editor leaves the search keyboard closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search')));
    await tester.pump();
    expect(_searchEditable(tester).focusNode.hasFocus, isTrue);

    await tester.tap(find.text('格式笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await tester.pumpAndSettle();

    expect(_searchEditable(tester).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'editorial theme owns the home layout and keeps library actions',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.notes
        ..clear()
        ..addAll([
          _note(
            '项目构想',
            document: Delta()..insert('下一次发布的重点\n'),
            tags: const ['工作', '灵感'],
          ),
          _note(
            '周末散步',
            document: Delta()..insert('沿着江边慢慢走\n'),
            tags: const ['生活'],
          ),
        ]);
      var createCount = 0;
      var calendarCount = 0;

      await tester.pumpWidget(
        _TestApp(
          style: AppThemeStyle.editorialJournal,
          child: NoteLibraryPage(
            materialController: materials,
            controller: controller,
            onCreateNote: () => createCount += 1,
            onOpenCalendar: () => calendarCount += 1,
          ),
        ),
      );
      await _pump(tester);

      expect(
        find.byKey(const Key('editorial-library-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('editorial-material-recent')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('editorial-material-recent')),
          matching: find.byIcon(Icons.attach_file_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('quill-home-assistant')),
          matching: find.byIcon(Icons.auto_awesome_outlined),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('editorial-library-grid')), findsOneWidget);
      expect(find.byType(SliverCrossAxisGroup), findsOneWidget);
      expect(find.byType(SliverGrid), findsNothing);
      expect(find.byKey(const Key('delta-library-list')), findsNothing);
      expect(find.textContaining('今天想记点什么？'), findsOneWidget);
      expect(find.byKey(const Key('editorial-filter-工作')), findsOneWidget);
      final searchPaper = find.ancestor(
        of: find.byKey(const Key('delta-library-search')),
        matching: find.byType(EditorialPaperSurface),
      );
      final bottomSheet = find
          .descendant(
            of: find.byKey(const Key('editorial-material-stack')),
            matching: find.byType(EditorialPaperSurface),
          )
          .first;
      expect(
        tester.getTopLeft(find.byKey(const Key('material-card-top'))).dy -
            tester.getBottomLeft(searchPaper).dy,
        closeTo(24, .1),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('editorial-filter-all'))).dy -
            tester.getBottomLeft(bottomSheet).dy,
        closeTo(24, 2),
      );
      final metadataNote = store.notes.first;
      final metadataTime = find.byKey(
        ValueKey('delta-note-time-${metadataNote.id.value}'),
      );
      final metadataTags = find.byKey(
        ValueKey('delta-note-tags-${metadataNote.id.value}'),
      );
      final preview = find.byKey(
        ValueKey('delta-note-preview-${metadataNote.id.value}'),
      );
      expect(
        tester.getTopLeft(metadataTime).dy - tester.getBottomLeft(preview).dy,
        lessThanOrEqualTo(16),
      );
      expect(
        tester
            .getSize(
              find.byKey(ValueKey('delta-note-${metadataNote.id.value}')),
            )
            .height,
        lessThan(160),
      );
      expect(
        tester.getTopLeft(metadataTime).dy,
        closeTo(tester.getTopLeft(metadataTags).dy, .01),
      );
      expect(
        tester.widget<Text>(metadataTime).style?.fontSize,
        tester.widget<Text>(metadataTags).style?.fontSize,
      );
      final floatingDock = tester.getRect(
        find.byKey(const Key('app-floating-navigation-dock')),
      );
      expect(floatingDock.width, closeTo(370, .01));
      expect(floatingDock.center.dx, closeTo(215, .01));
      expect(floatingDock.height, 64);
      expect(
        tester
            .getRect(find.byKey(const Key('editorial-library-scroll')))
            .bottom,
        greaterThan(floatingDock.bottom),
      );
      final scrollClearance = tester.widget<SliverPadding>(
        find.byKey(const Key('editorial-library-scroll-clearance')),
      );
      expect(
        (scrollClearance.padding as EdgeInsets).bottom,
        greaterThan(floatingDock.height),
      );
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const Key('editorial-library-surface')),
            )
            .extendBody,
        isTrue,
      );
      expect(
        tester
            .widget<Material>(
              find.byKey(const Key('app-floating-navigation-region')),
            )
            .type,
        MaterialType.transparency,
      );
      expect(
        find.byKey(const Key('editorial-home-dock-divider-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('editorial-home-dock-divider-right')),
        findsOneWidget,
      );
      for (final label in ['全部', '工作', '灵感', '生活']) {
        final chipKey = label == '全部'
            ? const Key('editorial-filter-all')
            : Key('editorial-filter-$label');
        final chip = find.descendant(
          of: find.byKey(chipKey),
          matching: find.byType(Text),
        );
        final material = find
            .ancestor(of: chip, matching: find.byType(Material))
            .first;
        expect(
          tester.getCenter(chip).dy,
          closeTo(tester.getCenter(material).dy, .01),
        );
      }

      await tester.tap(find.byKey(const Key('editorial-filter-工作')));
      await _pump(tester);
      expect(find.text('项目构想'), findsOneWidget);
      expect(find.text('周末散步'), findsNothing);

      await tester.tap(find.byKey(const Key('editorial-filter-all')));
      await _pump(tester);
      expect(find.text('周末散步'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('delta-library-search')),
        '江边',
      );
      await tester.pump(const Duration(milliseconds: 230));
      await _pump(tester);
      expect(find.text('项目构想'), findsNothing);
      expect(find.text('周末散步'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('delta-library-clear-shelf-search')),
      );
      await _pump(tester);

      await tester.tap(find.byKey(const Key('quill-home-new-note')));
      await tester.tap(find.byKey(const Key('delta-library-open-calendar')));
      await _pump(tester);
      expect(createCount, 1);
      expect(calendarCount, 1);

      final firstCard = find.byKey(
        ValueKey('delta-note-${store.notes.first.id.value}'),
      );
      await tester.longPress(firstCard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('delta-library-selection-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('delta-library-selection-actions')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editorial selection keeps actions, title and cobalt text readable',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = '早春呈水部张十八员外';
      final note = _note(
        title,
        document: Delta()..insert('天街小雨润如酥，草色遥看近却无。\n'),
      );
      store.notes
        ..clear()
        ..add(note);

      await tester.pumpWidget(
        _TestApp(
          style: AppThemeStyle.editorialJournal,
          child: NoteLibraryPage(
            materialController: materials,
            controller: controller,
            onChangePrivacy: (_, _) async => true,
          ),
        ),
      );
      await _pump(tester);

      final card = find.byKey(ValueKey('delta-note-${note.id.value}'));
      await tester.longPress(card);
      await tester.pumpAndSettle();

      final selectionIcon = find.byIcon(Icons.check_circle_rounded);
      final titleText = tester.widget<Text>(find.text(title));
      final previewText = tester.widget<Text>(
        find.byKey(ValueKey('delta-note-preview-${note.id.value}')),
      );
      expect(titleText.style?.color, AppPalette.editorialJournalLight.ink);
      expect(previewText.style?.color, AppPalette.editorialJournalLight.muted);
      expect(
        tester.getRect(find.text(title)).right,
        lessThan(tester.getRect(selectionIcon).left),
      );

      final dock = tester.getRect(
        find.byKey(const Key('app-floating-navigation-dock')),
      );
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const Key('editorial-library-surface')),
            )
            .extendBody,
        isTrue,
      );
      expect(
        tester
            .getRect(find.byKey(const Key('editorial-library-scroll')))
            .bottom,
        greaterThan(dock.bottom),
      );
      final scrollClearance = tester.widget<SliverPadding>(
        find.byKey(const Key('editorial-library-scroll-clearance')),
      );
      expect(
        (scrollClearance.padding as EdgeInsets).bottom,
        greaterThan(dock.height),
      );
      for (final key in const [
        Key('delta-library-privacy-selected'),
        Key('delta-library-pin-selected'),
        Key('delta-library-delete-selected'),
      ]) {
        final action = tester.getRect(find.byKey(key));
        expect(action.top, greaterThanOrEqualTo(dock.top));
        expect(action.bottom, lessThanOrEqualTo(dock.bottom));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editorial pinned state lives in the metadata row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = _note(
      '置顶笔记',
      document: Delta()..insert('标题区域只保留内容本身。\n'),
      tags: const ['灵感', '工作'],
    ).copyWith(isPinned: true);
    store.notes
      ..clear()
      ..add(note);

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final card = find.byKey(ValueKey('delta-note-${note.id.value}'));
    final title = find.text('置顶笔记');
    final preview = find.byKey(ValueKey('delta-note-preview-${note.id.value}'));
    final time = find.byKey(ValueKey('delta-note-time-${note.id.value}'));
    final status = find.byKey(
      ValueKey('delta-note-status-pinned-${note.id.value}'),
    );
    final tags = find.byKey(ValueKey('delta-note-tags-${note.id.value}'));
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.push_pin_outlined)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: status, matching: find.textContaining('置顶')),
      findsOneWidget,
    );
    expect(tester.getCenter(status).dy, closeTo(tester.getCenter(time).dy, 1));
    expect(tester.getCenter(status).dy, closeTo(tester.getCenter(tags).dy, 1));
    expect(tester.getRect(time).right, lessThan(tester.getRect(status).left));
    expect(tester.getRect(status).right, lessThan(tester.getRect(tags).left));
    expect(
      tester.getRect(title).left,
      closeTo(tester.getRect(preview).left, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial filters expose every tag through horizontal scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const tags = ['工作', '电影', '旅行', '灵感', '生活', '阅读', '随笔', '音乐'];
    store.notes
      ..clear()
      ..addAll([
        for (final tag in tags)
          _note('$tag笔记', document: Delta()..insert('$tag内容\n'), tags: [tag]),
      ]);

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final filterList = find.byKey(const Key('editorial-filter-scroll'));
    expect(
      tester.widget<ListView>(filterList).childrenDelegate.estimatedChildCount,
      tags.length * 2 + 1,
    );
    final filterScrollable = find.descendant(
      of: filterList,
      matching: find.byType(Scrollable),
    );
    final lastFilter = find.byKey(const Key('editorial-filter-音乐'));
    await tester.dragUntilVisible(
      lastFilter,
      filterScrollable,
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();

    final lastFilterRect = tester.getRect(lastFilter);
    expect(lastFilterRect.left, greaterThanOrEqualTo(0));
    expect(lastFilterRect.right, lessThanOrEqualTo(320));
    await tester.tap(lastFilter);
    await _pump(tester);
    expect(find.text('音乐笔记'), findsOneWidget);
    expect(find.text('工作笔记'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial scrolling keeps the grid and static dock stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.notes
      ..clear()
      ..addAll([
        for (var index = 0; index < 24; index++)
          _note('滚动笔记 $index', document: Delta()..insert('保持纸张质感的正文 $index\n')),
      ]);
    var cardBuildProbes = 0;

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
          resolveImage: (_) {
            cardBuildProbes++;
            return null;
          },
        ),
      ),
    );
    await _pump(tester);

    final widthLayout = find.byKey(const Key('editorial-library-width-layout'));
    expect(widthLayout, findsOneWidget);
    expect(
      find.descendant(
        of: widthLayout,
        matching: find.byType(SliverLayoutBuilder),
      ),
      findsNothing,
    );
    final probesBeforeScroll = cardBuildProbes;
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('editorial-library-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(1);
    await tester.pump();
    expect(cardBuildProbes, probesBeforeScroll);
    expect(
      find.byKey(const Key('app-floating-navigation-live-blur')),
      findsNothing,
    );
    final dock = find.byKey(const Key('app-floating-navigation-dock'));
    final dockColorBeforeScroll = tester.widget<Material>(dock).color;
    expect(
      dockColorBeforeScroll,
      Color.alphaBlend(
        AppPalette.editorialJournalLight.surface.withValues(alpha: .92),
        AppPalette.editorialJournalLight.canvas,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('editorial-library-scroll'))),
    );
    await gesture.moveBy(const Offset(0, -260));
    await tester.pump();

    expect(tester.widget<Material>(dock).color, dockColorBeforeScroll);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(dock).color, dockColorBeforeScroll);
  });

  testWidgets('editorial cards bound previews and decode images by DPR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = _imageAsset('photo.png');
    final textNote = _note(
      '长笔记',
      document: Delta()..insert('${List.filled(1000, '纸张正文').join()}\n'),
    );
    final imageNote = _note(
      '图片笔记',
      document: Delta()
        ..insert(NoteEmbed.attachment(image.id).toDeltaData())
        ..insert('\n'),
      assets: [image],
    );
    store.notes
      ..clear()
      ..addAll([textNote, imageNote]);

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
          resolveImage: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );
    await _pump(tester);

    final preview = tester.widget<Text>(
      find.byKey(ValueKey('delta-note-preview-${textNote.id.value}')),
    );
    expect(preview.data!.length, lessThanOrEqualTo(600));

    final imageWidget = tester.widget<Image>(
      find.descendant(
        of: find.byKey(ValueKey('delta-note-${imageNote.id.value}')),
        matching: find.byType(Image),
      ),
    );
    final provider = imageWidget.image as ResizeImage;
    expect(provider.width, 256);
    expect(provider.height, 256);
  });

  testWidgets('editorial cards preserve checklist state in previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = _note(
      '待办笔记',
      document: Delta()
        ..insert('nnn')
        ..insert('\n', {'list': 'unchecked'})
        ..insert('xxx')
        ..insert('\n', {'list': 'checked'})
        ..insert('ccc')
        ..insert('\n', {'list': 'unchecked'}),
    );
    store.notes
      ..clear()
      ..add(note);

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    final preview = tester.widget<Text>(
      find.byKey(ValueKey('delta-note-preview-${note.id.value}')),
    );
    expect(preview.data, '☐ nnn\n☑ xxx\n☐ ccc');
  });

  for (final style in const [
    AppThemeStyle.paper,
    AppThemeStyle.starlight,
    AppThemeStyle.sunnyGrowth,
  ]) {
    testWidgets('$style home cards use the shared bounded preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final note = _note(
        '长笔记',
        document: Delta()
          ..insert('${List.filled(1000, '概览正文').join()}不应显示的尾部\n'),
      );
      store.notes
        ..clear()
        ..add(note);

      await tester.pumpWidget(
        _TestApp(
          style: style,
          child: NoteLibraryPage(
            materialController: materials,
            controller: controller,
          ),
        ),
      );
      await _pump(tester);

      final preview = tester.widget<Text>(
        find.byKey(ValueKey('delta-note-preview-${note.id.value}')),
      );
      expect(preview.data!.length, lessThanOrEqualTo(600));
      expect(preview.data, isNot(contains('不应显示的尾部')));
    });
  }

  testWidgets('editorial home remains usable on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.notes
      ..clear()
      ..add(
        _note(
          '窄屏笔记',
          document: Delta()..insert('在很小的屏幕上也能安静阅读\n'),
          tags: const ['随想'],
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        textScaler: const TextScaler.linear(1.3),
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);

    expect(find.byKey(const Key('editorial-library-surface')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial home matches its visual contract', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.notes
      ..clear()
      ..addAll([
        _note(
          '产品灵感清单',
          document: Delta()..insert('把复杂的事情做得轻盈一些。\n'),
          tags: const ['灵感', '工作'],
        ).copyWith(isPinned: true),
        _note(
          '海边的下午',
          document: Delta()..insert('风穿过松林，潮水慢慢退去。\n'),
          tags: const ['生活'],
        ),
        _note(
          '本周阅读摘录',
          document: Delta()..insert('真正重要的设计让人感到自然。\n'),
          tags: const ['阅读'],
        ),
      ]);
    await tester.pumpWidget(
      _TestApp(
        style: AppThemeStyle.editorialJournal,
        child: NoteLibraryPage(
          materialController: materials,
          controller: controller,
        ),
      ),
    );
    await _pump(tester);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(EditorialJournalTokens.paperTextureAsset),
        tester.element(find.byKey(const Key('editorial-library-surface'))),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('editorial-library-surface')),
      matchesGoldenFile('goldens/editorial_home.png'),
    );
  });
}

Widget _testEditor(BuildContext context, Note? note) => Scaffold(
  body: Center(
    child: TextButton(
      key: const Key('close-test-editor'),
      onPressed: () => Navigator.pop(context),
      child: Text('编辑 ${note?.title}'),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
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

final class _PageLibraryStore implements NoteLibraryStore {
  _PageLibraryStore(this.notes);

  final List<Note> notes;

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

Note _note(
  String title, {
  required Delta document,
  List<NoteAsset> assets = const [],
  List<String> tags = const [],
  DateTime? updatedAt,
}) {
  final now = updatedAt ?? DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromDelta(document),
    assets: assets,
    tags: tags,
    revision: 1,
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _imageAsset(String originalName) {
  return _asset(NoteAssetKind.image, originalName);
}

NoteAsset _asset(NoteAssetKind kind, String originalName) {
  final now = DateTime.utc(2026, 7, 23, 12);
  final (directory, mimeType) = switch (kind) {
    NoteAssetKind.image => ('images', 'image/png'),
    NoteAssetKind.audio => ('audio', 'audio/mp4'),
    NoteAssetKind.video => ('video', 'video/mp4'),
    NoteAssetKind.file => ('files', 'application/octet-stream'),
  };
  return NoteAsset(
    id: NoteAttachmentId.generate(),
    kind: kind,
    storageKey: 'notes/$directory/${NoteAttachmentId.generate().value}',
    originalName: originalName,
    byteLength: _onePixelPng.length,
    mimeType: mimeType,
    createdAt: now,
    updatedAt: now,
  );
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child, this.style, this.textScaler});

  final Widget child;
  final AppThemeStyle? style;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: style == null ? null : buildAppTheme(style!, Brightness.light),
    builder: style == null && textScaler == null
        ? null
        : (context, child) {
            Widget result = child!;
            if (textScaler != null) {
              result = MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: result,
              );
            }
            return result;
          },
    home: child,
  );
}
