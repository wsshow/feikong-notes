import 'package:fknotes/models/note_calendar.dart';
import 'package:fknotes/services/calendar_lunar_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('month grids start on Monday and include adjacent dates', () {
    final august = NoteCalendarDates.month(DateTime(2026, 8));
    expect(august.length, 42);
    expect(august.first, DateTime(2026, 7, 27));
    expect(august.last, DateTime(2026, 9, 6));
    expect(august.map(NoteCalendarDates.key).toSet().length, 42);
    expect(NoteCalendarDates.month(DateTime(2021, 2)).length, 28);
    final leap = NoteCalendarDates.month(DateTime(2024, 2));
    expect(leap.length, 35);
    expect(leap, contains(DateTime(2024, 2, 29)));
    expect(
      NoteCalendarDates.month(DateTime(2021, 2), sixWeeks: true).length,
      42,
    );
  });

  test('month and year navigation clamp days at month boundaries', () {
    expect(
      NoteCalendarDates.shift(DateTime(2026, 1, 31), NoteCalendarView.month, 1),
      DateTime(2026, 2, 28),
    );
    expect(
      NoteCalendarDates.shift(DateTime(2024, 1, 31), NoteCalendarView.month, 1),
      DateTime(2024, 2, 29),
    );
    expect(
      NoteCalendarDates.shift(DateTime(2024, 2, 29), NoteCalendarView.year, 1),
      DateTime(2025, 2, 28),
    );
    expect(
      NoteCalendarDates.shift(
        DateTime(2026, 12, 31),
        NoteCalendarView.month,
        1,
      ),
      DateTime(2027, 1, 31),
    );
    expect(
      NoteCalendarDates.shift(
        DateTime(2026, 1, 31),
        NoteCalendarView.month,
        -1,
      ),
      DateTime(2025, 12, 31),
    );
  });

  test('weeks and days cross years with calendar rather than elapsed time', () {
    final week = NoteCalendarDates.week(DateTime(2026, 12, 31));
    expect(week.first, DateTime(2026, 12, 28));
    expect(week.last, DateTime(2027, 1, 3));
    expect(
      NoteCalendarDates.shift(DateTime(2026, 12, 31), NoteCalendarView.week, 1),
      DateTime(2027, 1, 7),
    );
    expect(
      NoteCalendarDates.shift(DateTime(2026, 12, 31), NoteCalendarView.day, 1),
      DateTime(2027, 1, 1),
    );
    for (final date in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
      expect(
        NoteCalendarDates.shift(date, NoteCalendarView.day, 1),
        DateTime(date.year, date.month, date.day + 1),
      );
    }
  });

  test('navigation stops at representable display years', () {
    for (final view in NoteCalendarView.values) {
      expect(
        NoteCalendarDates.shift(NoteCalendarDates.first, view, -1),
        NoteCalendarDates.first,
      );
      expect(
        NoteCalendarDates.shift(NoteCalendarDates.last, view, 1),
        NoteCalendarDates.last,
      );
    }
    expect(
      NoteCalendarDates.samePeriod(
        DateTime(9999, 8, 27),
        NoteCalendarDates.shift(
          DateTime(9999, 8, 27),
          NoteCalendarView.year,
          1,
        ),
        NoteCalendarView.year,
      ),
      isTrue,
    );
  });

  test('lunar conversion matches published civil calendar dates', () {
    // Hong Kong Observatory Gregorian-Lunar conversion tables, 2025 / 2026:
    // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2026e.pdf
    // https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2025e.pdf
    final service = CalendarLunarService();
    expect(service.forDay(DateTime(2026, 8, 27))!.fullDate, '七月十五');
    expect(service.forDay(DateTime(2026, 8, 13))!.label, '七月');
    expect(service.forDay(DateTime(2026, 2, 17))!.label, '春节');
    expect(service.forDay(DateTime(2026, 8, 7))!.label, '立秋');
    expect(service.forDay(DateTime(2026, 9, 25))!.label, '中秋节');
    expect(service.forDay(DateTime(2025, 7, 25))!.fullDate, '闰六月初一');
  });

  test(
    'display labels distinguish festivals, solar terms and ordinary dates',
    () {
      final service = CalendarLunarService();
      final festival = service.forDay(DateTime(2026, 8, 19))!;
      expect(festival.label, '七夕节');
      expect(festival.kind, CalendarDateKind.festival);
      expect(festival.description, '七月初七 · 七夕节');
      final term = service.forDay(DateTime(2026, 8, 7))!;
      expect(term.label, '立秋');
      expect(term.kind, CalendarDateKind.solarTerm);
      expect(term.description, contains('立秋'));
      final ordinary = service.forDay(DateTime(2026, 8, 13))!;
      expect(ordinary.kind, CalendarDateKind.ordinary);
      expect(ordinary.isSpecial, isFalse);
      expect(ordinary.description, ordinary.fullDate);
      final nationalDay = service.forDay(DateTime(2026, 10, 1))!;
      expect(nationalDay.label, '国庆节');
      expect(nationalDay.kind, CalendarDateKind.festival);
      expect(service.forDay(DateTime(2026, 1, 1))!.label, '元旦节');
      expect(service.forDay(DateTime(2026, 5, 10))!.label, '母亲节');
    },
  );

  test(
    'lunar cache is local-date based and does not fabricate remote years',
    () {
      final service = CalendarLunarService();
      final morning = service.forDay(DateTime(2026, 8, 27, 1));
      final night = service.forDay(DateTime(2026, 8, 27, 23).toUtc());
      expect(identical(morning, night), isTrue);
      expect(service.forDay(DateTime(1899, 12, 31)), isNull);
      expect(service.forDay(DateTime(2101)), isNull);
      expect(service.forDay(DateTime(1900)), isNotNull);
      expect(service.forDay(DateTime(2100, 12, 31)), isNotNull);
    },
  );
}
