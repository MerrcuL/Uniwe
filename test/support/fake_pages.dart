import 'fake_lsf.dart' show fakeAsi;

/// Fictional pages in the markup of the real ones: "Info über angemeldete
/// Prüfungen", the "Belegübersicht", LSF's list of cancelled classes and the
/// academic calendar of htw-berlin.de.

const String _base = 'https://lsf.htw-berlin.de/qisserver/rds';

String _page(String content) => '''
<html><head><title>HTW Berlin</title></head><body>
<table width=100%><tr><td>
<ul><li><a href="$_base?state=change&amp;type=1&amp;moduleParameter=studyPOSReportMenu&amp;asi=$fakeAsi">Bescheinigungen</a></li></ul>
</td><td>
<div class=content>$content</div>
</td></tr></table>
</body></html>''';

String _two(int n) => n.toString().padLeft(2, '0');

/// "09.11.2026"
String germanDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// "Info über angemeldete Prüfungen" with two exams — one [daysAhead] days
/// from now, one without a date — below the personal data box of the real
/// page. With [empty] the table has its header rows only.
String fakeRegisteredExamsHtml({int daysAhead = 12, bool empty = false}) {
  final now = DateTime.now();
  final date = DateTime(now.year, now.month, now.day + daysAhead);
  final rows = empty
      ? ''
      : '''
<tr><td class=tabelle1>1400</td><td class=tabelle1>Kryptologie</td><td class=tabelle1>Becker</td><td class=tabelle1>WiSe 26/27</td><td class=tabelle1>14.12.2026</td><td class=tabelle1>1</td><td class=tabelle1>${germanDate(date)}</td><td class=tabelle1>1</td></tr>
<tr><td class=tabelle1>1500</td><td class=tabelle1>Datenbanken</td><td class=tabelle1>Illes</td><td class=tabelle1>WiSe 26/27</td><td class=tabelle1>14.12.2026</td><td class=tabelle1>2</td><td class=tabelle1>&nbsp;</td><td class=tabelle1>2</td></tr>''';
  return _page('''
<h1 title="Sie sind hier: Info über angemeldete Prüfungen">Info über angemeldete Prüfungen</h1>
<table><tbody><tr><td>
<table align=left cellspacing=1 cellpadding=8><tbody><tr>
<td><font class=liste1>Name:&nbsp;Erika&nbsp;Mustermann</font></td>
<td><font class=liste1>Matrikelnr:&nbsp;000000</font></td>
<td><font class=liste1>Anschrift:&nbsp;Musterweg 1, 10000 Berlin</font></td>
</tr></table></tr>
<tr><td>
<table cellspacing=0 cellpadding=5 border=1 align=center width=100%><tbody>
<tr><th colspan=8 class=tabelleheader align=left> Bachelor Angewandte Informatik (Wintersemester 26/27) </th></tr>
<tr>
<th class=tabelleheader><span class=nobr>PrNr</span></th>
<th class=tabelleheader><span class=nobr>Prüfungsname</span></th>
<th class=tabelleheader><span class=nobr>Prüfer/-in</span></th>
<th class=tabelleheader><span class=nobr>Semester</span></th>
<th class=tabelleheader><span class=nobr>Anmeldedatum</span></th>
<th class=tabelleheader><span class=nobr>Termin</span></th>
<th class=tabelleheader><span class=nobr>Prüfungsdatum<sup>1</sup></span></th>
<th class=tabelleheader><span class=nobr>Versuch<sup>2</sup></span></th>
</tr>$rows
</table>
<br><sup>1</sup>Bei vorliegender Belegung finden Sie Raum- und Zeitinformationen in Ihrem <a href="$_base?state=wplan">persönlichen Stundenplan</a>.
</table>
''');
}

String _enrolment(
  String id,
  String number,
  String title,
  String group,
  String statuses,
  String rows,
) =>
    '''
<div class=abstand_leistung align=left></div>
<h2>Veranstaltung:
 <a class=regular href="$_base?state=verpublish&amp;status=init&amp;vmfile=no&amp;publishid=$id&amp;moduleCall=webInfo" title="Details ansehen zu $title">$number $title</a>
</h2>
<div class=Leistungen_Inhalt align=left>
 Gruppe: $group
 <br>
 $statuses
 &nbsp;&nbsp;&nbsp;
 <div align=left><a class=regular href="$_base?state=wwrite&amp;asi=$fakeAsi">Anmeldezahlen</a></div>
 <div align=left>
 <table summary="Termine der Veranstaltung $title" border=0><tbody>
 <tr><th scope=col class=mod>Tag</th><th scope=col class=mod>Zeit</th><th scope=col class=mod>Rhythmus</th><th scope=col class=mod>Dauer oder Termin</th><th scope=col class=mod>Raum</th><th scope=col class=mod>Lehrperson</th><th scope=col class=mod>Hinweis</th></tr>
 $rows
 </table>
 </div>
</div>
<br><hr>''';

String _enrolmentStatus(String cls, String label, String date) => '''
 <span class=$cls>
 $label
 </span>
 :&nbsp;$date
 Gruppenpriorität: 1''';

String _enrolmentDate(String day, String time, String rhythm, String duration,
        String room, String lecturer, String note) =>
    '''
 <tr><td class=mod_n_odd> $day </td><td class=mod_n_odd> $time </td><td class=mod_n_odd> $rhythm </td><td class=mod_n_odd> $duration&nbsp; </td>
 <td class=mod_n_odd><a class=regular href="$_base?state=wsearchv&amp;raum.rgid=1">$room</a></td>
 <td class=mod_n_odd><a class=regular href="$_base?state=verpublish&amp;personal.pid=1">$lecturer</a></td>
 <td class=mod_n_odd><span class=grueneWarnung>$note</span></td></tr>''';

/// The "Belegübersicht": two courses of the current semester (one with a
/// rejected first application) and the empty, collapsed past semester.
final String fakeEnrolmentsHtml = _page('''
<div class=kleinFett><span class=feld>Studiengänge</span></div>
<div class=functionnavi>
<div class=abstand_leistung align=left><h1>Aktuelle Veranstaltungen:</h1></div>
<div class=functionnavi>
<h2 style=background-color:#ffffff>Wintersemester 2026/2027:</h2>
<div class=evt_more_infos>Klick für mehr oder weniger Informationen</div>
<div class=Container_VeranstAus id=VeranstAus1>
${_enrolment('234776', '6212212262', 'B14 Cryptology (PCÜ)', '1. Zug, 1. Gruppe', _enrolmentStatus('grueneWarnung', 'zugelassen', '09.09.2026 06:50:35'), _enrolmentDate('Mo.', '09:45 bis 10:30', 'wöchentlich', '05.10.2026&nbsp;bis&nbsp;08.02.2027', 'WH TGS 2 001', 'Becker', 'findet statt'))}
${_enrolment('237233', '00204001', 'Spanisch, Grundstufe 1', 'Gruppe B', _enrolmentStatus('grueneWarnung', 'zugelassen', '18.09.2026 19:36:59') + _enrolmentStatus('warnung', 'abgelehnt', '11.09.2026 12:33:17'), _enrolmentDate('Di.', '17:30 bis 20:45', 'wöchentlich', '06.10.2026&nbsp;bis&nbsp;02.02.2027', 'WH TGS 1a 224', 'García', 'findet statt') + _enrolmentDate('Di.', '17:30 bis 19:30', 'Einzeltermin', 'am 09.02.2027', 'WH TGS 1a 328', 'García', 'findet statt'))}
</div></div></div>
<div class=functionnavi>
<div class=abstand_leistung align=left><h1>Absolvierte Veranstaltungen:</h1></div>
<div class=functionnavi>
<h2 style=background-color:#ffffff>Sommersemester 2026:</h2>
<div class=Container_VeranstAus id=VeranstAus2 style=display:none></div></div></div>
''');

String _cancelledRow(String start, String end, String number, String id,
        String title, String building, String room, String group,
        String remark) =>
    '''
<tr>
<td class="mod_n_odd"> $start</td>
<td class="mod_n_odd">$end</td>
<td class="mod_n_odd">$number</td>
<td class="mod_n_odd">
 <a class="regular" href="$_base?state=verpublish&amp;status=init&amp;vmfile=no&amp;publishid=$id&amp;moduleCall=webInfo">
 $title
 </a>
</td>
<td class="mod_n_odd">$building</td>
<td class="mod_n_odd">
 $building $room
</td>
<td class="mod_n_odd"> $group</td>
<td class="mod_n_odd">$remark</td>
</tr>''';

/// The lecture that is cancelled in [fakeCancelledHtml] (twice: two groups
/// at different times).
const String fakeCancelledPublishId = '236604';

/// LSF's public "Ausfallende Veranstaltungen" of one day. As on the real
/// page, rows have no cell for the (empty) lecturer column.
final String fakeCancelledHtml = '''
<html><body><div class="content_max_portal_qis">
<div class="InfoLeiste"> 3 Treffer </div>
<h2>Ausfallende Veranstaltungen Mo, 16.11.2026 </h2>
<table>
<tr>
<th scope="col" class="mod">Beginn</th><th scope="col" class="mod">Ende</th><th scope="col" class="mod">Nr.</th>
<th scope="col" class="mod">Titel der Veranstaltung</th><th scope="col" class="mod">Gebäude</th><th scope="col" class="mod">Raum</th>
<th scope="col" class="mod">Parallelgruppe</th><th scope="col" class="mod">Durchführende Lehrpersonen</th><th scope="col" class="mod">Bemerkung</th>
</tr>
${_cancelledRow('08:00', '09:30', '7041112', fakeCancelledPublishId, 'G11 Mathematik 1 (BÜ)', 'WH Gebäude C', '414', '1. Zug, 1. Gruppe', 'Ersatztermin: 17.11.26, 08:00-09:30, WH C403')}
${_cancelledRow('11:30', '13:00', '7041112', fakeCancelledPublishId, 'G11 Mathematik 1 (BÜ)', 'WH Gebäude C', '414', '1. Zug, 2. Gruppe', '')}
${_cancelledRow('08:00', '11:15', '5112211', '233435', 'B13 Grdl. Invest. u. Finanz.', 'TA Gebäude A', '118', '2. Zug', '')}
</table></div></body></html>''';

/// The academic calendar page of htw-berlin.de, with a teaching period that
/// started [startedDaysAgo] days ago and dates around today.
String fakeCalendarHtml({int startedDaysAgo = 44, bool english = false}) {
  final now = DateTime.now();
  DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
  final start = day(-startedDaysAgo);
  final end = day(-startedDaysAgo + 134);
  String short(DateTime d) => '${_two(d.day)}.${_two(d.month)}.';
  return '''
<html><body><main class="default"><article>
<h1 class="page-title">${english ? 'Academic calendar: winter semester 2026/27' : 'Akademischer Kalender: Wintersemester 2026/27'}</h1>
<section id="c1"></section>
<section id="c2"><div class="csc-header"><h1 class="">
 ${english ? 'Semester dates' : 'Semesterzeiten'}
 </h1></div><figure class="table"><table class="key-value_table"><tbody>
<tr><th>${english ? 'Start of teaching period from the 2nd semester onwards' : 'Lehrveranstaltungsbeginn ab dem 2. Fachsemester'}</th><td>${germanDate(start)}</td></tr>
<tr><th>${english ? 'Start of teaching period for first-year students' : 'Lehrveranstaltungsbeginn für Erstsemester'}</th><td>${germanDate(day(-startedDaysAgo + 4))}</td></tr>
<tr><th rowspan="1">${english ? 'Non-teaching period' : 'Vorlesungsfrei'}</th><td rowspan="1">${germanDate(day(40))} – ${germanDate(day(50))}</td></tr>
<tr><th rowspan="1">${english ? 'End of the teaching period' : 'Vorlesungsende'}</th><td rowspan="1">${germanDate(end)}</td></tr>
</tbody></table></figure></section>
<section id="c3"><div class="csc-header"><h1 class="">
 ${english ? 'Enrolment &amp; re-registration' : 'Einschreibung &amp; Rückmeldung'}
 </h1></div><figure class="table"><table class="key-value_table"><tbody>
<tr><th>Einschreibung der Studienbewerber*innen</th><td>bis ${germanDate(day(-30))}</td></tr>
<tr><th><a href="/studium/studienorganisation/rueckmeldung" class="internal-link">Rückmeldung</a>&nbsp;zum nächsten Semester</th><td>${short(day(-3))} - ${germanDate(day(20))}</td></tr>
<tr><th>Antrag auf Beurlaubung</th><td>bis ${germanDate(day(5))}</td></tr>
</tbody></table></figure></section>
<section id="c4"><div class="csc-header"><h1 class="">
 Kurse, Prüfungen &amp; Abschlussarbeit
 </h1></div><figure class="table"><table class="key-value_table"><tbody>
<tr><th>Kursbelegung</th><td><a href="/studium/studienorganisation/kursbelegung" class="internal-link">Termine</a></td></tr>
<tr><th>Online-Prüfungsanmeldung für den 1. und 2. Prüfungszeitraum</th><td>${short(day(30))} – ${germanDate(day(37))}, ${short(day(51))} – ${germanDate(day(55))}&nbsp;<br>(Ausschlussfrist)</td></tr>
<tr><th>1. Prüfungszeitraum</th><td>${short(day(72))} – ${germanDate(end)}</td></tr>
<tr><th rowspan="1">2. Prüfungszeitraum</th><td rowspan="1">${short(day(128))} – ${germanDate(day(144))} (${short(day(133))} prüfungsfrei)</td></tr>
</tbody></table></figure></section>
</article></main>
<aside><section id="c9"><table class="key-value_table"><tbody><tr><th scope="row">Wintersemester</th><td>01.10. bis 31.03.</td></tr></tbody></table></section></aside>
</body></html>''';
}
