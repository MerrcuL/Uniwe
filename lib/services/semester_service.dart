import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/semester_calendar.dart';
import 'cache_service.dart';
import 'exceptions.dart';
import 'semester_parser.dart';

/// The academic calendar from the university's public website.
class SemesterService {
  SemesterService({http.Client? client, CacheService? cache})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _cache = cache ?? CacheService.instance;

  static const Duration _timeout = Duration(seconds: 15);
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0)';

  /// The calendar changes a few times a year at most.
  static const Duration freshFor = Duration(hours: 12);

  static final Uri germanUrl = Uri.parse(
      'https://www.htw-berlin.de/studium/studienorganisation/akademischer-kalender/');
  static final Uri englishUrl = Uri.parse(
      'https://www.htw-berlin.de/en/studies/study-organisation/academic-calendar/');

  static Uri pageUrl(String languageCode) =>
      languageCode == 'de' ? germanUrl : englishUrl;

  final http.Client _client;
  final bool _ownsClient;
  final CacheService _cache;

  /// The calendar as last saved, with the time it was fetched.
  ({SemesterCalendar? calendar, DateTime? fetchedAt}) cached(
    String languageCode,
  ) {
    final entry = _cache.read(CacheService.semesterKey(languageCode));
    final data = entry.data;
    if (data is! Map) return (calendar: null, fetchedAt: null);
    try {
      return (
        calendar: SemesterCalendar.fromJson(Map<String, dynamic>.from(data)),
        fetchedAt: entry.timestamp,
      );
    } catch (_) {
      return (calendar: null, fetchedAt: null);
    }
  }

  static bool isFresh(DateTime? fetchedAt) =>
      fetchedAt != null &&
      DateTime.now().difference(fetchedAt).abs() < freshFor;

  /// Fetches the calendar in [languageCode] ('de', anything else is English)
  /// and saves it. Throws when the page cannot be loaded or has no dates.
  Future<SemesterCalendar> fetch(String languageCode) async {
    final url = pageUrl(languageCode);
    final response = await _client
        .get(url, headers: {'User-Agent': _userAgent}).timeout(_timeout);
    if (response.statusCode != 200) {
      throw HttpStatusException(response.statusCode, 'academic calendar');
    }
    final calendar = await compute(
      parseSemesterCalendarHtml,
      (response.body, url.toString()),
    );
    if (calendar.isEmpty) {
      throw const FormatException('Academic calendar without entries');
    }
    unawaited(
      _cache.save(CacheService.semesterKey(languageCode), calendar.toJson()),
    );
    return calendar;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
