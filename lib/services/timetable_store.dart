import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../models/timetable_event.dart';
import '../utils/iso_week.dart';
import 'cache_service.dart';

/// One week of events, pre-grouped and pre-sorted for display.
class WeekSchedule {
  final List<TimetableEvent> events;

  /// Events per weekday (index 0 = Monday … 6 = Sunday), sorted by start time.
  final List<List<TimetableEvent>> byDay;

  /// When this data was fetched from LSF (null for legacy cache entries).
  final DateTime? fetchedAt;

  WeekSchedule(List<TimetableEvent> events, this.fetchedAt)
      : events = List.unmodifiable(events),
        byDay = _groupByDay(events);

  bool get isEmpty => events.isEmpty;

  /// Earliest start and latest end (minutes since midnight) across the days
  /// `0 ..< dayCount`, or null if no event there has a usable time range.
  ({int start, int end})? timeRange(int dayCount) {
    int? start;
    int? end;
    for (var d = 0; d < dayCount && d < byDay.length; d++) {
      for (final e in byDay[d]) {
        if (!e.hasTimeRange) continue;
        final s = e.startMinutes!;
        final f = e.endMinutes!;
        if (start == null || s < start) start = s;
        if (end == null || f > end) end = f;
      }
    }
    if (start == null || end == null) return null;
    return (start: start, end: end);
  }

  static List<List<TimetableEvent>> _groupByDay(List<TimetableEvent> events) {
    final days = List.generate(7, (_) => <TimetableEvent>[]);
    for (final e in events) {
      final index = e.dayIndex;
      if (index >= 0) days[index].add(e);
    }
    for (final day in days) {
      day.sort(_compareEvents);
    }
    return List.unmodifiable(days.map(List<TimetableEvent>.unmodifiable));
  }

  static int _compareEvents(TimetableEvent a, TimetableEvent b) {
    final byStart = (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0);
    if (byStart != 0) return byStart;
    final byEnd = (a.endMinutes ?? 0).compareTo(b.endMinutes ?? 0);
    if (byEnd != 0) return byEnd;
    return a.title.compareTo(b.title);
  }
}

/// Holds the timetable of every visited week: memory first, then the
/// persistent cache, then LSF.
///
/// State is tracked per week, so a slow response for one week can never
/// clobber the loading/error state of the week that is on screen now.
class TimetableStore extends ChangeNotifier {
  TimetableStore({
    required Future<List<TimetableEvent>> Function(String weekKey) fetch,
    CacheService? cache,
    this.freshFor = const Duration(minutes: 15),
  })  : _fetch = fetch,
        _cache = cache ?? CacheService.instance;

  final Future<List<TimetableEvent>> Function(String weekKey) _fetch;
  final CacheService _cache;

  /// How long fetched data is served without asking LSF again.
  final Duration freshFor;

  final Map<String, WeekSchedule> _weeks = {};
  final Map<String, Future<bool>> _inFlight = {};
  final Set<String> _failed = {};
  int _generation = 0;
  bool _disposed = false;

  /// The schedule for [week], from memory or the persistent cache. Returns
  /// null if the week has never been loaded.
  WeekSchedule? schedule(IsoWeek week) {
    final key = week.key;
    final inMemory = _weeks[key];
    if (inMemory != null) return inMemory;

    final cached = _cache.read(CacheService.weekKey(key));
    final data = cached.data;
    if (data is! List) return null;
    try {
      final events = data
          .map((e) => TimetableEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return _weeks[key] = WeekSchedule(events, cached.timestamp);
    } catch (e) {
      log('TimetableStore: unreadable cache entry for $key: $e');
      return null;
    }
  }

  bool isLoading(IsoWeek week) => _inFlight.containsKey(week.key);

  /// True when the last attempt to load [week] from LSF failed.
  bool hasFailed(IsoWeek week) => _failed.contains(week.key);

  /// Loads [week] from LSF unless it was fetched within [freshFor]
  /// (or [force] is set). Returns whether up-to-date data is available.
  Future<bool> refresh(IsoWeek week, {bool force = false}) {
    final key = week.key;
    final running = _inFlight[key];
    if (running != null) return running;

    if (!force && !_failed.contains(key)) {
      // An empty week is never trusted as fresh: it is cheap to ask again
      // and must not hide classes for the whole freshness window.
      final current = schedule(week);
      final fetchedAt = current?.fetchedAt;
      if (current != null &&
          !current.isEmpty &&
          fetchedAt != null &&
          DateTime.now().difference(fetchedAt).abs() < freshFor) {
        return Future.value(true);
      }
    }

    late final Future<bool> future;
    future = _load(key, _generation).whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
      _notify();
    });
    _inFlight[key] = future;
    _notify();
    return future;
  }

  Future<bool> _load(String key, int generation) async {
    try {
      final events = await _fetch(key);
      if (generation != _generation) return false;
      _weeks[key] = WeekSchedule(events, DateTime.now());
      _failed.remove(key);
      unawaited(_cache.save(
        CacheService.weekKey(key),
        events.map((e) => e.toJson()).toList(),
      ));
      return true;
    } catch (e) {
      log('TimetableStore: loading $key failed: $e');
      if (generation == _generation) _failed.add(key);
      return false;
    }
  }

  /// Forgets everything (used on logout). Responses of requests that are
  /// still in flight are discarded.
  void clear() {
    _generation++;
    _weeks.clear();
    _inFlight.clear();
    _failed.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
