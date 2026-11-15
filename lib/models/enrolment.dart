/// The state of one application for a course group ("zugelassen",
/// "abgelehnt", …).
class EnrolmentStatus {
  const EnrolmentStatus({
    required this.label,
    this.group = '',
    this.date = '',
    this.positive = false,
  });

  /// LSF's wording, e.g. "zugelassen".
  final String label;

  /// "1. Zug, 2. Gruppe"
  final String group;

  /// When the status was set, as LSF prints it.
  final String date;

  /// LSF marks admissions green and everything else as a warning.
  final bool positive;

  bool get isRejected => label.toLowerCase().contains('abgelehnt');

  factory EnrolmentStatus.fromJson(Map<String, dynamic> json) =>
      EnrolmentStatus(
        label: json['label'] ?? '',
        group: json['group'] ?? '',
        date: json['date'] ?? '',
        positive: json['positive'] ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'label': label, 'group': group, 'date': date, 'positive': positive};
}

/// One row of a course's dates: when and where it meets.
class EnrolmentDate {
  const EnrolmentDate({
    this.day = '',
    this.time = '',
    this.rhythm = '',
    this.duration = '',
    this.room = '',
    this.lecturer = '',
    this.note = '',
  });

  final String day;

  /// "09:45 – 11:15"
  final String time;

  /// "wöchentlich", "gerade Woche", "Einzeltermin" …
  final String rhythm;

  /// "15.10.2026 bis 11.02.2027" or "am 28.01.2027"
  final String duration;
  final String room;
  final String lecturer;

  /// "findet statt", "fällt aus" …
  final String note;

  factory EnrolmentDate.fromJson(Map<String, dynamic> json) => EnrolmentDate(
        day: json['day'] ?? '',
        time: json['time'] ?? '',
        rhythm: json['rhythm'] ?? '',
        duration: json['duration'] ?? '',
        room: json['room'] ?? '',
        lecturer: json['lecturer'] ?? '',
        note: json['note'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'time': time,
        'rhythm': rhythm,
        'duration': duration,
        'room': room,
        'lecturer': lecturer,
        'note': note,
      };
}

/// A course the student enrolled in ("Belegübersicht").
class Enrolment {
  const Enrolment({
    required this.title,
    this.number = '',
    this.publishId,
    this.semester = '',
    this.statuses = const [],
    this.dates = const [],
  });

  final String number;
  final String title;
  final String? publishId;

  /// "Wintersemester 2026/2027"
  final String semester;
  final List<EnrolmentStatus> statuses;
  final List<EnrolmentDate> dates;

  /// The status that counts: an admission if there is one, else the first.
  EnrolmentStatus? get status {
    if (statuses.isEmpty) return null;
    for (final s in statuses) {
      if (s.positive) return s;
    }
    return statuses.first;
  }

  factory Enrolment.fromJson(Map<String, dynamic> json) => Enrolment(
        title: json['title'] ?? '',
        number: json['number'] ?? '',
        publishId: json['publishId'],
        semester: json['semester'] ?? '',
        statuses: [
          for (final s in json['statuses'] as List? ?? [])
            EnrolmentStatus.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        dates: [
          for (final d in json['dates'] as List? ?? [])
            EnrolmentDate.fromJson(Map<String, dynamic>.from(d as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'number': number,
        'publishId': publishId,
        'semester': semester,
        'statuses': [for (final s in statuses) s.toJson()],
        'dates': [for (final d in dates) d.toJson()],
      };
}
