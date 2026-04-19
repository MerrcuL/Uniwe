/// Lightweight ISO 8601 week helper — replaces the `isoweek` package.
///
/// An ISO week starts on Monday. Week 1 is the week containing the first
/// Thursday of the year (equivalently, the week containing January 4th).
class IsoWeek {
  /// Monday of this ISO week.
  final DateTime _monday;

  IsoWeek._(this._monday);

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

  /// Returns the [DateTime] for a given day offset.
  /// 0 = Monday, 1 = Tuesday, … 6 = Sunday.
  DateTime day(int index) => DateTime(_monday.year, _monday.month, _monday.day + index);

  /// The next ISO week.
  IsoWeek get next => IsoWeek._(DateTime(_monday.year, _monday.month, _monday.day + 7));

  /// The previous ISO week.
  IsoWeek get previous => IsoWeek._(DateTime(_monday.year, _monday.month, _monday.day - 7));

  @override
  bool operator ==(Object other) =>
      other is IsoWeek &&
      _monday.year == other._monday.year &&
      _monday.month == other._monday.month &&
      _monday.day == other._monday.day;

  @override
  int get hashCode => _monday.hashCode;
}
