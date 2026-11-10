import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniwe/l10n/app_localizations.dart';
import 'package:uniwe/models/grades.dart';
import 'package:uniwe/models/lecture_details.dart';
import 'package:uniwe/models/mensa_category.dart';
import 'package:uniwe/models/mensa_meal.dart';
import 'package:uniwe/models/timetable_event.dart';
import 'package:uniwe/services/auth_service.dart';
import 'package:uniwe/services/cache_service.dart';
import 'package:uniwe/services/document_service.dart';
import 'package:uniwe/services/exceptions.dart';
import 'package:uniwe/services/log_service.dart';
import 'package:uniwe/services/lsf_parser.dart';
import 'package:uniwe/services/lsf_scraper_service.dart';
import 'package:uniwe/services/timetable_store.dart';
import 'package:uniwe/utils/cookies.dart';
import 'package:uniwe/utils/event_layout.dart';
import 'package:uniwe/utils/iso_week.dart';

import 'support/fake_lsf.dart';
import 'support/fakes.dart';

TimetableEvent event(String title, String time, {String day = 'Montag'}) =>
    TimetableEvent(
      title: title,
      day: day,
      time: time,
      room: 'WH C 1',
      type: 'Vorlesung',
      frequency: 'wöch',
    );

const _timetableHtml = '''
<html><body><table>
<tr><td class="plan_rahmen">frame</td>
<td class="plan2"><table>
  <tr><td class="notiz"><a class="ver" href="rds?state=verpublish&amp;publishid=4711&amp;x=1">Mathematik 1 (B1)</a></td></tr>
  <tr><td class="notiz">Montag, 08:00 - 09:30, wöch</td></tr>
  <tr><td class="notiz">Vorlesung, Raum: WH C 345</td></tr>
</table></td>
<td class="plan3">
  <table><tr><td class="notiz"><a class="ver" href="rds?publishid=1">Physik</a></td></tr>
    <tr><td class="notiz">Dienstag, 10:00 - 11:30, 14-täg</td></tr>
    <tr><td class="notiz">Übung, Raum: TA A 1</td></tr></table>
  <table><tr><td class="notiz"><a class="ver" href="rds?publishid=2">Chemie</a>
    <span class="warnung">Prüfung</span></td></tr>
    <tr><td class="notiz">Dienstag, 10:00 - 12:00, Einzelt.</td></tr>
    <tr><td class="notiz">Klausur, Raum: TA B 2</td></tr></table>
</td></tr></table></body></html>''';

const _detailsHtml = '''
<table><tr><th>Credits</th><td> 5 </td><th>SWS</th><td>4</td></tr></table>
<table>
<tr><th>Tag</th><th>Zeit</th><th>Dauer</th><th>Lehrperson</th><th>Bemerkung</th></tr>
<tr><td>Mo.</td><td>08:00 bis 09:30</td><td>wöch</td><td><a href="rds?personal.pid=123">Prof. A</a></td><td></td></tr>
<tr><td>Fr.</td><td>10:00 bis 12:00</td><td>am 12.02.2027</td><td>Prof. A</td><td>Prüfung</td></tr>
<tr><td>Fr.</td><td>10:00 bis 12:00</td><td>am 12.02.2027</td><td>Prof. B</td><td>Prüfung</td></tr>
</table>''';

void main() {
  group('date paging', () {
    test('IsoWeek.index round-trips across DST and year boundaries', () {
      for (final date in [
        DateTime(2026, 3, 29), // EU DST start (a Sunday)
        DateTime(2026, 10, 25), // EU DST end
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
        DateTime(2024, 2, 29),
      ]) {
        final week = IsoWeek.fromDate(date);
        expect(IsoWeek.fromIndex(week.index), week, reason: '$date');
        expect(week.next.index, week.index + 1, reason: '$date');
        expect(week.previous.index, week.index - 1, reason: '$date');
      }
    });

    test('day pages are contiguous and skip weekends when hidden', () {
      final friday = DateTime(2026, 11, 13);
      final monday = DateTime(2026, 11, 16);
      expect(Dates.dayPage(monday, 5), Dates.dayPage(friday, 5) + 1);
      expect(Dates.dayPage(monday, 7), Dates.dayPage(friday, 7) + 3);

      // A Saturday maps to the following Monday in the 5-day pager.
      expect(
          Dates.dayPage(DateTime(2026, 11, 14), 5), Dates.dayPage(monday, 5));

      for (final days in [5, 7]) {
        for (var offset = 0; offset < 400; offset++) {
          final page = Dates.dayPage(friday, days) + offset;
          final date = Dates.dateOfDayPage(page, days);
          expect(Dates.dayPage(date, days), page);
        }
      }
    });
  });

  group('TimetableEvent', () {
    test('parses time range, weekday and clean title once', () {
      final e = event('Mathematik 1 (B12.3)', '08:00 - 09:30', day: 'Dienstag');
      expect(e.startMinutes, 480);
      expect(e.endMinutes, 570);
      expect(e.hasTimeRange, isTrue);
      expect(e.dayIndex, 1);
      expect(e.cleanTitle, 'Mathematik 1');
      expect(e.startLabel, '08:00');
      expect(e.endLabel, '09:30');
    });

    test('tolerates missing or malformed data', () {
      final e = event('X', '', day: '');
      expect(e.startMinutes, isNull);
      expect(e.hasTimeRange, isFalse);
      expect(e.dayIndex, -1);
      expect(event('X', '9:15').endMinutes, isNull);
    });
  });

  group('week grid layout', () {
    test('non-overlapping events take the full width', () {
      final placed = layoutDayEvents([
        event('A', '08:00 - 09:30'),
        event('B', '09:30 - 11:00'),
      ]);
      expect(placed.map((p) => p.columnCount), [1, 1]);
    });

    test('a chain of overlaps reuses free columns', () {
      // A and C never run at the same time, so two columns are enough.
      final placed = layoutDayEvents([
        event('A', '08:00 - 10:00'),
        event('B', '09:00 - 11:00'),
        event('C', '10:30 - 12:00'),
      ]);
      final byTitle = {for (final p in placed) p.event.title: p};
      expect(placed.every((p) => p.columnCount == 2), isTrue);
      expect(byTitle['A']!.column, 0);
      expect(byTitle['B']!.column, 1);
      expect(byTitle['C']!.column, 0);
    });

    test('events without a usable time range are skipped', () {
      expect(
        layoutDayEvents([event('A', ''), event('B', '10:00 - 09:00')]),
        isEmpty,
      );
    });
  });

  group('LSF parser', () {
    test('extracts events with their own details', () {
      final events = parseTimetableHtml(_timetableHtml);
      expect(events, hasLength(3));

      final math = events[0];
      expect(math.title, 'Mathematik 1 (B1)');
      expect(math.publishId, '4711');
      expect(math.day, 'Montag');
      expect(math.time, '08:00 - 09:30');
      expect(math.room, 'WH C 345');
      expect(math.type, 'Vorlesung');
      expect(math.frequency, 'wöch');
      expect(math.isOverlapping, isFalse);
      expect(math.isExam, isFalse);

      expect(events[1].isOverlapping, isTrue);
      expect(events[1].room, 'TA A 1');
      expect(events[1].isExam, isFalse);
      expect(events[2].isExam, isTrue);
      expect(events[2].room, 'TA B 2');
    });

    test('recognises the login page', () {
      expect(isLsfLoginPage('<input name="asdf">'), isTrue);
      expect(isLsfLoginPage(_timetableHtml), isFalse);
    });

    test('extracts lecture details', () {
      final parsed = parseLectureDetailsHtml(('99', _detailsHtml));
      expect(parsed.publishId, '99');
      expect(parsed.credits, '5');
      expect(parsed.sws, '4');
      expect(parsed.teachers, [
        const Lecturer(name: 'Prof. A', personId: '123'),
        const Lecturer(name: 'Prof. B'),
      ]);
      expect(parsed.examDates, hasLength(1));
      expect(parsed.examDates.single.date, '12.02.2027');
    });

    test('extracts person details from LSF person page', () {
      const html = '''
<html><body>
<table summary="Grunddaten zur Veranstaltung">
  <caption>Grunddaten</caption>
  <tr><th class=mod id=basic_1>Nachname</th><td class=mod_n_basic>Weber-Wulff</td></tr>
  <tr><th class=mod id=basic_3>Vorname</th><td class=mod_n_basic>Debora</td>
      <th class=mod id=basic_6>Personalstatus</th><td class=mod_n_basic>Lehrperson</td></tr>
  <tr><th class=mod id=basic_7>Titel</th><td class=mod_n_basic>Prof. Dr.</td></tr>
  <tr><th class=mod id=basic_11>Weitere Links</th>
      <td class=mod_n_basic><a href="rds?state=redirect&amp;destination=https%3A%2F%2Fpeople.f4.htw-berlin.de%2F%7Eweberwu%2F">Persönliche Homepage</a></td></tr>
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

      final person = parsePersonDetailsHtml(('1114', html));
      expect(person.personId, '1114');
      expect(person.displayName, 'Prof. Dr. Debora Weber-Wulff');
      expect(person.status, 'Lehrperson');
      expect(person.email, 'Debora.Weber-Wulff@HTW-Berlin.de');
      expect(person.phone, '030 123456');
      expect(person.address, 'Wilhelminenhofstraße 75A, 12459 Berlin');
      expect(person.office, 'C 446, Gebäude C');
      expect(person.homepage, Uri.parse('https://people.f4.htw-berlin.de/~weberwu/'));
      expect(person.functions, hasLength(1));
      expect(person.functions.first.institution, 'Fachbereich 4');
      expect(person.functions.first.role, 'Lehrbeauftragte*r');
      expect(person.courses, hasLength(1));
      expect(person.courses.first.title, 'Social Engineering');
      expect(person.courses.first.semester, 'WS 2026/27');
      expect(person.courses.first.lectureId, '234779');
    });
  });

  group('TimetableStore', () {
    late IsoWeek week;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CacheService.instance.resetForTesting();
      week = IsoWeek.fromDate(DateTime(2026, 11, 9));
    });

    test('loads, groups by day, caches and serves fresh data from memory',
        () async {
      var calls = 0;
      final store = TimetableStore(fetch: (key) async {
        calls++;
        expect(key, '46_2026');
        return [
          event('Late', '12:00 - 13:30'),
          event('Early', '08:00 - 09:30'),
          event('Tue', '08:00 - 09:30', day: 'Dienstag'),
        ];
      });

      expect(store.schedule(week), isNull);
      expect(await store.refresh(week), isTrue);
      final schedule = store.schedule(week)!;
      expect(schedule.byDay[0].map((e) => e.title), ['Early', 'Late']);
      expect(schedule.byDay[1].single.title, 'Tue');
      expect(schedule.timeRange(5), (start: 480, end: 810));

      // Fresh: no second request.
      expect(await store.refresh(week), isTrue);
      expect(calls, 1);
      expect(await store.refresh(week, force: true), isTrue);
      expect(calls, 2);

      // A new store finds the week in the persistent cache.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final restored = TimetableStore(fetch: (_) async => throw 'offline');
      expect(restored.schedule(week)!.events, hasLength(3));
      store.dispose();
      restored.dispose();
    });

    test('concurrent refreshes share one request; failures are per week',
        () async {
      var calls = 0;
      final store = TimetableStore(fetch: (key) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (key == week.next.key) throw Exception('boom');
        return [event('A', '08:00 - 09:30')];
      });

      final results = await Future.wait([
        store.refresh(week),
        store.refresh(week),
        store.refresh(week.next),
      ]);
      expect(results, [true, true, false]);
      expect(calls, 2);
      expect(store.hasFailed(week), isFalse);
      expect(store.hasFailed(week.next), isTrue);
      expect(store.isLoading(week), isFalse);
      store.dispose();
    });

    test('clear() discards responses that are still in flight', () async {
      final store = TimetableStore(fetch: (key) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return [event('A', '08:00 - 09:30')];
      });
      final pending = store.refresh(week);
      store.clear();
      expect(await pending, isFalse);
      // Nothing from the old session may reappear (memory or cache).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.schedule(week), isNull);
      store.dispose();
    });
  });

  group('grades and documents', () {
    test('parses the grade list: overall, exams, groups, no personal data',
        () {
      final report = parseGradeListHtml(fakeGradeListHtml);
      expect(report.programs, ['Angewandte Informatik · Bachelor']);
      expect(report.average, '1,9'); // footnote mark stripped
      expect(report.credits, '25');
      expect(report.results.map((r) => r.number),
          ['1100', '1200', '1200', '1300', '55000']);

      final first = report.results.first;
      expect(first.name, 'Mathematik 1');
      expect(first.semester, 'WiSe 25/26');
      expect(first.grade, '2,3');
      expect(first.gradeValue, 2.3);
      expect(first.status, ExamStatus.passed);
      expect(first.credits, '5');
      expect(first.attempt, '1');
      expect(first.date, '10.02.2026');
      expect(first.isGroup, isFalse);
      final link = first.distributionUrl!;
      expect(link.queryParameters['struct'], 'abschluss');
      expect(link.queryParameters['nodeID'], endsWith('pruefung:labnr=1100'));
      expect(link.queryParameters.containsKey('asi'), isFalse);

      expect(report.results[1].status, ExamStatus.failed);
      expect(report.results[2].remark, 'FNB');
      expect(report.results[2].attempt, '2');
      expect(report.results[3].grade, isEmpty);
      expect(report.results[3].distributionUrl, isNull);

      // The group with a grade; the empty selection account is left out.
      expect(report.groups, hasLength(1));
      final group = report.groups.single;
      expect(group.isGroup, isTrue);
      expect(group.grade, '1,65');
      expect(group.credits, '8');
      expect(group.status, ExamStatus.other);
      expect(group.statusLabel, 'Prüfung vorhanden');

      // Newest semester first, LSF order within a semester.
      expect(report.bySemester.map((e) => e.key), ['SoSe 26', 'WiSe 25/26']);
      expect(report.bySemester.first.value.map((r) => r.number),
          ['1200', '1300', '55000']);

      // Nothing of the personal data table leaks into the report.
      final everything = [
        ...report.programs,
        for (final r in [...report.results, ...report.groups]) ...[
          r.name,
          r.number,
          r.semester,
          r.statusLabel,
        ],
      ].join(' ');
      expect(everything, isNot(contains('Mustermann')));
      expect(everything, isNot(contains('Musterweg')));
    });

    test('parses the programme tree and the grade distribution', () {
      final lists = parseGradeTreeHtml(fakeGradeTreeHtml);
      // The degree covers the programme below it; only it is fetched.
      expect(lists, hasLength(1));
      expect(lists.single.queryParameters['nodeID'],
          'auswahlBaum|abschluss:abschl=84,stgnr=1');
      expect(lists.single.queryParameters.containsKey('asi'), isFalse);

      final distribution = parseGradeDistributionHtml(fakeDistributionHtml)!;
      expect(distribution.participants, 40);
      expect(distribution.average, '2,6');
      expect(distribution.maxCount, 20);
      expect(distribution.bands.map((b) => b.nameKey), [
        'bandVeryGood',
        'bandGood',
        'bandSatisfactory',
        'bandSufficient',
        'bandFailed',
      ]);
      expect(distribution.bands.map((b) => b.range),
          ['1,0–1,3', '1,7–2,3', '2,7–3,3', '3,7–4,0', '5,0']);
      expect(distribution.bands.map((b) => b.count), [4, 20, 9, 0, 7]);
      expect(distribution.bands.map((b) => b.includesYou),
          [false, true, false, false, false]);
      expect(parseGradeDistributionHtml(fakeGradeListHtml), isNull);
    });

    test('parses the PDFs of the achievement page', () {
      final documents = parseAchievementDocumentsHtml(fakeAchievementHtml);
      expect(documents.records.map((d) => d.title), ['SS 26', 'WS 25/26']);
      expect(documents.records.first.url.queryParameters['publishid'],
          '20261');
      expect(documents.transcripts.map((d) => d.title), ['Grade Transcript']);
      for (final d in [...documents.records, ...documents.transcripts]) {
        expect(d.url.queryParameters.containsKey('asi'), isFalse);
      }
    });

    test('parses the documents menu and its languages', () {
      final documents = parseDocumentsMenuHtml(fakeDocumentsHtml);
      expect(documents.map((d) => d.url.queryParameters['moduleCall']), [
        'immabescheinigung',
        'immabescheinigung_en',
        'Pruefungsleistungen_be',
        'Pruefungsleistungen_been',
      ]);
      expect(documents.map((d) => d.isEnglish), [false, true, false, true]);
      expect(documents.map((d) => d.nameKey), [
        'docEnrolment',
        'docEnrolment',
        'docPassedResults',
        'docPassedResults',
      ]);
      expect(parseLsfAsi(fakeDocumentsHtml), fakeAsi);
      expect(parseLsfAsi('<html><a href="?state=user">x</a></html>'), isNull);
    });

    test('semester order', () {
      expect(GradeReport.semesterOrder('WS 26/27'),
          greaterThan(GradeReport.semesterOrder('SS 26')));
      expect(GradeReport.semesterOrder('SS 26'),
          greaterThan(GradeReport.semesterOrder('WS 25/26')));
      expect(GradeReport.semesterOrder('WiSe 26/27'),
          greaterThan(GradeReport.semesterOrder('SoSe 26')));
      expect(GradeReport.semesterOrder('Sommersemester 26'),
          GradeReport.semesterOrder('SoSe 26'));
      expect(GradeReport.semesterOrder('?'), -1);
    });

    test('file names for documents', () {
      expect(DocumentService.fileName('Grade Transcript'),
          'Grade_Transcript.pdf');
      expect(DocumentService.fileName('Bescheinigung über Prüfungsleistungen'),
          'Bescheinigung_über_Prüfungsleistungen.pdf');
      expect(DocumentService.fileName('WS 25/26'), 'WS_25_26.pdf');
      expect(DocumentService.fileName('///'), 'document.pdf');
    });

    AuthService signedIn(FakeLsf lsf) {
      final logger = LogService();
      return AuthService(
        LsfScraperService(logger, client: lsf.client),
        logger,
        storage: FakeSecureStorage(username: 's0123456', password: 'secret'),
      );
    }

    test('grades and documents use the session token', () async {
      final lsf = FakeLsf();
      final auth = signedIn(lsf);

      final report = await auth.fetchGrades();
      expect(report.results, hasLength(5));
      final gradeRequests = lsf.requests
          .where((u) => u.queryParameters['state'] == 'notenspiegelStudent')
          .toList();
      // Tree, then the degree's list.
      expect(gradeRequests.map((u) => u.queryParameters['next']),
          ['tree.vm', 'list.vm']);
      for (final request in gradeRequests) {
        expect(request.queryParameters['asi'], fakeAsi);
      }

      final distribution =
          await auth.fetchDistribution(report.results.first);
      expect(distribution!.participants, 40);
      expect(lsf.requests.last.queryParameters['struct'], 'abschluss');
      expect(lsf.requests.last.queryParameters['asi'], fakeAsi);
      expect(await auth.fetchDistribution(report.results[3]), isNull);

      final documents = await auth.fetchAchievementDocuments();
      expect(lsf.requests.last.queryParameters['asi'], fakeAsi);
      final pdf = await auth.downloadDocument(documents.transcripts.single);
      expect(pdf, fakePdf);
      final docRequest = lsf.requests.last;
      expect(docRequest.queryParameters['moduleCall'], 'gradetranscript');
      expect(docRequest.queryParameters['asi'], fakeAsi);
      auth.dispose();
    });

    test('a document LSF does not offer is reported, without re-logins',
        () async {
      final lsf = FakeLsf()
        ..onDocument = (_) => http.Response(fakeDocumentsHtml, 200,
            headers: {'content-type': 'text/html'});
      final auth = signedIn(lsf);
      final documents = await auth.fetchDocuments();
      final loginsBefore = lsf.logins;
      await expectLater(auth.downloadDocument(documents.first),
          throwsA(isA<DocumentUnavailableException>()));
      expect(lsf.logins, loginsBefore);
      auth.dispose();
    });

    test('a lost session is restored before downloading', () async {
      var expired = true;
      final lsf = FakeLsf();
      lsf.onDocument = (_) {
        if (expired) {
          expired = false;
          return http.Response('<form><input name="asdf"></form>', 200);
        }
        return http.Response.bytes(fakePdf, 200);
      };
      final auth = signedIn(lsf);
      final documents = await auth.fetchDocuments();
      final loginsBefore = lsf.logins;
      expect(await auth.downloadDocument(documents.first), fakePdf);
      expect(lsf.logins, loginsBefore + 1);
      auth.dispose();
    });
  });

  group('moodle', () {
    const loginPage = '<html><form class="login-form" id="login" method="post">'
        '<input type="hidden" name="logintoken" value="tok123">'
        '<input name="username"><input name="password"></form></html>';

    /// Moodle that accepts [password] and counts sign-ins.
    ({http.Client client, List<Map<String, String>> posts}) fakeMoodle(
        String password) {
      final posts = <Map<String, String>>[];
      final client = MockClient((request) async {
        if (request.url.host != AuthService.moodleHost) {
          // LSF start-up login of the AuthService.
          return http.Response('', 302,
              headers: {'set-cookie': 'JSESSIONID=x; Path=/'});
        }
        if (request.method == 'GET') {
          return http.Response(loginPage, 200,
              headers: {'set-cookie': 'MoodleSession=anon; path=/; secure'});
        }
        posts.add(request.bodyFields);
        final ok = request.bodyFields['password'] == password &&
            request.headers['Cookie'] == 'MoodleSession=anon';
        return http.Response('', 303, headers: {
          if (ok) ...{
            'location':
                'https://moodle.htw-berlin.de/login/index.php?testsession=42',
            'set-cookie': 'MoodleSession=user${posts.length}; path=/; secure',
          } else
            'location':
                'https://moodle.htw-berlin.de/login/index.php?loginredirect=1',
        });
      });
      return (client: client, posts: posts);
    }

    AuthService authWith(http.Client client, String password) {
      final logger = LogService();
      return AuthService(
        LsfScraperService(logger, client: client),
        logger,
        storage: FakeSecureStorage(username: 's0123456', password: password),
        httpClient: () => client,
      );
    }

    test('signs in with the stored credentials and the login token',
        () async {
      final moodle = fakeMoodle('secret');
      final auth = authWith(moodle.client, 'secret');
      await Future<void>.delayed(Duration.zero);

      final cookies = await auth.getMoodleCookies();
      expect(cookies, {'MoodleSession': 'user1'});
      expect(moodle.posts.single, {
        'anchor': '',
        'logintoken': 'tok123',
        'username': 's0123456',
        'password': 'secret',
      });

      // A recent session is reused; `fresh` signs in again.
      expect(await auth.getMoodleCookies(), {'MoodleSession': 'user1'});
      expect(moodle.posts, hasLength(1));
      expect(await auth.getMoodleCookies(fresh: true),
          {'MoodleSession': 'user2'});
      auth.dispose();
    });

    test('a rejected login yields no session', () async {
      final moodle = fakeMoodle('other');
      final auth = authWith(moodle.client, 'secret');
      await Future<void>.delayed(Duration.zero);
      expect(await auth.getMoodleCookies(), isNull);
      auth.dispose();
    });

    test('logout forgets the Moodle session', () async {
      final moodle = fakeMoodle('secret');
      final auth = authWith(moodle.client, 'secret');
      await Future<void>.delayed(Duration.zero);
      await auth.getMoodleCookies();
      await auth.logout();
      expect(await auth.getMoodleCookies(), isNull); // no credentials left
      expect(moodle.posts, hasLength(1));
      auth.dispose();
    });
  });

  group('empty timetables', () {
    test('an empty week is re-checked with a fresh login before it is believed',
        () async {
      SharedPreferences.setMockInitialValues({});
      await CacheService.instance.resetForTesting();

      var logins = 0;
      var timetableRequests = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          logins++;
          return http.Response('', 302,
              headers: {'set-cookie': 'JSESSIONID=s$logins; Path=/'});
        }
        timetableRequests++;
        // The stale session renders an empty plan; the new one the real one.
        final fresh = request.headers['Cookie']!.contains('JSESSIONID=s2');
        return http.Response.bytes(
          utf8.encode(fresh ? _timetableHtml : '<html><table></table></html>'),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final logger = LogService();
      final auth = AuthService(
        LsfScraperService(logger, client: client),
        logger,
        storage: FakeSecureStorage(username: 's0123456', password: 'secret'),
      );

      final events = await auth.fetchTimetable('46_2026');
      expect(events, hasLength(3));
      expect(logins, 2); // startup login + verification login
      expect(timetableRequests, 2);
      expect(auth.isAuthenticated, isTrue);
      auth.dispose();
    });

    test('the store asks again for a week that came back empty', () async {
      SharedPreferences.setMockInitialValues({});
      await CacheService.instance.resetForTesting();
      final week = IsoWeek.fromDate(DateTime(2026, 11, 9));

      var calls = 0;
      final store = TimetableStore(fetch: (_) async {
        calls++;
        return calls == 1 ? [] : [event('A', '08:00 - 09:30')];
      });
      expect(await store.refresh(week), isTrue);
      expect(store.schedule(week)!.isEmpty, isTrue);
      expect(await store.refresh(week), isTrue);
      expect(calls, 2);
      expect(store.schedule(week)!.events, hasLength(1));
      store.dispose();
    });
  });

  group('CacheService', () {
    test('prunes old entries and removes by prefix', () async {
      final old = DateTime.now().subtract(const Duration(days: 60));
      SharedPreferences.setMockInitialValues({
        '__data_timetable_1_2026': '[]',
        '__ts_timetable_1_2026': old.toIso8601String(),
        '__data_timetable_2_2026': '[]',
        '__ts_timetable_2_2026': DateTime.now().toIso8601String(),
        '__data_mensa_2037_2026-11-09': '[]',
        '__ts_mensa_2037_2026-11-09': DateTime.now().toIso8601String(),
        'themeMode': 'dark',
      });
      final cache = CacheService.instance;
      await cache.resetForTesting();

      await cache.prune();
      expect(cache.read('timetable_1_2026').data, isNull);
      expect(cache.read('timetable_2_2026').data, isNotNull);

      await cache
          .removeWhere((k) => k.startsWith(CacheService.timetablePrefix));
      expect(cache.read('timetable_2_2026').data, isNull);
      expect(cache.read('mensa_2037_2026-11-09').data, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'dark');
    });
  });

  test('mergeSetCookie keeps commas inside Expires dates intact', () {
    final cookies = <String, String>{};
    mergeSetCookie(
      'JSESSIONID=abc; Path=/; Expires=Wed, 09 Nov 2026 10:00:00 GMT, other=1; HttpOnly',
      cookies,
    );
    expect(cookies, {'JSESSIONID': 'abc', 'other': '1'});
    expect(cookieHeader(cookies), 'JSESSIONID=abc; other=1');
  });

  test('MensaCategory matches singular/plural API names and orders', () {
    expect(MensaCategory.match('Suppe')!.key, 'Suppen');
    expect(MensaCategory.match('Salate')!.key, 'Salat');
    expect(MensaCategory.match('Hauptgericht')!.key, 'Essen');
    expect(MensaCategory.match('Getränke'), isNull);
    expect(
      MensaCategory.ordered(['Dessert', 'unknown', 'Essen']).map((c) => c.key),
      [
        'Dessert',
        'Essen',
        'Beilagen',
        'Suppen',
        'Salat',
        'Aktionen',
        'Vorspeisen',
      ],
    );
  });

  test('meal notes lose the category prefix and list number', () {
    expect(MensaMeal.cleanNote('Allergens: 27 Sellerie'), 'Sellerie');
    expect(MensaMeal.cleanNote('Allergens: 21a Weizen'), 'Weizen');
    expect(MensaMeal.cleanNote('Additives: 9 Phosphat'), 'Phosphat');
    expect(
      MensaMeal.cleanNote('Allergens: 30 Milch und Milchprodukte (inkl. Laktose)'),
      'Milch und Milchprodukte (inkl. Laktose)',
    );
    expect(MensaMeal.cleanNote('Klimaessen'), 'Klimaessen');
    expect(MensaMeal.cleanNote('2 Portionen'), 'Portionen');

    final meal = MensaMeal.fromJson({
      'id': 1,
      'name': 'X',
      'category': 'Essen',
      'prices': <String, double>{},
      'notes': ['Vegan', 'Allergens: 27 Sellerie', 'Additives: 27 Sellerie'],
    });
    expect(meal.noteCodes, ['27']);
    expect(
      MensaMeal.fromJson({
        'id': 2,
        'name': 'Y',
        'category': 'Essen',
        'prices': <String, double>{},
        'notes': ['Allergens: 21a Weizen', 'Additives: 9 Phosphat', 'Klimaessen'],
      }).noteCodes,
      ['21a', '9'],
    );
    // Rating and footprint texts are not allergens.
    expect(
      MensaMeal.fromJson({
        'id': 3,
        'name': 'Z',
        'category': 'Essen',
        'prices': <String, double>{},
        'notes': [
          'Grüner Ampelpunkt: Die beste Wahl – je öfter, desto besser',
          'Der Wasserverbrauch für dieses Gericht liegt unter dem Durchschnitt',
          'Dieses Gericht verursacht weniger als halb so viel CO₂',
          'Allergens: 28 Soja',
        ],
      }).displayNotes,
      ['Soja'],
    );
    // The diet label is its own tag; duplicates collapse.
    expect(meal.displayNotes, ['Sellerie']);
  });

  test('every string is translated in both languages', () {
    expect(AppLocalizations.keysFor('de'), AppLocalizations.keysFor('en'));
  });
}
