import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/semester_calendar.dart';
import '../services/haptic_service.dart';
import '../services/home_widget_service.dart';
import '../services/semester_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import '../widgets/expressive.dart';
import '../widgets/info_widgets.dart';

/// The academic calendar: how far the teaching period has come, what is due
/// next, and every date of the semester.
class SemesterScreen extends StatefulWidget {
  const SemesterScreen({super.key, this.service});

  /// Injectable for tests.
  final SemesterService? service;

  @override
  State<SemesterScreen> createState() => _SemesterScreenState();
}

class _SemesterScreenState extends State<SemesterScreen> {
  late final SemesterService _service = widget.service ?? SemesterService();

  String? _language;
  SemesterCalendar? _calendar;
  DateTime? _fetchedAt;
  bool _hasError = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (language == _language) return;
    // The page exists in both languages; follow the app language.
    _language = language;
    final cached = _service.cached(language);
    _calendar = cached.calendar;
    _fetchedAt = cached.fetchedAt;
    _hasError = false;
    if (_calendar == null || !SemesterService.isFresh(_fetchedAt)) _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final language = _language!;
    final generation = ++_generation;
    try {
      final calendar = await _service.fetch(language);
      if (language == 'de') HomeWidgetService.instance.sync();
      if (!mounted || generation != _generation) return;
      setState(() {
        _calendar = calendar;
        _fetchedAt = DateTime.now();
        _hasError = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _hasError = true);
    }
  }

  void _retry() {
    setState(() => _hasError = false);
    _load();
  }

  void _openLink(Uri link) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    launchUrl(link, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('semesterDates')),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: l10n.get('openWebsite'),
            onPressed: () => _openLink(
              SemesterService.pageUrl(_language ?? 'de'),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: AppMotion.effectsDefault,
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final calendar = _calendar;
    if (calendar == null) {
      if (!_hasError) return const LoadingState();
      return StatusMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorSemester'),
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    final today = Dates.today();
    final upcoming = calendar.upcoming(today).take(4).toList();
    final gutter = AppSpacing.gutter(context);
    final fetchedAt = _fetchedAt;

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          AppSpacing.bottomInset(context),
        ),
        children: [
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBanner(
                icon: Icons.cloud_off_outlined,
                text: fetchedAt == null
                    ? l10n.get('offlineCache')
                    : '${l10n.get('offlineCache')} '
                        '${l10n.get('lastUpdated')}: ${Formats.timestamp(fetchedAt)}',
              ),
            ),
          _ProgressCard(calendar: calendar, today: today),
          if (upcoming.isNotEmpty) ...[
            SectionHeader(
              l10n.get('semesterUpNext'),
              icon: Icons.upcoming_outlined,
            ),
            ListGroup(
              children: [
                for (final item in upcoming)
                  _UpcomingTile(
                    entry: item.entry,
                    date: item.date,
                    today: today,
                  ),
              ],
            ),
          ],
          for (final section in calendar.sections) ...[
            SectionHeader(section.title),
            ListGroup(
              children: [
                for (final entry in section.entries)
                  _EntryTile(
                    entry: entry,
                    today: today,
                    onOpen: entry.link == null
                        ? null
                        : () => _openLink(entry.link!),
                  ),
              ],
            ),
          ],
          FootNote(l10n.get('semesterSource')),
        ],
      ),
    );
  }
}

/// The spans the time scale draws on top of the teaching period.
({List<DateSpan> breaks, List<DateSpan> exams}) _scaleSpans(
  SemesterCalendar calendar,
) {
  final breakLabel =
      RegExp(r'vorlesungsfrei|non-teaching', caseSensitive: false);
  final examLabel =
      RegExp(r'prüfungszeitraum|examination period', caseSensitive: false);
  final registration =
      RegExp(r'anmeldung|registration', caseSensitive: false);
  final breaks = <DateSpan>[];
  final exams = <DateSpan>[];
  for (final section in calendar.sections) {
    for (final entry in section.entries) {
      if (breakLabel.hasMatch(entry.label)) {
        breaks.addAll(entry.spans);
      } else if (examLabel.hasMatch(entry.label) &&
          !registration.hasMatch(entry.label)) {
        exams.addAll(entry.spans);
      }
    }
  }
  return (breaks: breaks, exams: exams);
}

/// Semester name, a time scale of the semester with today marked, and the
/// running week of the teaching period.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.calendar, required this.today});

  final SemesterCalendar calendar;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final on = scheme.onPrimaryContainer;

    final start = calendar.lectureStart;
    final end = calendar.lectureEnd;
    final week = calendar.lectureWeek(today);
    final progress = calendar.lectureProgress(today);

    String? headline;
    String? detail;
    if (start != null && end != null) {
      if (today.isBefore(start)) {
        final days = DateTime.utc(start.year, start.month, start.day)
            .difference(DateTime.utc(today.year, today.month, today.day))
            .inDays;
        headline = l10n.get('lecturesStart');
        detail = l10n.inDays(days);
      } else if (today.isAfter(end)) {
        headline = l10n.get('lecturesOver');
      } else if (week != null) {
        headline = l10n
            .get('lectureWeekOf')
            .replaceAll('{n}', '${week.week}')
            .replaceAll('{total}', '${week.total}');
        final left = DateTime.utc(end.year, end.month, end.day)
            .difference(DateTime.utc(today.year, today.month, today.day))
            .inDays;
        detail = l10n.get('daysOfLecturesLeft').replaceAll('{n}', '$left');
      }
    }

    final scale = _scaleSpans(calendar);
    // The scale runs to the end of the last exam period, if there is one.
    var scaleEnd = end;
    for (final span in scale.exams) {
      if (scaleEnd != null && span.end.isAfter(scaleEnd)) scaleEnd = span.end;
    }

    return SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, size: 20, color: on),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  calendar.semesterName,
                  style: theme.textTheme.titleSmall?.copyWith(color: on),
                ),
              ),
            ],
          ),
          if (headline != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    headline,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: on,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (progress != null && week != null)
                  Text(
                    '${(progress * 100).round()} %',
                    style: theme.textTheme.titleMedium?.copyWith(color: on),
                  ),
              ],
            ),
            if (detail != null)
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(color: on),
              ),
          ],
          if (start != null && scaleEnd != null) ...[
            const SizedBox(height: 16),
            Semantics(
              label: l10n.get('timeScale'),
              value: progress == null ? null : '${(progress * 100).round()} %',
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ScalePainter(
                    start: start,
                    end: scaleEnd,
                    lectureEnd: end!,
                    today: today,
                    breaks: scale.breaks,
                    exams: scale.exams,
                    track: on.withValues(alpha: 0.16),
                    lecture: scheme.primary,
                    exam: scheme.tertiary,
                    pause: scheme.surface,
                    marker: on,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Formats.dayMonth(start),
                  style: theme.textTheme.labelSmall?.copyWith(color: on),
                ),
                Text(
                  Formats.date(scaleEnd),
                  style: theme.textTheme.labelSmall?.copyWith(color: on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Legend(
                  color: scheme.primary,
                  label: l10n.get('legendLectures'),
                  textColor: on,
                ),
                if (scale.breaks.isNotEmpty)
                  _Legend(
                    color: scheme.surface,
                    label: l10n.get('legendBreak'),
                    textColor: on,
                  ),
                if (scale.exams.isNotEmpty)
                  _Legend(
                    color: scheme.tertiary,
                    label: l10n.get('legendExams'),
                    textColor: on,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: textColor),
        ),
      ],
    );
  }
}

/// The semester as a bar: teaching period, breaks and exam periods to
/// scale, with a marker for today.
class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.start,
    required this.end,
    required this.lectureEnd,
    required this.today,
    required this.breaks,
    required this.exams,
    required this.track,
    required this.lecture,
    required this.exam,
    required this.pause,
    required this.marker,
  });

  final DateTime start;
  final DateTime end;
  final DateTime lectureEnd;
  final DateTime today;
  final List<DateSpan> breaks;
  final List<DateSpan> exams;
  final Color track;
  final Color lecture;
  final Color exam;
  final Color pause;
  final Color marker;

  static int _days(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  @override
  void paint(Canvas canvas, Size size) {
    final total = _days(start, end) + 1;
    if (total <= 1) return;
    const barHeight = 12.0;
    final top = (size.height - barHeight) / 2;
    const radius = Radius.circular(barHeight / 2);

    // Position of the start of [day] (or of its end) on the bar.
    double x(DateTime day, {bool endOfDay = false}) =>
        ((_days(start, day) + (endOfDay ? 1 : 0)) / total).clamp(0.0, 1.0) *
        size.width;

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, barHeight),
      radius,
    );
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(bar.outerRect, Paint()..color = track);

    void segment(DateTime from, DateTime to, Color color) {
      final left = x(from);
      final right = x(to, endOfDay: true);
      if (right <= left) return;
      canvas.drawRect(
        Rect.fromLTRB(left, top, right, top + barHeight),
        Paint()..color = color,
      );
    }

    segment(start, lectureEnd, lecture);
    for (final span in exams) {
      segment(span.start, span.end, exam);
    }
    for (final span in breaks) {
      segment(span.start, span.end, pause);
    }
    canvas.restore();

    if (!today.isBefore(start) && !today.isAfter(end)) {
      final cx = (x(today) + x(today, endOfDay: true)) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx.clamp(3.0, size.width - 3.0), size.height / 2),
            width: 6,
            height: size.height,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = marker,
      );
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.start != start ||
      old.end != end ||
      old.today != today ||
      old.lecture != lecture ||
      old.track != track ||
      old.breaks != breaks ||
      old.exams != exams;
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({
    required this.entry,
    required this.date,
    required this.today,
  });

  final CalendarEntry entry;
  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final active = entry.stateOn(today) == CalendarEntryState.active;
    final days = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    final urgent = active && days <= 7;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DateBlock(
            date: date,
            background: active ? null : scheme.surfaceContainerHighest,
            foreground: active ? null : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                TonalPill(
                  dense: true,
                  icon: active
                      ? Icons.hourglass_bottom_rounded
                      : Icons.schedule_rounded,
                  label: active
                      ? (days == 0
                          ? l10n.get('endsToday')
                          : l10n
                              .get('daysRemaining')
                              .replaceAll('{n}', '$days'))
                      : l10n.inDays(days),
                  background: urgent
                      ? scheme.errorContainer
                      : active
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                  foreground: urgent
                      ? scheme.onErrorContainer
                      : active
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.today,
    required this.onOpen,
  });

  final CalendarEntry entry;
  final DateTime today;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final state = entry.stateOn(today);
    final past = state == CalendarEntryState.past;
    final active = state == CalendarEntryState.active;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: past ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.text,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: past
                          ? scheme.onSurfaceVariant
                          : onOpen != null
                              ? scheme.primary
                              : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (active)
              TonalPill(
                dense: true,
                label: l10n.get('now'),
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              )
            else if (past)
              Icon(Icons.check_rounded, size: 18, color: scheme.outline)
            else if (onOpen != null)
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
