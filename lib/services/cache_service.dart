import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin persistent cache backed by SharedPreferences.
///
/// Stores JSON-encoded payloads alongside an ISO-8601 timestamp.
/// SharedPreferences keeps everything in memory once loaded, so reads are
/// synchronous after [init] — screens can show cached data in their very
/// first frame instead of flashing a spinner.
class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  static const String _tsPrefix = '__ts_';
  static const String _dataPrefix = '__data_';

  SharedPreferences? _prefs;

  /// Must complete before [read] returns anything. Idempotent.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Re-binds to the current SharedPreferences instance (tests replace it).
  @visibleForTesting
  Future<void> resetForTesting() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String _tsKey(String key) => '$_tsPrefix$key';
  String _dataKey(String key) => '$_dataPrefix$key';

  /// Returns true when [ts] is from the same calendar day as now.
  bool isSameDay(DateTime ts) {
    final now = DateTime.now();
    return ts.year == now.year && ts.month == now.month && ts.day == now.day;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(String key, Object json) async {
    try {
      await init();
      final prefs = _prefs!;
      await prefs.setString(_dataKey(key), jsonEncode(json));
      await prefs.setString(_tsKey(key), DateTime.now().toIso8601String());
    } catch (e, st) {
      log('CacheService.save error for $key: $e', stackTrace: st);
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the decoded JSON and the time it was written, or nulls when the
  /// entry is missing, unreadable, or the cache is not initialised yet.
  ({Object? data, DateTime? timestamp}) read(String key) {
    final prefs = _prefs;
    if (prefs == null) return (data: null, timestamp: null);
    try {
      final raw = prefs.getString(_dataKey(key));
      if (raw == null) return (data: null, timestamp: null);
      final tsRaw = prefs.getString(_tsKey(key));
      final ts = tsRaw != null ? DateTime.tryParse(tsRaw) : null;
      return (data: jsonDecode(raw), timestamp: ts);
    } catch (e, st) {
      log('CacheService.read error for $key: $e', stackTrace: st);
      return (data: null, timestamp: null);
    }
  }

  // ── Maintenance ───────────────────────────────────────────────────────────

  /// Removes every entry whose logical key satisfies [test].
  Future<void> removeWhere(bool Function(String key) test) async {
    try {
      await init();
      final prefs = _prefs!;
      final doomed = prefs
          .getKeys()
          .where((k) => k.startsWith(_dataPrefix))
          .map((k) => k.substring(_dataPrefix.length))
          .where(test)
          .toList();
      for (final key in doomed) {
        await prefs.remove(_dataKey(key));
        await prefs.remove(_tsKey(key));
      }
    } catch (e, st) {
      log('CacheService.removeWhere error: $e', stackTrace: st);
    }
  }

  /// Deletes entries older than [maxAge]. Every visited week and menu day gets
  /// its own key, so without this the store (which is loaded into memory in
  /// full at every app start) would grow without bound.
  Future<void> prune({Duration maxAge = const Duration(days: 21)}) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final cutoff = DateTime.now().subtract(maxAge);
    await removeWhere((key) {
      final tsRaw = prefs.getString(_tsKey(key));
      final ts = tsRaw != null ? DateTime.tryParse(tsRaw) : null;
      return ts == null || ts.isBefore(cutoff);
    });
  }

  // ── Convenience keys ─────────────────────────────────────────────────────

  static const String timetablePrefix = 'timetable_';

  /// Key for one week's timetable: e.g. "timetable_12_2026"
  static String weekKey(String weekStr) => '$timetablePrefix$weekStr';

  /// Key for one day's Mensa menu: e.g. "mensa_2037_2026-04-03"
  static String mensaKey(int canteenId, String date) =>
      'mensa_${canteenId}_$date';

  /// Key for Mensa available-days list
  static String mensaDaysKey(int canteenId) => 'mensaDays_$canteenId';
}
