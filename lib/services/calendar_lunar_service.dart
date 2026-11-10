import 'package:lunar/lunar.dart';

import '../models/note_calendar.dart';

enum CalendarDateKind { ordinary, festival, solarTerm }

final class CalendarLunarDate {
  const CalendarLunarDate({
    required this.label,
    required this.fullDate,
    required this.kind,
  });

  final String label;
  final String fullDate;
  final CalendarDateKind kind;

  bool get isSpecial => kind != CalendarDateKind.ordinary;
  String get description => isSpecial ? '$fullDate · $label' : fullDate;
}

/// Offline, civil-date conversion. Keep only display strings in a bounded cache;
/// a year overview never needs to construct hundreds of lunar ephemerides.
final class CalendarLunarService {
  final _cache = <int, CalendarLunarDate>{};

  CalendarLunarDate? forDay(DateTime date) {
    final day = NoteCalendarDates.day(date);
    // Outside the supported display range the Gregorian calendar still works.
    if (day.year < 1900 || day.year > 2100) return null;
    final key = NoteCalendarDates.key(day);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final lunar = Lunar.fromDate(day);
    final month = '${lunar.getMonthInChinese()}月';
    final lunarDay = lunar.getDayInChinese();
    final term = lunar.getJieQi();
    // Festival labels describe dates, never statutory days off or make-up work.
    final festivals = [
      ...lunar.getFestivals(),
      ...lunar.getSolar().getFestivals(),
    ];
    final result = CalendarLunarDate(
      label: festivals.isNotEmpty
          ? festivals.first
          : term.isNotEmpty
          ? term
          : lunar.getDay() == 1
          ? month
          : lunarDay,
      fullDate: '$month$lunarDay',
      kind: festivals.isNotEmpty
          ? CalendarDateKind.festival
          : term.isNotEmpty
          ? CalendarDateKind.solarTerm
          : CalendarDateKind.ordinary,
    );
    _cache[key] = result;
    if (_cache.length > 512) _cache.remove(_cache.keys.first);
    return result;
  }
}
