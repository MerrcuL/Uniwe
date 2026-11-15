/// A span of whole days, both ends included. A deadline ("bis 15.10.2026")
/// is a span of one day with [isDeadline] set.
class DateSpan {
  const DateSpan(this.start, this.end, {this.isDeadline = false});

  final DateTime start;
  final DateTime end;
  final bool isDeadline;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  factory DateSpan.fromJson(Map<String, dynamic> json) => DateSpan(
        DateTime.parse(json['start'] as String),
        DateTime.parse(json['end'] as String),
        isDeadline: json['deadline'] == true,
      );

  Map<String, dynamic> toJson() => {
        'start': _iso(start),
        'end': _iso(end),
        if (isDeadline) 'deadline': true,
      };

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum CalendarEntryState { undated, past, active, upcoming }

/// One line of the academic calendar: "Rückmeldung · 01.01. - 05.02.2027".
class CalendarEntry {
  CalendarEntry({
    required this.label,
    required this.text,
    this.spans = const [],
    this.link,
  });

  final String label;

  /// The dates as the university words them.
  final String text;

  /// The dates found in [text], in order.
  final List<DateSpan> spans;

  /// Where the entry points to when it has no dates of its own.
  final Uri? link;

  CalendarEntryState stateOn(DateTime today) {
    if (spans.isEmpty) return CalendarEntryState.undated;
    var upcoming = false;
    for (final span in spans) {
      // A deadline is "on" from now until its day.
      if (span.isDeadline ? !today.isAfter(span.end) : span.contains(today)) {
        return CalendarEntryState.active;
      }
      if (today.isBefore(span.start)) upcoming = true;
    }
    return upcoming ? CalendarEntryState.upcoming : CalendarEntryState.past;
  }

  /// The next day this entry matters on: the end of what is running, else
  /// the start of what comes next. Null when everything is over.
  DateTime? nextDate(DateTime today) {
    DateTime? best;
    for (final span in spans) {
      final DateTime candidate;
      if (span.isDeadline || span.contains(today)) {
        candidate = span.end;
      } else {
        candidate = span.start;
      }
      if (candidate.isBefore(today)) continue;
      if (best == null || candidate.isBefore(best)) best = candidate;
    }
    return best;
  }

  factory CalendarEntry.fromJson(Map<String, dynamic> json) => CalendarEntry(
        label: json['label'] ?? '',
        text: json['text'] ?? '',
        spans: [
          for (final s in json['spans'] as List? ?? [])
            DateSpan.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        link: json['link'] == null ? null : Uri.tryParse(json['link']),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'text': text,
        'spans': [for (final s in spans) s.toJson()],
        if (link != null) 'link': link.toString(),
      };
}

class CalendarSection {
  const CalendarSection({required this.title, required this.entries});

  final String title;
  final List<CalendarEntry> entries;

  factory CalendarSection.fromJson(Map<String, dynamic> json) =>
      CalendarSection(
        title: json['title'] ?? '',
        entries: [
          for (final e in json['entries'] as List? ?? [])
            CalendarEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'entries': [for (final e in entries) e.toJson()],
      };
}

/// The academic calendar of one semester, as published by HTW Berlin.
class SemesterCalendar {
  const SemesterCalendar({
    required this.title,
    required this.sections,
    this.lectureStart,
    this.lectureEnd,
  });

  /// "Akademischer Kalender: Wintersemester 2026/27"
  final String title;
  final List<CalendarSection> sections;

  /// First and last day of the teaching period, when the page names them.
  final DateTime? lectureStart;
  final DateTime? lectureEnd;

  /// [title] without the "Akademischer Kalender:" lead-in.
  String get semesterName {
    final index = title.indexOf(':');
    final name = index < 0 ? title : title.substring(index + 1);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return title;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  bool get isEmpty => sections.every((s) => s.entries.isEmpty);

  static int _days(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  /// How much of the teaching period is over on [today], 0…1; null when the
  /// period is unknown.
  double? lectureProgress(DateTime today) {
    final start = lectureStart;
    final end = lectureEnd;
    if (start == null || end == null || !end.isAfter(start)) return null;
    final total = _days(start, end) + 1;
    return (_days(start, today) / total).clamp(0.0, 1.0);
  }

  /// The running week of the teaching period (1-based) and their total, or
  /// null outside of it.
  ({int week, int total})? lectureWeek(DateTime today) {
    final start = lectureStart;
    final end = lectureEnd;
    if (start == null || end == null) return null;
    if (today.isBefore(start) || today.isAfter(end)) return null;
    // Weeks are counted Monday to Sunday, like the timetable.
    final firstMonday =
        DateTime(start.year, start.month, start.day - (start.weekday - 1));
    final week = _days(firstMonday, today) ~/ 7 + 1;
    final total = _days(firstMonday, end) ~/ 7 + 1;
    return (week: week, total: total);
  }

  /// Everything that is running or still ahead, soonest first.
  List<({CalendarEntry entry, DateTime date})> upcoming(DateTime today) {
    final list = <({CalendarEntry entry, DateTime date})>[];
    for (final section in sections) {
      for (final entry in section.entries) {
        final date = entry.nextDate(today);
        if (date != null) list.add((entry: entry, date: date));
      }
    }
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  factory SemesterCalendar.fromJson(Map<String, dynamic> json) =>
      SemesterCalendar(
        title: json['title'] ?? '',
        sections: [
          for (final s in json['sections'] as List? ?? [])
            CalendarSection.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        lectureStart: json['lectureStart'] == null
            ? null
            : DateTime.tryParse(json['lectureStart']),
        lectureEnd: json['lectureEnd'] == null
            ? null
            : DateTime.tryParse(json['lectureEnd']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'sections': [for (final s in sections) s.toJson()],
        if (lectureStart != null) 'lectureStart': DateSpan._iso(lectureStart!),
        if (lectureEnd != null) 'lectureEnd': DateSpan._iso(lectureEnd!),
      };
}
