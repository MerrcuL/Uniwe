class ExamDate {
  final String day;
  final String time;
  final String date;

  const ExamDate({required this.day, required this.time, required this.date});

  @override
  bool operator ==(Object other) =>
      other is ExamDate &&
      other.day == day &&
      other.time == time &&
      other.date == date;

  @override
  int get hashCode => Object.hash(day, time, date);
}

/// A lecturer named on a lecture page. [personId] is LSF's `personal.pid`,
/// present when LSF links the name to the person's page.
class Lecturer {
  final String name;
  final String? personId;

  const Lecturer({required this.name, this.personId});

  @override
  bool operator ==(Object other) =>
      other is Lecturer && other.name == name && other.personId == personId;

  @override
  int get hashCode => Object.hash(name, personId);

  @override
  String toString() => personId == null ? name : '$name ($personId)';
}

/// Extra information scraped from an LSF lecture detail page.
class LectureDetails {
  final String publishId;
  final String? credits;
  final String? sws;
  final List<Lecturer> teachers;
  final List<ExamDate> examDates;

  const LectureDetails({
    required this.publishId,
    this.credits,
    this.sws,
    this.teachers = const [],
    this.examDates = const [],
  });

  bool get isEmpty =>
      (credits == null || credits!.isEmpty) &&
      (sws == null || sws!.isEmpty) &&
      teachers.isEmpty &&
      examDates.isEmpty;
}
