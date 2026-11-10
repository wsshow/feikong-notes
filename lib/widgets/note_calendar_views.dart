import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_calendar.dart';
import '../services/calendar_lunar_service.dart';
import 'app_icon.dart';
import 'note_calendar_note_card.dart';
import 'sunny_growth_decoration.dart';

typedef CalendarNoteCounter = int Function(DateTime day);

class NoteCalendarMonthView extends StatelessWidget {
  const NoteCalendarMonthView({
    required this.focus,
    required this.today,
    required this.count,
    required this.lunar,
    required this.onDay,
    super.key,
  });

  final DateTime focus;
  final DateTime today;
  final CalendarNoteCounter count;
  final CalendarLunarService lunar;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final days = NoteCalendarDates.month(focus);
    final weeks = days.length ~/ 7;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return LayoutBuilder(
      builder: (context, constraints) {
        final weekdayHeight = math.max(32.0, 22 * scale);
        final availableRowHeight =
            (constraints.maxHeight - weekdayHeight - 12) / weeks;
        final cellWidth = (constraints.maxWidth - 24) / 7;
        // Paper layouts keep a deliberate weekly rhythm instead of stretching
        // whitespace inside every row to consume the remaining viewport.
        final rowHeight = context.appComponents.usesPaperCraftDecoration
            ? math.max(96.0 * scale, cellWidth * 1.72)
            : math.max(90.0 * scale, availableRowHeight);
        return SingleChildScrollView(
          key: ValueKey('calendar-month-scroll-${focus.year}-${focus.month}'),
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            _calendarScrollEndPadding(context, 12),
          ),
          child: Column(
            key: const Key('note-calendar-grid'),
            children: [
              SizedBox(height: weekdayHeight, child: const _WeekdayLabels()),
              for (var week = 0; week < weeks; week++)
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final day in days.skip(week * 7).take(7))
                        Expanded(
                          child: day.year < 1 || day.year > 9999
                              ? const SizedBox.shrink()
                              : _MonthDay(
                                  day: day,
                                  lunar: lunar.forDay(day),
                                  noteCount: count(day),
                                  selected: NoteCalendarDates.sameDay(
                                    day,
                                    focus,
                                  ),
                                  today: NoteCalendarDates.sameDay(day, today),
                                  inMonth: day.month == focus.month,
                                  onTap: () => onDay(day),
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class NoteCalendarYearView extends StatelessWidget {
  const NoteCalendarYearView({
    required this.focus,
    required this.today,
    required this.count,
    required this.onMonth,
    super.key,
  });

  final DateTime focus;
  final DateTime today;
  final CalendarNoteCounter count;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final sunny = context.appComponents.usesIllustratedCalendar;
      final columns = sunny
          ? (scale > 1.7
                ? 1
                : (constraints.maxWidth < 360 || scale > 1.3 ? 2 : 3))
          : ((constraints.maxWidth - 32) / (108 * scale)).floor().clamp(1, 4);
      final rows = sunny ? 3 : (12 / columns).ceil();
      final gap = sunny ? AppSpacing.sm : 20.0;
      final height = math.max(
        sunny
            ? SunnyGrowthTokens.compYearCardMinHeight * scale
            : 52.0 * scale + 7 * 20 * scale,
        (constraints.maxHeight - 24 - (rows - 1) * gap) / rows,
      );
      return GridView.builder(
        key: ValueKey('calendar-year-grid-${focus.year}'),
        padding: EdgeInsets.fromLTRB(
          sunny ? AppSpacing.sm : 16,
          8,
          sunny ? AppSpacing.sm : 16,
          _calendarScrollEndPadding(context, 16),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: height,
          mainAxisSpacing: gap,
          crossAxisSpacing: sunny ? AppSpacing.xs : 12,
        ),
        itemCount: 12,
        itemBuilder: (context, index) => _MiniMonth(
          month: DateTime(focus.year, index + 1),
          focus: focus,
          today: today,
          count: count,
          onTap: () => onMonth(index + 1),
        ),
      );
    },
  );
}

class NoteCalendarWeekView extends StatelessWidget {
  const NoteCalendarWeekView({
    required this.focus,
    required this.today,
    required this.notesForDay,
    required this.lunar,
    required this.onDay,
    required this.onOpenNote,
    super.key,
  });

  final DateTime focus;
  final DateTime today;
  final List<Note> Function(DateTime day) notesForDay;
  final CalendarLunarService lunar;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<Note> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final days = NoteCalendarDates.week(
      focus,
    ).where((day) => day.year >= 1 && day.year <= 9999).toList();
    final notes = {for (final day in days) day: notesForDay(day)};
    final total = notes.values.fold(0, (sum, day) => sum + day.length);
    final activeDays = notes.values.where((day) => day.isNotEmpty).length;
    return SingleChildScrollView(
      key: ValueKey('calendar-week-list-${NoteCalendarDates.key(days.first)}'),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        _calendarScrollEndPadding(context, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              context.l10n.calendarWeekSummary(total, activeDays),
              key: const Key('calendar-week-summary'),
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
          ),
          for (final day in days)
            _WeekDay(
              day: day,
              lunar: lunar.forDay(day),
              notes: notes[day]!,
              selected: NoteCalendarDates.sameDay(day, focus),
              today: NoteCalendarDates.sameDay(day, today),
              onTap: () => onDay(day),
              onOpenNote: onOpenNote,
            ),
        ],
      ),
    );
  }
}

class NoteCalendarDayView extends StatelessWidget {
  const NoteCalendarDayView({
    required this.day,
    required this.notes,
    required this.lunar,
    required this.onOpenNote,
    this.showEmptyState = true,
    super.key,
  });

  final DateTime day;
  final List<Note> notes;
  final CalendarLunarDate? lunar;
  final ValueChanged<Note> onOpenNote;
  final bool showEmptyState;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: ValueKey('calendar-day-scroll-${NoteCalendarDates.key(day)}'),
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: _dateDescription(context, day, lunar, notes.length),
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: context.appColors.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${day.day}',
                        key: ValueKey(
                          'calendar-date-${NoteCalendarDates.key(day)}',
                        ),
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: _dayColor(context, day),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat.EEEE(
                                context.l10n.localeName,
                              ).format(day),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _dayColor(context, day),
                              ),
                            ),
                            if (lunar != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.calendarLunarDate(
                                  lunar!.description,
                                ),
                                key: ValueKey(
                                  'calendar-lunar-${NoteCalendarDates.key(day)}',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _lunarColor(context, lunar),
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
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    context.l10n.noteCountShort(notes.length),
                    key: ValueKey(
                      'calendar-count-${NoteCalendarDates.key(day)}',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.appColors.ink,
                    ),
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      context.l10n.calendarLatestFirst,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (notes.isEmpty && showEmptyState)
        SliverToBoxAdapter(
          child: Padding(
            key: const Key('calendar-day-empty'),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                AppIcon(
                  Icons.description_outlined,
                  size: 32,
                  color: context.appColors.subtle,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.noNotesOnDate,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.muted),
                ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          _calendarScrollEndPadding(context, 24),
        ),
        sliver: SliverList.builder(
          itemCount: notes.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NoteCalendarNoteCard(
              key: ValueKey(notes[index].id),
              note: notes[index],
              onTap: () => onOpenNote(notes[index]),
            ),
          ),
        ),
      ),
    ],
  );
}

double _calendarScrollEndPadding(BuildContext context, double base) =>
    base +
    (context.appComponents.usesFloatingNavigationDock
        ? AppBottomDock.floatingScrollClearance(context)
        : 0);

class _MonthDay extends StatelessWidget {
  static const _dateVerticalPadding = 4.0;
  static const _countGap = 6.0;

  const _MonthDay({
    required this.day,
    required this.lunar,
    required this.noteCount,
    required this.selected,
    required this.today,
    required this.inMonth,
    required this.onTap,
  });

  final DateTime day;
  final CalendarLunarDate? lunar;
  final int noteCount;
  final bool selected;
  final bool today;
  final bool inMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = [
      _dateDescription(context, day, lunar, noteCount),
      if (today) context.l10n.today,
    ].join(' · ');
    final showLunar =
        !context.appComponents.usesIllustratedCalendar ||
        MediaQuery.textScalerOf(context).scale(12) <= 20;
    final showToday =
        context.appComponents.usesIllustratedCalendar && today && selected;
    final foreground = selected
        ? context.appColors.onStrong
        : inMonth
        ? _dayColor(context, day)
        : context.appColors.subtle;
    final badge = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _CountBadge(
        key: ValueKey('calendar-count-${NoteCalendarDates.key(day)}'),
        count: noteCount,
        onSelected: selected,
      ),
    );
    return Semantics(
      label: description,
      button: true,
      onTap: onTap,
      selected: selected,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: InkWell(
          key: ValueKey('calendar-day-${NoteCalendarDates.key(day)}'),
          borderRadius: BorderRadius.circular(context.appRadii.date),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              children: [
                Container(
                  key: ValueKey(
                    'calendar-day-surface-${NoteCalendarDates.key(day)}',
                  ),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: _dateVerticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? context.appColors.accent : null,
                    gradient: selected
                        ? context.appColors.primaryGradient
                        : null,
                    borderRadius: BorderRadius.circular(context.appRadii.date),
                  ),
                  // Paint the today outline without adding a layout inset.
                  foregroundDecoration: today && !selected
                      ? BoxDecoration(
                          border: Border.all(
                            color: context.appColors.accent,
                            width: context.appComponents.usesIllustratedCalendar
                                ? SunnyGrowthTokens.compTodayStroke
                                : 1,
                          ),
                          borderRadius: BorderRadius.circular(
                            context.appRadii.date,
                          ),
                        )
                      : null,
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${day.day}',
                          key: ValueKey(
                            'calendar-date-${NoteCalendarDates.key(day)}',
                          ),
                          style: TextStyle(
                            fontSize:
                                context.appComponents.usesIllustratedCalendar
                                ? SunnyGrowthTokens.typeCalendarDay.fontSize
                                : 22,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
                      if (showLunar || showToday) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (showToday) context.l10n.calendarTodayMarker,
                            if (showLunar && lunar != null) lunar!.label,
                          ].join('·'),
                          key: ValueKey(
                            'calendar-lunar-${NoteCalendarDates.key(day)}',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            height: 1.2,
                            fontSize:
                                context.appComponents.usesIllustratedCalendar
                                ? SunnyGrowthTokens.typeCaption.fontSize
                                : 11,
                            color: selected
                                ? context.appColors.onStrong
                                : inMonth
                                ? _lunarColor(context, lunar)
                                : context.appColors.subtle,
                          ),
                        ),
                      ],
                      if (selected && noteCount > 0) ...[
                        // Match the date block's bottom padding plus the gap
                        // used by unselected cells; only the paint extends.
                        const SizedBox(
                          height: _dateVerticalPadding + _countGap,
                        ),
                        badge,
                      ],
                    ],
                  ),
                ),
                if (!selected && noteCount > 0) ...[
                  const SizedBox(height: _countGap),
                  badge,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.focus,
    required this.today,
    required this.count,
    required this.onTap,
  });

  final DateTime month;
  final DateTime focus;
  final DateTime today;
  final CalendarNoteCounter count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = NoteCalendarDates.month(month, sixWeeks: true);
    final total = days
        .where((day) => day.month == month.month)
        .fold<int>(0, (sum, day) => sum + count(day));
    return Semantics(
      label:
          '${DateFormat.yMMMM(context.l10n.localeName).format(month)} · ${context.l10n.noteCountShort(total)}',
      button: true,
      onTap: onTap,
      selected: focus.month == month.month,
      excludeSemantics: true,
      child: Material(
        color: context.appComponents.usesLayeredCalendarSurfaces
            ? context.appColors.surface
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.appRadii.large),
          side: context.appComponents.usesLayeredCalendarSurfaces
              ? BorderSide(color: context.appColors.line)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('calendar-mini-month-${month.year}-${month.month}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.appRadii.large),
          child: Padding(
            padding: context.appComponents.usesLayeredCalendarSurfaces
                ? const EdgeInsets.all(AppSpacing.xs)
                : EdgeInsets.zero,
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat.MMM(context.l10n.localeName).format(month),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:
                                context.appComponents.usesIllustratedCalendar
                                ? SunnyGrowthTokens.typeSection.fontSize
                                : 20,
                            fontWeight: month.month == focus.month
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: context.appColors.ink,
                          ),
                        ),
                      ),
                      if (total > 0)
                        Flexible(
                          child: _CountBadge(
                            key: ValueKey(
                              'calendar-month-count-${month.month}',
                            ),
                            count: total,
                          ),
                        ),
                    ],
                  ),
                ),
                const Expanded(child: _WeekdayLabels(compact: true)),
                for (var week = 0; week < 6; week++)
                  Expanded(
                    child: Row(
                      children: [
                        for (final day in days.skip(week * 7).take(7))
                          Expanded(
                            child: day.month != month.month
                                ? const SizedBox.shrink()
                                : _MiniDay(
                                    day: day,
                                    today: NoteCalendarDates.sameDay(
                                      day,
                                      today,
                                    ),
                                    selected: NoteCalendarDates.sameDay(
                                      day,
                                      focus,
                                    ),
                                    hasNotes: count(day) > 0,
                                  ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.day,
    required this.today,
    required this.selected,
    required this.hasNotes,
  });

  final DateTime day;
  final bool today;
  final bool selected;
  final bool hasNotes;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration:
              (context.appComponents.usesIllustratedCalendar ? selected : today)
              ? BoxDecoration(
                  color: context.appColors.accent,
                  gradient: context.appColors.primaryGradient,
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          foregroundDecoration:
              context.appComponents.usesIllustratedCalendar &&
                  today &&
                  !selected
              ? BoxDecoration(
                  border: Border.all(
                    color: context.appColors.accent,
                    width: SunnyGrowthTokens.compTodayStroke,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.xxs),
                )
              : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${day.day}',
              key: ValueKey('calendar-mini-date-${NoteCalendarDates.key(day)}'),
              style: TextStyle(
                fontSize: context.appComponents.usesIllustratedCalendar
                    ? SunnyGrowthTokens.typeMiniDay.fontSize
                    : 11,
                color:
                    (context.appComponents.usesIllustratedCalendar
                        ? selected
                        : today)
                    ? context.appColors.onStrong
                    : _dayColor(context, day),
                fontWeight: hasNotes ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
      if (hasNotes)
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: ValueKey('calendar-mini-mark-${NoteCalendarDates.key(day)}'),
            width: 8,
            height: 2,
            decoration: BoxDecoration(
              color: context.appColors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
    ],
  );
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.day,
    required this.lunar,
    required this.notes,
    required this.selected,
    required this.today,
    required this.onTap,
    required this.onOpenNote,
  });

  final DateTime day;
  final CalendarLunarDate? lunar;
  final List<Note> notes;
  final bool selected;
  final bool today;
  final VoidCallback onTap;
  final ValueChanged<Note> onOpenNote;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('calendar-week-day-${NoteCalendarDates.key(day)}'),
    padding: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.appColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: _dateDescription(context, day, lunar, notes.length),
          button: true,
          onTap: onTap,
          selected: selected,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('calendar-day-${NoteCalendarDates.key(day)}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? context.appColors.accent : null,
                      gradient: selected
                          ? context.appColors.primaryGradient
                          : null,
                      borderRadius: BorderRadius.circular(
                        context.appRadii.medium,
                      ),
                    ),
                    foregroundDecoration: today && !selected
                        ? BoxDecoration(
                            border: Border.all(color: context.appColors.accent),
                            borderRadius: BorderRadius.circular(
                              context.appRadii.medium,
                            ),
                          )
                        : null,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${day.day}',
                        key: ValueKey(
                          'calendar-date-${NoteCalendarDates.key(day)}',
                        ),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? context.appColors.onStrong
                              : _dayColor(context, day),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.MMMEd(context.l10n.localeName).format(day),
                          style: TextStyle(
                            fontSize:
                                context.appComponents.usesIllustratedCalendar
                                ? SunnyGrowthTokens.typeLabel.fontSize
                                : 13,
                            fontWeight: FontWeight.w500,
                            color: _dayColor(context, day),
                          ),
                        ),
                        if (lunar != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            lunar!.description,
                            key: ValueKey(
                              'calendar-lunar-${NoteCalendarDates.key(day)}',
                            ),
                            style: TextStyle(
                              color: _lunarColor(context, lunar),
                              fontSize:
                                  context.appComponents.usesIllustratedCalendar
                                  ? SunnyGrowthTokens.typeCaption.fontSize
                                  : 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CountBadge(
                    key: ValueKey(
                      'calendar-count-${NoteCalendarDates.key(day)}',
                    ),
                    count: notes.length,
                  ),
                  const SizedBox(width: 4),
                  AppIcon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: context.appColors.subtle,
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final note in notes.take(2))
          Padding(
            padding: const EdgeInsets.only(left: 60, bottom: 6),
            child: NoteCalendarNoteCard(
              key: ValueKey(note.id),
              note: note,
              compact: true,
              onTap: () => onOpenNote(note),
            ),
          ),
        if (notes.length > 2)
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey(
                  'calendar-week-more-${NoteCalendarDates.key(day)}',
                ),
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: context.appColors.accent,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(context.l10n.calendarViewAllNotes(notes.length)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.onSelected = false, super.key});

  final int count;
  final bool onSelected;

  @override
  Widget build(BuildContext context) =>
      context.appComponents.usesIllustratedCalendar && count == 0
      ? const SizedBox.shrink()
      : Tooltip(
          message: context.l10n.noteCountShort(count),
          child: Container(
            constraints: BoxConstraints(
              minWidth: 22,
              minHeight: context.appComponents.usesIllustratedCalendar ? 24 : 0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: onSelected
                  ? context.appColors.surface
                  : count > 0
                  ? context.appColors.accentSoft
                  : null,
              borderRadius: BorderRadius.circular(
                context.appComponents.usesIllustratedCalendar
                    ? AppRadius.pill
                    : AppRadius.small,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                context.appComponents.usesIllustratedCalendar && count > 99
                    ? '99+'
                    : context.l10n.calendarNoteCount(count),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: context.appComponents.usesIllustratedCalendar
                      ? SunnyGrowthTokens.typeCaption.fontSize
                      : 11,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color:
                      context.appComponents.usesIllustratedCalendar &&
                          onSelected
                      ? context.appColors.accent
                      : context.appColors.onAccentSoft,
                ),
              ),
            ),
          ),
        );
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final zh = context.l10n.localeName.startsWith('zh');
    const chinese = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Text(
              zh
                  ? chinese[index]
                  : (compact
                            ? DateFormat.EEEEE(context.l10n.localeName)
                            : DateFormat.E(context.l10n.localeName))
                        .format(DateTime(2024, 1, 1 + index)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: index >= 5
                    ? context.appColors.calendarWeekend
                    : context.appColors.muted,
                fontSize: context.appComponents.usesIllustratedCalendar
                    ? (compact
                          ? SunnyGrowthTokens.typeCaption.fontSize
                          : SunnyGrowthTokens.typeLabel.fontSize)
                    : (compact ? 10 : 12),
              ),
            ),
          ),
      ],
    );
  }
}

Color _dayColor(BuildContext context, DateTime day) =>
    day.weekday >= DateTime.saturday
    ? context.appColors.calendarWeekend
    : context.appColors.ink;

Color _lunarColor(BuildContext context, CalendarLunarDate? lunar) =>
    switch (lunar?.kind) {
      CalendarDateKind.festival => context.appColors.calendarFestival,
      CalendarDateKind.solarTerm => context.appColors.calendarSolarTerm,
      _ => context.appColors.muted,
    };

String _dateDescription(
  BuildContext context,
  DateTime day,
  CalendarLunarDate? lunar,
  int noteCount,
) => [
  DateFormat.yMMMMEEEEd(context.l10n.localeName).format(day),
  if (lunar != null) context.l10n.calendarLunarDate(lunar.fullDate),
  if (lunar != null && lunar.isSpecial) lunar.label,
  context.l10n.noteCountShort(noteCount),
].join(' · ');
