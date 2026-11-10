class TransportArrival {
  final String lineName;
  final DateTime? when;
  final DateTime? plannedWhen;
  final int delay;
  final String originName;
  final String provenance;
  final String direction;

  /// The trip was cancelled by the operator. The API reports such departures
  /// with `when: null`, so they must not be presented as running on schedule.
  final bool cancelled;

  TransportArrival({
    required this.lineName,
    this.when,
    this.plannedWhen,
    required this.delay,
    required this.originName,
    required this.provenance,
    required this.direction,
    this.cancelled = false,
  });

  factory TransportArrival.fromJson(Map<String, dynamic> json) {
    final rawWhen = json['when'] as String?;
    final rawPlanned = json['plannedWhen'] as String?;
    return TransportArrival(
      lineName: json['line']?['name']?.toString() ?? '',
      when: rawWhen != null ? DateTime.tryParse(rawWhen)?.toLocal() : null,
      plannedWhen:
          rawPlanned != null ? DateTime.tryParse(rawPlanned)?.toLocal() : null,
      delay: (json['delay'] as num?)?.toInt() ?? 0,
      originName: json['origin']?['name']?.toString() ?? '',
      provenance: json['provenance']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      cancelled: json['cancelled'] == true,
    );
  }

  DateTime get scheduledTime => plannedWhen ?? when ?? DateTime.now();
  DateTime get actualTime => when ?? plannedWhen ?? DateTime.now();

  /// Difference between real-time and scheduled departure, in whole minutes.
  int get delayMinutes =>
      (actualTime.difference(scheduledTime).inSeconds / 60).round();
}
