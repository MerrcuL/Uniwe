class TimetableEvent {
  final String title;
  final String day;
  final String time;
  final String room;
  final String type;
  final String frequency;
  final String? publishId;
  final bool isExam;
  final bool isOverlapping;

  TimetableEvent({
    required this.title,
    required this.day,
    required this.time,
    required this.room,
    required this.type,
    required this.frequency,
    this.publishId,
    this.isExam = false,
    this.isOverlapping = false,
  });

  factory TimetableEvent.fromJson(Map<String, dynamic> json) {
    return TimetableEvent(
      title: json['title'] ?? '',
      day: json['day'] ?? '',
      time: json['time'] ?? '',
      room: json['room'] ?? '',
      type: json['type'] ?? '',
      frequency: json['frequency'] ?? '',
      publishId: json['publishId'],
      isExam: json['isExam'] ?? false,
      isOverlapping: json['isOverlapping'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'day': day,
      'time': time,
      'room': room,
      'type': type,
      'frequency': frequency,
      'publishId': publishId,
      'isExam': isExam,
      'isOverlapping': isOverlapping,
    };
  }
}
