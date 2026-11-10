/// A PDF document LSF generates on request (certificate, transcript, record
/// of achievement).
class LsfDocument {
  const LsfDocument({required this.title, required this.url});

  /// The document's name as LSF shows it.
  final String title;

  /// Where LSF generates it, without the session-bound `asi` parameter
  /// (the current one is added when the document is downloaded).
  final Uri url;

  /// The language of the document, guessed from its LSF report name.
  bool get isEnglish {
    final call = url.queryParameters['moduleCall'] ?? '';
    return call.endsWith('_en') ||
        call.endsWith('_been') ||
        call == 'gradetranscript';
  }

  /// Localization key of a short name for the documents LSF is known to
  /// offer, or null for others (then LSF's own title is shown).
  String? get nameKey {
    final call = url.queryParameters['moduleCall'];
    return switch (call) {
      'immabescheinigung' || 'immabescheinigung_en' => 'docEnrolment',
      'immabescheinigungzeit' ||
      'immabescheinigungzeit_en' =>
        'docEnrolmentHistory',
      'Pruefungsleistungen' || 'gradetranscript' => 'docAllResults',
      'Pruefungsleistungen_be' ||
      'Pruefungsleistungen_been' =>
        'docPassedResults',
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is LsfDocument && other.title == title && other.url == url;

  @override
  int get hashCode => Object.hash(title, url);
}

enum ExamStatus { passed, failed, other }

/// One row of the grade overview ("Noten- und Klassenspiegel"): an exam, or
/// a module group whose grade LSF calculates from its modules.
class ExamResult {
  const ExamResult({
    required this.number,
    required this.name,
    required this.semester,
    required this.grade,
    required this.status,
    required this.statusLabel,
    this.credits = '',
    this.remark = '',
    required this.attempt,
    required this.date,
    this.isGroup = false,
    this.distributionUrl,
  });

  final String number;
  final String name;

  /// As LSF writes it, e.g. "SoSe 26" or "WiSe 25/26".
  final String semester;

  /// The grade as written, e.g. "1,3"; empty for ungraded exams.
  final String grade;

  final ExamStatus status;

  /// The status as LSF writes it ("bestanden", …).
  final String statusLabel;

  /// Credit points (ECTS) as written, or empty.
  final String credits;

  /// LSF's remark code ("FNB", "mE", …), or empty.
  final String remark;
  final String attempt;

  /// "dd.mm.yyyy", or empty.
  final String date;

  /// A module group (LSF "Konto") rather than a single exam.
  final bool isGroup;

  /// The page with the grade distribution of this exam, without `asi`.
  final Uri? distributionUrl;

  double? get gradeValue => double.tryParse(grade.replaceAll(',', '.'));
}

/// How everyone who took an exam did ("Klassenspiegel").
class GradeDistribution {
  const GradeDistribution({
    required this.bands,
    this.participants,
    this.average,
  });

  final List<GradeBand> bands;
  final int? participants;

  /// The class average as written, e.g. "2,1".
  final String? average;

  int get maxCount =>
      bands.fold(0, (max, band) => band.count > max ? band.count : max);
}

/// A grade range of a [GradeDistribution], e.g. "gut (1,7 - 2,3)".
class GradeBand {
  const GradeBand({
    required this.label,
    required this.range,
    required this.count,
    required this.includesYou,
  });

  /// The German grade word LSF uses ("sehr gut", …).
  final String label;

  /// The grade range, e.g. "1,7–2,3".
  final String range;
  final int count;

  /// Whether the student's own result is in this band.
  final bool includesYou;

  /// Localization key of the band's name, from LSF's German grade word.
  String? get nameKey => switch (label.toLowerCase()) {
        'sehr gut' => 'bandVeryGood',
        'gut' => 'bandGood',
        'befriedigend' => 'bandSatisfactory',
        'ausreichend' => 'bandSufficient',
        'nicht ausreichend' => 'bandFailed',
        _ => null,
      };
}

/// The student's grades as LSF reports them.
class GradeReport {
  const GradeReport({
    required this.programs,
    required this.results,
    this.groups = const [],
    this.average,
    this.credits,
  });

  /// Degree programmes, e.g. "Informatik · Bachelor".
  final List<String> programs;

  /// The exams.
  final List<ExamResult> results;

  /// Module groups with a grade or credits of their own, in LSF's order.
  final List<ExamResult> groups;

  /// LSF's overall average (an arithmetic mean, not weighted), as written.
  final String? average;

  /// The credit points achieved so far, as written.
  final String? credits;

  bool get isEmpty => results.isEmpty && groups.isEmpty;

  /// Results grouped by semester, newest semester first, keeping LSF's order
  /// within a semester.
  List<MapEntry<String, List<ExamResult>>> get bySemester {
    final groups = <String, List<ExamResult>>{};
    for (final result in results) {
      (groups[result.semester] ??= []).add(result);
    }
    final entries = groups.entries.toList();
    // A stable sort keeps semesters LSF could not date in their order.
    mergeSortBy(entries, (e) => -semesterOrder(e.key));
    return entries;
  }

  /// Sort key of an LSF semester label: summer 2026 ("SoSe 26") comes before
  /// winter 2026/27 ("WiSe 26/27"). Unknown labels sort last.
  static double semesterOrder(String label) {
    final match = RegExp(
      r'^(SS|SoSe|Sommersemester|WS|WiSe|Wintersemester)\s*(\d{2,4})',
    ).firstMatch(label.trim());
    if (match == null) return -1;
    var year = int.parse(match.group(2)!);
    if (year < 100) year += 2000;
    final winter = match.group(1)!.startsWith('W');
    return year + (winter ? 0.5 : 0);
  }
}

/// The PDFs on LSF's achievement page: per-semester records of achievement
/// ("Leistungsnachweis", newest first) and transcripts.
class AchievementDocuments {
  const AchievementDocuments({required this.records, required this.transcripts});

  final List<LsfDocument> records;
  final List<LsfDocument> transcripts;
}

/// Stable in-place sort by a numeric key (List.sort is not stable).
void mergeSortBy<T>(List<T> list, double Function(T) key) {
  final keyed = [
    for (var i = 0; i < list.length; i++) (i, key(list[i]), list[i]),
  ];
  keyed.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < keyed.length; i++) {
    list[i] = keyed[i].$3;
  }
}
