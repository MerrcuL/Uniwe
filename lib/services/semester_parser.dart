import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../models/semester_calendar.dart';

// Pure HTML → model functions for the academic calendar on htw-berlin.de,
// top-level so they can run on a background isolate via `compute`.

String _text(dom.Element element) => element.text
    .replaceAll(' ', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final RegExp _dateToken = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?');
final RegExp _deadlineLead =
    RegExp(r'^\s*(bis|by|until)\b', caseSensitive: false);

/// The dates in a calendar cell.
///
/// Understands single days ("13.02.2027"), spans whose first date may lack
/// the year ("01.10. - 05.10.2026", "23.12.2026 – 02.01.2027"), deadlines
/// ("bis 15.10.2026") and several of them separated by commas. Remarks in
/// brackets ("(27.03. prüfungsfrei)") are not dates of the entry.
List<DateSpan> parseCalendarDates(String text) {
  final spans = <DateSpan>[];
  final plain = text.replaceAll(RegExp(r'\([^)]*\)'), ' ');

  for (final part in plain.split(RegExp(r'[,;]'))) {
    final tokens = _dateToken.allMatches(part).toList();
    if (tokens.isEmpty) continue;

    int? year(RegExpMatch m) {
      final raw = m.group(3);
      if (raw == null) return null;
      final value = int.parse(raw);
      return raw.length == 2 ? 2000 + value : value;
    }

    DateTime? date(RegExpMatch m, int? y) {
      if (y == null) return null;
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(y, month, day);
    }

    if (tokens.length >= 2) {
      final endYear = year(tokens[1]);
      final end = date(tokens[1], endYear);
      if (end == null) continue;
      var start = date(tokens[0], year(tokens[0]) ?? endYear);
      if (start == null) continue;
      // "23.12. – 02.01.2027": the span began in the year before.
      if (start.isAfter(end) && year(tokens[0]) == null) {
        start = DateTime(start.year - 1, start.month, start.day);
      }
      if (start.isAfter(end)) continue;
      spans.add(DateSpan(start, end));
    } else {
      final day = date(tokens[0], year(tokens[0]));
      if (day == null) continue;
      spans.add(
        DateSpan(day, day, isDeadline: _deadlineLead.hasMatch(part)),
      );
    }
  }
  return spans;
}

/// Parses the "Akademischer Kalender" page (German or English). [baseUrl]
/// resolves the relative links of entries that only point elsewhere.
SemesterCalendar parseSemesterCalendarHtml((String, String) input) {
  final (html, baseUrl) = input;
  final document = parser.parse(html);
  final base = Uri.parse(baseUrl);
  final root = document.querySelector('main article') ??
      document.querySelector('main') ??
      document.body;
  if (root == null) return const SemesterCalendar(title: '', sections: []);

  final title = _text(root.querySelector('h1.page-title') ??
      root.querySelector('h1') ??
      dom.Element.tag('span'));

  final sections = <CalendarSection>[];
  for (final section in root.querySelectorAll('section')) {
    final table = section.querySelector('table');
    if (table == null) continue;
    // Sections can nest; a table belongs to the innermost one only.
    dom.Element? owner = table.parent;
    while (owner != null && owner.localName != 'section') {
      owner = owner.parent;
    }
    if (!identical(owner, section)) continue;
    final heading = section.querySelector('h1, h2, h3');
    final entries = <CalendarEntry>[];
    for (final row in table.querySelectorAll('tr')) {
      final th = row.querySelector('th');
      final td = row.querySelector('td');
      if (th == null || td == null) continue;
      final label = _text(th);
      // Line breaks separate the date from its remark.
      for (final br in td.querySelectorAll('br')) {
        br.replaceWith(dom.Text(' '));
      }
      final text = _text(td);
      if (label.isEmpty || text.isEmpty) continue;
      final spans = parseCalendarDates(text);
      Uri? link;
      if (spans.isEmpty) {
        final href = (td.querySelector('a') ?? th.querySelector('a'))
            ?.attributes['href'];
        if (href != null && href.isNotEmpty) {
          try {
            link = base.resolve(href);
          } catch (_) {
            link = null;
          }
        }
      }
      entries.add(
        CalendarEntry(label: label, text: text, spans: spans, link: link),
      );
    }
    if (entries.isEmpty) continue;
    sections.add(CalendarSection(
      title: heading == null ? '' : _text(heading),
      entries: entries,
    ));
  }

  // The teaching period: from the earliest "…beginn" to "Vorlesungsende"
  // (or their English wording) of the section that names the end.
  DateTime? lectureStart;
  DateTime? lectureEnd;
  final endLabel = RegExp(
    r'vorlesungsende|ende der vorlesung|end of (the )?(teaching|lecture)',
    caseSensitive: false,
  );
  final startLabel = RegExp(
    r'beginn|start of (the )?(teaching|lecture)',
    caseSensitive: false,
  );
  for (final section in sections) {
    CalendarEntry? end;
    for (final entry in section.entries) {
      if (entry.spans.isNotEmpty && endLabel.hasMatch(entry.label)) {
        end = entry;
        break;
      }
    }
    if (end == null) continue;
    lectureEnd = end.spans.last.end;
    for (final entry in section.entries) {
      if (entry.spans.isEmpty || !startLabel.hasMatch(entry.label)) continue;
      final start = entry.spans.first.start;
      if (lectureStart == null || start.isBefore(lectureStart)) {
        lectureStart = start;
      }
    }
    break;
  }
  if (lectureStart == null ||
      lectureEnd == null ||
      !lectureEnd.isAfter(lectureStart)) {
    lectureStart = null;
    lectureEnd = null;
  }

  return SemesterCalendar(
    title: title,
    sections: sections,
    lectureStart: lectureStart,
    lectureEnd: lectureEnd,
  );
}
