import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/timetable_event.dart';
import '../../services/timetable_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/event_layout.dart';
import '../../utils/formats.dart';
import '../../utils/iso_week.dart';

/// Calendar-style overview of one week: days as columns, time as the
/// vertical axis.
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.week,
    required this.schedule,
    required this.dayCount,
    required this.onEventTap,
    required this.onDayTap,
  });

  final IsoWeek week;
  final WeekSchedule schedule;

  /// 5 (Mon–Fri) or 7 (Mon–Sun).
  final int dayCount;
  final ValueChanged<TimetableEvent> onEventTap;
  final ValueChanged<DateTime> onDayTap;

  static const double _timeColumnWidth = 44;
  static const double _headerHeight = 60;
  static const double _verticalInset = 8;
  static const double _minHourHeight = 44;
  static const int _defaultStartHour = 8;
  static const int _defaultEndHour = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final today = Dates.today();
    // Space covered by the floating navigation bar / gesture area.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Visible hours: the events' span plus one hour of air on both sides.
    var startHour = _defaultStartHour;
    var endHour = _defaultEndHour;
    final range = schedule.timeRange(dayCount);
    if (range != null) {
      startHour = (range.start ~/ 60 - 1).clamp(0, 23);
      endHour = ((range.end / 60).ceil() + 1).clamp(1, 24);
      if (startHour >= endHour) {
        startHour = _defaultStartHour;
        endHour = _defaultEndHour;
      }
    }
    final hours = endHour - startHour;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = math.max(
          0.0,
          (constraints.maxWidth - _timeColumnWidth - 4) / dayCount,
        );
        final available = constraints.maxHeight -
            _headerHeight -
            2 * _verticalInset -
            bottomInset;
        // Fill the screen when there is room, scroll when there is not.
        final hourHeight = math.max(available / hours, _minHourHeight);
        final gridHeight = hourHeight * hours;

        return Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Row(
                children: [
                  const SizedBox(width: _timeColumnWidth),
                  for (var d = 0; d < dayCount; d++)
                    SizedBox(
                      width: dayWidth,
                      child: _DayHeader(
                        date: week.day(d),
                        isToday: Dates.isSameDay(week.day(d), today),
                        locale: locale,
                        onTap: () => onDayTap(week.day(d)),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: _verticalInset,
                  bottom: _verticalInset + bottomInset,
                ),
                child: SizedBox(
                  height: gridHeight,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridLinesPainter(
                              hours: hours,
                              hourHeight: hourHeight,
                              leftInset: _timeColumnWidth,
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        for (var h = 0; h <= hours; h++)
                          Positioned(
                            top: h * hourHeight - 7,
                            left: 0,
                            width: _timeColumnWidth - 8,
                            child: Text(
                              '${(startHour + h).toString().padLeft(2, '0')}:00',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        for (var d = 0; d < dayCount; d++)
                          for (final placed in layoutDayEvents(schedule.byDay[d]))
                            _positionedEvent(
                              placed,
                              dayLeft: _timeColumnWidth + d * dayWidth,
                              dayWidth: dayWidth,
                              startHour: startHour,
                              hourHeight: hourHeight,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _positionedEvent(
    PlacedEvent placed, {
    required double dayLeft,
    required double dayWidth,
    required int startHour,
    required double hourHeight,
  }) {
    final event = placed.event;
    final width = dayWidth / placed.columnCount;
    final top = (event.startMinutes! / 60 - startHour) * hourHeight;
    final height =
        (event.endMinutes! - event.startMinutes!) / 60 * hourHeight;

    return Positioned(
      top: top,
      left: dayLeft + placed.column * width,
      width: width,
      height: height,
      child: _GridEventTile(
        event: event,
        height: height,
        onTap: () => onEventTap(event),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.isToday,
    required this.locale,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: Formats.fullDate(date, locale),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.mediumRadius,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                Formats.weekdayShort(date, locale),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  date.day.toString(),
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isToday ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridEventTile extends StatelessWidget {
  const _GridEventTile({
    required this.event,
    required this.height,
    required this.onTap,
  });

  final TimetableEvent event;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        event.isExam ? scheme.errorContainer : scheme.primaryContainer;
    final foreground =
        event.isExam ? scheme.onErrorContainer : scheme.onPrimaryContainer;

    // Very short events have no room for text; never ask for zero lines.
    final contentHeight = height - 2 - 8;
    final showRoom = contentHeight >= 40 && event.room.isNotEmpty;
    final titleLines =
        math.max(1, ((contentHeight - (showRoom ? 13 : 0)) / 12).floor());

    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 0, 1, 2),
      child: Semantics(
        button: true,
        label: '${event.cleanTitle}, ${event.time}, ${event.room}',
        excludeSemantics: true,
        child: Material(
          color: background,
          borderRadius: AppShapes.smallRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: contentHeight < 11
                ? const SizedBox.expand()
                : Padding(
                    padding: const EdgeInsets.all(4),
                    // Clips instead of overflowing when the tile is short.
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.cleanTitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                              height: 1.2,
                            ),
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showRoom)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                event.room,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: foreground,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Draws all hour lines in one pass instead of one widget per line and day.
class _GridLinesPainter extends CustomPainter {
  const _GridLinesPainter({
    required this.hours,
    required this.hourHeight,
    required this.leftInset,
    required this.color,
  });

  final int hours;
  final double hourHeight;
  final double leftInset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 0; h <= hours; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(leftInset, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter oldDelegate) =>
      oldDelegate.hours != hours ||
      oldDelegate.hourHeight != hourHeight ||
      oldDelegate.leftInset != leftInset ||
      oldDelegate.color != color;
}
