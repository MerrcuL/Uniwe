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

  static final RegExp _clockRegex = RegExp(r'(\d{1,2})[:.](\d{2})');
  static final RegExp _titleSuffixRegex = RegExp(r'\s*\([^)]*\)$');

  /// Day-name prefixes (German as delivered by LSF, plus English) per weekday.
  static const List<List<String>> _dayPrefixes = [
    ['mo'],
    ['di', 'tu'],
    ['mi', 'we'],
    ['do', 'th'],
    ['fr'],
    ['sa'],
    ['so', 'su'],
  ];

  // Derived values are parsed once and cached: they are needed on every
  // build of the day list and the week grid.
  late final List<int> _clockMinutes = _clockRegex
      .allMatches(time)
      .map((m) => int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!))
      .toList(growable: false);

  /// Start of the event in minutes since midnight, if [time] is parseable.
  int? get startMinutes => _clockMinutes.isNotEmpty ? _clockMinutes[0] : null;

  /// End of the event in minutes since midnight, if [time] contains one.
  int? get endMinutes => _clockMinutes.length > 1 ? _clockMinutes[1] : null;

  /// True when the event can be placed on a time axis.
  bool get hasTimeRange {
    final start = startMinutes;
    final end = endMinutes;
    return start != null && end != null && end > start;
  }

  /// 0 = Monday … 6 = Sunday, or -1 when [day] is not a known weekday.
  late final int dayIndex = _parseDayIndex(day);

  /// [title] without the trailing "(…)" module-number suffix LSF appends.
  late final String cleanTitle = title.replaceAll(_titleSuffixRegex, '').trim();

  String get startLabel =>
      time.contains('-') ? time.split('-').first.trim() : time.trim();

  String get endLabel => time.contains('-') ? time.split('-').last.trim() : '';

  static int _parseDayIndex(String day) {
    final lower = day.trim().toLowerCase();
    if (lower.isEmpty) return -1;
    for (var i = 0; i < _dayPrefixes.length; i++) {
      for (final prefix in _dayPrefixes[i]) {
        if (lower.startsWith(prefix)) return i;
      }
    }
    return -1;
  }

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
