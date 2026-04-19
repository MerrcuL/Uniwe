import 'dart:convert';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin persistent cache backed by SharedPreferences.
///
/// Stores JSON-encoded payloads alongside an ISO-8601 timestamp.
/// Cache entries are considered "fresh" if they were written today
/// (same calendar date) — which is the right policy for both the 
/// timetable (week-based) and the Mensa  menu (day-based).
class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _tsKey(String key)   => '__ts_$key';
  String _dataKey(String key) => '__data_$key';

  /// Returns true when [ts] is from the same calendar day as now.
  bool isSameDay(DateTime ts) {
    final now = DateTime.now();
    return ts.year == now.year && ts.month == now.month && ts.day == now.day;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(String key, Object json) async {
    try {
      final prefs = await _store;
      await prefs.setString(_dataKey(key), jsonEncode(json));
      await prefs.setString(_tsKey(key), DateTime.now().toIso8601String());
    } catch (e, st) {
      log('CacheService.save error for $key: $e', stackTrace: st);
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the decoded json object and the timestamp it was written, or null
  /// for either if not found.
  Future<({Object? data, DateTime? timestamp})> load(String key) async {
    try {
      final prefs = await _store;
      final raw  = prefs.getString(_dataKey(key));
      final tsRaw = prefs.getString(_tsKey(key));
      if (raw == null) return (data: null, timestamp: null);
      final ts = tsRaw != null ? DateTime.tryParse(tsRaw) : null;
      return (data: jsonDecode(raw), timestamp: ts);
    } catch (e, st) {
      log('CacheService.load error for $key: $e', stackTrace: st);
      return (data: null, timestamp: null);
    }
  }

  // ── Convenience keys ─────────────────────────────────────────────────────

  /// Key for one week's timetable: e.g. "timetable_12_2026"
  static String weekKey(String weekStr) => 'timetable_$weekStr';

  /// Key for one day's Mensa menu: e.g. "mensa_2037_2026-04-03"
  static String mensaKey(int canteenId, String date) => 'mensa_${canteenId}_$date';

  /// Key for Mensa available-days list
  static String mensaDaysKey(int canteenId) => 'mensaDays_$canteenId';
}
