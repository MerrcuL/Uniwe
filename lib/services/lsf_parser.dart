import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/grades.dart';
import '../models/lecture_details.dart';
import '../models/person_details.dart';
import '../models/timetable_event.dart';

// Pure HTML → model functions. They are top-level so they can run on a
// background isolate via `compute`: parsing a full LSF page takes long enough
// on a phone to drop frames when done on the UI thread.

const List<String> _ignoredPlanClasses = [
  'plan_rahmen',
  'plan5',
  'plan6',
  'plan7',
  'plan9',
];

/// If the LSF login form is present the session is missing or has expired.
/// LSF uses `asdf` as the name of the username field.
bool isLsfLoginPage(String html) => html.contains('name="asdf"');

List<TimetableEvent> parseTimetableHtml(String html) {
  final document = parser.parse(html);
  final events = <TimetableEvent>[];

  final eventCells = document.querySelectorAll('td').where((element) {
    final className = element.className;
    if (!className.startsWith('plan')) return false;
    return !_ignoredPlanClasses.contains(className);
  });

  for (final cell in eventCells) {
    final titleTags = cell.querySelectorAll('a.ver');
    if (titleTags.isEmpty) continue;

    final isOverlapping = titleTags.length > 1;

    for (final titleTag in titleTags) {
      final title = titleTag.text.trim();
      String? publishId;
      final href = titleTag.attributes['href'] ?? '';
      final uri = Uri.tryParse(href.replaceAll('&amp;', '&'));
      if (uri != null && uri.queryParameters.containsKey('publishid')) {
        publishId = uri.queryParameters['publishid'];
      }

      // LSF wraps each of several overlapping events in its own nested
      // <table>; use that as the scope for the event's details.
      dom.Element eventContainer = cell;
      var current = titleTag.parent;
      while (current != null && current != cell) {
        if (current.localName == 'table') {
          eventContainer = current;
          break;
        }
        current = current.parent;
      }

      String? day;
      String? time;
      String? room;
      String? type;
      String? frequency;

      for (final noteCell in eventContainer.querySelectorAll('td.notiz')) {
        final text =
            noteCell.text.replaceAll('\n', ' ').replaceAll('\r', '').trim();

        if (text.contains('Raum:')) {
          final parts = text.split('Raum:');
          room = parts[1].trim();

          final typeParts = parts[0].split(',');
          if (typeParts.isNotEmpty) {
            type = typeParts[0].trim();
          }
        } else if (text.contains(':') &&
            text.contains('-') &&
            text.contains(',')) {
          final timeParts = text.split(',');
          if (timeParts.length >= 2) {
            day = timeParts[0].trim();
            time = timeParts[1].trim();
          }
          if (timeParts.length >= 3) {
            frequency = timeParts[2].trim();
          }
        }
      }

      final isExam = eventContainer
          .querySelectorAll('span.warnung')
          .any((span) => span.text.contains('Prüfung'));

      events.add(TimetableEvent(
        title: title,
        day: day ?? '',
        time: time ?? '',
        room: room ?? '',
        type: type ?? '',
        frequency: frequency ?? '',
        publishId: publishId,
        isExam: isExam,
        isOverlapping: isOverlapping,
      ));
    }
  }

  return events;
}

/// Parses a lecture detail page. Takes `(publishId, html)` so it can be used
/// with `compute`, which passes a single message.
LectureDetails parseLectureDetailsHtml((String, String) input) {
  final (publishId, html) = input;
  final document = parser.parse(html);

  String? credits;
  String? sws;
  final teachers = <Lecturer>[];
  final examDates = <ExamDate>[];

  for (final cell in document.querySelectorAll('th, td')) {
    final text = cell.text.trim();
    if (text != 'Credits' && text != 'SWS') continue;
    final next = cell.nextElementSibling;
    if (next == null || next.localName != 'td') continue;
    final value = next.text.trim();
    if (text == 'Credits') {
      credits = value;
    } else {
      sws = value;
    }
  }

  for (final table in document.querySelectorAll('table')) {
    final headers =
        table.querySelectorAll('th').map((e) => e.text.trim()).toList();
    if (!headers.contains('Lehrperson')) continue;

    final dayIdx = headers.indexOf('Tag');
    final timeIdx = headers.indexOf('Zeit');
    final durationIdx = headers.indexOf('Dauer');
    final teacherIdx = headers.indexOf('Lehrperson');
    final remarkIdx = headers.indexOf('Bemerkung');
    if (dayIdx == -1 ||
        timeIdx == -1 ||
        durationIdx == -1 ||
        teacherIdx == -1 ||
        remarkIdx == -1) {
      continue;
    }
    final maxIdx = [dayIdx, timeIdx, durationIdx, teacherIdx, remarkIdx]
        .reduce((a, b) => a > b ? a : b);

    for (final row in table.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length <= maxIdx) continue;

      final teacherCell = cells[teacherIdx];
      final teacherLinks = teacherCell.querySelectorAll('a');
      if (teacherLinks.isNotEmpty) {
        for (final a in teacherLinks) {
          final href = a.attributes['href'] ?? '';
          final match = RegExp(r'personal\.pid=(\d+)').firstMatch(href);
          final pid = match?.group(1);
          final name = a.text.trim();
          if (name.isNotEmpty && !teachers.any((t) => t.name == name)) {
            teachers.add(Lecturer(name: name, personId: pid));
          }
        }
      } else {
        final teacher = teacherCell.text.trim();
        if (teacher.isNotEmpty && !teachers.any((t) => t.name == teacher)) {
          teachers.add(Lecturer(name: teacher));
        }
      }

      if (cells[remarkIdx].text.contains('Prüfung')) {
        final exam = ExamDate(
          day: cells[dayIdx].text.trim(),
          time: cells[timeIdx].text.trim(),
          date: cells[durationIdx].text.trim().replaceAll('am ', ''),
        );
        if (!examDates.contains(exam)) examDates.add(exam);
      }
    }
  }

  return LectureDetails(
    publishId: publishId,
    credits: (credits == null || credits.isEmpty) ? null : credits,
    sws: (sws == null || sws.isEmpty) ? null : sws,
    teachers: teachers,
    examDates: examDates,
  );
}

/// The session-bound `asi` token LSF appends to the links of a signed-in
/// session (needed for grades and documents), or null if the page has none —
/// which means the session is not signed in.
String? parseLsfAsi(String html) {
  final match = RegExp(r'''[?&;]asi=([^&"'\s<>#]+)''').firstMatch(html);
  final value = match?.group(1);
  return (value == null || value.isEmpty) ? null : value;
}

String _cellText(dom.Element element) => element.text
    .replaceAll(' ', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The cells of [row] itself (not of tables nested in it).
List<dom.Element> _ownCells(dom.Element row, String tag) =>
    row.children.where((cell) => cell.localName == tag).toList();

/// The rows of [table] itself (not of tables nested in it).
List<dom.Element> _ownRows(dom.Element table) =>
    table.querySelectorAll('tr').where((row) {
      var parent = row.parent;
      while (parent != null && parent.localName != 'table') {
        parent = parent.parent;
      }
      return identical(parent, table);
    }).toList();

/// An LSF link with its `asi` (and fragment) removed; the token of the live
/// session is added when the link is followed.
Uri? _withoutAsi(String? href) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null || !uri.hasQuery) return null;
  final params = Map.of(uri.queryParameters)..remove('asi');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    path: uri.path,
    queryParameters: params,
  );
}

/// An LSF document (PDF report) link, without `asi`.
Uri? _documentUrl(String? href) {
  final uri = _withoutAsi(href);
  if (uri == null || uri.queryParameters['state'] != 'hisreports') return null;
  return uri;
}

/// The PDFs on the "Leistungsstand und -bescheinigungen" page.
AchievementDocuments parseAchievementDocumentsHtml(String html) {
  final document = parser.parse(html);
  final records = <LsfDocument>[];
  final transcripts = <LsfDocument>[];

  for (final table in document.querySelectorAll('table')) {
    final rows = _ownRows(table);
    if (rows.isEmpty) continue;
    final headers = _ownCells(rows.first, 'th').map(_cellText).toList();
    final isRecords = headers.contains('Semester') && !headers.contains('Note');
    final isDocuments = headers.contains('Dokumente');
    if (!isRecords && !isDocuments) continue;
    for (final row in rows.skip(1)) {
      final cells = _ownCells(row, 'td');
      if (cells.length < 2) continue;
      final url = _documentUrl(cells[1].querySelector('a')?.attributes['href']);
      if (url == null) continue;
      (isRecords ? records : transcripts)
          .add(LsfDocument(title: _cellText(cells[0]), url: url));
    }
  }
  return AchievementDocuments(records: records, transcripts: transcripts);
}

/// The degree programmes on the start page of "Noten- und Klassenspiegel",
/// as links to their grade lists (without `asi`).
///
/// The page is a tree (degree → programme → …); the shallowest list links
/// cover everything below them, so only those are returned.
List<Uri> parseGradeTreeHtml(String html) {
  final document = parser.parse(html);
  final byDepth = <int, List<Uri>>{};
  for (final link in document.querySelectorAll('a')) {
    final url = _withoutAsi(link.attributes['href']);
    if (url == null) continue;
    final params = url.queryParameters;
    final node = params['nodeID'] ?? '';
    if (params['state'] != 'notenspiegelStudent' ||
        params['next'] != 'list.vm' ||
        !node.startsWith('auswahlBaum|abschluss:')) {
      continue;
    }
    final depth = '|'.allMatches(node).length;
    final list = byDepth[depth] ??= [];
    if (!list.any((u) => u.queryParameters['nodeID'] == node)) list.add(url);
  }
  if (byDepth.isEmpty) return const [];
  final shallowest = byDepth.keys.reduce((a, b) => a < b ? a : b);
  return byDepth[shallowest]!;
}

ExamStatus _examStatus(String label) {
  final status = label.toLowerCase();
  if (status.contains('nicht bestanden') || status.contains('endgültig')) {
    return ExamStatus.failed;
  }
  if (status.contains('bestanden')) return ExamStatus.passed;
  return ExamStatus.other;
}

/// Parses a grade list of "Noten- und Klassenspiegel".
///
/// Only the grade table is read; the personal data LSF shows above it
/// (address, date of birth, …) is ignored. Columns are found by their header
/// text, so a changed column order does not mix up grade and credits.
GradeReport parseGradeListHtml(String html) {
  final document = parser.parse(html);
  final programs = <String>[];
  final results = <ExamResult>[];
  final groups = <ExamResult>[];
  String? average;
  String? credits;

  for (final table in document.querySelectorAll('table')) {
    final rows = _ownRows(table);
    final headerIndex = rows.indexWhere((row) => _ownCells(row, 'th')
        .any((cell) => _cellText(cell).startsWith('Prüfungsnr')));
    if (headerIndex < 0) continue;

    // "Abschluss: [84] Bachelor Studiengang: [621] Informatik"
    for (final row in rows.take(headerIndex)) {
      final text = _cellText(row);
      final degree =
          RegExp(r'Abschluss:\s*(?:\[\d+\]\s*)?(.+?)\s*(?:Studiengang:|$)')
              .firstMatch(text)
              ?.group(1);
      final subject = RegExp(r'Studiengang:\s*(?:\[\d+\]\s*)?(.+)$')
          .firstMatch(text)
          ?.group(1);
      if (subject != null && subject.isNotEmpty) {
        programs.add(
            degree == null || degree.isEmpty ? subject : '$subject · $degree');
      }
    }

    final headers = _ownCells(rows[headerIndex], 'th').map(_cellText).toList();
    int col(bool Function(String h) test) => headers.indexWhere(test);
    final numberCol = col((h) => h.startsWith('Prüfungsnr'));
    final nameCol = col((h) => h.contains('Prüfungstext'));
    final semesterCol = col((h) => h.startsWith('Semester'));
    final gradeCol = col((h) => h == 'Note');
    final statusCol = col((h) => h == 'Status');
    final creditsCol = col((h) => h.contains('Leistungspunkte'));
    final remarkCol = col((h) => h.startsWith('Vermerk'));
    final attemptCol = col((h) => h.startsWith('Versuch'));
    final dateCol = col((h) => h.contains('datum'));
    if (nameCol < 0 || gradeCol < 0) continue;

    var isFirstAccount = true;
    for (final row in rows.skip(headerIndex + 1)) {
      final cells = _ownCells(row, 'td');
      if (cells.isEmpty) continue;

      // Expand colspans so values line up with their headers.
      final values = <String>[];
      dom.Element? gradeCell;
      for (final cell in cells) {
        final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        if (values.length <= gradeCol && values.length + span > gradeCol) {
          gradeCell = cell;
        }
        values.add(_cellText(cell));
        for (var i = 1; i < span; i++) {
          values.add('');
        }
      }
      String at(int i) => i >= 0 && i < values.length ? values[i] : '';

      final name = at(nameCol);
      if (name.isEmpty) continue;
      final rowClass = cells.first.className;
      final isAccount = rowClass.startsWith('qis_konto');

      // The grade cell may carry a footnote mark ("1,3 2)") and the link to
      // the grade distribution.
      var gradeText = at(gradeCol);
      String? link;
      if (gradeCell != null) {
        link = gradeCell.querySelector('a')?.attributes['href'];
        final copy = gradeCell.clone(true);
        for (final extra in copy.querySelectorAll('sup, a')) {
          extra.remove();
        }
        gradeText = _cellText(copy);
      }

      final statusLabel = at(statusCol);
      final result = ExamResult(
        number: at(numberCol),
        name: name,
        semester: at(semesterCol),
        grade: gradeText,
        status: _examStatus(statusLabel),
        statusLabel: statusLabel,
        credits: at(creditsCol),
        remark: at(remarkCol),
        attempt: at(attemptCol),
        date: at(dateCol),
        isGroup: isAccount,
        distributionUrl: link == null ? null : _withoutAsi(link),
      );

      if (rowClass == 'qis_kontoOnTop' && isFirstAccount) {
        // The account on top of everything: the overall standing.
        isFirstAccount = false;
        if (result.grade.isNotEmpty) average = result.grade;
        if (result.credits.isNotEmpty) credits = result.credits;
        continue;
      }
      if (isAccount) {
        final hasCredits = (int.tryParse(result.credits) ?? 0) > 0;
        if (result.grade.isNotEmpty || hasCredits) groups.add(result);
        continue;
      }
      results.add(result);
    }
  }

  return GradeReport(
    programs: programs,
    results: results,
    groups: groups,
    average: average,
    credits: credits,
  );
}

/// Parses the grade distribution ("NOTENSPIEGEL") of a single exam, or
/// returns null when the page has none.
GradeDistribution? parseGradeDistributionHtml(String html) {
  final document = parser.parse(html);
  for (final table in document.querySelectorAll('table')) {
    final rows = _ownRows(table);
    if (!rows.any((row) => _cellText(row).toUpperCase() == 'NOTENSPIEGEL')) {
      continue;
    }
    final bands = <GradeBand>[];
    int? participants;
    String? average;
    for (final row in rows) {
      final text = _cellText(row);
      final band = RegExp(
        r'^(.+?)\s*\(\s*(\d,\d)\s*-\s*(\d,\d)\s*\)\s*(\d+)(.*)$',
      ).firstMatch(text);
      if (band != null) {
        final from = band.group(2)!;
        final to = band.group(3)!;
        bands.add(GradeBand(
          label: band.group(1)!.trim(),
          range: from == to ? from : '$from–$to',
          count: int.parse(band.group(4)!),
          includesYou: band.group(5)!.contains('Ihrer'),
        ));
        continue;
      }
      final participantsMatch =
          RegExp(r'^Teilnehmende\s*(\d+)').firstMatch(text);
      if (participantsMatch != null) {
        participants = int.parse(participantsMatch.group(1)!);
        continue;
      }
      final averageMatch =
          RegExp(r'^Durchschnittsnote\s*(\d,\d+)').firstMatch(text);
      if (averageMatch != null) average = averageMatch.group(1);
    }
    if (bands.isEmpty) return null;
    return GradeDistribution(
      bands: bands,
      participants: participants,
      average: average,
    );
  }
  return null;
}

/// Parses the "Bescheinigungen" menu: every document LSF can generate.
List<LsfDocument> parseDocumentsMenuHtml(String html) {
  final document = parser.parse(html);
  final seen = <Uri>{};
  final documents = <LsfDocument>[];
  for (final link in document.querySelectorAll('a')) {
    final url = _documentUrl(link.attributes['href']);
    if (url == null || !seen.add(url)) continue;
    final title = _cellText(link);
    if (title.isEmpty) continue;
    documents.add(LsfDocument(title: title, url: url));
  }
  return documents;
}

/// Parses a person/lecturer detail page ("Einzelansicht").
PersonDetails parsePersonDetailsHtml((String, String) input) {
  final (personId, html) = input;
  final document = parser.parse(html);

  final fieldValues = <String, String>{};
  final fieldLinks = <String, String>{};

  for (final th in document.querySelectorAll('th')) {
    final key = _cellText(th);
    if (key.isEmpty) continue;
    final next = th.nextElementSibling;
    if (next != null && next.localName == 'td') {
      final value = _cellText(next);
      fieldValues[key] = value;
      final a = next.querySelector('a');
      if (a != null && a.attributes.containsKey('href')) {
        fieldLinks[key] = a.attributes['href']!;
      }
    }
  }

  // Extract homepage URL
  Uri? homepage;
  final rawHomepage = fieldValues['Hyperlink'] ??
      fieldLinks['Hyperlink'] ??
      fieldLinks['Weitere Links'];
  if (rawHomepage != null && rawHomepage.isNotEmpty) {
    if (rawHomepage.contains('destination=')) {
      final match = RegExp(r'destination=([^&]+)').firstMatch(rawHomepage);
      if (match != null) {
        final decoded = Uri.decodeComponent(match.group(1)!);
        homepage = Uri.tryParse(decoded);
      }
    } else {
      homepage = Uri.tryParse(rawHomepage);
    }
  }

  // Extract email
  String? email = fieldValues['E-Mail-Adresse'] ?? fieldValues['E-Mail'];
  final emailLink = fieldLinks['E-Mail-Adresse'] ?? fieldLinks['E-Mail'];
  if (emailLink != null && emailLink.startsWith('mailto:')) {
    email = emailLink.substring('mailto:'.length).trim();
  }
  if (email != null && email.isEmpty) email = null;

  // Extract phone
  String? phone = fieldValues['Telefon'];
  if (phone != null && phone.isEmpty) phone = null;

  // Extract consultation hours (Sprechzeit / Sprechstunde)
  String? consultation;
  for (final entry in fieldValues.entries) {
    if (entry.key.contains('Sprechzeit') || entry.key.contains('Sprechstunde')) {
      if (entry.value.isNotEmpty) {
        consultation = entry.value;
        break;
      }
    }
  }

  final functions = <PersonFunction>[];
  for (final table in document.querySelectorAll('table')) {
    final headers = table.querySelectorAll('th').map(_cellText).toList();
    if (headers.contains('Einrichtung') && headers.contains('Funktion')) {
      for (final row in _ownRows(table)) {
        final cells = _ownCells(row, 'td');
        if (cells.length >= 2) {
          final inst = _cellText(cells[0]);
          final role = _cellText(cells[1]);
          if (inst.isNotEmpty || role.isNotEmpty) {
            functions.add(PersonFunction(institution: inst, role: role));
          }
        }
      }
    }
  }

  final courses = <PersonCourse>[];
  for (final table in document.querySelectorAll('table')) {
    final headers = table.querySelectorAll('th').map(_cellText).toList();
    if (headers.contains('Veranstaltungen') && headers.contains('Semester')) {
      for (final row in _ownRows(table)) {
        final cells = _ownCells(row, 'td');
        if (cells.length >= 3) {
          final title = _cellText(cells[1]);
          final semester = _cellText(cells[2]);
          String? lectureId;
          final a = cells[1].querySelector('a');
          if (a != null) {
            final href = a.attributes['href'] ?? '';
            final match = RegExp(r'veranstaltung\.veranstid=(\d+)').firstMatch(href);
            lectureId = match?.group(1);
          }
          if (title.isNotEmpty) {
            courses.add(PersonCourse(
              title: title,
              semester: semester,
              lectureId: lectureId,
            ));
          }
        }
      }
    }
  }

  String? strOrNull(String? val) =>
      (val == null || val.trim().isEmpty) ? null : val.trim();

  return PersonDetails(
    personId: personId,
    title: strOrNull(fieldValues['Titel']),
    firstName: strOrNull(fieldValues['Vorname']),
    lastName: strOrNull(fieldValues['Nachname']),
    nameSuffix: strOrNull(fieldValues['Namenszusatz']),
    status: strOrNull(fieldValues['Personalstatus']),
    remark: strOrNull(fieldValues['Bemerkung']),
    consultationHours: consultation,
    email: email,
    phone: phone,
    street: strOrNull(fieldValues['Straße']),
    postalCode: strOrNull(fieldValues['PLZ']),
    city: strOrNull(fieldValues['Ort']),
    room: strOrNull(fieldValues['Dienstzimmer']),
    building: strOrNull(fieldValues['Gebäude']),
    homepage: homepage,
    functions: functions,
    courses: courses,
  );
}
