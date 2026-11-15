import 'timetable_event.dart';

/// One row of LSF's public "Ausfallende Veranstaltungen" list: a class that
/// does not take place on a given day.
class CancelledLecture {
  CancelledLecture({
    required this.start,
    required this.end,
    required this.title,
    this.number = '',
    this.publishId,
    this.building = '',
    this.room = '',
    this.group = '',
    this.lecturers = '',
    this.remark = '',
  });

  /// "08:00"
  final String start;
  final String end;
  final String number;
  final String title;

  /// LSF's id of the lecture, the same one timetable events carry.
  final String? publishId;
  final String building;
  final String room;

  /// "1. Zug, 2. Gruppe"
  final String group;
  final String lecturers;

  /// Free text of the lecturer, often the replacement date.
  final String remark;

  static int? _minutes(String clock) {
    final match = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(clock);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  late final int? startMinutes = _minutes(start);
  late final int? endMinutes = _minutes(end);

  String get time => end.isEmpty ? start : '$start – $end';

  /// The campus prefix of [building] ("WH", "TA", "TGS"), or ''.
  String get campus {
    final match = RegExp(r'^(WH|TA|TGS)\b').firstMatch(building.trim());
    return match?.group(1) ?? '';
  }

  /// Whether this is [event] of the personal timetable (on the day this
  /// cancellation is for). A lecture can run in several groups and slots
  /// under one id, so the start time has to agree as well.
  bool matches(TimetableEvent event) {
    final id = publishId;
    if (id == null || id.isEmpty || id != event.publishId) return false;
    final mine = startMinutes;
    final theirs = event.startMinutes;
    return mine == null || theirs == null || mine == theirs;
  }

  factory CancelledLecture.fromJson(Map<String, dynamic> json) =>
      CancelledLecture(
        start: json['start'] ?? '',
        end: json['end'] ?? '',
        title: json['title'] ?? '',
        number: json['number'] ?? '',
        publishId: json['publishId'],
        building: json['building'] ?? '',
        room: json['room'] ?? '',
        group: json['group'] ?? '',
        lecturers: json['lecturers'] ?? '',
        remark: json['remark'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'title': title,
        'number': number,
        'publishId': publishId,
        'building': building,
        'room': room,
        'group': group,
        'lecturers': lecturers,
        'remark': remark,
      };
}
