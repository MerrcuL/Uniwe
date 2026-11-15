import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../app_events.dart';
import '../models/cancelled_lecture.dart';
import '../models/mensa_category.dart';
import '../models/mensa_meal.dart';
import '../models/registered_exam.dart';
import '../models/semester_calendar.dart';
import '../models/timetable_event.dart';
import '../navigation/nav_layout.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import 'auth_service.dart';
import 'cache_service.dart';
import 'mensa_service.dart';
import 'semester_service.dart';
import 'settings_service.dart';

/// A home screen widget of the app.
enum HomeWidgetKind {
  nextClass('NextClassWidget', NavIds.timetable),
  today('TodayWidget', NavIds.timetable),
  mensa('MensaWidget', NavIds.mensa),
  semester('SemesterWidget', NavIds.semester);

  const HomeWidgetKind(this.className, this.destination);

  /// The Android receiver class (in the app's package).
  final String className;

  /// What a tap on the widget opens.
  final String destination;
}

/// Builds the data the home screen widgets show.
///
/// Widgets cannot run the app's code: they are drawn by a small piece of
/// native code from a handful of JSON strings this service leaves for them
/// (see `android/.../widgets`). Everything here comes from the caches, so a
/// sync is cheap and never needs the session; it runs whenever one of the
/// sources is refreshed.
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  static const String _androidPackage = 'org.mercul.uniwe.widgets';

  /// How many days of the timetable the widgets get.
  static const int timetableDays = 14;

  SettingsService? _settings;
  AuthService? _auth;
  CacheService _cache = CacheService.instance;
  MensaService? _mensa;
  SemesterService? _semester;

  Timer? _debounce;
  bool _listening = false;
  bool _wasAuthenticated = false;
  String? _lastSignature;

  /// Home screen widgets only exist on Android. (The real platform, not
  /// the one widget tests pretend to run on.)
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Connects the service to the app's state. Until then [sync] does
  /// nothing, which is also what keeps it quiet in widget tests.
  void configure({
    required SettingsService settings,
    required AuthService auth,
    CacheService? cache,
  }) {
    _settings?.removeListener(_onSettingsChanged);
    _auth?.removeListener(_onAuthChanged);
    _settings = settings;
    _auth = auth;
    _cache = cache ?? CacheService.instance;
    _wasAuthenticated = auth.isAuthenticated;
    settings.addListener(_onSettingsChanged);
    auth.addListener(_onAuthChanged);
    sync();
  }

  void _onSettingsChanged() {
    final s = _settings!;
    final signature =
        '${s.locale.languageCode}|${s.canteenId}|${s.mensaPriceCategory}|${s.mensaDietFilters.join(',')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    sync();
  }

  void _onAuthChanged() {
    final isAuthenticated = _auth!.isAuthenticated;
    if (isAuthenticated == _wasAuthenticated) return;
    _wasAuthenticated = isAuthenticated;
    sync();
  }

  /// Rebuilds the widget data soon. Calls in quick succession (a refresh
  /// usually updates several sources) end up as one update.
  Future<void> sync() async {
    if (_settings == null || !isSupported) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_syncNow());
    });
  }

  Future<void> _syncNow() async {
    final settings = _settings;
    final auth = _auth;
    if (settings == null || auth == null) return;
    try {
      final language = settings.locale.languageCode;
      final signedIn = auth.isAuthenticated;
      final today = Dates.today();

      await HomeWidget.saveWidgetData<String>('locale', language);
      await HomeWidget.saveWidgetData<String>(
        'timetable',
        jsonEncode(buildTimetable(today, signedIn: signedIn, cache: _cache)),
      );
      await HomeWidget.saveWidgetData<String>(
        'exams',
        jsonEncode(signedIn ? buildExams(today, cache: _cache) : const []),
      );
      await HomeWidget.saveWidgetData<String>(
        'mensa',
        jsonEncode(await _mensaPayload(settings, today, language)),
      );
      await HomeWidget.saveWidgetData<String>(
        'semester',
        jsonEncode(await _semesterPayload(today, language)),
      );
      for (final kind in HomeWidgetKind.values) {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: '$_androidPackage.${kind.className}',
        );
      }
    } catch (e) {
      // No widget host (tests, other platforms): nothing to update.
      log('HomeWidgetService: sync failed: $e');
    }
  }

  // ── Payloads ──────────────────────────────────────────────────────────────

  /// The classes of the next [timetableDays] days, from the cached weeks.
  /// `until` is the last day the cache covers, so the widget can tell "no
  /// classes" from "not loaded".
  @visibleForTesting
  static Map<String, Object?> buildTimetable(
    DateTime today, {
    required bool signedIn,
    CacheService? cache,
  }) {
    final store = cache ?? CacheService.instance;
    final days = <Map<String, Object?>>[];
    String? until;
    if (signedIn) {
      for (var offset = 0; offset < timetableDays; offset++) {
        final date = DateTime(today.year, today.month, today.day + offset);
        final week = store
            .read(CacheService.weekKey(IsoWeek.fromDate(date).key))
            .data;
        // Weeks are contiguous: stop at the first one that is missing.
        if (week is! List) break;
        until = Formats.isoDate(date);

        final cancelledRaw =
            store.read(CacheService.cancelledKey(Formats.isoDate(date))).data;
        final cancelled = <CancelledLecture>[];
        if (cancelledRaw is List) {
          try {
            for (final c in cancelledRaw) {
              cancelled.add(CancelledLecture.fromJson(
                  Map<String, dynamic>.from(c as Map)));
            }
          } catch (_) {
            cancelled.clear();
          }
        }

        final events = <TimetableEvent>[];
        try {
          for (final e in week) {
            final event =
                TimetableEvent.fromJson(Map<String, dynamic>.from(e as Map));
            if (event.dayIndex == date.weekday - 1 && event.hasTimeRange) {
              events.add(event);
            }
          }
        } catch (_) {
          events.clear();
        }
        if (events.isEmpty) continue;
        events.sort(
          (a, b) => (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0),
        );
        days.add({
          'date': Formats.isoDate(date),
          'events': [
            for (final e in events)
              {
                'title': e.cleanTitle,
                'start': e.startMinutes,
                'end': e.endMinutes,
                'room': e.room,
                'exam': e.isExam,
                'cancelled': cancelled.any((c) => c.matches(e)),
              },
          ],
        });
      }
    }
    return {'signedIn': signedIn, 'until': until, 'days': days};
  }

  /// Registered exams with a date that is still ahead, soonest first.
  @visibleForTesting
  static List<Map<String, Object?>> buildExams(
    DateTime today, {
    CacheService? cache,
  }) {
    final data =
        (cache ?? CacheService.instance).read(CacheService.examsKey).data;
    if (data is! Map) return const [];
    try {
      final registrations =
          ExamRegistrations.fromJson(Map<String, dynamic>.from(data));
      return [
        for (final exam in registrations.upcoming(today))
          if (exam.day case final day?)
            {'name': exam.name, 'date': Formats.isoDate(day)},
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The semester as the widget draws it: the teaching period and the next
  /// few dates of the calendar.
  @visibleForTesting
  static Map<String, Object?> buildSemester(
    SemesterCalendar? calendar,
    DateTime today,
  ) {
    if (calendar == null) return const {};
    final start = calendar.lectureStart;
    final end = calendar.lectureEnd;
    return {
      'name': calendar.semesterName,
      if (start != null) 'start': Formats.isoDate(start),
      if (end != null) 'end': Formats.isoDate(end),
      'next': [
        // Enough to still have something to show weeks after the last sync.
        for (final item in calendar.upcoming(today).take(12))
          {
            'label': item.entry.label,
            'date': Formats.isoDate(item.date),
            'active':
                item.entry.stateOn(today) == CalendarEntryState.active,
          },
      ],
    };
  }

  /// The main dishes of the next open days, with the user's price.
  @visibleForTesting
  static Map<String, Object?> buildMensa({
    required String campus,
    required Map<String, List<MensaMeal>> mealsByDay,
    required String priceKey,
    required Set<String> dietFilters,
    required String language,
  }) {
    final days = <Map<String, Object?>>[];
    for (final entry in mealsByDay.entries) {
      var meals = entry.value.where((m) => m.matchesDiet(dietFilters));
      final mains =
          meals.where((m) => MensaCategory.match(m.category)?.key == 'Essen');
      if (mains.isNotEmpty) meals = mains;
      if (meals.isEmpty) continue;
      days.add({
        'date': entry.key,
        'meals': [
          for (final meal in meals.take(8))
            {
              'name': meal.name,
              'price': meal.prices[priceKey] == null
                  ? ''
                  : Formats.price(meal.prices[priceKey]!, language),
              'diet': meal.isVegan
                  ? 'vegan'
                  : meal.isVegetarian
                      ? 'vegetarian'
                      : '',
            },
        ],
      });
    }
    return {'campus': campus, 'days': days};
  }

  Future<Map<String, Object?>> _mensaPayload(
    SettingsService settings,
    DateTime today,
    String language,
  ) async {
    final canteenId = settings.canteenId;
    final todayKey = Formats.isoDate(today);

    List<String>? openDays;
    final cachedDays = _cache.read(CacheService.mensaDaysKey(canteenId));
    if (cachedDays.data is List &&
        cachedDays.timestamp != null &&
        _cache.isSameDay(cachedDays.timestamp!)) {
      openDays = [for (final d in cachedDays.data as List) '$d'];
    }
    final service = _mensa ??= MensaService();
    try {
      if (openDays == null) {
        openDays = await service.fetchDays(canteenId);
        unawaited(_cache.save(CacheService.mensaDaysKey(canteenId), openDays));
      }
    } catch (_) {
      openDays = cachedDays.data is List
          ? [for (final d in cachedDays.data as List) '$d']
          : const [];
    }

    final mealsByDay = <String, List<MensaMeal>>{};
    final upcoming =
        openDays.where((d) => d.compareTo(todayKey) >= 0).take(3);
    for (final day in upcoming) {
      final key = CacheService.mensaKey(canteenId, day);
      final cached = _cache.read(key);
      List<MensaMeal>? meals;
      if (cached.data is List) {
        try {
          meals = [
            for (final m in cached.data as List)
              MensaMeal.fromJson(Map<String, dynamic>.from(m as Map)),
          ];
        } catch (_) {
          meals = null;
        }
      }
      final fresh =
          cached.timestamp != null && _cache.isSameDay(cached.timestamp!);
      if (meals == null || !fresh) {
        try {
          meals = await service.fetchMeals(canteenId, day);
          unawaited(_cache.save(key, meals.map((m) => m.toJson()).toList()));
        } catch (_) {
          // Keep what the cache had, if anything.
        }
      }
      if (meals != null && meals.isNotEmpty) mealsByDay[day] = meals;
    }

    return buildMensa(
      campus: settings.campus == 'TA' ? 'TA' : 'WH',
      mealsByDay: mealsByDay,
      priceKey: settings.mensaPriceCategory,
      dietFilters: settings.mensaDietFilters,
      language: language,
    );
  }

  Future<Map<String, Object?>> _semesterPayload(
    DateTime today,
    String language,
  ) async {
    final service = _semester ??= SemesterService(cache: _cache);
    final cached = service.cached(language);
    var calendar = cached.calendar;
    if (calendar == null || !SemesterService.isFresh(cached.fetchedAt)) {
      try {
        calendar = await service.fetch(language);
      } catch (_) {
        // Offline: the cached calendar (if any) is still right.
      }
    }
    return buildSemester(calendar, today);
  }

  // ── Launches & pinning ────────────────────────────────────────────────────

  /// Turns taps on widgets into [AppEvents.requestOpen]. A widget launches
  /// the app with `uniwe://open/<destination>`.
  void listenForLaunches() {
    // Not before the app connected the service (never, in widget tests).
    if (_listening || _settings == null || !isSupported) return;
    _listening = true;
    void handle(Uri? uri) {
      if (uri == null || uri.scheme != 'uniwe') return;
      final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      if (id != null && NavIds.all.contains(id)) AppEvents.requestOpen(id);
    }

    try {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(handle).catchError(
        (Object e) {
          log('HomeWidgetService: no launch info: $e');
        },
      );
      HomeWidget.widgetClicked.listen(handle, onError: (Object _) {});
    } catch (e) {
      log('HomeWidgetService: cannot listen for launches: $e');
    }
  }

  /// Whether the launcher lets apps offer a widget for pinning.
  Future<bool> canPin() async {
    if (!isSupported) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the launcher to add [kind] to the home screen.
  Future<void> requestPin(HomeWidgetKind kind) async {
    if (!isSupported) return;
    try {
      await HomeWidget.requestPinWidget(
        qualifiedAndroidName: '$_androidPackage.${kind.className}',
      );
    } catch (e) {
      log('HomeWidgetService: pinning failed: $e');
    }
  }
}
