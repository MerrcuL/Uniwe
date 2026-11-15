import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../models/cancelled_lecture.dart';
import '../models/timetable_event.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import 'cache_service.dart';

/// The classes LSF lists as cancelled, per day: memory first, then the
/// persistent cache, then LSF.
///
/// Shared by the timetable (which marks the user's own classes), the list of
/// all cancellations and the home screen widgets.
class CancellationStore extends ChangeNotifier {
  CancellationStore({
    required Future<List<CancelledLecture>> Function(DateTime date) fetch,
    CacheService? cache,
    this.freshFor = const Duration(minutes: 15),
  })  : _fetch = fetch,
        _cache = cache ?? CacheService.instance;

  /// LSF only announces cancellations for the near future; days further
  /// away (or in the past) are not asked for.
  static const int horizonDays = 14;

  final Future<List<CancelledLecture>> Function(DateTime date) _fetch;
  final CacheService _cache;
  final Duration freshFor;

  final Map<String, List<CancelledLecture>> _days = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<bool>> _inFlight = {};
  final Set<String> _failed = {};
  bool _disposed = false;

  static String _key(DateTime date) => Formats.isoDate(date);

  /// Whether cancellations for [date] can be known at all right now.
  static bool isInRange(DateTime date) {
    final today = Dates.today();
    final day = Dates.dateOnly(date);
    return !day.isBefore(today) &&
        day.difference(today).inDays <= horizonDays;
  }

  /// The cancellations of [date], or null if they have never been loaded.
  List<CancelledLecture>? forDate(DateTime date) {
    final key = _key(date);
    final inMemory = _days[key];
    if (inMemory != null) return inMemory;

    final cached = _cache.read(CacheService.cancelledKey(key));
    final data = cached.data;
    if (data is! List) return null;
    try {
      final list = List<CancelledLecture>.unmodifiable(data.map(
        (e) => CancelledLecture.fromJson(Map<String, dynamic>.from(e as Map)),
      ));
      final timestamp = cached.timestamp;
      if (timestamp != null) _fetchedAt[key] = timestamp;
      return _days[key] = list;
    } catch (e) {
      log('CancellationStore: unreadable cache entry for $key: $e');
      return null;
    }
  }

  DateTime? fetchedAt(DateTime date) {
    forDate(date);
    return _fetchedAt[_key(date)];
  }

  bool isLoading(DateTime date) => _inFlight.containsKey(_key(date));

  bool hasFailed(DateTime date) => _failed.contains(_key(date));

  /// The cancellation of [event] on [date], if LSF lists one.
  CancelledLecture? match(DateTime date, TimetableEvent event) {
    if (event.publishId == null) return null;
    final list = forDate(date);
    if (list == null) return null;
    for (final lecture in list) {
      if (lecture.matches(event)) return lecture;
    }
    return null;
  }

  /// Loads [date] from LSF unless it was fetched within [freshFor] (or
  /// [force] is set). Returns whether up-to-date data is available.
  Future<bool> refresh(DateTime date, {bool force = false}) {
    final key = _key(date);
    final running = _inFlight[key];
    if (running != null) return running;

    if (!force && !_failed.contains(key)) {
      final fetchedAt = this.fetchedAt(date);
      if (_days.containsKey(key) &&
          fetchedAt != null &&
          DateTime.now().difference(fetchedAt).abs() < freshFor) {
        return Future.value(true);
      }
    }

    late final Future<bool> future;
    future = _load(date, key).whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
      _notify();
    });
    _inFlight[key] = future;
    _notify();
    return future;
  }

  Future<bool> _load(DateTime date, String key) async {
    try {
      final lectures = await _fetch(date);
      _days[key] = List.unmodifiable(lectures);
      _fetchedAt[key] = DateTime.now();
      _failed.remove(key);
      unawaited(_cache.save(
        CacheService.cancelledKey(key),
        lectures.map((l) => l.toJson()).toList(),
      ));
      return true;
    } catch (e) {
      log('CancellationStore: loading $key failed: $e');
      _failed.add(key);
      return false;
    }
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
