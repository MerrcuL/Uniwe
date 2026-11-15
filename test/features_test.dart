import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniwe/app_events.dart';
import 'package:uniwe/models/mensa_meal.dart';
import 'package:uniwe/models/semester_calendar.dart';
import 'package:uniwe/models/timetable_event.dart';
import 'package:uniwe/navigation/nav_layout.dart';
import 'package:uniwe/screens/cancelled_screen.dart';
import 'package:uniwe/screens/enrolments_screen.dart';
import 'package:uniwe/screens/exams_screen.dart';
import 'package:uniwe/screens/main_screen.dart';
import 'package:uniwe/screens/navigation_settings_screen.dart';
import 'package:uniwe/screens/semester_screen.dart';
import 'package:uniwe/screens/timetable_screen.dart';
import 'package:uniwe/screens/widgets_screen.dart';
import 'package:uniwe/services/cache_service.dart';
import 'package:uniwe/services/home_widget_service.dart';
import 'package:uniwe/services/lsf_parser.dart';
import 'package:uniwe/services/semester_parser.dart';
import 'package:uniwe/services/semester_service.dart';
import 'package:uniwe/services/settings_service.dart';
import 'package:uniwe/utils/formats.dart';
import 'package:uniwe/utils/iso_week.dart';
import 'package:uniwe/widgets/floating_tab_bar.dart';

import 'support/fake_lsf.dart';
import 'support/fakes.dart';

// Tests for exams, enrolments, cancelled classes, semester dates, the
// configurable navigation and the data of the home screen widgets.
// Set UNIWE_SCREENSHOTS=<dir> to also write PNGs of each screen.

final _screenshotDir = Platform.environment['UNIWE_SCREENSHOTS'];
final _boundaryKey = GlobalKey();

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    var any = false;
    for (final name in files) {
      final file = File('$dir/$name');
      if (!file.existsSync()) continue;
      any = true;
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    if (any) await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

void _usePhone(WidgetTester tester, {Size size = const Size(360, 760)}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = _screenshotDir;
  if (dir == null) return;
  final boundary = _boundaryKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

Widget _framed(Widget app) => RepaintBoundary(key: _boundaryKey, child: app);

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Parsing runs on background isolates: give them real time.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await _settle(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

Map<String, Object?> _eventJson(
  String title,
  DateTime day,
  String time, {
  String? publishId,
  bool exam = false,
}) =>
    {
      'title': title,
      'day': _weekdays[day.weekday - 1],
      'time': time,
      'room': 'WH C 414',
      'type': 'Vorlesung',
      'frequency': 'wöch',
      'publishId': publishId,
      'isExam': exam,
      'isOverlapping': false,
    };

SemesterService _semesterService() => SemesterService(
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            fakeCalendarHtml(english: request.url.path.startsWith('/en/')),
          ),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

void main() {
  setUpAll(_loadFonts);

  setUp(() => AppEvents.currentTab.value = AppTab.timetable);

  group('parsers', () {
    test('cancelled classes, with LSF leaving the lecturer cell out', () {
      final lectures = parseCancelledLecturesHtml(fakeCancelledHtml);
      expect(lectures, hasLength(3));

      final first = lectures.first;
      expect(first.start, '08:00');
      expect(first.end, '09:30');
      expect(first.number, '7041112');
      expect(first.title, 'G11 Mathematik 1 (BÜ)');
      expect(first.publishId, fakeCancelledPublishId);
      expect(first.building, 'WH Gebäude C');
      expect(first.room, 'WH Gebäude C 414');
      expect(first.group, '1. Zug, 1. Gruppe');
      expect(first.lecturers, isEmpty);
      // The last cell is the remark, not the (missing) lecturers.
      expect(first.remark, 'Ersatztermin: 17.11.26, 08:00-09:30, WH C403');
      expect(first.campus, 'WH');
      expect(lectures.last.campus, 'TA');
      expect(lectures.last.remark, isEmpty);

      // JSON round trip (the cache).
      final copy = lectures
          .map((l) => jsonDecode(jsonEncode(l.toJson())))
          .map((j) => parseCancelledLecturesHtml('').isEmpty
              ? Map<String, dynamic>.from(j as Map)
              : <String, dynamic>{})
          .toList();
      expect(copy.first['publishId'], fakeCancelledPublishId);
    });

    test('a cancellation only matches the same lecture at the same time', () {
      final lectures = parseCancelledLecturesHtml(fakeCancelledHtml);
      TimetableEvent event(String time, String? id) => TimetableEvent(
            title: 'Mathematik 1',
            day: 'Montag',
            time: time,
            room: '',
            type: '',
            frequency: '',
            publishId: id,
          );

      expect(
        lectures.first.matches(event('08:00 - 09:30', fakeCancelledPublishId)),
        isTrue,
      );
      // Another group of the same lecture, later that day.
      expect(
        lectures.first.matches(event('11:30 - 13:00', fakeCancelledPublishId)),
        isFalse,
      );
      expect(lectures.first.matches(event('08:00 - 09:30', '1')), isFalse);
      expect(lectures.first.matches(event('08:00 - 09:30', null)), isFalse);
    });

    test('registered exams, without the personal data above them', () {
      final registrations = parseRegisteredExamsHtml(fakeRegisteredExamsHtml());
      expect(
        registrations.programs,
        ['Bachelor Angewandte Informatik (Wintersemester 26/27)'],
      );
      expect(registrations.exams, hasLength(2));

      final exam = registrations.exams.first;
      expect(exam.number, '1400');
      expect(exam.name, 'Kryptologie');
      expect(exam.examiner, 'Becker');
      expect(exam.semester, 'WiSe 26/27');
      expect(exam.registeredOn, '14.12.2026');
      expect(exam.period, '1');
      expect(exam.attempt, '1');
      expect(exam.day, _day(12));
      expect(exam.daysUntil(_day(0)), 12);

      final undated = registrations.exams.last;
      expect(undated.name, 'Datenbanken');
      expect(undated.date, isEmpty);
      expect(undated.day, isNull);
      expect(undated.attempt, '2');

      expect(jsonEncode(registrations.toJson()), isNot(contains('Mustermann')));

      // Dated exams first; over ones are "past".
      expect(
        registrations.upcoming(_day(0)).map((e) => e.name),
        ['Kryptologie', 'Datenbanken'],
      );
      expect(registrations.upcoming(_day(13)).map((e) => e.name),
          ['Datenbanken']);
      expect(registrations.past(_day(13)).map((e) => e.name), ['Kryptologie']);
    });

    test('no registered exams: the programme is still known', () {
      final registrations =
          parseRegisteredExamsHtml(fakeRegisteredExamsHtml(empty: true));
      expect(registrations.exams, isEmpty);
      expect(registrations.programs, hasLength(1));
    });

    test('enrolments with states and dates', () {
      final enrolments = parseEnrolmentsHtml(fakeEnrolmentsHtml);
      expect(enrolments, hasLength(2));

      final crypto = enrolments.first;
      expect(crypto.number, '6212212262');
      expect(crypto.title, 'B14 Cryptology (PCÜ)');
      expect(crypto.publishId, '234776');
      expect(crypto.semester, 'Wintersemester 2026/2027');
      expect(crypto.statuses, hasLength(1));
      expect(crypto.status!.label, 'zugelassen');
      expect(crypto.status!.positive, isTrue);
      expect(crypto.status!.group, '1. Zug, 1. Gruppe');
      expect(crypto.status!.date, '09.09.2026 06:50');
      expect(crypto.dates, hasLength(1));
      expect(crypto.dates.single.day, 'Mo.');
      expect(crypto.dates.single.time, '09:45 – 10:30');
      expect(crypto.dates.single.rhythm, 'wöchentlich');
      expect(crypto.dates.single.duration, '05.10.2026 bis 08.02.2027');
      expect(crypto.dates.single.room, 'WH TGS 2 001');
      expect(crypto.dates.single.lecturer, 'Becker');
      expect(crypto.dates.single.note, 'findet statt');

      // Rejected first, admitted later: the admission counts.
      final spanish = enrolments.last;
      expect(spanish.title, 'Spanisch, Grundstufe 1');
      expect(spanish.statuses.map((s) => s.label), ['zugelassen', 'abgelehnt']);
      expect(spanish.statuses.last.isRejected, isTrue);
      expect(spanish.statuses.last.positive, isFalse);
      expect(spanish.status!.positive, isTrue);
      expect(spanish.dates, hasLength(2));
      expect(spanish.dates.last.duration, 'am 09.02.2027');
    });

    test('calendar dates', () {
      List<String> spans(String text) => [
            for (final s in parseCalendarDates(text))
              '${Formats.isoDate(s.start)}..${Formats.isoDate(s.end)}'
                  '${s.isDeadline ? '!' : ''}',
          ];

      expect(spans('13.02.2027'), ['2027-02-13..2027-02-13']);
      expect(spans('01.10. - 05.10.2026'), ['2026-10-01..2026-10-05']);
      // Across the turn of the year, with and without the first year.
      expect(spans('23.12.2026 – 02.01.2027'), ['2026-12-23..2027-01-02']);
      expect(spans('23.12. – 02.01.2027'), ['2026-12-23..2027-01-02']);
      expect(spans('bis 15.10.2026'), ['2026-10-15..2026-10-15!']);
      expect(spans('by 15.10.2026'), ['2026-10-15..2026-10-15!']);
      expect(
        spans('14.12. – 21.12.2026, 04.01. – 08.01.2027 (Ausschlussfrist)'),
        ['2026-12-14..2026-12-21', '2027-01-04..2027-01-08'],
      );
      // A date in a remark is not a date of the entry.
      expect(
        spans('22.03. – 07.04.2027 (27.03. prüfungsfrei)'),
        ['2027-03-22..2027-04-07'],
      );
      expect(spans('01.10.2026 (keine Lehrveranstaltungen)'),
          ['2026-10-01..2026-10-01']);
      expect(spans('Termine'), isEmpty);
      expect(spans('01.04. bis 30.09.'), isEmpty);
      expect(spans('99.99.2026'), isEmpty);
    });

    test('the academic calendar page, in both languages', () {
      for (final english in [false, true]) {
        final calendar = parseSemesterCalendarHtml((
          fakeCalendarHtml(english: english),
          'https://www.htw-berlin.de/studium/',
        ));
        expect(
          calendar.semesterName,
          english ? 'Winter semester 2026/27' : 'Wintersemester 2026/27',
        );
        // The sidebar ("Wintersemester 01.10. bis 31.03.") is not part of it.
        expect(calendar.sections, hasLength(3));
        expect(calendar.lectureStart, _day(-44));
        expect(calendar.lectureEnd, _day(90));

        final today = _day(0);
        expect(calendar.lectureProgress(today), closeTo(44 / 135, 0.001));
        final week = calendar.lectureWeek(today)!;
        expect(week.week, inInclusiveRange(7, 8));
        expect(week.total, inInclusiveRange(20, 21));
        expect(calendar.lectureWeek(_day(-50)), isNull);
        expect(calendar.lectureWeek(_day(100)), isNull);

        final entries = [for (final s in calendar.sections) ...s.entries];
        CalendarEntry entry(String start) =>
            entries.firstWhere((e) => e.label.startsWith(start));

        expect(entry('Einschreibung').stateOn(today), CalendarEntryState.past);
        expect(entry('Rückmeldung').stateOn(today), CalendarEntryState.active);
        expect(entry('Rückmeldung').nextDate(today), _day(20));
        // A deadline is "on" until its day.
        expect(entry('Antrag').stateOn(today), CalendarEntryState.active);
        expect(entry('Antrag').nextDate(today), _day(5));
        expect(entry('1. Prüf').stateOn(today), CalendarEntryState.upcoming);
        expect(entry('1. Prüf').nextDate(today), _day(72));
        expect(entry('Online').spans, hasLength(2));
        expect(entry('Kursbelegung').stateOn(today),
            CalendarEntryState.undated);
        expect(
          entry('Kursbelegung').link.toString(),
          'https://www.htw-berlin.de/studium/studienorganisation/kursbelegung',
        );

        // Soonest first.
        final upcoming = calendar.upcoming(today);
        expect(upcoming.first.entry.label, startsWith('Antrag'));
        expect(upcoming.first.date, _day(5));
        expect(
          upcoming.map((u) => u.date).toList(),
          [...upcoming.map((u) => u.date)]..sort(),
        );

        // JSON round trip (the cache).
        final copy = SemesterCalendar.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(jsonEncode(calendar.toJson())) as Map,
          ),
        );
        expect(copy.semesterName, calendar.semesterName);
        expect(copy.lectureStart, calendar.lectureStart);
        expect(copy.lectureEnd, calendar.lectureEnd);
        expect(copy.sections.length, calendar.sections.length);
        expect(copy.upcoming(today).length, upcoming.length);
        expect(
          copy.sections[1].entries[2].spans.single.isDeadline,
          isTrue,
        );
      }
    });
  });

  group('navigation layout', () {
    test('the default matches the former fixed navigation', () {
      expect(NavLayout.standard.bar, ['timetable', 'mensa', 'transport']);
      expect(NavLayout.standard.menu.first, 'lsf');
      expect(NavLayout.standard.hidden, isEmpty);
      expect(
        {...NavLayout.standard.bar, ...NavLayout.standard.menu},
        NavIds.all.toSet(),
      );
    });

    test('moves between the bar, the menu and the hidden ones', () {
      var layout = NavLayout.standard.move('grades', NavSection.bar, 1);
      expect(layout.bar, ['timetable', 'grades', 'mensa', 'transport']);
      expect(layout.menu, isNot(contains('grades')));
      expect(layout.sectionOf('grades'), NavSection.bar);

      // The bar is full now.
      expect(layout.problemWithMove('exams', NavSection.bar),
          NavMoveProblem.barFull);
      expect(layout.move('exams', NavSection.bar), same(layout));
      // Reordering inside a full bar still works.
      layout = layout.move('transport', NavSection.bar, 0);
      expect(layout.bar, ['transport', 'timetable', 'grades', 'mensa']);

      layout = layout.move('mensa', NavSection.hidden);
      expect(layout.hidden, ['mensa']);
      expect(layout.bar, hasLength(3));

      // LSF and Moodle are full-screen browsers.
      expect(layout.problemWithMove('lsf', NavSection.bar),
          NavMoveProblem.menuOnly);
      expect(layout.problemWithMove('moodle', NavSection.hidden), isNull);

      // The bar never ends up with the menu alone.
      layout = layout
          .move('transport', NavSection.menu)
          .move('grades', NavSection.menu);
      expect(layout.bar, ['timetable']);
      expect(layout.problemWithMove('timetable', NavSection.menu),
          NavMoveProblem.barEmpty);
      expect(layout.move('timetable', NavSection.hidden), same(layout));
    });

    test('stored layouts are repaired', () {
      final layout = NavLayout.normalized(
        bar: ['lsf', 'mensa', 'mensa', 'gone', 'grades', 'exams', 'email',
            'transport'],
        menu: ['mensa', 'moodle'],
        hidden: ['certificates', 'grades'],
      );
      // Unknown and duplicate ids are dropped, LSF leaves the bar, and what
      // does not fit moves to the front of the menu.
      expect(layout.bar, ['mensa', 'grades', 'exams', 'email']);
      expect(layout.menu.take(3), ['lsf', 'transport', 'moodle']);
      expect(layout.hidden, ['certificates']);
      // Destinations the stored layout did not know join the menu.
      expect(layout.menu, containsAll(['timetable', 'cancelled', 'semester']));
      expect(
        {...layout.bar, ...layout.menu, ...layout.hidden},
        NavIds.all.toSet(),
      );

      final empty = NavLayout.normalized(
        bar: const [],
        menu: const ['lsf', 'grades'],
        hidden: const [],
      );
      expect(empty.bar, ['grades']);
    });

    test('settings persist the layout and migrate the e-mail switch',
        () async {
      SharedPreferences.setMockInitialValues({'emailInNavBar': true});
      var settings = SettingsService();
      await settings.loadSettings();
      expect(
        settings.navLayout.bar,
        ['timetable', 'mensa', 'email', 'transport'],
      );
      expect(settings.navLayout.menu, isNot(contains('email')));

      await settings.updateNavLayout(
        settings.navLayout.move('mensa', NavSection.hidden),
      );
      settings = SettingsService();
      await settings.loadSettings();
      expect(settings.navLayout.bar, ['timetable', 'email', 'transport']);
      expect(settings.navLayout.hidden, ['mensa']);

      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.loadSettings();
      expect(settings.navLayout, NavLayout.standard);
    });
  });

  group('home screen widget data', () {
    test('timetable: the next days of the cached weeks, cancellations marked',
        () async {
      final today = _day(0);
      final week = IsoWeek.fromDate(today);
      SharedPreferences.setMockInitialValues({
        ...cacheEntry(CacheService.weekKey(week.key), [
          _eventJson('Mathematik 1 (B1)', today, '08:00 - 09:30',
              publishId: fakeCancelledPublishId),
          _eventJson('Physik', today, '11:30 - 13:00',
              publishId: fakeCancelledPublishId),
          _eventJson('Ohne Zeit', today, ''),
        ]),
        ...cacheEntry(
          CacheService.cancelledKey(Formats.isoDate(today)),
          [
            for (final l in parseCancelledLecturesHtml(fakeCancelledHtml))
              l.toJson(),
          ],
        ),
      });
      await CacheService.instance.resetForTesting();

      final signedOut =
          HomeWidgetService.buildTimetable(today, signedIn: false);
      expect(signedOut['signedIn'], isFalse);
      expect(signedOut['days'], isEmpty);

      final data = HomeWidgetService.buildTimetable(today, signedIn: true);
      final days = data['days'] as List;
      expect(days, hasLength(1));
      final day = days.single as Map;
      expect(day['date'], Formats.isoDate(today));
      final events = day['events'] as List;
      // Events without a time cannot be "next".
      expect(events.map((e) => (e as Map)['title']),
          ['Mathematik 1', 'Physik']);
      expect((events[0] as Map)['start'], 8 * 60);
      expect((events[0] as Map)['end'], 9 * 60 + 30);
      expect((events[0] as Map)['cancelled'], isTrue);
      // Same lecture, but the cancelled group meets at another time.
      expect((events[1] as Map)['cancelled'], isTrue);

      // Only this week is cached: the data ends on its Sunday.
      expect(data['until'], Formats.isoDate(week.day(6)));
      expect(jsonEncode(data), isNotEmpty);
    });

    test('exams: dated and still ahead', () async {
      SharedPreferences.setMockInitialValues(cacheEntry(
        CacheService.examsKey,
        parseRegisteredExamsHtml(fakeRegisteredExamsHtml()).toJson(),
      ));
      await CacheService.instance.resetForTesting();

      expect(HomeWidgetService.buildExams(_day(0)), [
        {'name': 'Kryptologie', 'date': Formats.isoDate(_day(12))},
      ]);
      expect(HomeWidgetService.buildExams(_day(13)), isEmpty);
    });

    test('semester: teaching period and what comes next', () {
      final calendar = parseSemesterCalendarHtml((
        fakeCalendarHtml(),
        'https://www.htw-berlin.de/studium/',
      ));
      final data = HomeWidgetService.buildSemester(calendar, _day(0));
      expect(data['name'], 'Wintersemester 2026/27');
      expect(data['start'], Formats.isoDate(_day(-44)));
      expect(data['end'], Formats.isoDate(_day(90)));
      final next = data['next'] as List;
      expect((next.first as Map)['label'], startsWith('Antrag'));
      expect((next.first as Map)['active'], isTrue);
      expect(HomeWidgetService.buildSemester(null, _day(0)), isEmpty);
    });

    test('mensa: main dishes with the chosen price and diet', () {
      MensaMeal meal(String name, String category, List<String> notes) =>
          MensaMeal(
            id: name.hashCode,
            name: name,
            notes: notes,
            prices: const {'students': 2.45, 'employees': 4.9},
            category: category,
          );
      final meals = <String, List<MensaMeal>>{
        '2026-11-16': [
          meal('Curry', 'Essen', ['Vegan']),
          meal('Schnitzel', 'Essen', []),
          meal('Suppe', 'Suppen', ['Vegan']),
        ],
        '2026-11-17': [meal('Salat', 'Salat', [])],
      };

      var data = HomeWidgetService.buildMensa(
        campus: 'WH',
        mealsByDay: meals,
        priceKey: 'employees',
        dietFilters: const {},
        language: 'de',
      );
      expect(data['campus'], 'WH');
      var days = data['days'] as List;
      expect(days, hasLength(2));
      // Main dishes only, when the day has any.
      final first = (days[0] as Map)['meals'] as List;
      expect(first.map((m) => (m as Map)['name']), ['Curry', 'Schnitzel']);
      expect((first[0] as Map)['price'], contains('4,90'));
      expect((first[0] as Map)['diet'], 'vegan');
      expect(((days[1] as Map)['meals'] as List).single['name'], 'Salat');

      data = HomeWidgetService.buildMensa(
        campus: 'WH',
        mealsByDay: meals,
        priceKey: 'students',
        dietFilters: const {'vegan'},
        language: 'en',
      );
      days = data['days'] as List;
      // The second day has nothing vegan.
      expect(days, hasLength(1));
      expect(
        ((days[0] as Map)['meals'] as List).map((m) => (m as Map)['name']),
        ['Curry'],
      );
    });
  });

  group('screens', () {
    testWidgets('registered exams: countdown, list and empty state',
        (tester) async {
      _usePhone(tester);
      final lsf = FakeLsf();
      final app = await TestApp.create(signedIn: true, lsfClient: lsf.client);

      await tester.pumpWidget(_framed(app.wrap(const ExamsScreen())));
      await _settleIo(tester);
      expect(find.text('Registered exams'), findsOneWidget);
      expect(find.text('Next exam'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('days left'), findsOneWidget);
      expect(find.text('Kryptologie'), findsNWidgets(2)); // card and list
      expect(find.text('Datenbanken'), findsOneWidget);
      expect(find.text('in 12 days'), findsOneWidget);
      expect(find.text('Date not set yet'), findsOneWidget);
      expect(find.text('Attempt 2'), findsOneWidget);
      expect(find.text('Period 1'), findsOneWidget);
      expect(find.textContaining('Mustermann'), findsNothing);
      await _shot(tester, 'exams_light');

      // The result is cached for the next visit (and the widgets).
      expect(CacheService.instance.read(CacheService.examsKey).data, isMap);

      await tester.pumpWidget(_framed(app.wrap(
        ExamsScreen(key: UniqueKey()),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settleIo(tester);
      expect(find.text('Angemeldete Prüfungen'), findsOneWidget);
      expect(find.text('Nächste Prüfung'), findsOneWidget);
      expect(find.text('in 12 Tagen'), findsOneWidget);
      await _shot(tester, 'exams_dark_de');
      await _unmount(tester);
    });

    testWidgets('exams offline: cache with a notice, else a retry',
        (tester) async {
      _usePhone(tester);
      var app = await TestApp.create(signedIn: true);
      await tester.pumpWidget(_framed(app.wrap(const ExamsScreen())));
      await _settleIo(tester);
      expect(find.text('Exams could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      app = await TestApp.create(
        signedIn: true,
        prefs: cacheEntry(
          CacheService.examsKey,
          parseRegisteredExamsHtml(fakeRegisteredExamsHtml(empty: true))
              .toJson(),
        ),
      );
      await tester.pumpWidget(
        _framed(app.wrap(ExamsScreen(key: UniqueKey()))),
      );
      await _settleIo(tester);
      expect(find.text('No registered exams'), findsOneWidget);
      expect(
        find.textContaining('Bachelor Angewandte Informatik'),
        findsOneWidget,
      );
      expect(find.text('Exams could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await _shot(tester, 'exams_empty');
      await _unmount(tester);
    });

    testWidgets('enrolments: summary, states and the details sheet',
        (tester) async {
      _usePhone(tester);
      final lsf = FakeLsf();
      final app = await TestApp.create(signedIn: true, lsfClient: lsf.client);

      await tester.pumpWidget(_framed(app.wrap(const EnrolmentsScreen())));
      await _settleIo(tester);
      expect(find.text('Wintersemester 2026/2027'), findsOneWidget);
      expect(find.text('B14 Cryptology (PCÜ)'), findsOneWidget);
      expect(find.text('Spanisch, Grundstufe 1'), findsOneWidget);
      expect(find.text('Courses'), findsOneWidget);
      // Summary label and one pill per course.
      expect(find.text('Admitted'), findsNWidgets(3));
      expect(find.text('Rejected'), findsNothing);
      await _shot(tester, 'enrolments_light');

      await tester.tap(find.text('Spanisch, Grundstufe 1'));
      await _settleIo(tester);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Dates'), findsOneWidget);
      expect(find.text('Di. 17:30 – 20:45'), findsOneWidget);
      expect(find.text('WH TGS 1a 224'), findsOneWidget);
      expect(find.textContaining('am 09.02.2027'), findsOneWidget);
      expect(find.text('Open in LSF'), findsOneWidget);
      await _shot(tester, 'enrolment_sheet');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      await tester.pumpWidget(_framed(app.wrap(
        EnrolmentsScreen(key: UniqueKey()),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settleIo(tester);
      expect(find.text('Belegungen'), findsOneWidget);
      expect(find.text('Zugelassen'), findsNWidgets(3));
      await _shot(tester, 'enrolments_dark_de');
      await _unmount(tester);
    });

    testWidgets('cancelled classes: own ones first, campus filter',
        (tester) async {
      _usePhone(tester);
      final lsf = FakeLsf();
      final today = _day(0);
      final app = await TestApp.create(
        signedIn: true,
        lsfClient: lsf.client,
        prefs: cacheEntry(
          CacheService.weekKey(IsoWeek.fromDate(today).key),
          [
            _eventJson('G11 Mathematik 1 (BÜ)', today, '08:00 - 09:30',
                publishId: fakeCancelledPublishId),
          ],
        ),
      );

      await tester.pumpWidget(_framed(app.wrap(const CancelledScreen())));
      await _settleIo(tester);
      // LSF is asked for the selected day, without needing a session.
      final request = lsf.requests
          .lastWhere((u) => u.queryParameters['state'] == 'currentLectures');
      expect(request.queryParameters['HISCalendar_Date'], germanDate(today));
      expect(request.queryParameters['type'], '1');

      expect(find.text('Your classes'), findsOneWidget);
      expect(find.text('All classes · 2'), findsOneWidget);
      expect(find.text('G11 Mathematik 1 (BÜ)'), findsNWidgets(2));
      expect(find.text('B13 Grdl. Invest. u. Finanz.'), findsOneWidget);
      expect(
        find.text('Ersatztermin: 17.11.26, 08:00-09:30, WH C403'),
        findsOneWidget,
      );
      await _shot(tester, 'cancelled_light');

      await tester.tap(find.text('TA'));
      await _settle(tester);
      expect(find.text('All classes · 1'), findsOneWidget);
      // The user's own class stays, whatever the campus.
      expect(find.text('G11 Mathematik 1 (BÜ)'), findsOneWidget);

      await tester.tap(find.text('TGS'));
      await _settle(tester);
      expect(find.textContaining('All classes'), findsNothing);
      expect(find.text('Your classes'), findsOneWidget);

      await tester.pumpWidget(_framed(app.wrap(
        CancelledScreen(key: UniqueKey()),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settleIo(tester);
      expect(find.text('Ausfallende Veranstaltungen'), findsOneWidget);
      expect(find.text('Deine Veranstaltungen'), findsOneWidget);
      await _shot(tester, 'cancelled_dark_de');
      await _unmount(tester);
    });

    testWidgets('the timetable marks a cancelled class', (tester) async {
      _usePhone(tester);
      final today = _day(0);
      final week = IsoWeek.fromDate(today);
      final app = await TestApp.create(
        signedIn: true,
        prefs: {
          'showWeekends': true,
          ...cacheEntry(
            CacheService.weekKey(week.key),
            [
              _eventJson('G11 Mathematik 1 (BÜ)', today, '08:00 - 09:30',
                  publishId: fakeCancelledPublishId),
              _eventJson('Physik', today, '09:45 - 11:15', publishId: '1'),
            ],
          ),
          ...cacheEntry(
            CacheService.cancelledKey(Formats.isoDate(today)),
            [
              for (final l in parseCancelledLecturesHtml(fakeCancelledHtml))
                l.toJson(),
            ],
          ),
        },
      );

      await tester.pumpWidget(_framed(app.wrap(const TimetableScreen())));
      await _settle(tester);
      expect(find.text('G11 Mathematik 1'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text('Ersatztermin: 17.11.26, 08:00-09:30, WH C403'),
        findsOneWidget,
      );
      final title = tester.widget<Text>(find.text('G11 Mathematik 1'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      expect(
        tester.widget<Text>(find.text('Physik')).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );
      await _shot(tester, 'timetable_cancelled');

      // The details say so, too.
      await tester.tap(find.text('G11 Mathematik 1'));
      await _settle(tester);
      expect(find.text('Cancelled on this day'), findsOneWidget);
      await _shot(tester, 'timetable_cancelled_sheet');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      // Week view: struck through as well.
      await tester.tap(find.byIcon(Icons.calendar_view_week_outlined));
      await _settle(tester);
      final gridTitle = tester.widget<Text>(find.text('G11 Mathematik 1'));
      expect(gridTitle.style?.decoration, TextDecoration.lineThrough);
      await _shot(tester, 'timetable_cancelled_week');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('semester dates: progress, what is next, all dates',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();

      await tester.pumpWidget(_framed(app.wrap(
        SemesterScreen(service: _semesterService()),
      )));
      await _settleIo(tester);
      expect(
        find.widgetWithText(AppBar, 'Semester dates'),
        findsOneWidget,
      );
      expect(find.text('Winter semester 2026/27'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Week \d+ of \d+$')), findsOneWidget);
      expect(find.text('33 %'), findsOneWidget);
      expect(find.text('90 days of lectures left'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('5 days left'), findsOneWidget); // deadline
      expect(find.text('Exam periods'), findsOneWidget); // legend
      await _shot(tester, 'semester_light');

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await _settle(tester);
      await _shot(tester, 'semester_light_list');
      expect(tester.takeException(), isNull);

      // German page for the German app, from the same service.
      await tester.pumpWidget(_framed(app.wrap(
        SemesterScreen(key: UniqueKey(), service: _semesterService()),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settleIo(tester);
      expect(find.text('Semestertermine'), findsOneWidget);
      expect(find.text('Wintersemester 2026/27'), findsOneWidget);
      expect(find.text('Als Nächstes'), findsOneWidget);
      await _shot(tester, 'semester_dark_de');

      // Both are cached per language.
      expect(SemesterService().cached('de').calendar, isNotNull);
      expect(SemesterService().cached('en').calendar, isNotNull);
      await _unmount(tester);
    });

    testWidgets('semester dates offline without cache offer a retry',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(
        SemesterScreen(service: SemesterService(client: offlineClient())),
      )));
      await _settleIo(tester);
      expect(
        find.text('The academic calendar could not be loaded.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('navigation settings rearrange the bar and the menu',
        (tester) async {
      _usePhone(tester, size: const Size(360, 1500));
      final app = await TestApp.create();

      await tester.pumpWidget(
        _framed(app.wrap(const NavigationSettingsScreen())),
      );
      await _settle(tester);
      expect(find.text('Navigation bar · 3/4'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('Nothing here'), findsOneWidget); // nothing hidden
      expect(find.text('Menu only'), findsNWidgets(2)); // LSF, Moodle
      await _shot(tester, 'navigation_settings');

      Future<void> moveTo(String destination, String section) async {
        final row = find.ancestor(
          of: find.text(destination),
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.more_vert_rounded),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text(section).last);
        await _settle(tester);
      }

      await moveTo('Grades', 'Navigation bar');
      expect(app.settings.navLayout.bar,
          ['timetable', 'mensa', 'transport', 'grades']);
      expect(find.text('Navigation bar · 4/4'), findsOneWidget);

      // A fifth one does not fit.
      await moveTo('Exams', 'Navigation bar');
      expect(app.settings.navLayout.bar, hasLength(4));
      expect(find.textContaining('holds up to 4'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);

      // Neither do LSF and Moodle.
      await moveTo('Moodle', 'Navigation bar');
      expect(app.settings.navLayout.bar, isNot(contains('moodle')));
      expect(find.textContaining('only be opened from the menu'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);

      await moveTo('Mensa', 'Hidden');
      expect(app.settings.navLayout.hidden, ['mensa']);
      expect(find.text('Nothing here'), findsNothing);
      await _shot(tester, 'navigation_settings_changed');

      // Dragging: pull "Transport" to the top of the bar.
      final handle = find.descendant(
        of: find.ancestor(
          of: find.text('Transport'),
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Icons.drag_handle_rounded),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await _settle(tester);
      expect(app.settings.navLayout.bar,
          ['transport', 'timetable', 'grades']);

      await tester.tap(find.text('Hide Navigation Labels'));
      await _settle(tester);
      expect(app.settings.hideLabels, isTrue);

      await tester.tap(find.byIcon(Icons.restart_alt_rounded));
      await _settle(tester);
      expect(app.settings.navLayout, NavLayout.standard);

      // The layout survives a restart.
      await app.settings
          .updateNavLayout(NavLayout.standard.move('exams', NavSection.bar));
      final reloaded = SettingsService();
      await reloaded.loadSettings();
      expect(reloaded.navLayout.bar, contains('exams'));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('the shell follows the layout', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(const MainScreen())));
      await _settle(tester);

      FloatingTabBar bar() =>
          tester.widget<FloatingTabBar>(find.byType(FloatingTabBar));
      expect(bar().items.map((i) => i.label),
          ['Timetable', 'Mensa', 'Transport', 'Menu']);

      // New destinations are in the menu by default.
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await _settle(tester);
      for (final title in ['Exams', 'Enrolments', 'Cancellations', 'Semester']) {
        await tester.scrollUntilVisible(find.text(title), 100,
            scrollable: find.byType(Scrollable).last);
        expect(find.text(title), findsOneWidget);
      }
      await _shot(tester, 'menu_new');

      // A screen that needs the account asks for it as a tab, too.
      await app.settings.updateNavLayout(
        NavLayout.standard
            .move('mensa', NavSection.hidden)
            .move('grades', NavSection.hidden)
            .move('exams', NavSection.bar, 0)
            .move('semester', NavSection.bar),
      );
      await _settle(tester);
      expect(bar().items.map((i) => i.label),
          ['Exams', 'Timetable', 'Transport', 'Semester', 'Menu']);
      expect(find.text('Grades'), findsNothing); // hidden
      expect(find.text('Mensa'), findsNothing);

      await tester.tap(find.byIcon(Icons.assignment_outlined));
      await _settle(tester);
      expect(AppEvents.currentTab.value, AppTab.exams);
      expect(find.text('Sign-in required'), findsOneWidget);
      await _shot(tester, 'exams_tab_signed_out');

      // Moving the open tab out of the bar falls back to the menu.
      await app.settings.updateNavLayout(NavLayout.standard);
      await _settle(tester);
      expect(AppEvents.currentTab.value, AppTab.more);

      // A widget tap opens its destination: a tab if there is one …
      AppEvents.requestOpen('timetable');
      await _settle(tester);
      expect(AppEvents.currentTab.value, AppTab.timetable);
      // … else as a page.
      AppEvents.requestOpen('semester');
      await _settle(tester);
      expect(find.byType(SemesterScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      await _unmount(tester);
    });

    testWidgets('widgets page lists every widget', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(const WidgetsScreen())));
      await _settle(tester);
      expect(find.text('Home screen widgets'), findsOneWidget);
      for (final title in ['Next class', 'Classes of the day', 'Mensa',
          'Semester']) {
        expect(find.text(title), findsOneWidget);
      }
      // No launcher in tests: the manual way is explained.
      expect(find.textContaining('Long-press'), findsOneWidget);
      await _shot(tester, 'widgets_screen');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });
}
