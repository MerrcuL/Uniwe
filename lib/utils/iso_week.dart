/// Lightweight ISO 8601 week helper — replaces the `isoweek` package.
///
/// An ISO week starts on Monday. Week 1 is the week containing the first
/// Thursday of the year (equivalently, the week containing January 4th).
class IsoWeek {
  /// Monday of this ISO week.
  final DateTime _monday;

  IsoWeek._(this._monday);

  /// A fixed Monday used as origin for [index]-based paging.
  static const int _epochYear = 2020;
  static const int _epochMonth = 1;
  static const int _epochDay = 6;

  /// The ISO week containing [date].
  factory IsoWeek.fromDate(DateTime date) {
    // Normalize to noon to avoid DST edge-cases.
    final d = DateTime(date.year, date.month, date.day, 12);
    // weekday: Monday=1 … Sunday=7
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return IsoWeek._(DateTime(monday.year, monday.month, monday.day));
  }

  /// The current ISO week.
  factory IsoWeek.current() => IsoWeek.fromDate(DateTime.now());

  /// The week [index] weeks after the paging origin. Inverse of [index].
  factory IsoWeek.fromIndex(int index) =>
      IsoWeek._(DateTime(_epochYear, _epochMonth, _epochDay + index * 7));

  /// Number of weeks between the paging origin and this week. Stable and
  /// DST-safe, which makes it usable as a `PageView` page number.
  int get index {
    final days = DateTime.utc(_monday.year, _monday.month, _monday.day)
        .difference(DateTime.utc(_epochYear, _epochMonth, _epochDay))
        .inDays;
    return (days / 7).floor();
  }

  /// ISO week number (1–53).
  int get weekNumber {
    // The Thursday of this week determines the year and week number.
    final thursday = _monday.add(const Duration(days: 3));
    // Jan 4 is always in week 1.
    final jan4 = DateTime(thursday.year, 1, 4);
    final jan4Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final diff = thursday.difference(jan4Monday).inDays;
    return (diff / 7).floor() + 1;
  }

  /// The ISO year this week belongs to (may differ from calendar year at
  /// year boundaries).
  int get year {
    final thursday = _monday.add(const Duration(days: 3));
    return thursday.year;
  }

  /// Identifier used by LSF and the cache, e.g. `46_2026`.
  String get key => '${weekNumber}_$year';

  /// Returns the [DateTime] for a given day offset.
  /// 0 = Monday, 1 = Tuesday, … 6 = Sunday.
  DateTime day(int index) =>
      DateTime(_monday.year, _monday.month, _monday.day + index);

  /// The next ISO week.
  IsoWeek get next => IsoWeek.fromDate(
      DateTime(_monday.year, _monday.month, _monday.day + 7));

  /// The previous ISO week.
  IsoWeek get previous => IsoWeek.fromDate(
      DateTime(_monday.year, _monday.month, _monday.day - 7));

  @override
  bool operator ==(Object other) =>
      other is IsoWeek &&
      _monday.year == other._monday.year &&
      _monday.month == other._monday.month &&
      _monday.day == other._monday.day;

  @override
  int get hashCode => Object.hash(_monday.year, _monday.month, _monday.day);

  @override
  String toString() => 'IsoWeek($key)';
}

/// Date-only helpers shared by the calendar-like screens.
abstract final class Dates {
  /// [date] with the time-of-day stripped.
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime today() => dateOnly(DateTime.now());

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Moves a weekend date to the following Monday when weekends are hidden.
  static DateTime skipWeekend(DateTime date, {required bool showWeekends}) {
    final d = dateOnly(date);
    if (showWeekends || d.weekday <= DateTime.friday) return d;
    return DateTime(d.year, d.month, d.day + (8 - d.weekday));
  }

  /// Page number of [date] in a pager that shows [daysPerWeek] days of every
  /// week back to back (5 = Mon–Fri, 7 = Mon–Sun).
  static int dayPage(DateTime date, int daysPerWeek) {
    final d = skipWeekend(date, showWeekends: daysPerWeek >= 7);
    return IsoWeek.fromDate(d).index * daysPerWeek + (d.weekday - 1);
  }

  /// Inverse of [dayPage].
  static DateTime dateOfDayPage(int page, int daysPerWeek) {
    final week = (page / daysPerWeek).floor();
    final day = page - week * daysPerWeek;
    return IsoWeek.fromIndex(week).day(day);
  }
}
