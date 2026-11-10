import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_calendar.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_calendar_page.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/widgets/app_icon.dart';
import 'package:fknotes/widgets/note_calendar_views.dart';
import 'package:flutter/material.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 8, 27, 15, 30);

  testWidgets('month fills the screen with lunar dates and note counts only', (
    tester,
  ) async {
    await _pumpCalendar(
      tester,
      notes: [
        _note('上午记录', DateTime(2026, 8, 27, 9)),
        _note('下午记录', DateTime(2026, 8, 27, 15)),
      ],
    );
    expect(find.byKey(const Key('calendar-month-view')), findsOneWidget);
    expect(find.byKey(const Key('calendar-period-title')), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);
    expect(find.byKey(const Key('calendar-year-picker')), findsNothing);
    expect(find.text('上午记录'), findsNothing);
    expect(find.text('下午记录'), findsNothing);
    expect(_countText(tester, 20260827), '2 条');
    expect(find.byKey(const Key('calendar-lunar-20260827')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-20260727')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-20260906')), findsOneWidget);
    final grid = tester.getRect(find.byKey(const Key('note-calendar-grid')));
    final bar = tester.getRect(find.byKey(const Key('calendar-navigation')));
    expect(grid.height, greaterThan(650));
    expect(grid.bottom, lessThanOrEqualTo(bar.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial calendar layers months onto paper cards', (
    tester,
  ) async {
    final appearance = ValueNotifier((
      AppThemeStyle.editorialJournal,
      Brightness.light,
    ));
    addTearDown(appearance.dispose);
    await _pumpCalendar(tester, appearance: appearance);

    final floatingDock = tester.getRect(
      find.byKey(const Key('app-floating-navigation-dock')),
    );
    expect(floatingDock.width, closeTo(370, .01));
    expect(floatingDock.center.dx, closeTo(215, .01));
    expect(floatingDock.height, 64);
    expect(
      find.byKey(const Key('app-floating-navigation-live-blur')),
      findsNothing,
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const Key('app-floating-navigation-dock')),
          )
          .color,
      Color.alphaBlend(
        AppPalette.editorialJournalLight.surface.withValues(alpha: .92),
        AppPalette.editorialJournalLight.canvas,
      ),
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
      tester.getRect(find.byKey(const Key('calendar-month-view'))).bottom,
      greaterThan(floatingDock.bottom),
    );
    final monthScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('calendar-month-scroll-2026-8')),
    );
    expect(
      (monthScroll.padding! as EdgeInsets).bottom,
      greaterThan(floatingDock.height),
    );
    expect(find.byKey(const Key('calendar-home-primary')), findsOneWidget);
    expect(
      tester
          .widget<AppIcon>(
            find.byKey(const ValueKey('calendar-view-month-icon')),
          )
          .color,
      AppPalette.editorialJournalLight.accent,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('calendar-view-month-label')))
          .style
          ?.color,
      AppPalette.editorialJournalLight.muted,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-view-month-icon-slot')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    for (final view in NoteCalendarView.values) {
      final button = find.byKey(Key('calendar-view-${view.name}'));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    await _tap(tester, 'calendar-view-year');
    expect(
      tester
          .widget<AppIcon>(
            find.byKey(const ValueKey('calendar-view-year-icon')),
          )
          .color,
      AppPalette.editorialJournalLight.accent,
    );
    expect(
      tester
          .widget<AppIcon>(
            find.byKey(const ValueKey('calendar-view-month-icon')),
          )
          .color,
      AppPalette.editorialJournalLight.muted,
    );

    final title = tester.widget<Text>(
      find.byKey(const Key('calendar-period-label')),
    );
    expect(
      title.style?.fontFamily,
      AppComponentTheme.editorial.displayFontFamily,
    );
    await _tap(tester, 'calendar-view-year');
    final january = find.byKey(const Key('calendar-mini-month-2026-1'));
    final material = tester.widget<Material>(
      find.ancestor(of: january, matching: find.byType(Material)).first,
    );
    expect(material.color, AppPalette.editorialJournalLight.surface);
    expect(
      (material.shape! as RoundedRectangleBorder).side,
      isNot(BorderSide.none),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial month keeps a compact content-sized weekly rhythm', (
    tester,
  ) async {
    final appearance = ValueNotifier((
      AppThemeStyle.editorialJournal,
      Brightness.light,
    ));
    addTearDown(appearance.dispose);
    await _pumpCalendar(
      tester,
      appearance: appearance,
      notes: [_note('日历节奏', DateTime(2026, 8, 27, 9))],
    );

    final firstWeek = tester.getRect(
      find.byKey(const Key('calendar-day-20260727')),
    );
    final secondWeek = tester.getRect(
      find.byKey(const Key('calendar-day-20260803')),
    );
    final weeklyStep = secondWeek.top - firstWeek.top;
    expect(weeklyStep, inInclusiveRange(96, 106));
    expect(
      tester.getSize(find.byKey(const Key('note-calendar-grid'))).height,
      lessThan(650),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial calendar matches its floating dock contract', (
    tester,
  ) async {
    final appearance = ValueNotifier((
      AppThemeStyle.editorialJournal,
      Brightness.light,
    ));
    addTearDown(appearance.dispose);
    await _pumpCalendar(
      tester,
      appearance: appearance,
      notes: [
        _note('晨间记录', DateTime(2026, 8, 27, 9)),
        _note('午后灵感', DateTime(2026, 8, 27, 15)),
      ],
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(EditorialJournalTokens.paperTextureAsset),
        tester.element(find.byKey(const Key('note-calendar-page'))),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('note-calendar-page')),
      matchesGoldenFile('goldens/editorial_calendar.png'),
    );
  });

  testWidgets(
    'today is an outlined pill with the existing touch target in every view',
    (tester) async {
      await _pumpCalendar(tester);
      for (final view in NoteCalendarView.values) {
        await _tap(tester, 'calendar-view-${view.name}');
        final today = find.byKey(const Key('calendar-today'));
        final style = tester.widget<TextButton>(today).style!;
        expect(style.shape!.resolve({}), isA<StadiumBorder>());
        expect(style.side!.resolve({})!.width, greaterThan(0));
        expect(style.side!.resolve({})!.color.a, greaterThan(0));
        expect(tester.getSize(today).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(today).width, greaterThanOrEqualTo(48));
      }
    },
  );

  for (final style in AppThemeStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${style.name} ${brightness.name} integrates selected counts and date accents',
        (tester) async {
          final appearance = ValueNotifier((style, brightness));
          addTearDown(appearance.dispose);
          await _pumpCalendar(
            tester,
            appearance: appearance,
            notes: [
              _note('记录一', today),
              _note('记录二', today),
              _note('其他日期', DateTime(2026, 8, 24)),
            ],
          );
          final colors = AppPalette.forStyle(style, brightness);
          final surface = find.byKey(
            const Key('calendar-day-surface-20260827'),
          );
          final badge = find.byKey(const Key('calendar-count-20260827'));
          expect(find.descendant(of: surface, matching: badge), findsOneWidget);
          expect(_countText(tester, 20260827), '2 条');
          expect(
            tester.getRect(surface).contains(tester.getRect(badge).center),
            isTrue,
          );
          expect(
            tester.getRect(badge).bottom,
            lessThan(tester.getRect(surface).bottom),
          );
          final decoration =
              tester.widget<Container>(surface).decoration! as BoxDecoration;
          expect(decoration.color, colors.accent);
          expect(decoration.gradient, colors.primaryGradient);
          final badgeContainer = tester.widget<Container>(
            find.descendant(of: badge, matching: find.byType(Container)),
          );
          expect(
            (badgeContainer.decoration! as BoxDecoration).color,
            colors.surface,
          );
          expect(
            _dateTextColor(tester, 'calendar-date-20260827'),
            colors.onStrong,
          );
          expect(
            _dateTextColor(tester, 'calendar-date-20260801'),
            colors.calendarWeekend,
          );
          expect(_dateTextColor(tester, 'calendar-date-20260803'), colors.ink);
          expect(
            _dateTextColor(tester, 'calendar-lunar-20260819'),
            colors.calendarFestival,
          );
          expect(
            _dateTextColor(tester, 'calendar-lunar-20260807'),
            colors.calendarSolarTerm,
          );
          expect(
            _dateTextColor(tester, 'calendar-date-20260906'),
            colors.subtle,
          );
          expect(
            tester.widget<Text>(find.text('六')).style!.color,
            colors.calendarWeekend,
          );

          final grid = tester.getRect(
            find.byKey(const Key('note-calendar-grid')),
          );
          await _tap(tester, 'calendar-day-20260824');
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const Key('note-calendar-grid'))),
            grid,
          );
          expect(find.descendant(of: surface, matching: badge), findsNothing);
          final todaySurface = tester.widget<Container>(surface);
          expect(
            (todaySurface.foregroundDecoration! as BoxDecoration).border,
            Border.all(
              color: colors.accent,
              width: style == AppThemeStyle.sunnyGrowth
                  ? SunnyGrowthTokens.compTodayStroke
                  : 1,
            ),
          );
          expect((todaySurface.decoration! as BoxDecoration).color, isNull);
          expect(_countText(tester, 20260827), '2 条');

          await _tap(tester, 'calendar-view-week');
          expect(_countText(tester, 20260827), '2 条');
          expect(
            _dateTextColor(tester, 'calendar-date-20260829'),
            colors.calendarWeekend,
          );
          await _tap(tester, 'calendar-view-year');
          await tester.ensureVisible(
            find.byKey(const Key('calendar-mini-month-2026-8')),
          );
          await tester.pumpAndSettle();
          expect(
            _dateTextColor(tester, 'calendar-mini-date-20260801'),
            colors.calendarWeekend,
          );
          final monthCount = find.descendant(
            of: find.byKey(const Key('calendar-month-count-8')),
            matching: find.byType(Text),
          );
          expect(tester.widget<Text>(monthCount).data, '3 条');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'special labels remain visible and accessible in week and day views',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpCalendar(tester, now: DateTime(2026, 8, 19));
        expect(
          find.bySemanticsLabel(RegExp('农历七月初七.*七夕节.*0 条笔记')),
          findsOneWidget,
        );
        for (final view in [NoteCalendarView.week, NoteCalendarView.day]) {
          await _tap(tester, 'calendar-view-${view.name}');
          final label = tester.widget<Text>(
            find.byKey(const Key('calendar-lunar-20260819')),
          );
          expect(label.data, contains('七夕节'));
          expect(label.style!.color, AppPalette.paperLight.calendarFestival);
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('compact badges keep their unit in English on a narrow phone', (
    tester,
  ) async {
    await _pumpCalendar(
      tester,
      locale: 'en',
      size: const Size(320, 568),
      notes: [_note('First note', today), _note('Second note', today)],
    );
    expect(_countText(tester, 20260827), '2 notes');
    await _tap(tester, 'calendar-view-week');
    expect(_countText(tester, 20260827), '2 notes');
    expect(_countText(tester, 20260828), '0 notes');
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale, locale) in [
    (const Size(430, 932), 1.0, 'zh'),
    (const Size(320, 568), 1.0, 'zh'),
    (const Size(320, 568), 2.0, 'zh'),
    (const Size(320, 568), 2.0, 'en'),
  ]) {
    testWidgets(
      'selected, ordinary and outlined-today cells align at ${size.width} $scale $locale',
      (tester) async {
        await _pumpCalendar(
          tester,
          now: DateTime(2026, 8, 26),
          size: size,
          textScale: scale,
          locale: locale,
          notes: [
            for (final day in [25, 26, 27])
              for (var count = 0; count < (day == 27 ? 3 : 2); count++)
                _note('记录 $day-$count', DateTime(2026, 8, day)),
          ],
        );
        await tester.ensureVisible(
          find.byKey(const Key('calendar-day-20260826')),
        );
        await tester.pumpAndSettle();
        final positions = <String, double>{};
        for (final part in ['date', 'lunar', 'count']) {
          final left = tester
              .getTopLeft(find.byKey(Key('calendar-$part-20260825')))
              .dy;
          positions[part] = left;
          for (final day in [26, 27]) {
            expect(
              tester
                  .getTopLeft(find.byKey(Key('calendar-$part-202608$day')))
                  .dy,
              closeTo(left, .01),
              reason: '$part must not move when a cell is selected',
            );
          }
        }
        await _tap(tester, 'calendar-day-20260825');
        await tester.tap(find.byTooltip(locale == 'zh' ? '关闭' : 'Close'));
        await tester.pumpAndSettle();
        for (final part in positions.keys) {
          for (final day in [25, 26, 27]) {
            expect(
              tester
                  .getTopLeft(find.byKey(Key('calendar-$part-202608$day')))
                  .dy,
              closeTo(positions[part]!, .01),
              reason:
                  'Selection and today outlines must only change paint, not $part geometry',
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'theme changes retain calendar focus, geometry, scroll and open timeline',
    (tester) async {
      final appearance = ValueNotifier((AppThemeStyle.paper, Brightness.light));
      addTearDown(appearance.dispose);
      final note = _note('主题切换保留这条笔记', DateTime(2026, 7, 27, 9));
      await _pumpCalendar(tester, notes: [note], appearance: appearance);
      await _tap(tester, 'calendar-previous-period');
      final state = tester.state(find.byType(NoteCalendarPage));
      final grid = tester.getRect(find.byKey(const Key('note-calendar-grid')));
      final navigation = tester.getRect(
        find.byKey(const Key('calendar-navigation')),
      );
      appearance.value = (AppThemeStyle.starlight, Brightness.light);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(NoteCalendarPage)), same(state));
      expect(_focus(tester, NoteCalendarView.month), DateTime(2026, 7, 27));
      expect(tester.getRect(find.byKey(const Key('note-calendar-grid'))), grid);
      expect(
        tester.getRect(find.byKey(const Key('calendar-navigation'))),
        navigation,
      );
      expect(_countText(tester, 20260727), '1 条');
      await _tap(tester, 'calendar-day-20260727');
      appearance.value = (AppThemeStyle.starlight, Brightness.dark);
      await tester.pumpAndSettle();
      expect(find.text(note.title), findsOneWidget);
      final sheet = find.byKey(const Key('note-day-timeline-sheet'));
      expect(sheet, findsOneWidget);
      expect(tester.element(sheet).appColors, AppPalette.starlightDark);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await _tap(tester, 'calendar-view-year');
      await tester.drag(
        find.byKey(const Key('calendar-year-grid-2026')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('calendar-year-grid-2026')),
          matching: find.byType(Scrollable),
        ),
      );
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(0));
      appearance.value = (AppThemeStyle.paper, Brightness.light);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(NoteCalendarPage)), same(state));
      expect(_focus(tester, NoteCalendarView.year), DateTime(2026, 7, 27));
      expect(scrollable.position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens the original timeline in descending edit time', (
    tester,
  ) async {
    final notes = [
      _note('上午记录', DateTime(2026, 8, 27, 9)),
      _note('下午记录', DateTime(2026, 8, 27, 15)),
    ];
    final fixture = await _pumpCalendar(tester, notes: notes);
    await _tap(tester, 'calendar-day-20260827');
    expect(find.byKey(const Key('note-day-timeline-sheet')), findsOneWidget);
    expect(find.text('笔记时间轴 · 2 条笔记'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('下午记录')).dy,
      lessThan(tester.getTopLeft(find.text('上午记录')).dy),
    );
    await _tap(tester, 'calendar-note-${notes.last.id.value}');
    expect(fixture.openedNote?.id, notes.last.id);
    expect(find.byKey(const Key('note-day-timeline-sheet')), findsNothing);
  });

  testWidgets(
    'empty dates still open the timeline and return to the calendar',
    (tester) async {
      await _pumpCalendar(tester);
      await _tap(tester, 'calendar-day-20260827');
      expect(find.text('这一天没有笔记'), findsNWidgets(2));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-month-view')), findsOneWidget);
      expect(find.byKey(const Key('note-day-timeline-sheet')), findsNothing);
    },
  );

  testWidgets(
    'month title and year tab open the year, a month drills back in',
    (tester) async {
      await _pumpCalendar(tester, notes: [_note('记录', DateTime(2026, 8, 27))]);
      await _tap(tester, 'calendar-period-title');
      expect(find.byKey(const Key('calendar-year-view')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('2026'), findsOneWidget);
      final grid = tester.widget<GridView>(
        find.byKey(const Key('calendar-year-grid-2026')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      await tester.ensureVisible(
        find.byKey(const Key('calendar-mini-month-2026-8')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('calendar-mini-mark-20260827')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('calendar-month-count-8')), findsOneWidget);
      await _tap(tester, 'calendar-mini-month-2026-8');
      expect(_focus(tester, NoteCalendarView.month), DateTime(2026, 8, 27));
      await _tap(tester, 'calendar-view-year');
      expect(find.byKey(const Key('calendar-year-view')), findsOneWidget);
    },
  );

  for (final view in NoteCalendarView.values) {
    testWidgets(
      '${view.name} follows the finger and previews the adjacent period',
      (tester) async {
        await _pumpCalendar(tester);
        await _tap(tester, 'calendar-view-${view.name}');
        final current = find.byKey(Key('calendar-${view.name}-view'));
        final original = tester.getRect(current);
        final header = tester.getRect(
          find.byKey(const Key('calendar-period-title')),
        );
        final navigation = tester.getRect(
          find.byKey(const Key('calendar-navigation')),
        );
        final gesture = await tester.startGesture(original.center);
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump();
        await gesture.moveBy(Offset(-original.width * .35, 0));
        await tester.pump();
        final preview = find.byKey(Key('calendar-${view.name}-view-preview-1'));
        final moving = tester.getRect(current);
        final incoming = tester.getRect(preview);
        expect(moving.left, lessThan(original.left - 24));
        expect(moving.right, greaterThan(original.left));
        expect(incoming.left, closeTo(moving.right, .01));
        expect(incoming.intersect(original).width, greaterThan(24));
        expect(_focus(tester, view), DateTime(2026, 8, 27));
        expect(
          tester.getRect(find.byKey(const Key('calendar-period-title'))),
          header,
        );
        expect(
          tester.getRect(find.byKey(const Key('calendar-navigation'))),
          navigation,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(current), moving);
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.getRect(current).left, lessThan(moving.left));
        await tester.pumpAndSettle();
        expect(
          _focus(tester, view),
          NoteCalendarDates.shift(DateTime(2026, 8, 27), view, 1),
        );
        // The next period's header may wrap differently; horizontal alignment
        // and the fixed navigation boundary must remain unchanged.
        final settled = tester.getRect(current);
        expect(settled.left, original.left);
        expect(settled.right, original.right);
        expect(settled.bottom, original.bottom);
        expect(preview, findsNothing);
        expect(find.byKey(const Key('note-day-timeline-sheet')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${view.name} swipes change one period in either direction', (
      tester,
    ) async {
      final base = DateTime(2026, 12, 31);
      await _pumpCalendar(tester, now: base);
      await _tap(tester, 'calendar-view-${view.name}');
      await _swipe(tester, -240);
      expect(_focus(tester, view), NoteCalendarDates.shift(base, view, 1));
      await _swipe(tester, 240);
      expect(_focus(tester, view), base);
      await _tap(tester, 'calendar-previous-period');
      expect(_focus(tester, view), NoteCalendarDates.shift(base, view, -1));
      await _tap(tester, 'calendar-today');
      expect(_focus(tester, view), base);
    });
  }

  testWidgets('a short drag springs back without replacing the scrolled year', (
    tester,
  ) async {
    await _pumpCalendar(tester);
    await _tap(tester, 'calendar-view-year');
    final grid = find.byKey(const Key('calendar-year-grid-2026'));
    await tester.drag(grid, const Offset(0, -150));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: grid, matching: find.byType(Scrollable)),
    );
    final offset = scrollable.position.pixels;
    expect(offset, greaterThan(0));
    final current = find.byKey(const Key('calendar-year-view'));
    final original = tester.getRect(current);
    final gesture = await tester.startGesture(original.center);
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-45, 0));
    await tester.pump();
    expect(tester.getRect(current).left, lessThan(original.left));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(current), original);
    expect(_focus(tester, NoteCalendarView.year), DateTime(2026, 8, 27));
    expect(
      tester.state(
        find.descendant(of: grid, matching: find.byType(Scrollable)),
      ),
      same(scrollable),
    );
    expect(scrollable.position.pixels, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today and scale controls cancel a pending period transition', (
    tester,
  ) async {
    await _pumpCalendar(tester);
    for (final control in [
      'calendar-today',
      'calendar-view-month',
      'calendar-view-year',
    ]) {
      await tester.tap(find.byKey(const Key('calendar-next-period')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const Key('calendar-month-view-preview-1')),
        findsOneWidget,
      );
      await _tap(tester, control);
      expect(
        _focus(
          tester,
          control == 'calendar-view-year'
              ? NoteCalendarView.year
              : NoteCalendarView.month,
        ),
        DateTime(2026, 8, 27),
      );
      expect(
        find.byKey(const Key('calendar-month-view-preview-1')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion keeps direct dragging but settles immediately', (
    tester,
  ) async {
    await _pumpCalendar(tester, reduceMotion: true);
    final current = find.byKey(const Key('calendar-month-view'));
    final original = tester.getRect(current);
    final gesture = await tester.startGesture(original.center);
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(Offset(-original.width * .4, 0));
    await tester.pump();
    expect(tester.getRect(current).left, lessThan(original.left));
    await gesture.up();
    await tester.pump();
    expect(_focus(tester, NoteCalendarView.month), DateTime(2026, 9, 27));
    expect(
      find.byKey(const Key('calendar-month-view-preview-1')),
      findsNothing,
    );
    expect(tester.getRect(current), original);
    expect(tester.takeException(), isNull);
  });

  for (final (boundary, distance) in [
    (NoteCalendarDates.first, 240.0),
    (NoteCalendarDates.last, -240.0),
  ]) {
    testWidgets('swipes cannot cross the supported date boundary $boundary', (
      tester,
    ) async {
      await _pumpCalendar(tester, now: boundary);
      await _swipe(tester, distance);
      expect(_focus(tester, NoteCalendarView.month), boundary);
      expect(find.byKey(const Key('calendar-period-slot--1')), findsNothing);
      expect(find.byKey(const Key('calendar-period-slot-1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching scales retains focus and adjacent-month taps work', (
    tester,
  ) async {
    await _pumpCalendar(tester);
    await _tap(tester, 'calendar-day-20260901');
    expect(find.byKey(const Key('note-day-timeline-sheet')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    for (final view in NoteCalendarView.values) {
      await _tap(tester, 'calendar-view-${view.name}');
      expect(_focus(tester, view), DateTime(2026, 9, 1));
    }
  });

  testWidgets('week and day open visible notes directly without a sheet', (
    tester,
  ) async {
    final note = _note('本日记录', today);
    final fixture = await _pumpCalendar(tester, notes: [note]);
    for (final view in [NoteCalendarView.week, NoteCalendarView.day]) {
      await _tap(tester, 'calendar-view-${view.name}');
      expect(find.text('本日记录'), findsOneWidget);
      expect(find.text('本日记录 正文'), findsOneWidget);
      expect(find.text('15:30'), findsOneWidget);
      await _tap(tester, 'calendar-note-${note.id.value}');
      expect(fixture.openedNote?.id, note.id);
      expect(find.byType(BottomSheet), findsNothing);
      expect(_focus(tester, view), DateTime(2026, 8, 27));
      fixture.openedNote = null;
    }
  });

  testWidgets('week previews two latest notes and drills into the full day', (
    tester,
  ) async {
    final notes = [
      for (var hour = 9; hour < 14; hour++)
        _note('记录 $hour', DateTime(2026, 8, 27, hour)),
    ];
    final fixture = await _pumpCalendar(
      tester,
      notes: [...notes, _note('隐私记录', today).copyWith(isPrivate: true)],
    );
    await _tap(tester, 'calendar-view-week');
    expect(find.text('本周 5 条笔记 · 1 天有记录'), findsOneWidget);
    expect(find.text('记录 13'), findsOneWidget);
    expect(find.text('记录 12'), findsOneWidget);
    expect(find.text('记录 11'), findsNothing);
    expect(find.text('隐私记录'), findsNothing);
    expect(
      tester.getTopLeft(find.text('记录 13')).dy,
      lessThan(tester.getTopLeft(find.text('记录 12')).dy),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('calendar-week-day-20260828')))
          .height,
      lessThan(
        tester
            .getSize(find.byKey(const Key('calendar-week-day-20260827')))
            .height,
      ),
    );
    await _tap(tester, 'calendar-week-more-20260827');
    expect(_focus(tester, NoteCalendarView.day), DateTime(2026, 8, 27));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('5 条笔记'), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const Key('calendar-day-scroll-20260827')),
      matching: find.byType(Scrollable),
    );
    final oldest = find.byKey(Key('calendar-note-${notes.first.id.value}'));
    await tester.scrollUntilVisible(oldest, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(oldest);
    await tester.pumpAndSettle();
    expect(fixture.openedNote?.id, notes.first.id);
    expect(find.text('隐私记录'), findsNothing);
    await _tap(tester, 'calendar-view-week');
    await _tap(tester, 'calendar-day-20260828');
    expect(_focus(tester, NoteCalendarView.day), DateTime(2026, 8, 28));
    expect(find.byKey(const Key('calendar-day-empty')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('day keeps every note reachable and resets scrolling on paging', (
    tester,
  ) async {
    final notes = [
      for (var minute = 0; minute < 50; minute++)
        _note('当天记录 $minute', DateTime(2026, 8, 27, 12, minute)),
      _note('第二天记录', DateTime(2026, 8, 28)),
    ];
    final fixture = await _pumpCalendar(tester, notes: notes);
    await _tap(tester, 'calendar-view-day');
    expect(find.text('50 条笔记'), findsOneWidget);
    expect(find.text('当天记录 49'), findsOneWidget);
    expect(find.text('第二天记录'), findsNothing);
    final scrollable = find.descendant(
      of: find.byKey(const Key('calendar-day-scroll-20260827')),
      matching: find.byType(Scrollable),
    );
    final oldest = find.byKey(Key('calendar-note-${notes.first.id.value}'));
    await tester.scrollUntilVisible(
      oldest,
      600,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(_focus(tester, NoteCalendarView.day), DateTime(2026, 8, 27));
    await tester.tap(oldest);
    await tester.pumpAndSettle();
    expect(fixture.openedNote?.id, notes.first.id);
    await _tap(tester, 'calendar-next-period');
    expect(find.text('第二天记录'), findsOneWidget);
    expect(find.text('当天记录 0'), findsNothing);
    final nextScroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('calendar-day-scroll-20260828')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(nextScroll.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline notes refresh after opening, moving, hiding and deleting',
    (tester) async {
      final note = _note('待编辑', today);
      final fixture = await _pumpCalendar(tester, notes: [note]);
      await _tap(tester, 'calendar-view-day');
      fixture.onOpenNote = (opened) async {
        fixture.store.notes[0] = opened.copyWith(
          title: '已编辑',
          document: NoteDocument.fromPlainText('更新后的正文'),
        );
      };
      await _tap(tester, 'calendar-note-${note.id.value}');
      expect(find.text('已编辑'), findsOneWidget);
      expect(find.text('更新后的正文'), findsOneWidget);
      fixture.store.notes[0] = fixture.store.notes[0].copyWith(
        updatedAt: DateTime(2026, 8, 28),
      );
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-day-empty')), findsOneWidget);
      await _tap(tester, 'calendar-view-week');
      expect(_countText(tester, 20260827), '0 条');
      expect(_countText(tester, 20260828), '1 条');
      expect(find.text('已编辑'), findsOneWidget);
      fixture.store.notes[0] = fixture.store.notes[0].copyWith(isPrivate: true);
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('已编辑'), findsNothing);
      expect(find.text('本周 0 条笔记 · 0 天有记录'), findsOneWidget);
      fixture.store.notes.clear();
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      await _tap(tester, 'calendar-day-20260828');
      expect(find.byKey(const Key('calendar-day-empty')), findsOneWidget);
    },
  );

  testWidgets(
    'day shows tags and meaningful previews for attachment-only notes',
    (tester) async {
      final assetId = NoteAttachmentId.generate();
      final note = _note('', today).copyWith(
        tags: ['旅行', '灵感', '备忘', '更多标签'],
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.attachment(assetId).toDeltaData())
            ..insert('\n'),
        ),
        assets: [
          NoteAsset(
            id: assetId,
            kind: NoteAssetKind.image,
            storageKey: 'notes/images/calendar-test.png',
            originalName: '旅行照片.png',
            byteLength: 100,
            mimeType: 'image/png',
            createdAt: today,
            updatedAt: today,
          ),
        ],
      );
      await _pumpCalendar(tester, notes: [note]);
      await _tap(tester, 'calendar-view-day');
      expect(find.text('无标题'), findsOneWidget);
      expect(find.text('旅行照片.png'), findsOneWidget);
      expect(find.text('#旅行'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('图片 · 1 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('year title offers a year picker without losing the scale', (
    tester,
  ) async {
    await _pumpCalendar(tester);
    await _tap(tester, 'calendar-view-year');
    await _tap(tester, 'calendar-period-title');
    expect(find.byKey(const Key('calendar-year-picker')), findsOneWidget);
    await tester.tap(find.text('2027年'));
    await tester.pumpAndSettle();
    expect(_focus(tester, NoteCalendarView.year), DateTime(2027, 8, 27));
    expect(find.byKey(const Key('calendar-year-picker')), findsNothing);
  });

  testWidgets('vertical scrolling and small horizontal drags do not page', (
    tester,
  ) async {
    await _pumpCalendar(tester);
    await _tap(tester, 'calendar-view-year');
    final bar = tester.getRect(find.byKey(const Key('calendar-navigation')));
    await tester.drag(
      find.byKey(const Key('calendar-swipe-area')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(_focus(tester, NoteCalendarView.year), DateTime(2026, 8, 27));
    expect(tester.getRect(find.byKey(const Key('calendar-navigation'))), bar);
    await _swipe(tester, 35);
    expect(_focus(tester, NoteCalendarView.year), DateTime(2026, 8, 27));
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('fixed home action works from every scale', (tester) async {
    final fixture = await _pumpCalendar(tester, routed: true);
    for (final view in NoteCalendarView.values) {
      await tester.tap(find.text('打开日历'));
      await tester.pumpAndSettle();
      await _tap(tester, 'calendar-view-${view.name}');
      final home = find.byKey(const Key('calendar-back-home'));
      expect(tester.getSize(home).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(home).width, greaterThanOrEqualTo(48));
      await _tap(tester, 'calendar-back-home');
      expect(find.byKey(const Key('test-home')), findsOneWidget);
      expect(find.byType(NoteCalendarPage), findsNothing);
    }
    expect(fixture.controller.notes, isEmpty);
  });

  testWidgets('system back dismisses a timeline before leaving the calendar', (
    tester,
  ) async {
    final fixture = await _pumpCalendar(tester, routed: true);
    await tester.tap(find.text('打开日历'));
    await tester.pumpAndSettle();
    await _tap(tester, 'calendar-day-20260827');
    await fixture.navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(NoteCalendarPage), findsOneWidget);
    expect(find.byKey(const Key('note-day-timeline-sheet')), findsNothing);
    await fixture.navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-home')), findsOneWidget);
  });

  testWidgets(
    'counts use local edit dates, exclude private notes and refresh',
    (tester) async {
      final ordinary = _note('公开', DateTime(2026, 8, 27, 23, 50).toUtc());
      final private = _note('隐私', today).copyWith(isPrivate: true);
      final fixture = await _pumpCalendar(tester, notes: [ordinary, private]);
      expect(_countText(tester, 20260827), '1 条');
      await _tap(tester, 'calendar-day-20260827');
      expect(find.text('隐私'), findsNothing);
      fixture.store.notes.add(_note('新记录', today));
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('笔记时间轴 · 2 条笔记'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(_countText(tester, 20260827), '2 条');
      fixture.store.notes.removeWhere((note) => !note.isPrivate);
      await fixture.controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-count-20260827')), findsNothing);
    },
  );

  testWidgets('day controls expose complete dates and accessible tap actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCalendar(tester, notes: [_note('记录', today)]);
      final day = find.bySemanticsLabel(RegExp('2026年8月27日.*农历七月十五.*1 条笔记'));
      expect(day, findsOneWidget);
      expect(
        tester
            .getSemantics(day)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'today refreshes after midnight without moving the browsed date',
    (tester) async {
      final fixture = await _pumpCalendar(
        tester,
        now: DateTime(2026, 8, 27, 23, 59, 50),
      );
      fixture.clock = DateTime(2026, 8, 28);
      await tester.pump(const Duration(seconds: 10));
      final month = tester.widget<NoteCalendarMonthView>(
        find.byType(NoteCalendarMonthView),
      );
      expect(month.today, DateTime(2026, 8, 28));
      expect(month.focus, DateTime(2026, 8, 27));
      await _tap(tester, 'calendar-today');
      expect(_focus(tester, NoteCalendarView.month), DateTime(2026, 8, 28));
    },
  );

  testWidgets('failed count refresh is visible and retry recovers', (
    tester,
  ) async {
    final fixture = await _pumpCalendar(tester);
    fixture.store.fail = true;
    await fixture.controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('笔记数量加载失败，请重试'), findsOneWidget);
    fixture.store.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('笔记数量加载失败，请重试'), findsNothing);
  });

  for (final (size, scale, locale) in [
    (const Size(320, 568), 1.0, 'zh'),
    (const Size(320, 568), 2.0, 'zh'),
    (const Size(320, 568), 2.0, 'en'),
    (const Size(932, 430), 1.3, 'en'),
  ]) {
    testWidgets(
      'all scales fit ${size.width}x${size.height} at $scale $locale',
      (tester) async {
        await _pumpCalendar(
          tester,
          size: size,
          textScale: scale,
          locale: locale,
          notes: [_note('记录', today)],
        );
        for (final view in NoteCalendarView.values) {
          await _tap(tester, 'calendar-view-${view.name}');
          expect(find.byKey(Key('calendar-${view.name}-view')), findsOneWidget);
          final bar = tester.getRect(
            find.byKey(const Key('calendar-navigation')),
          );
          final content = tester.getRect(
            find.byKey(Key('calendar-${view.name}-view')),
          );
          expect(content.bottom, lessThanOrEqualTo(bar.top));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Color? _dateTextColor(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).style!.color;

DateTime _focus(WidgetTester tester, NoteCalendarView view) => switch (view) {
  NoteCalendarView.year =>
    tester
        .widget<NoteCalendarYearView>(
          find.byKey(const Key('calendar-year-view')),
        )
        .focus,
  NoteCalendarView.month =>
    tester
        .widget<NoteCalendarMonthView>(
          find.byKey(const Key('calendar-month-view')),
        )
        .focus,
  NoteCalendarView.week =>
    tester
        .widget<NoteCalendarWeekView>(
          find.byKey(const Key('calendar-week-view')),
        )
        .focus,
  NoteCalendarView.day =>
    tester
        .widget<NoteCalendarDayView>(find.byKey(const Key('calendar-day-view')))
        .day,
};

String? _countText(WidgetTester tester, int day) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(Key('calendar-count-$day')),
        matching: find.byType(Text),
      ),
    )
    .data;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _swipe(WidgetTester tester, double distance) async {
  final area = tester.getRect(find.byKey(const Key('calendar-swipe-area')));
  final start = Offset(
    distance < 0 ? area.right - 24 : area.left + 24,
    area.center.dy,
  );
  await tester.dragFrom(start, Offset(distance, 0));
  await tester.pumpAndSettle();
}

Future<_Fixture> _pumpCalendar(
  WidgetTester tester, {
  List<Note> notes = const [],
  DateTime? now,
  Size size = const Size(430, 932),
  double textScale = 1,
  String locale = 'zh',
  bool routed = false,
  bool reduceMotion = false,
  ValueNotifier<(AppThemeStyle, Brightness)>? appearance,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _CalendarStore(List.of(notes));
  final controller = NoteLibraryController(storeLoader: () async => store);
  addTearDown(controller.dispose);
  await controller.initialize();
  final fixture = _Fixture(
    store,
    controller,
    now ?? DateTime(2026, 8, 27, 15, 30),
  );
  Widget page() => NoteCalendarPage(
    controller: controller,
    now: () => fixture.clock,
    onOpenNote: (note) async {
      fixture.openedNote = note;
      await fixture.onOpenNote?.call(note);
    },
  );
  final theme =
      appearance ?? ValueNotifier((AppThemeStyle.paper, Brightness.light));
  if (appearance == null) addTearDown(theme.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder<(AppThemeStyle, Brightness)>(
      valueListenable: theme,
      builder: (context, value, _) => MaterialApp(
        theme: buildAppTheme(value.$1, value.$2),
        navigatorKey: fixture.navigator,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: routed
            ? Scaffold(
                key: const Key('test-home'),
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => page()),
                    ),
                    child: const Text('打开日历'),
                  ),
                ),
              )
            : page(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Note _note(String title, DateTime updatedAt) => Note(
  id: NoteId.generate(),
  title: title,
  document: NoteDocument.fromPlainText('$title 正文'),
  revision: 1,
  createdAt: DateTime.utc(2025),
  updatedAt: updatedAt,
);

final class _Fixture {
  _Fixture(this.store, this.controller, this.clock);
  final _CalendarStore store;
  final NoteLibraryController controller;
  DateTime clock;
  Note? openedNote;
  Future<void> Function(Note)? onOpenNote;
  final navigator = GlobalKey<NavigatorState>();
}

final class _CalendarStore implements NoteLibraryStore {
  _CalendarStore(this.notes);
  final List<Note> notes;
  var fail = false;

  @override
  Future<List<Note>> list() async {
    if (fail) throw StateError('test read failed');
    return List.of(notes);
  }

  @override
  Future<List<Note>> search(String query) => list();

  @override
  Future<Note> update(Note note) async => note;

  @override
  Future<void> deletePermanently(Note note) async {}
}
