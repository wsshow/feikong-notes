import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_calendar.dart';
import '../providers/note_library_controller.dart';
import '../services/calendar_lunar_service.dart';
import '../widgets/app_icon.dart';
import '../widgets/editorial_paper_surface.dart';
import '../widgets/note_calendar_pager.dart';
import '../widgets/note_calendar_views.dart';
import '../widgets/sunny_growth_decoration.dart';

typedef NoteCalendarOpener = Future<void> Function(Note note);

final class NoteCalendarPage extends StatefulWidget {
  const NoteCalendarPage({
    required this.controller,
    required this.onOpenNote,
    this.now,
    super.key,
  });

  final NoteLibraryController controller;
  final NoteCalendarOpener onOpenNote;
  final DateTime Function()? now;

  @override
  State<NoteCalendarPage> createState() => _NoteCalendarPageState();
}

final class _NoteCalendarPageState extends State<NoteCalendarPage>
    with WidgetsBindingObserver {
  final _lunar = CalendarLunarService();
  final _pager = GlobalKey<NoteCalendarPagerState>();
  var _view = NoteCalendarView.month;
  late DateTime _focus;
  Timer? _midnightTimer;
  List<Note>? _indexedNotes;
  final _notesByDay = <int, List<Note>>{};
  var _daySheetOpen = false;
  var _openingNote = false;

  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toLocal();
  DateTime get _today => NoteCalendarDates.day(_now);

  @override
  void initState() {
    super.initState();
    _focus = NoteCalendarDates.clamp(_today);
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setState(() {});
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now;
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(midnight.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  void _indexNotes() {
    final notes = widget.controller.notes;
    if (identical(notes, _indexedNotes)) return;
    _indexedNotes = notes;
    _notesByDay.clear();
    for (final note in notes) {
      if (note.isPrivate != widget.controller.privateSpace) continue;
      _notesByDay
          .putIfAbsent(
            NoteCalendarDates.key(note.updatedAt.toLocal()),
            () => [],
          )
          .add(note);
    }
    for (final notes in _notesByDay.values) {
      notes.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    }
  }

  List<Note> _notesForDay(DateTime day) =>
      _notesByDay[NoteCalendarDates.key(day)] ?? const [];

  int _count(DateTime day) => _notesForDay(day).length;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('note-calendar-page'),
    extendBody: context.appComponents.usesFloatingNavigationDock,
    backgroundColor: context.appColors.paperPrimary,
    body: AppThemeCanvas(
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            _indexNotes();
            return Column(
              children: [
                _buildHeader(context),
                if (widget.controller.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.calendarLoadFailed,
                            style: TextStyle(
                              color: context.appColors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              unawaited(widget.controller.refresh()),
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                if (widget.controller.isLoading)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: context.appColors.ink,
                    backgroundColor: context.appColors.line,
                  )
                else
                  const SizedBox(height: 2),
                Expanded(
                  child: NoteCalendarPager(
                    key: _pager,
                    period: (_view, _focus),
                    canPrevious: _canChange(-1),
                    canNext: _canChange(1),
                    adjacentBuilder: (offset) => _buildView(offset: offset),
                    onChanged: (offset) => setState(() {
                      _focus = NoteCalendarDates.shift(_focus, _view, offset);
                    }),
                    child: _buildView(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    bottomNavigationBar: _buildNavigation(context),
  );

  Widget _buildHeader(BuildContext context) {
    final locale = context.l10n.localeName;
    final sunny = context.appComponents.usesIllustratedCalendar;
    final titleStyle = sunny
        ? switch (_view) {
            NoteCalendarView.month => SunnyGrowthTokens.typeMonth,
            NoteCalendarView.year => SunnyGrowthTokens.typeYear,
            NoteCalendarView.week => SunnyGrowthTokens.typeSection,
            NoteCalendarView.day => SunnyGrowthTokens.typePage,
          }
        : (Theme.of(context).textTheme.headlineLarge ?? const TextStyle())
              .copyWith(
                fontSize: _view == NoteCalendarView.week ? 22 : 32,
                fontWeight: FontWeight.w600,
                height: 1.2,
              );
    final week = NoteCalendarDates.week(_focus);
    final title = switch (_view) {
      NoteCalendarView.year => '${_focus.year}',
      NoteCalendarView.month =>
        (locale.startsWith('zh')
                ? DateFormat.MMM(locale)
                : DateFormat.MMMM(locale))
            .format(_focus),
      NoteCalendarView.week =>
        '${DateFormat.Md(locale).format(week.first)} – ${DateFormat.Md(locale).format(week.last)}',
      NoteCalendarView.day => DateFormat.MMMMd(locale).format(_focus),
    };
    final heading = Tooltip(
      message: _view == NoteCalendarView.year
          ? context.l10n.calendarChooseYear
          : context.l10n.calendarShowYear,
      child: InkWell(
        key: const Key('calendar-period-title'),
        borderRadius: BorderRadius.circular(context.appRadii.small),
        onTap: _view == NoteCalendarView.year
            ? () {
                _pager.currentState?.cancelTransition();
                unawaited(_chooseYear());
              }
            : () => _selectView(NoteCalendarView.year),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _view == NoteCalendarView.year
                    ? context.l10n.calendarSubtitle
                    : _view == NoteCalendarView.week &&
                          week.first.year != week.last.year
                    ? '${week.first.year}–${week.last.year}'
                    : DateFormat.y(locale).format(_focus),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: sunny
                      ? context.appColors.link
                      : context.appColors.muted,
                  fontSize: sunny ? SunnyGrowthTokens.typeLabel.fontSize : 12,
                ),
              ),
              const SizedBox(height: 4),
              SunnyGrowthHeading(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const Key('calendar-period-label'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle.copyWith(color: context.appColors.ink),
                    ),
                    if (context.appComponents.usesPaperCraftDecoration) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: 54,
                        height: 3,
                        decoration: BoxDecoration(
                          color: context.appColors.decoration,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final today = TextButton(
      key: const Key('calendar-today'),
      style: TextButton.styleFrom(
        foregroundColor: context.appColors.accent,
        backgroundColor: context.appColors.surface,
        side: BorderSide(
          color: context.appColors.accent.withValues(alpha: sunny ? 1 : .28),
        ),
        shape: const StadiumBorder(),
        minimumSize: Size(64, sunny ? SunnyGrowthTokens.compControlHeight : 36),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () {
        _pager.currentState?.cancelTransition();
        setState(() => _focus = NoteCalendarDates.clamp(_today));
      },
      child: Text(context.l10n.today),
    );
    final arrows = [
      IconButton(
        key: const Key('calendar-previous-period'),
        tooltip: context.l10n.previousPage,
        onPressed: _canChange(-1) ? () => _changePeriod(-1) : null,
        icon: AppIcon(
          Icons.chevron_left_rounded,
          size: sunny ? SunnyGrowthTokens.compIconSize : 20,
        ),
      ),
      IconButton(
        key: const Key('calendar-next-period'),
        tooltip: context.l10n.nextPage,
        onPressed: _canChange(1) ? () => _changePeriod(1) : null,
        icon: AppIcon(
          Icons.chevron_right_rounded,
          size: sunny ? SunnyGrowthTokens.compIconSize : 20,
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    Row(children: [today, const Spacer(), ...arrows]),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: heading),
                    today,
                    ...arrows,
                  ],
                );
        },
      ),
    );
  }

  Widget _buildView({int offset = 0}) {
    final focus = offset == 0
        ? _focus
        : NoteCalendarDates.shift(_focus, _view, offset);
    final key = Key(
      'calendar-${_view.name}-view${offset == 0 ? '' : '-preview-$offset'}',
    );
    return switch (_view) {
      NoteCalendarView.year => NoteCalendarYearView(
        key: key,
        focus: focus,
        today: _today,
        count: _count,
        onMonth: (month) => setState(() {
          _focus = NoteCalendarDates.inMonth(focus.year, month, focus.day);
          _view = NoteCalendarView.month;
        }),
      ),
      NoteCalendarView.month => NoteCalendarMonthView(
        key: key,
        focus: focus,
        today: _today,
        count: _count,
        lunar: _lunar,
        onDay: (day) => unawaited(_openDay(day)),
      ),
      NoteCalendarView.week => NoteCalendarWeekView(
        key: key,
        focus: focus,
        today: _today,
        notesForDay: _notesForDay,
        lunar: _lunar,
        onDay: _selectDay,
        onOpenNote: (note) => unawaited(_openNote(note)),
      ),
      NoteCalendarView.day => NoteCalendarDayView(
        key: key,
        day: focus,
        notes: _notesForDay(focus),
        lunar: _lunar.forDay(focus),
        showEmptyState:
            !widget.controller.isLoading && !widget.controller.hasError,
        onOpenNote: (note) => unawaited(_openNote(note)),
      ),
    };
  }

  Widget _buildNavigation(BuildContext context) {
    if (context.appComponents.usesFloatingNavigationDock) {
      return _buildFloatingNavigation(context);
    }
    return AppBottomDock(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            key: const Key('calendar-navigation'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _viewButton(
                NoteCalendarView.year,
                context.l10n.calendarYear,
                Icons.calendar_month_outlined,
              ),
              _viewButton(
                NoteCalendarView.month,
                context.l10n.calendarMonth,
                Icons.calendar_today_outlined,
              ),
              _navigationButton(
                key: const Key('calendar-back-home'),
                label: context.l10n.home,
                tooltip: context.l10n.calendarBackHome,
                icon: Icons.home_outlined,
                selected: false,
                onTap: () => Navigator.maybePop(context),
              ),
              _viewButton(
                NoteCalendarView.week,
                context.l10n.calendarWeek,
                Icons.view_column_outlined,
              ),
              _viewButton(
                NoteCalendarView.day,
                context.l10n.calendarDay,
                Icons.table_rows_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingNavigation(BuildContext context) => AppBottomDock(
    child: SizedBox(
      height: AppBottomDock.floatingContentHeight,
      child: Row(
        key: const Key('calendar-navigation'),
        children: [
          _floatingViewButton(
            NoteCalendarView.year,
            context.l10n.calendarYear,
            Icons.calendar_month_outlined,
          ),
          _floatingViewButton(
            NoteCalendarView.month,
            context.l10n.calendarMonth,
            Icons.calendar_today_outlined,
          ),
          _CalendarDockDivider(color: context.appColors.line),
          Expanded(
            flex: 3,
            child: EditorialDockPrimaryAction(
              actionKey: const Key('calendar-back-home'),
              emblemKey: const Key('calendar-home-primary'),
              label: context.l10n.home,
              icon: Icons.home_outlined,
              iconSize: 23,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
          _CalendarDockDivider(color: context.appColors.line),
          _floatingViewButton(
            NoteCalendarView.week,
            context.l10n.calendarWeek,
            Icons.view_column_outlined,
          ),
          _floatingViewButton(
            NoteCalendarView.day,
            context.l10n.calendarDay,
            Icons.table_rows_outlined,
          ),
        ],
      ),
    ),
  );

  Widget _floatingViewButton(
    NoteCalendarView view,
    String label,
    IconData icon,
  ) {
    final selected = _view == view;
    return Expanded(
      flex: 2,
      child: Semantics(
        selected: selected,
        child: Tooltip(
          message: label,
          child: InkWell(
            key: ValueKey('calendar-view-${view.name}'),
            onTap: () => _selectView(view),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  key: ValueKey('calendar-view-${view.name}-icon-slot'),
                  width: 31,
                  height: 29,
                  child: Center(
                    child: AppIcon(
                      icon,
                      key: ValueKey('calendar-view-${view.name}-icon'),
                      size: 19,
                      color: selected
                          ? context.appColors.accent
                          : context.appColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  key: ValueKey('calendar-view-${view.name}-label'),
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewButton(NoteCalendarView view, String label, IconData icon) =>
      _navigationButton(
        key: ValueKey('calendar-view-${view.name}'),
        label: label,
        tooltip: label,
        icon: icon,
        selected: _view == view,
        onTap: () => _selectView(view),
      );

  Widget _navigationButton({
    required Key key,
    required String label,
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) => Expanded(
    child: Semantics(
      selected: selected,
      child: Tooltip(
        message: tooltip,
        child: TextButton(
          key: key,
          style: TextButton.styleFrom(
            foregroundColor: context.appColors.muted,
            minimumSize: const Size(48, 60),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.appRadii.medium),
            ),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                icon,
                key: key is ValueKey<String>
                    ? ValueKey('${key.value}-icon')
                    : null,
                size: context.appComponents.usesIllustratedCalendar
                    ? SunnyGrowthTokens.compNavigationIconSize
                    : 24,
                color: selected
                    ? context.appColors.accent
                    : context.appColors.muted,
              ),
              const SizedBox(height: 4),
              Text(
                key: key is ValueKey<String>
                    ? ValueKey('${key.value}-label')
                    : null,
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: context.appComponents.usesIllustratedCalendar
                      ? SunnyGrowthTokens.typeLabel.fontSize
                      : 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  bool _canChange(int offset) => !NoteCalendarDates.samePeriod(
    NoteCalendarDates.shift(_focus, _view, offset),
    _focus,
    _view,
  );

  void _selectView(NoteCalendarView view) {
    _pager.currentState?.cancelTransition();
    setState(() => _view = view);
  }

  void _selectDay(DateTime day) {
    _pager.currentState?.cancelTransition();
    setState(() {
      _focus = NoteCalendarDates.clamp(day);
      _view = NoteCalendarView.day;
    });
  }

  Future<void> _openNote(Note note) async {
    if (_openingNote) return;
    _openingNote = true;
    try {
      await widget.onOpenNote(note);
      if (mounted) await widget.controller.refresh();
    } finally {
      _openingNote = false;
    }
  }

  void _changePeriod(int offset) {
    if (!_canChange(offset)) return;
    _pager.currentState?.goToPeriod(offset);
  }

  Future<void> _chooseYear() => AppOverlay.bottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(context.l10n.calendarChooseYear)),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const AppIcon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: YearPicker(
              key: const Key('calendar-year-picker'),
              firstDate: NoteCalendarDates.first,
              lastDate: NoteCalendarDates.last,
              selectedDate: _focus,
              currentDate: _today,
              onChanged: (date) {
                setState(() {
                  _focus = NoteCalendarDates.inMonth(
                    date.year,
                    _focus.month,
                    _focus.day,
                  );
                });
                Navigator.pop(sheetContext);
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openDay(DateTime day) async {
    if (_daySheetOpen) return;
    _daySheetOpen = true;
    setState(() => _focus = NoteCalendarDates.clamp(day));
    try {
      await AppOverlay.bottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        builder: (sheetContext) => AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            _indexNotes();
            return _NoteDayTimelineSheet(
              day: day,
              notes: _notesForDay(day),
              onOpenNote: (note) async {
                Navigator.pop(sheetContext);
                await _openNote(note);
              },
            );
          },
        ),
      );
    } finally {
      _daySheetOpen = false;
    }
  }
}

final class _CalendarDockDivider extends StatelessWidget {
  const _CalendarDockDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(width: 1, height: 28, color: color.withValues(alpha: .62)),
  );
}

final class _NoteDayTimelineSheet extends StatelessWidget {
  const _NoteDayTimelineSheet({
    required this.day,
    required this.notes,
    required this.onOpenNote,
  });

  final DateTime day;
  final List<Note> notes;
  final NoteCalendarOpener onOpenNote;

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.localeName;
    return FractionallySizedBox(
      key: const Key('note-day-timeline-sheet'),
      heightFactor: .72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.yMMMMd(locale).format(day),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notes.isEmpty
                            ? context.l10n.noNotesOnDate
                            : '${context.l10n.noteTimeline} · ${context.l10n.noteCountShort(notes.length)}',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.noNotesOnDate,
                      style: TextStyle(color: context.appColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return _TimelineNote(
                        note: note,
                        last: index == notes.length - 1,
                        onTap: () => unawaited(onOpenNote(note)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

final class _TimelineNote extends StatelessWidget {
  const _TimelineNote({
    required this.note,
    required this.last,
    required this.onTap,
  });

  final Note note;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            DateFormat.Hm(
              context.l10n.localeName,
            ).format(note.updatedAt.toLocal()),
            style: TextStyle(color: context.appColors.muted, fontSize: 12),
          ),
        ),
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(top: 5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 8),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 1, color: context.appColors.line),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: context.appColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('calendar-note-${note.id.value}'),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.title.trim().isEmpty
                                ? context.l10n.untitled
                                : note.title.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (note.overviewText case final summary
                              when summary.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppIcon(
                      Icons.chevron_right_rounded,
                      color: context.appColors.subtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
