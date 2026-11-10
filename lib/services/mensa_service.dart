import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mensa_meal.dart';
import 'exceptions.dart';

/// OpenMensa client.
///
/// Both calls throw on network / server errors instead of returning an empty
/// list, so the UI can tell "the canteen serves nothing" apart from "we could
/// not find out" and offer a retry.
class MensaService {
  static const String _baseUrl = 'https://openmensa.org/api/v2';
  static const Duration _timeout = Duration(seconds: 12);

  // Reuse single client for connection pooling
  final http.Client _client;

  MensaService({http.Client? client}) : _client = client ?? http.Client();

  /// Open days (ISO dates) of the canteen.
  Future<List<String>> fetchDays(int canteenId) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/canteens/$canteenId/days'))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw HttpStatusException(response.statusCode, 'Mensa days');
    }
    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList
        .where((d) => d is Map && d['closed'] == false && d['date'] != null)
        .map<String>((d) => d['date'].toString())
        .toList();
  }

  Future<List<MensaMeal>> fetchMeals(int canteenId, String date) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/canteens/$canteenId/days/$date/meals'))
        .timeout(_timeout);
    // OpenMensa answers 404 for a day it has no menu for.
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw HttpStatusException(response.statusCode, 'Mensa meals');
    }
    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList
        .whereType<Map>()
        .map((m) => MensaMeal.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  void dispose() => _client.close();
}
