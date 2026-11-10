import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fictional LSF pages in the markup of the real ones ("Noten- und
/// Klassenspiegel", achievement page, "Bescheinigungen" menu), with a layout
/// table around the content like LSF.
const String fakeAsi = 'TestAsi.123';

const String _base = 'https://lsf.htw-berlin.de/qisserver/rds';

String _page(String content) => '''
<html><head><title>HTW Berlin</title></head><body>
<table width=100%><tr><td>
<ul><li><a href="$_base?state=change&amp;type=1&amp;moduleParameter=studyPOSReportMenu&amp;asi=$fakeAsi">Bescheinigungen</a></li></ul>
</td><td>
<div class=content>$content</div>
</td></tr></table>
</body></html>''';

String _doc(String call) =>
    '$_base?state=hisreports&amp;status=transform&amp;publishid=0&amp;vmfile=no&amp;moduleCall=$call&amp;asi=$fakeAsi';

String _record(String id) =>
    '$_base?state=hisreports&amp;status=transform&amp;publishid=$id&amp;vmfile=no&amp;moduleCall=Notenspiegel&amp;asi=$fakeAsi';

const String _degreeNode =
    'auswahlBaum%7Cabschluss%3Aabschl%3D84%2Cstgnr%3D1';

String _gradeList() =>
    '$_base?state=notenspiegelStudent&amp;next=list.vm&amp;nextdir=qispos/notenspiegel/student&amp;createInfos=Y&amp;struct=auswahlBaum&amp;nodeID=$_degreeNode&amp;expand=0&amp;asi=$fakeAsi';

String _distribution(String exam) =>
    '$_base?state=notenspiegelStudent&amp;next=list.vm&amp;nextdir=qispos/notenspiegel/student&amp;createInfos=Y&amp;struct=abschluss&amp;nodeID=$_degreeNode%7Cstudiengang%3Astg%3D999%7CkontoOnTop%3Alabnrzu%3D1%7Cpruefung%3Alabnr%3D$exam&amp;expand=0&amp;asi=$fakeAsi';

/// The programme tree: degree → programme, each with a link to its list.
final String fakeGradeTreeHtml = _page('''
<h1>Noten- und Klassenspiegel</h1>
<ul class=treelist>
<li><a href="$_base?state=notenspiegelStudent&amp;next=tree.vm&amp;nextdir=qispos/notenspiegel/student&amp;struct=auswahlBaum&amp;expand=1&amp;asi=$fakeAsi">Abschluss Bachelor</a>
<a href="${_gradeList()}" title="Leistungen anzeigen"><img src="info.svg"></a>
<ul><li><a href="$_base?state=notenspiegelStudent&amp;next=list.vm&amp;nextdir=qispos/notenspiegel/student&amp;createInfos=Y&amp;struct=auswahlBaum&amp;nodeID=$_degreeNode%7Cstudiengang%3Astg%3D999&amp;expand=0&amp;asi=$fakeAsi">Angewandte Informatik</a></li></ul>
</li></ul>
''');

String _exam(String nr, String name, String semester, String grade,
        String status, String credits, String attempt, String date,
        {String remark = '', bool link = true}) =>
    '''
<tr>
<td class=tabelle1_alignleft valign=top> $nr </td>
<td class=tabelle1_alignleft valign=top> $name </td>
<td class=tabelle1_alignleft valign=top nowrap> $semester </td>
<td class=tabelle1_alignright valign=top nowrap> $grade ${link ? '<a href="${_distribution(nr)}"><img src="chart.svg" alt="Klassenspiegel"></a>' : ''}</td>
<td class=tabelle1_aligncenter valign=top> $status </td>
<td class=tabelle1_alignright valign=top> $credits </td>
<td class=tabelle1_aligncenter valign=top> $remark </td>
<td class=tabelle1_alignright valign=top> $attempt </td>
<td class=tabelle1_alignright valign=top> $date </td>
</tr>''';

String _account(String cls, String nr, String name, String semester,
        String grade, String status, String credits) =>
    '''
<tr>
<td class=$cls valign=top align=left> <b>$nr</b> </td>
<td class=$cls valign=top align=left> $name </td>
<td class=$cls valign=top align=left> $semester </td>
<td class=$cls valign=top align=right> $grade </td>
<td class=$cls valign=top align=center> $status </td>
<td class=$cls valign=top align=right> $credits </td>
<td class=$cls valign=top align=left> </td>
<td class=$cls valign=top align=left> </td>
<td class=$cls valign=top align=left> </td>
</tr>''';

/// Personal data the app must never pick up.
const String _personalTable = '''
<table summary="Personendaten">
<tr><th class=mod_header>Name des Studierenden</th><td class=mod_n_basic>Erika Mustermann</td></tr>
<tr><th class=mod_header>Matrikelnummer</th><td class=mod_n_basic>000000</td></tr>
<tr><th class=mod_header>Anschrift</th><td class=mod_n_basic>Musterweg 1, 10000 Berlin</td></tr>
</table>''';

/// A grade list: overall account, exams of two semesters (one failed, one
/// free attempt), and a module group with its own grade.
final String fakeGradeListHtml = _page('''
<h1>Noten- und Klassenspiegel</h1>
$_personalTable
<table border=0><tbody>
<tr><th class=tabelleheader align=left colspan=9> <i>Abschluss:</i> [84] Bachelor <i>Studiengang:</i> [999] Angewandte Informatik</tr>
<tr>
<th class=tabelleheader scope=col> Prüfungsnr. </th>
<th class=tabelleheader scope=col> &nbsp;&nbsp;&nbsp;Prüfungstext </th>
<th class=tabelleheader scope=col> Semester&nbsp; </th>
<th class=tabelleheader scope=col> Note </th>
<th class=tabelleheader scope=col> Status </th>
<th class=tabelleheader scope=col> Leistungspunkte </th>
<th class=tabelleheader scope=col> Vermerk<sup>1)</sup> </th>
<th class=tabelleheader scope=col> Versuch </th>
<th class=tabelleheader scope=col> Prüfungsdatum </th>
</tr>
<tr>
<td class=qis_kontoOnTop valign=top align=left> <b>100</b> </td>
<td class=qis_kontoOnTop valign=top colspan=2 align=left> Studienplanübersicht </td>
<td class=qis_kontoOnTop valign=top align=right> 1,9<sup>2)</sup> </td>
<td class=qis_kontoOnTop valign=top align=center> </td>
<td class=qis_kontoOnTop valign=top align=right> 25 </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
</tr>
${_exam('1100', 'Mathematik 1', 'WiSe 25/26', '2,3', 'bestanden', '5', '1', '10.02.2026')}
${_exam('1200', 'Programmierung 1', 'WiSe 25/26', '5,0', 'nicht bestanden', '0', '1', '12.02.2026')}
${_exam('1200', 'Programmierung 1', 'SoSe 26', '1,7', 'bestanden', '6', '2', '20.07.2026', remark: 'FNB')}
${_exam('1300', 'Projektarbeit', 'SoSe 26', '', 'bestanden', '6', '1', '', link: false)}
<tr>
<td class=qis_kontoOnTop valign=top align=left> <b>7000</b> </td>
<td class=qis_kontoOnTop valign=top colspan=2 align=left> Wahlpflicht - bewusst auswählen! </td>
<td class=qis_kontoOnTop valign=top align=right> </td>
<td class=qis_kontoOnTop valign=top align=center> </td>
<td class=qis_kontoOnTop valign=top align=right> 0 </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
<td class=qis_kontoOnTop valign=top align=left> </td>
</tr>
${_account('qis_konto', '7600', 'Variante 1: Sprachen', 'SoSe 26', '1,65', 'Prüfung vorhanden', '8')}
${_exam('55000', 'Englisch B2', 'SoSe 26', '1,3', 'bestanden', '4', '1', '21.07.2026')}
</table>
''');

/// The grade distribution of one exam.
final String fakeDistributionHtml = _page('''
<h1>Noten- und Klassenspiegel</h1>
$_personalTable
<table border=0 width=100%><tbody>
<tr><th class=tabelleheader> Prüfungsnr. </th><th class=tabelleheader> Prüfungstext </th><th class=tabelleheader> Semester </th><th class=tabelleheader> Note </th><th class=tabelleheader> Status </th><th class=tabelleheader> Leistungspunkte </th><th class=tabelleheader> Vermerk </th><th class=tabelleheader> Versuch </th><th class=tabelleheader> Prüfungsdatum </th></tr>
<tr><td class=tabelle1> 1100 </td><td class=tabelle1> Mathematik 1 </td><td class=tabelle1> Wintersemester 25/26 </td><td class=tabelle1> 2,3 </td><td class=tabelle1> bestanden </td><td class=tabelle1> 5 </td><td class=tabelle1> </td><td class=tabelle1> 1 </td><td class=tabelle1> 10.02.2026 </td></tr>
</table>
<table border=0 align=left width=60%><tbody>
<tr><td><br></td></tr>
<tr><td class=tabelleheader colspan=2 align=center>NOTENSPIEGEL</td></tr>
<tr><td class=tabelleheader align=left> Notenbereich </td><td class=tabelleheader align=left>Anzahl</td></tr>
<tr><td class=tabelle1 align=right> sehr gut (1,0 - 1,3) </td><td class=tabelle1 align=right>4 </td></tr>
<tr><td class=tabelle1 align=right> gut (1,7 - 2,3) </td><td class=tabelle1 align=right>20 (inklusive Ihrer Leistung) </td></tr>
<tr><td class=tabelle1 align=right> befriedigend (2,7 - 3,3) </td><td class=tabelle1 align=right>9 </td></tr>
<tr><td class=tabelle1 align=right> ausreichend (3,7 - 4,0) </td><td class=tabelle1 align=right>0 </td></tr>
<tr><td class=tabelle1 align=right> nicht ausreichend (5,0 - 5,0) </td><td class=tabelle1 align=right>7 </td></tr>
<tr><td class=tabelleheader>Teilnehmende<td class=tabelle1 align=right>40</td></tr>
<tr><td class=tabelleheader> Durchschnittsnote <td class=tabelle1 align=right>2,6</td></tr>
</table>
''');

/// The "Leistungsstand und -bescheinigungen" page with its PDFs.
final String fakeAchievementHtml = _page('''
<h1>Noten- und Klassenspiegel</h1>
<table cellspacing=0 cellpadding=5 border=1 width=100%><tbody>
<tr><th class=tabelleheader>Prüfungsnummer</th><th class=tabelleheader>Prüfungsname</th><th class=tabelleheader>Semester</th><th class=tabelleheader>Note</th></tr>
<tr><td class=tabelle1>1100</td><td class=tabelle1>Mathematik 1</td><td class=tabelle1>WS 25/26</td><td class=tabelle1>2,3</td></tr>
</table>
<h2>Leistungsnachweis</h2>
<table cellspacing=0 cellpadding=5 border=1><tbody>
<tr><th class=tabelleheader>Semester</th><th class=tabelleheader>PDF-Dokumente</th></tr>
<tr><td class=tabelle1>&nbsp; SS 26&nbsp; </td><td class=tabelle1><a href="${_record('20261')}"><img src="x.svg"></a></td></tr>
<tr><td class=tabelle1>&nbsp; WS 25/26&nbsp; </td><td class=tabelle1><a href="${_record('20252')}"><img src="x.svg"></a></td></tr>
</table>
<h2>Bescheinigungen</h2>
<table cellspacing=0 cellpadding=5 border=1><tbody>
<tr><th class=tabelleheader>Dokumente</th><th class=tabelleheader>PDF-Dokumente</th></tr>
<tr><td class=tabelle1>Grade Transcript</td><td class=tabelle1><a href="${_doc('gradetranscript')}"><img src="x.svg"></a></td></tr>
</table>
''');

final String fakeDocumentsHtml = _page('''
<h1>Bescheinigungen</h1>
<ul class=liste>
<li><a href="${_doc('immabescheinigung')}" class=auflistung>aktuelle Immatrikulationsbescheinigung</a></li>
<li><a href="${_doc('immabescheinigung_en')}" class=auflistung>current confirmation of enrolment</a></li>
<li><a href="${_doc('Pruefungsleistungen_be')}" class=auflistung>Bescheinigung über nur bestandene Prüfungsleistungen</a></li>
<li><a href="${_doc('Pruefungsleistungen_been')}" class=auflistung>Transcript of passed examinations</a></li>
</ul>
''');

final List<int> fakePdf = utf8.encode('%PDF-1.4 fake');

const String fakeLectureDetailsHtml = '''
<table><tr><th>Credits</th><td> 5 </td><th>SWS</th><td>4</td></tr></table>
<table>
<tr><th>Tag</th><th>Zeit</th><th>Dauer</th><th>Lehrperson</th><th>Bemerkung</th></tr>
<tr><td>Mo.</td><td>08:00 bis 09:30</td><td>wöch</td><td><a href="https://lsf.htw-berlin.de/qisserver/rds?state=verpublish&amp;personal.pid=1114">Prof. Dr. Debora Weber-Wulff</a></td><td></td></tr>
</table>''';

const String fakePersonHtml = '''
<html><head><title>Prof. Dr. Debora Weber-Wulff</title></head><body>
<table summary="Grunddaten zur Veranstaltung">
  <caption>Grunddaten</caption>
  <tr><th class=mod id=basic_1>Nachname</th><td class=mod_n_basic>Weber-Wulff</td></tr>
  <tr><th class=mod id=basic_3>Vorname</th><td class=mod_n_basic>Debora</td>
      <th class=mod id=basic_6>Personalstatus</th><td class=mod_n_basic>Lehrperson</td></tr>
  <tr><th class=mod id=basic_7>Titel</th><td class=mod_n_basic>Prof. Dr.</td></tr>
  <tr><th class=mod id=basic_11>Weitere Links</th>
      <td class=mod_n_basic><a href="https://people.f4.htw-berlin.de/~weberwu/">Persönliche Homepage</a></td></tr>
</table>
<table summary="Angaben zur Dienstadresse">
  <tr><th class=mod id=pAdress_1>PLZ</th><td class=mod_n_basic>12459</td>
      <th class=mod id=pAdress_2>Telefon</th><td class=mod_n_basic>030 123456</td></tr>
  <tr><th class=mod id=pAdress_3>Ort</th><td class=mod_n_basic>Berlin</td></tr>
  <tr><th class=mod id=pAdress_5>Straße</th><td class=mod_n_basic>Wilhelminenhofstraße 75A</td>
      <th class=mod id=pAdress_6>E-Mail-Adresse</th>
      <td class=mod_n_basic><a href="mailto:Debora.Weber-Wulff@HTW-Berlin.de">Debora.Weber-Wulff@HTW-Berlin.de</a></td></tr>
  <tr><th class=mod id=pAdress_7>Dienstzimmer</th><td class=mod_n_basic>C 446</td>
      <th class=mod id=pAdress_8>Hyperlink</th>
      <td class=mod_n_basic><a href="https://people.f4.htw-berlin.de/~weberwu/">https://people.f4.htw-berlin.de/~weberwu/</a></td></tr>
  <tr><th class=mod id=pAdress_9>Gebäude</th><td class=mod_n_basic>Gebäude C</td></tr>
</table>
<table summary="Funktionen">
  <tr><th>Einrichtung</th><th>Funktion</th></tr>
  <tr><td>Fachbereich 4</td><td>Lehrbeauftragte*r</td></tr>
</table>
<table summary="Veranstaltungen">
  <tr><th>Vst.-Nr.</th><th>Veranstaltungen</th><th>Semester</th></tr>
  <tr><td>6212411262</td><td><a href="rds?veranstaltung.veranstid=234779">Social Engineering</a></td><td>WS 2026/27</td></tr>
</table>
</body></html>''';

/// An LSF that accepts any login and serves the pages above. Requests are
/// recorded in [requests]; [onDocument] decides what a document request
/// returns (default: a PDF).
class FakeLsf {
  final List<Uri> requests = [];
  int logins = 0;
  http.Response Function(Uri url)? onDocument;

  late final http.Client client = MockClient((request) async {
    requests.add(request.url);
    if (request.method == 'POST') {
      logins++;
      return http.Response('', 302,
          headers: {'set-cookie': 'JSESSIONID=s$logins; Path=/'});
    }
    http.Response page(String body) => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
    final params = request.url.queryParameters;
    switch (params['state']) {
      case 'change':
        return page(fakeDocumentsHtml);
      case 'htmlbesch':
        return page(fakeAchievementHtml);
      case 'notenspiegelStudent':
        if (params['next'] == 'tree.vm') return page(fakeGradeTreeHtml);
        if (params['struct'] == 'abschluss') return page(fakeDistributionHtml);
        return page(fakeGradeListHtml);
      case 'verpublish':
        if (params['publishSubDir'] == 'personal') {
          return page(fakePersonHtml);
        }
        return page(fakeLectureDetailsHtml);
      case 'hisreports':
        final custom = onDocument;
        if (custom != null) return custom(request.url);
        return http.Response.bytes(fakePdf, 200,
            headers: {'content-type': 'application/pdf'});
    }
    return http.Response('not found', 404);
  });
}
