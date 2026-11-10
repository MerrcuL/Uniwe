import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import '../models/transport_arrival.dart';
import 'exceptions.dart';

class TransportService {
  static const String _baseUrl = 'https://v6.bvg.transport.rest/stops';
  static const Duration _timeout = Duration(seconds: 12);
  static const String _query =
      'duration=60&results=40&remarks=false&tram=true&bus=false&suburban=false&subway=false&express=false&regional=false';
  static final RegExp _numericLineRegex = RegExp(r'^\d+$');

  final http.Client _client;

  TransportService({http.Client? client}) : _client = client ?? http.Client();

  /// Tram departures of [stopId] within the next hour, soonest first.
  ///
  /// Throws when the departures cannot be loaded. The arrivals request only
  /// enriches the result (it tells us where a tram comes from), so its failure
  /// is tolerated.
  Future<List<TransportArrival>> fetchDepartures(String stopId) async {
    final departuresFuture = _client
        .get(Uri.parse('$_baseUrl/$stopId/departures?$_query'))
        .timeout(_timeout);
    final originsFuture = _fetchOrigins(stopId);

    final response = await departuresFuture;
    if (response.statusCode != 200) {
      throw HttpStatusException(response.statusCode, 'departures');
    }
    final originByTrip = await originsFuture;

    final decoded = jsonDecode(response.body);
    final List<dynamic> departures =
        decoded is Map ? (decoded['departures'] as List?) ?? const [] : const [];

    final parsed = departures
        .whereType<Map>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          final origin = originByTrip[map['tripId']];
          if (origin != null) {
            map['origin'] = {'name': origin};
          }
          return TransportArrival.fromJson(map);
        })
        .where((m) =>
            m.lineName.startsWith('M') ||
            _numericLineRegex.hasMatch(m.lineName))
        .toList()
      ..sort((a, b) => a.actualTime.compareTo(b.actualTime));

    return parsed;
  }

  Future<Map<String, String>> _fetchOrigins(String stopId) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/$stopId/arrivals?$_query'))
          .timeout(_timeout);
      if (response.statusCode != 200) return const {};
      final decoded = jsonDecode(response.body);
      final List<dynamic> arrivals =
          decoded is Map ? (decoded['arrivals'] as List?) ?? const [] : const [];
      final origins = <String, String>{};
      for (final arr in arrivals.whereType<Map>()) {
        final tripId = arr['tripId'];
        final origin = arr['origin'];
        final originName = origin is Map ? origin['name'] : null;
        if (tripId is String && originName is String) {
          origins[tripId] = originName;
        }
      }
      return origins;
    } catch (e) {
      log('TransportService: arrivals lookup failed: $e');
      return const {};
    }
  }

  void dispose() => _client.close();
}
