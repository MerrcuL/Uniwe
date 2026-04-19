import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/transport_arrival.dart';

class TransportService {
  static const String _baseUrl = 'https://v6.bvg.transport.rest/stops';
  
  final http.Client _client = http.Client();

  Future<List<TransportArrival>> fetchDepartures(String stopId) async {
    try {
      final depUrl = '$_baseUrl/$stopId/departures?duration=60&results=40&remarks=false&tram=true&bus=false&suburban=false&subway=false&express=false&regional=false';
      final arrUrl = '$_baseUrl/$stopId/arrivals?duration=60&results=40&remarks=false&tram=true&bus=false&suburban=false&subway=false&express=false&regional=false';
      
      final responses = await Future.wait([
        _client.get(Uri.parse(depUrl)),
        _client.get(Uri.parse(arrUrl)),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final List<dynamic> departures = jsonDecode(responses[0].body)['departures'] ?? [];
        final List<dynamic> arrivals = jsonDecode(responses[1].body)['arrivals'] ?? [];
        
        final Map<String, String> originMap = {};
        for(var arr in arrivals) {
           final tripId = arr['tripId'];
           final originName = arr['origin']?['name'];
           if (tripId != null && originName != null) {
              originMap[tripId] = originName;
           }
        }
        
        final List<TransportArrival> parsed = departures
            .map((e) {
               final tripId = e['tripId'];
               if (tripId != null && originMap.containsKey(tripId)) {
                  e['origin'] = {'name': originMap[tripId]};
               }
               return TransportArrival.fromJson(e);
            })
            .where((m) => m.lineName.startsWith('M') || RegExp(r'^\d+$').hasMatch(m.lineName))
            .toList();
            
        return parsed;
      }
      log('TransportService.fetchDepartures: unexpected status ${responses[0].statusCode} / ${responses[1].statusCode}');
    } catch (e, st) {
      log('TransportService.fetchDepartures error: $e', stackTrace: st);
    }
    return [];
  }

  void dispose() => _client.close();
}
