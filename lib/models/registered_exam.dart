/// One exam the student is registered for ("Info über angemeldete
/// Prüfungen").
class RegisteredExam {
  RegisteredExam({
    required this.name,
    this.number = '',
    this.examiner = '',
    this.semester = '',
    this.registeredOn = '',
    this.period = '',
    this.date = '',
    this.attempt = '',
    this.program = '',
  });

  final String number;
  final String name;
  final String examiner;
  final String semester;

  /// When the registration was made, as LSF prints it.
  final String registeredOn;

  /// LSF's "Termin": the examination period (1 or 2).
  final String period;

  /// "12.02.2027", or '' while no date is set.
  final String date;
  final String attempt;

  /// The degree programme the exam belongs to.
  final String program;

  /// [date] as a day, or null if it is missing or not a date.
  late final DateTime? day = () {
    final match = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(date);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }();

  /// Whole days from [today] until the exam (negative once it is over).
  int? daysUntil(DateTime today) {
    final d = day;
    if (d == null) return null;
    return DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
  }

  factory RegisteredExam.fromJson(Map<String, dynamic> json) => RegisteredExam(
        name: json['name'] ?? '',
        number: json['number'] ?? '',
        examiner: json['examiner'] ?? '',
        semester: json['semester'] ?? '',
        registeredOn: json['registeredOn'] ?? '',
        period: json['period'] ?? '',
        date: json['date'] ?? '',
        attempt: json['attempt'] ?? '',
        program: json['program'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'number': number,
        'examiner': examiner,
        'semester': semester,
        'registeredOn': registeredOn,
        'period': period,
        'date': date,
        'attempt': attempt,
        'program': program,
      };
}

/// The registered exams, with the programmes LSF listed them under (also
/// known when there are no exams yet).
class ExamRegistrations {
  const ExamRegistrations({required this.programs, required this.exams});

  final List<String> programs;
  final List<RegisteredExam> exams;

  /// Exams that are still ahead (or have no date yet), soonest first; exams
  /// without a date come last.
  List<RegisteredExam> upcoming(DateTime today) {
    final list = exams.where((e) => (e.daysUntil(today) ?? 0) >= 0).toList();
    list.sort((a, b) {
      final da = a.day;
      final db = b.day;
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

  List<RegisteredExam> past(DateTime today) =>
      exams.where((e) => (e.daysUntil(today) ?? 0) < 0).toList();

  factory ExamRegistrations.fromJson(Map<String, dynamic> json) =>
      ExamRegistrations(
        programs: [for (final p in json['programs'] as List? ?? []) '$p'],
        exams: [
          for (final e in json['exams'] as List? ?? [])
            RegisteredExam.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'programs': programs,
        'exams': [for (final e in exams) e.toJson()],
      };
}
