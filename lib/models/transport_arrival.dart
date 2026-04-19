import 'package:flutter/foundation.dart';

class TransportArrival {
  final String lineName;
  final DateTime? when;
  final DateTime? plannedWhen;
  final int delay;
  final String originName;
  final String provenance;
  final String direction;

  TransportArrival({
    required this.lineName,
    this.when,
    this.plannedWhen,
    required this.delay,
    required this.originName,
    required this.provenance,
    required this.direction,
  });

  factory TransportArrival.fromJson(Map<String, dynamic> json) {
    return TransportArrival(
      lineName: json['line']?['name'] ?? '',
      when: json['when'] != null ? DateTime.parse(json['when']).toLocal() : null,
      plannedWhen: json['plannedWhen'] != null ? DateTime.parse(json['plannedWhen']).toLocal() : null,
      delay: json['delay'] ?? 0,
      originName: json['origin']?['name'] ?? '',
      provenance: json['provenance'] ?? '',
      direction: json['direction'] ?? '',
    );
  }

  DateTime get scheduledTime => plannedWhen ?? when ?? DateTime.now();
  DateTime get actualTime => when ?? plannedWhen ?? DateTime.now();
}
