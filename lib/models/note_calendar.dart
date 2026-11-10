/// The four scales share one focused local date.
enum NoteCalendarView { year, month, week, day }

abstract final class NoteCalendarDates {
  static DateTime day(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static int key(DateTime value) =>
      value.year * 10000 + value.month * 100 + value.day;

  static bool sameDay(DateTime left, DateTime right) => key(left) == key(right);

  static bool samePeriod(
    DateTime left,
    DateTime right,
    NoteCalendarView view,
  ) => switch (view) {
    NoteCalendarView.year => left.year == right.year,
    NoteCalendarView.month =>
      left.year == right.year && left.month == right.month,
    NoteCalendarView.week => sameDay(weekStart(left), weekStart(right)),
    NoteCalendarView.day => sameDay(left, right),
  };

  static DateTime get first => DateTime(1);
  static DateTime get last => DateTime(9999, 12, 31);

  static DateTime clamp(DateTime value) => value.isBefore(first)
      ? first
      : value.isAfter(last)
      ? last
      : value;

  static DateTime inMonth(int year, int month, int preferredDay) {
    final length = DateTime(year, month + 1, 0).day;
    return clamp(DateTime(year, month, preferredDay.clamp(1, length)));
  }

  static DateTime shift(
    DateTime date,
    NoteCalendarView view,
    int offset,
  ) => switch (view) {
    NoteCalendarView.year => inMonth(date.year + offset, date.month, date.day),
    NoteCalendarView.month => inMonth(date.year, date.month + offset, date.day),
    // Calendar arithmetic, not elapsed 24-hour durations: DST changes
    // must not duplicate or skip a local day.
    NoteCalendarView.week => clamp(
      DateTime(date.year, date.month, date.day + offset * 7),
    ),
    NoteCalendarView.day => clamp(
      DateTime(date.year, date.month, date.day + offset),
    ),
  };

  static DateTime weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  static List<DateTime> week(DateTime date) {
    final start = weekStart(date);
    return [
      for (var index = 0; index < 7; index++)
        DateTime(start.year, start.month, start.day + index),
    ];
  }

  static List<DateTime> month(DateTime date, {bool sixWeeks = false}) {
    final first = DateTime(date.year, date.month);
    final start = weekStart(first);
    final length = DateTime(date.year, date.month + 1, 0).day;
    final count = sixWeeks ? 42 : ((first.weekday - 1 + length + 6) ~/ 7) * 7;
    return [
      for (var index = 0; index < count; index++)
        DateTime(start.year, start.month, start.day + index),
    ];
  }
}
