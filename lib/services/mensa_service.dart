import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/mensa_meal.dart';

class MensaService {
  static const String _baseUrl = 'https://openmensa.org/api/v2';

  // Reuse single client for connection pooling
  final http.Client _client = http.Client();

  Future<List<String>> fetchDays(int canteenId) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/canteens/$canteenId/days'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .where((d) => d['closed'] == false)
            .map<String>((d) => d['date'].toString())
            .toList();
      }
      log('MensaService.fetchDays: unexpected status ${response.statusCode}');
    } catch (e, st) {
      log('MensaService.fetchDays error: $e', stackTrace: st);
    }
    return [];
  }

  Future<List<MensaMeal>> fetchMeals(int canteenId, String date) async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/canteens/$canteenId/days/$date/meals'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((m) => MensaMeal.fromJson(m)).toList();
      }
      log('MensaService.fetchMeals: unexpected status ${response.statusCode}');
    } catch (e, st) {
      log('MensaService.fetchMeals error: $e', stackTrace: st);
    }
    return [];
  }

  void dispose() => _client.close();
}
