import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uniwe/main.dart';
import 'package:uniwe/models/mensa_meal.dart';
import 'package:uniwe/models/timetable_event.dart';
import 'package:uniwe/models/transport_arrival.dart';
import 'package:uniwe/services/auth_service.dart';
import 'package:uniwe/services/log_service.dart';
import 'package:uniwe/services/lsf_scraper_service.dart';
import 'package:uniwe/services/settings_service.dart';
import 'package:uniwe/utils/iso_week.dart';

void main() {
  testWidgets('UniweApp foundational smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.loadSettings();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LogService()),
          ChangeNotifierProvider.value(value: settings),
          ProxyProvider<LogService, LsfScraperService>(
            update: (_, logger, prev) => prev ?? LsfScraperService(logger),
            dispose: (_, scraper) => scraper.dispose(),
          ),
          ChangeNotifierProxyProvider2<LsfScraperService, LogService, AuthService>(
            create: (context) => AuthService(
              context.read<LsfScraperService>(),
              context.read<LogService>(),
            ),
            update: (_, scraper, logger, auth) =>
                auth ?? AuthService(scraper, logger),
          ),
        ],
        child: const UniweApp(),
      ),
    );

    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  group('IsoWeek tests', () {
    test('next and previous preserve equality and week numbers across months and DST', () {
      final w = IsoWeek.fromDate(DateTime(2026, 3, 25)); // Week before Europe DST transition
      final nextWeek = w.next;
      final backToW = nextWeek.previous;

      expect(backToW, equals(w));
      expect(backToW.hashCode, equals(w.hashCode));
      expect(nextWeek.weekNumber, equals(w.weekNumber + 1));
    });

    test('ISO week boundary at year end / start', () {
      final dec31 = IsoWeek.fromDate(DateTime(2026, 12, 31));
      expect(dec31.weekNumber, equals(53));
      expect(dec31.year, equals(2026));
      expect(dec31.next.weekNumber, equals(1));
      expect(dec31.next.year, equals(2027));
    });
  });

  group('Model serialization tests', () {
    test('MensaMeal diet detection and JSON round-trip', () {
      final veganMeal = MensaMeal.fromJson({
        'id': 1,
        'name': 'Tofu Curry',
        'notes': ['Vegan', 'glutenfrei'],
        'prices': {'students': 2.50, 'employees': 4.20},
        'category': 'Essen',
      });
      expect(veganMeal.isVegan, isTrue);
      expect(veganMeal.isVegetarian, isFalse);

      final roundTrip = MensaMeal.fromJson(veganMeal.toJson());
      expect(roundTrip.name, equals('Tofu Curry'));
      expect(roundTrip.prices['students'], equals(2.50));
    });

    test('TransportArrival handles malformed timestamps gracefully', () {
      final arrival = TransportArrival.fromJson({
        'line': {'name': 'M17'},
        'when': 'invalid-date',
        'plannedWhen': '2026-11-09T12:00:00+01:00',
        'delay': 120,
        'origin': {'name': 'S Schöneweide'},
        'direction': 'Falkenberg',
      });
      expect(arrival.lineName, equals('M17'));
      expect(arrival.when, isNull);
      expect(arrival.plannedWhen, isNotNull);
    });

    test('TimetableEvent JSON round-trip', () {
      final event = TimetableEvent(
        title: 'Mathematik 1',
        day: 'Montag',
        time: '08:00 - 09:30',
        room: 'WH C 345',
        type: 'Vorlesung',
        frequency: 'wöch',
        publishId: '12345',
        isExam: false,
        isOverlapping: true,
      );
      final restored = TimetableEvent.fromJson(event.toJson());
      expect(restored.title, equals('Mathematik 1'));
      expect(restored.publishId, equals('12345'));
      expect(restored.isOverlapping, isTrue);
    });
  });
}
