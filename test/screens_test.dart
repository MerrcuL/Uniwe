import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniwe/app_events.dart';
import 'package:uniwe/screens/about_screen.dart';
import 'package:uniwe/screens/certificates_screen.dart';
import 'package:uniwe/screens/grades_screen.dart';
import 'package:uniwe/screens/log_screen.dart';
import 'package:uniwe/screens/login_screen.dart';
import 'package:uniwe/screens/main_screen.dart';
import 'package:uniwe/screens/mensa_screen.dart';
import 'package:uniwe/screens/mensa_settings_screen.dart';
import 'package:uniwe/screens/more_screen.dart';
import 'package:uniwe/screens/settings_screen.dart';
import 'package:uniwe/screens/timetable_screen.dart';
import 'package:uniwe/screens/transport_screen.dart';
import 'package:uniwe/services/cache_service.dart';
import 'package:uniwe/services/mensa_service.dart';
import 'package:uniwe/services/transport_service.dart';
import 'package:uniwe/utils/formats.dart';
import 'package:uniwe/utils/iso_week.dart';
import 'package:uniwe/widgets/expressive.dart';
import 'package:uniwe/widgets/floating_tab_bar.dart';
import 'package:uniwe/models/timetable_event.dart';
import 'package:uniwe/widgets/timetable/event_card.dart';
import 'package:uniwe/widgets/timetable/event_details_sheet.dart';
import 'package:uniwe/widgets/timetable/week_grid.dart';

import 'support/fake_lsf.dart';
import 'support/fakes.dart';

// Widget tests that pump every screen with realistic data on a small phone,
// in both languages and themes. Any layout overflow or build exception fails
// the test. Set UNIWE_SCREENSHOTS=<dir> to also write PNGs of each state.

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
      loader.addFont(
        file.readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
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

/// Lets futures, fake timers and short animations run.
Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Map<String, Object?> _event(
  String title,
  String day,
  String time, {
  String room = 'WH C 345',
  String type = 'Vorlesung',
  String frequency = 'wöch',
  bool exam = false,
  bool overlapping = false,
}) =>
    {
      'title': title,
      'day': day,
      'time': time,
      'room': room,
      'type': type,
      'frequency': frequency,
      'publishId': null,
      'isExam': exam,
      'isOverlapping': overlapping,
    };

List<Map<String, Object?>> _weekEvents() {
  const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];
  return [
    for (final day in days) ...[
      _event('Mathematik für Ingenieure 2 (B21.1)', day, '08:00 - 09:30'),
      _event('Programmierung 2', day, '09:45 - 11:15',
          type: 'Übung', room: 'WH C 624', frequency: '14-täg'),
      _event('Datenbanken und verteilte Systeme', day, '12:15 - 13:45',
          type: 'Seminaristischer Lehrvortrag', overlapping: true),
      _event('Technisches Englisch', day, '13:00 - 14:30',
          room: 'WH A 012', overlapping: true),
      _event('Physik Klausur', day, '15:45 - 17:15',
          room: 'WH G 001', frequency: 'Einzelt.', exam: true),
      _event('Kurzer Termin', day, '17:30 - 17:45', room: 'WH B 1'),
    ],
  ];
}

DateTime get _shownDay => Dates.skipWeekend(Dates.today(), showWeekends: false);

Map<String, Object> _timetableCache() => cacheEntry(
      CacheService.weekKey(IsoWeek.fromDate(_shownDay).key),
      _weekEvents(),
      // Old enough that the store asks LSF again instead of trusting it.
      at: DateTime.now().subtract(const Duration(hours: 2)),
    );

MensaService _mensaService() {
  final today = DateTime.now();
  final days = [
    for (var i = 0; i < 8; i++)
      Formats.isoDate(DateTime(today.year, today.month, today.day + i)),
  ];
  return MensaService(
    client: jsonClient((request) {
      if (request.url.path.endsWith('/days')) {
        return [
          for (final d in days) {'date': d, 'closed': false},
        ];
      }
      return [
        {
          'id': 1,
          'name': 'Kichererbsen-Curry mit Basmatireis und frischem Koriander',
          'category': 'Essen',
          'prices': {'students': 2.45, 'employees': 4.9, 'others': 5.85},
          'notes': [
            'Vegan',
            'Allergens: 27 Sellerie',
            'Allergens: 29 Senf',
            'Allergens: 28 Soja',
            'Grüner Ampelpunkt: Die beste Wahl',
            'Der Wasserverbrauch für dieses Gericht liegt unter dem Durchschnitt',
          ],
        },
        {
          'id': 2,
          'name': 'Hähnchenschnitzel mit Paprikasauce',
          'category': 'Essen',
          'prices': {'students': 3.2, 'employees': 5.5, 'others': 6.4},
          'notes': ['Allergens: 21a Weizen', 'Allergens: 23 Eier', 'Additives: 9 Phosphat'],
        },
        {
          'id': 3,
          'name': 'Tomatensuppe',
          'category': 'Suppen',
          'prices': {'students': 0.75, 'employees': 1.5, 'others': 1.8},
          'notes': ['ovo-lacto-vegetabil'],
        },
        {
          'id': 4,
          'name': 'Schokoladenpudding',
          'category': 'Dessert',
          'prices': {'students': 0.9},
          'notes': ['Milch und Milchprodukte'],
        },
        {
          'id': 5,
          'name': 'Hausgemachte Limonade',
          'category': 'Getränke',
          'prices': <String, double>{},
          'notes': <String>[],
        },
      ];
    }),
  );
}

TransportService _transportService() {
  final now = DateTime.now();
  Map<String, Object?> departure(
    String trip,
    String line,
    String direction,
    int inMinutes, {
    int delay = 0,
    bool cancelled = false,
  }) {
    final planned = now.add(Duration(minutes: inMinutes));
    return {
      'tripId': trip,
      'line': {'name': line},
      'direction': direction,
      'plannedWhen': planned.toIso8601String(),
      'when': cancelled
          ? null
          : planned.add(Duration(minutes: delay)).toIso8601String(),
      'delay': delay * 60,
      'cancelled': cancelled,
    };
  }

  return TransportService(
    client: jsonClient((request) {
      if (request.url.path.endsWith('/arrivals')) {
        return {
          'arrivals': [
            {
              'tripId': 't1',
              'origin': {'name': 'Firlstr.'},
            },
          ],
        };
      }
      return {
        'departures': [
          departure('gone', '27', 'Krankenhaus Köpenick', -5),
          departure('t1', '27', 'Krankenhaus Köpenick', 0),
          departure('t2', 'M17', 'S Schöneweide', 3, delay: 1),
          departure('t3', '67', 'S Schöneweide/Sterndamm', 9, delay: 7),
          departure('t4', '63', 'Mahlsdorf-Süd', 12, cancelled: true),
          departure('t5', '60', 'Johannisthal, Haeckelstr.', 21),
          departure('bus', 'X11', 'Dahlem', 2),
        ],
      };
    }),
  );
}

void main() {
  setUpAll(_loadFonts);

  setUp(() => AppEvents.currentTab.value = AppTab.timetable);

  group('Timetable', () {
    testWidgets('day view shows cached classes offline and pages by day/week',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create(prefs: _timetableCache(), signedIn: true);
      await tester.pumpWidget(_framed(app.wrap(const TimetableScreen())));
      await _settle(tester);

      expect(find.byType(EventCard), findsWidgets);
      expect(find.text('Mathematik für Ingenieure 2'), findsOneWidget);
      // English locale translates LSF's German vocabulary.
      expect(find.text('Lecture'), findsWidgets);
      // The refresh failed (no network): cached data plus a notice.
      expect(find.textContaining('Offline.'), findsOneWidget);
      await _shot(tester, 'timetable_day_light');

      // Swipe to the next day and back.
      final before = _shownDay;
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await _settle(tester);

      // Next week via the header, then back to today.
      await tester.tap(find.byTooltip('Next week'));
      await _settle(tester);
      final nextWeek = IsoWeek.fromDate(before).next;
      expect(find.textContaining('Week ${nextWeek.weekNumber}'), findsOneWidget);
      await tester.tap(find.byTooltip('Go to today').first);
      await _settle(tester);
      expect(
        find.textContaining('Week ${IsoWeek.fromDate(before).weekNumber}'),
        findsOneWidget,
      );

      // Event details open immediately.
      await tester.tap(find.byType(EventCard).first);
      await _settle(tester);
      expect(find.text('Mathematik für Ingenieure 2'), findsNWidgets(2));
      await _shot(tester, 'timetable_details_light');
      await tester.tapAt(const Offset(180, 40));
      await _settle(tester);

      // Switch to the week grid.
      await tester.tap(find.byTooltip('Week view'));
      await _settle(tester);
      expect(find.byType(WeekGrid), findsOneWidget);
      expect(app.settings.timetableIsWeekView, isTrue);
      await _shot(tester, 'timetable_week_light');

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('week grid, weekends, compact cards, dark theme, German',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create(
        prefs: {
          ..._timetableCache(),
          'timetableIsWeekView': true,
          'showWeekends': true,
          'compactTimetableView': true,
        },
        signedIn: true,
      );
      await tester.pumpWidget(_framed(app.wrap(
        const TimetableScreen(),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settle(tester);
      expect(find.byType(WeekGrid), findsOneWidget);
      await _shot(tester, 'timetable_week_dark_de');

      // Swipe to the next week and back.
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await _settle(tester);
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await _settle(tester);

      await tester.tap(find.byTooltip('Tagesansicht'));
      await _settle(tester);
      expect(find.byType(DayPill), findsNWidgets(7));
      await _shot(tester, 'timetable_day_compact_dark_de');

      // Changing the weekend setting re-creates the pager without errors.
      await app.settings.updateShowWeekends(false);
      await _settle(tester);
      expect(find.byType(DayPill), findsNWidgets(5));

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('signed out shows the login prompt; no cache shows retry',
        (tester) async {
      _usePhone(tester);
      var app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(const TimetableScreen())));
      await _settle(tester);
      expect(find.text('Timetable unavailable'), findsOneWidget);
      await _shot(tester, 'timetable_signed_out');

      await tester.tap(find.text('Sign in'));
      await _settle(tester);
      expect(find.text('HTW LSF Login'), findsOneWidget);
      await _shot(tester, 'login_sheet');
      // Empty form is rejected locally.
      await tester.tap(find.text('Log in'));
      await _settle(tester);
      expect(find.text('Please fill in all fields'), findsOneWidget);
      await _unmount(tester);

      app = await TestApp.create(signedIn: true);
      await tester.pumpWidget(_framed(app.wrap(const TimetableScreen())));
      await _settle(tester, 20);
      expect(find.text('Retry'), findsOneWidget);
      await _shot(tester, 'timetable_error');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('fits a very small screen with large text', (tester) async {
      _usePhone(tester, size: const Size(320, 480));
      final app = await TestApp.create(prefs: _timetableCache(), signedIn: true);
      await tester.pumpWidget(_framed(MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: const TextScaler.linear(1.6)),
        child: app.wrap(const TimetableScreen()),
      )));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Week view'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('Mensa', () {
    testWidgets('shows the menu grouped by category', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(
          _framed(app.wrap(MensaScreen(service: _mensaService()))));
      await _settle(tester);

      expect(find.text('Main Dishes'), findsOneWidget);
      expect(find.text('Soups'), findsOneWidget);
      // Once as a filter chip, once as the tag on the dish.
      expect(find.text('Vegan'), findsNWidgets(2));
      expect(find.text('Vegetarian'), findsNWidgets(2));
      expect(find.text('€2.45'), findsOneWidget);
      // Unknown API categories are kept, after the known ones.
      final menu = find.descendant(
        of: find.byType(PageView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(find.text('Getränke'), 200,
          scrollable: menu.last);
      await tester.scrollUntilVisible(find.text('Main Dishes'), -200,
          scrollable: menu.last);
      await _settle(tester);
      await _shot(tester, 'mensa_light');

      // Diet filters: vegan only, then vegan or meat, then vegetarian.
      expect(find.text('Mensa WH'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
      await _settle(tester);
      expect(find.textContaining('Kichererbsen'), findsOneWidget);
      expect(find.textContaining('Hähnchenschnitzel'), findsNothing);
      expect(find.text('Tomatensuppe'), findsNothing);
      expect(app.settings.mensaDietFilters, {'vegan'});
      await _shot(tester, 'mensa_filter_vegan');
      await tester.tap(find.widgetWithText(FilterChip, 'Meat'));
      await _settle(tester);
      expect(find.textContaining('Hähnchenschnitzel'), findsOneWidget);
      expect(find.text('Tomatensuppe'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
      await tester.tap(find.widgetWithText(FilterChip, 'Meat'));
      await tester.tap(find.widgetWithText(FilterChip, 'Vegetarian'));
      await _settle(tester);
      // Vegan dishes count as vegetarian too.
      expect(find.textContaining('Kichererbsen'), findsOneWidget);
      expect(find.text('Tomatensuppe'), findsOneWidget);
      expect(find.textContaining('Hähnchenschnitzel'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Vegetarian'));
      await _settle(tester);
      expect(find.textContaining('Hähnchenschnitzel'), findsOneWidget);

      // Staff prices via settings.
      await app.settings.updateMensaPriceCategory('employees');
      await _settle(tester);
      expect(find.text('€4.90'), findsOneWidget);

      // Details sheet.
      await tester.tap(find.textContaining('Kichererbsen'));
      await _settle(tester);
      expect(find.text('Labels & allergens'), findsOneWidget);
      // Only real allergens/additives are labels; rating texts are not.
      expect(find.text('Sellerie'), findsWidgets);
      expect(find.textContaining('Ampelpunkt'), findsNothing);
      expect(find.textContaining('Wasserverbrauch'), findsNothing);
      await _shot(tester, 'mensa_details');
      await tester.tapAt(const Offset(180, 40));
      await _settle(tester);

      // Next day by tapping its chip, then by swiping.
      await tester.tap(find.byType(DayPill).at(1));
      await _settle(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await _settle(tester);
      expect(find.text('Main Dishes'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('compact, dark, German; campus switch reloads', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create(prefs: {'compactMensaView': true});
      // The old Mensa-only switch carries over into the single setting.
      expect(app.settings.compactView, isTrue);
      await tester.pumpWidget(_framed(app.wrap(
        MensaScreen(service: _mensaService()),
        brightness: Brightness.dark,
        locale: const Locale('de'),
      )));
      await _settle(tester);
      expect(find.text('Hauptgerichte'), findsOneWidget);
      expect(find.text('2,45 €'), findsOneWidget);
      expect(find.text('Mensa WH'), findsOneWidget);
      // Compact cards: dish, price, diet tag and allergen numbers only.
      expect(find.text('21a · 23 · 9'), findsOneWidget);
      expect(find.text('Weizen'), findsNothing);
      expect(find.text('Vegetarisch'), findsNWidgets(2));
      await _shot(tester, 'mensa_compact_dark_de');

      await app.settings.updateCampus('TA');
      await _settle(tester);
      expect(find.text('Mensa TA'), findsOneWidget);
      expect(find.text('Hauptgerichte'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('offline without cache offers a retry instead of spinning',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(
        MensaScreen(service: MensaService(client: offlineClient())),
      )));
      await _settle(tester);
      expect(find.text('The menu could not be loaded.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await _shot(tester, 'mensa_error');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('Transport', () {
    testWidgets('groups upcoming departures and hides departed ones',
        (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      AppEvents.currentTab.value = AppTab.transport;
      await tester.pumpWidget(
          _framed(app.wrap(TransportScreen(service: _transportService()))));
      await _settle(tester);

      expect(find.text('S Schöneweide'), findsWidgets);
      expect(find.text('S Köpenick'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('+7 min'), findsOneWidget);
      // Bus lines are filtered out, as before.
      expect(find.text('X11'), findsNothing);
      await _shot(tester, 'transport_light');

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('network failure shows an error with retry', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      AppEvents.currentTab.value = AppTab.transport;
      await tester.pumpWidget(_framed(app.wrap(
        TransportScreen(service: TransportService(client: offlineClient())),
        brightness: Brightness.dark,
      )));
      await _settle(tester);
      expect(find.text('Departures could not be loaded.'), findsOneWidget);
      await _shot(tester, 'transport_error_dark');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('Settings', () {
    testWidgets('all controls work and persist', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create(signedIn: true);
      await tester.pumpWidget(_framed(app.wrap(const SettingsScreen())));
      await _settle(tester);
      expect(find.text('s0123456'), findsOneWidget);
      await _shot(tester, 'settings_light');

      await tester.tap(find.text('TGS'));
      await _settle(tester);
      expect(app.settings.campus, 'TGS');
      expect(find.textContaining('TGS campus only affects'), findsOneWidget);

      await tester.tap(find.text('Show Weekends'));
      await _settle(tester);
      expect(app.settings.showWeekends, isTrue);

      // One compact switch for timetable and Mensa.
      await tester.scrollUntilVisible(find.text('Compact View'), 200);
      await tester.tap(find.text('Compact View'));
      await _settle(tester);
      expect(app.settings.compactView, isTrue);

      await tester.scrollUntilVisible(find.text('Dark'), 200);
      await tester.tap(find.text('Dark'));
      await _settle(tester);
      expect(app.settings.themeMode, ThemeMode.dark);

      await tester.scrollUntilVisible(find.text('About'), 200);
      await _settle(tester);
      await _shot(tester, 'settings_bottom_light');

      // Logging out asks first, then clears the session.
      await tester.scrollUntilVisible(find.text('Log out'), -300);
      await _settle(tester);
      await tester.tap(find.text('Log out'));
      await _settle(tester);
      expect(find.text('Log out?'), findsOneWidget);
      await _shot(tester, 'logout_dialog');
      await tester.tap(find.widgetWithText(FilledButton, 'Log out').last);
      await _settle(tester);
      expect(app.auth.isAuthenticated, isFalse);
      expect(find.text('Log in'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('sub-screens render in dark German', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      for (final (name, screen) in <(String, Widget)>[
        ('settings_dark_de', const SettingsScreen()),
        ('menu_dark_de', const MoreScreen()),
        ('mensa_settings_dark_de', const MensaSettingsScreen()),
        ('about_dark_de', const AboutScreen()),
        ('logs_dark_de', const LogScreen()),
      ]) {
        app.logger.warning('Beispielwarnung', 'Details');
        await tester.pumpWidget(_framed(app.wrap(
          screen,
          brightness: Brightness.dark,
          locale: const Locale('de'),
        )));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: name);
        await _shot(tester, name);
      }
      await _unmount(tester);
    });

    testWidgets('grades, distribution sheet and certificates from LSF',
        (tester) async {
      _usePhone(tester);
      final lsf = FakeLsf();
      final app = await TestApp.create(signedIn: true, lsfClient: lsf.client);

      // Parsing runs on background isolates: give them real time.
      Future<void> settleIo() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump();
        }
        await _settle(tester);
        expect(tester.takeException(), isNull);
      }

      Future<void> load(Widget screen, {bool dark = false}) async {
        await tester.pumpWidget(_framed(app.wrap(
          screen,
          brightness: dark ? Brightness.dark : Brightness.light,
          locale: dark ? const Locale('de') : const Locale('en'),
        )));
        await settleIo();
      }

      await load(const GradesScreen());
      expect(find.text('Angewandte Informatik · Bachelor'), findsOneWidget);
      expect(find.text('1,9'), findsOneWidget); // LSF's average
      expect(find.text('25'), findsOneWidget); // credits
      expect(find.text('SoSe 26'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Free attempt'), findsOneWidget);
      expect(find.textContaining('6 ECTS'), findsWidgets);
      expect(find.text('Mustermann'), findsNothing);
      await _shot(tester, 'grades_light');

      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await _settle(tester);
      expect(find.text('Module groups'), findsOneWidget);
      expect(find.text('1,65'), findsOneWidget);
      expect(find.text('Transcripts and certificates'), findsOneWidget);
      await _shot(tester, 'grades_light_bottom');

      // The details sheet loads the distribution of the exam.
      await load(GradesScreen(key: UniqueKey()));
      await tester.tap(find.text('Mathematik 1'));
      await settleIo();
      expect(find.text('Grade distribution'), findsOneWidget);
      expect(find.text('40 participants'), findsOneWidget);
      expect(find.text('Class average'), findsOneWidget);
      expect(find.text('2,6'), findsOneWidget);
      expect(find.text('Very good'), findsOneWidget);
      expect(lsf.requests.last.queryParameters['struct'], 'abschluss');
      await _shot(tester, 'grades_distribution');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      await load(GradesScreen(key: UniqueKey()), dark: true);
      expect(find.text('Nicht bestanden'), findsOneWidget);
      expect(find.text('Freiversuch'), findsOneWidget);
      await _shot(tester, 'grades_dark_de');
      await tester.tap(find.text('Mathematik 1'));
      await settleIo();
      expect(find.text('Notenspiegel'), findsOneWidget);
      expect(find.text('Durchschnitt aller'), findsOneWidget);
      await _shot(tester, 'grades_distribution_dark_de');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      await load(const CertificatesScreen());
      expect(find.text('Certificate of enrolment'), findsNWidgets(2));
      expect(find.text('English'), findsOneWidget);
      await _shot(tester, 'certificates_light');

      // Opening a document downloads it with the session token. (The hand-off
      // to a PDF viewer has no platform side in tests and reports failure.)
      final english = find.text('Certificate of enrolment').last;
      await tester.ensureVisible(english);
      await tester.tap(english);
      await settleIo();
      final request = lsf.requests.last;
      expect(request.queryParameters['moduleCall'], 'immabescheinigung_en');
      expect(request.queryParameters['asi'], fakeAsi);
      expect(find.text('The document could not be downloaded.'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await _settle(tester);
      expect(find.text('Records of achievement'), findsOneWidget);
      expect(find.text('WS 25/26'), findsOneWidget);
      await _shot(tester, 'certificates_light_bottom');
      await _unmount(tester);
    });

    testWidgets('login sheet reports rejected credentials', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showLoginDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 's0000001');
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.tap(find.text('Log in'));
      await _settle(tester);
      // The offline client makes this a network error, not "wrong password".
      expect(find.text('Network error. Please try again.'), findsOneWidget);
      expect(app.auth.isAuthenticated, isFalse);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('Navigation shell', () {
    testWidgets('builds tabs lazily and keeps their state', (tester) async {
      _usePhone(tester);
      final app = await TestApp.create();
      await tester.pumpWidget(_framed(app.wrap(const MainScreen())));
      await _settle(tester);

      // Only the first tab exists until another one is opened.
      expect(find.byType(TimetableScreen), findsOneWidget);
      expect(find.byType(MensaScreen, skipOffstage: false), findsNothing);
      expect(find.byType(MoreScreen, skipOffstage: false), findsNothing);
      expect(find.byType(FloatingTabBar), findsOneWidget);
      await _shot(tester, 'shell_light');

      // Scrubbing: press the bar on the first tab, slide to the second and
      // release — that opens it without lifting the finger in between.
      final bar = tester.getRect(find.byType(FloatingTabBar));
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * 0.1, bar.bottom - 40),
      );
      await tester.pump(const Duration(milliseconds: 50));
      for (final fraction in [0.15, 0.2, 0.25, 0.3]) {
        await gesture.moveTo(
          Offset(bar.left + bar.width * fraction, bar.bottom - 40),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Nothing switches until the finger is lifted.
      expect(AppEvents.currentTab.value, AppTab.timetable);
      await gesture.up();
      await _settle(tester);
      expect(AppEvents.currentTab.value, AppTab.mensa);
      await _shot(tester, 'shell_mensa_tab');
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await _settle(tester);
      expect(AppEvents.currentTab.value, AppTab.timetable);

      // The last destination is the menu: LSF, planned features, settings.
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await _settle(tester);
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(AppEvents.currentTab.value, AppTab.more);
      expect(find.text('LSF'), findsOneWidget);
      expect(find.text('Moodle'), findsOneWidget);
      expect(find.text('Grades'), findsOneWidget);
      expect(find.text('Certificates'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      await _shot(tester, 'menu_light');

      // Turning animations off must not rebuild (and reset) the tabs.
      final timetableState =
          tester.state(find.byType(TimetableScreen, skipOffstage: false));
      await app.settings.updateAnimationsEnabled(false);
      await _settle(tester);
      expect(
        tester.state(find.byType(TimetableScreen, skipOffstage: false)),
        same(timetableState),
      );

      // Settings open from the bottom of the menu and return to it.
      await tester.tap(find.text('Settings').last);
      await _settle(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      expect(find.byType(SettingsScreen), findsNothing);

      // E-mail can move from the bar into the menu, below LSF.
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
      await app.settings.updateEmailInNavBar(false);
      await _settle(tester);
      expect(find.byIcon(Icons.email_outlined), findsNothing);
      expect(find.text('HTW web mail'), findsOneWidget);
      expect(AppEvents.currentTab.value, AppTab.more);
      await tester.tap(find.text('HTW web mail'));
      await _settle(tester);
      expect(find.text('Webmail'), findsOneWidget); // signed-out prompt
      await tester.tap(find.byIcon(Icons.close_rounded));
      await _settle(tester);
      await app.settings.updateEmailInNavBar(true);
      await _settle(tester);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);

      // LSF needs a session: signed out, it asks to sign in first.
      await tester.tap(find.text('LSF'));
      await _settle(tester);
      expect(find.text('HTW LSF Login'), findsOneWidget);
      await tester.tapAt(const Offset(180, 40));
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.email_outlined));
      await _settle(tester);
      expect(find.text('Webmail'), findsOneWidget);

      // Let the delayed update check finish.
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('uses a navigation rail on wide windows', (tester) async {
      _usePhone(tester, size: const Size(900, 600));
      final app = await TestApp.create(prefs: _timetableCache(), signedIn: true);
      await tester.pumpWidget(_framed(app.wrap(const MainScreen())));
      await _settle(tester);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingTabBar), findsNothing);
      await _shot(tester, 'shell_tablet');
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets(
        'subject details lecturer field is clickable and opens professor details',
        (tester) async {
      _usePhone(tester);
      final lsf = FakeLsf();
      final app = await TestApp.create(signedIn: true, lsfClient: lsf.client);

      Future<void> settleIo() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump();
        }
        await _settle(tester);
        expect(tester.takeException(), isNull);
      }

      final event = TimetableEvent(
        title: 'Social Engineering',
        day: 'Dienstag',
        time: '14:00 - 15:30',
        room: 'TGS Haus 1a/b 416',
        type: 'Vorlesung',
        frequency: 'wöch',
        publishId: '234779',
      );

      await tester.pumpWidget(_framed(app.wrap(
        Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showEventDetails(context, event),
                child: const Text('Open Event'),
              ),
            ),
          );
        }),
      )));
      await _settle(tester);

      await tester.tap(find.text('Open Event'));
      await settleIo();

      expect(find.text('Social Engineering'), findsOneWidget);
      expect(find.text('TGS Haus 1a/b 416'), findsOneWidget);
      expect(find.text('Prof. Dr. Debora Weber-Wulff'), findsOneWidget);

      await tester.tap(find.text('Prof. Dr. Debora Weber-Wulff'));
      await settleIo();

      expect(find.text('Debora.Weber-Wulff@HTW-Berlin.de'), findsOneWidget);
      expect(find.text('Wilhelminenhofstraße 75A, 12459 Berlin'), findsOneWidget);
      expect(find.text('Lehrperson'), findsOneWidget);
      expect(find.text('Fachbereich 4'), findsOneWidget);
      expect(find.text('Open in LSF'), findsWidgets);

      await _shot(tester, 'professor_details_sheet');

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });
}
