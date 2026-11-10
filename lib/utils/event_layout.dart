import '../models/timetable_event.dart';

/// An event with its horizontal slot inside a day column of the week grid.
class PlacedEvent {
  final TimetableEvent event;

  /// Zero-based column inside its group of overlapping events.
  final int column;

  /// Number of columns the group needs; the event's width is `1 / columnCount`
  /// of the day column.
  final int columnCount;

  const PlacedEvent(this.event, this.column, this.columnCount);
}

/// Packs the events of one day into as few side-by-side columns as possible.
///
/// Events that (transitively) overlap form a group. Inside a group every
/// event goes into the first column that is free at its start time, so three
/// events of which only two collide at any moment share the width in halves,
/// not in thirds. Events without a usable time range are skipped.
List<PlacedEvent> layoutDayEvents(Iterable<TimetableEvent> events) {
  final timed = events.where((e) => e.hasTimeRange).toList()
    ..sort((a, b) {
      final byStart = a.startMinutes!.compareTo(b.startMinutes!);
      return byStart != 0
          ? byStart
          : b.endMinutes!.compareTo(a.endMinutes!); // longer first
    });

  final placed = <PlacedEvent>[];
  var group = <(TimetableEvent, int)>[];
  var columnEnds = <int>[];
  var groupEnd = 0;

  void flush() {
    for (final (event, column) in group) {
      placed.add(PlacedEvent(event, column, columnEnds.length));
    }
    group = [];
    columnEnds = [];
  }

  for (final event in timed) {
    final start = event.startMinutes!;
    final end = event.endMinutes!;

    if (group.isNotEmpty && start >= groupEnd) flush();

    var column = columnEnds.indexWhere((columnEnd) => columnEnd <= start);
    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(end);
    } else {
      columnEnds[column] = end;
    }
    group.add((event, column));
    if (end > groupEnd) groupEnd = end;
  }
  flush();

  return placed;
}
