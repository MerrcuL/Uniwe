import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/lecture_details.dart';
import '../../models/timetable_event.dart';
import '../../screens/lsf_browser_screen.dart';
import '../../services/auth_service.dart';
import '../../services/haptic_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/timetable_text.dart';
import '../app_sheet.dart';
import '../expressive.dart';
import 'person_details_sheet.dart';

/// Opens the details of [event] in a modal bottom sheet.
///
/// The sheet appears immediately with what the timetable already knows and
/// loads lecturer, credits and exam dates from LSF in place — tapping an
/// event never waits on the network.
Future<void> showEventDetails(BuildContext context, TimetableEvent event) {
  return showAppSheet<void>(
    context,
    builder: (_) => _EventDetailsSheet(event: event),
  );
}

class _EventDetailsSheet extends StatefulWidget {
  const _EventDetailsSheet({required this.event});

  final TimetableEvent event;

  @override
  State<_EventDetailsSheet> createState() => _EventDetailsSheetState();
}

class _EventDetailsSheetState extends State<_EventDetailsSheet> {
  Future<LectureDetails?>? _details;

  @override
  void initState() {
    super.initState();
    final publishId = widget.event.publishId;
    if (publishId != null) {
      _details = context
          .read<AuthService>()
          .fetchLectureDetails(publishId)
          .then<LectureDetails?>((details) => details)
          .catchError((Object _) => null);
    }
  }

  void _openInLsf() {
    final publishId = widget.event.publishId;
    if (publishId == null) return;
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => LsfBrowserScreen(publishId: publishId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final event = widget.event;

    final type = TimetableText.eventType(event, l10n);
    final frequency = TimetableText.frequency(event.frequency, l10n);
    final timeLine = [
      if (event.day.isNotEmpty) event.day,
      if (event.time.isNotEmpty) event.time,
    ].join(', ');

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(event.cleanTitle, style: theme.textTheme.headlineSmall),
            if (type.isNotEmpty || frequency.isNotEmpty || event.isOverlapping)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (type.isNotEmpty)
                      TonalPill(
                        label: type,
                        icon: event.isExam
                            ? Icons.assignment_late_outlined
                            : Icons.class_outlined,
                        background: event.isExam
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        foreground: event.isExam
                            ? scheme.onErrorContainer
                            : scheme.onPrimaryContainer,
                      ),
                    if (frequency.isNotEmpty)
                      TonalPill(
                        label: frequency,
                        icon: Icons.repeat_rounded,
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurfaceVariant,
                      ),
                    if (event.isOverlapping)
                      TonalPill(
                        label: l10n.get('overlappingLabel'),
                        icon: Icons.warning_amber_rounded,
                        background: semantic.warningContainer,
                        foreground: semantic.onWarningContainer,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            ListGroup(
              children: [
                if (timeLine.isNotEmpty)
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    label: l10n.get('detailTime'),
                    value: timeLine,
                  ),
                if (event.room.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: l10n.get('detailRoom'),
                    value: event.room,
                  ),
              ],
            ),
            if (_details != null)
              AnimatedSize(
                duration: Durations.long2,
                curve: Curves.easeInOutCubicEmphasized,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: FutureBuilder<LectureDetails?>(
                  future: _details,
                  builder: (context, snapshot) {
                    final Widget stateChild;
                    if (snapshot.connectionState != ConnectionState.done) {
                      stateChild = const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.only(top: 20),
                        child: Center(
                          child: ExpressiveLoadingIndicator(size: 40),
                        ),
                      );
                    } else {
                      final details = snapshot.data;
                      if (details == null) {
                        stateChild = Padding(
                          key: const ValueKey('error'),
                          padding: const EdgeInsets.only(top: 12),
                          child: InfoBanner(
                            icon: Icons.cloud_off_outlined,
                            text: l10n.get('detailsUnavailable'),
                          ),
                        );
                      } else if (details.isEmpty) {
                        stateChild = const SizedBox(
                          key: ValueKey('empty'),
                          width: double.infinity,
                        );
                      } else {
                        stateChild = _ExtraDetails(
                          key: const ValueKey('loaded'),
                          details: details,
                        );
                      }
                    }

                    return AnimatedSwitcher(
                      duration: Durations.medium4,
                      reverseDuration: Durations.short4,
                      switchInCurve: Easing.emphasizedDecelerate,
                      switchOutCurve: Easing.emphasizedAccelerate,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: stateChild,
                    );
                  },
                ),
              ),
            if (event.publishId != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openInLsf,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.get('openInLsf')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lecturer, credits and exam dates, once they have arrived from LSF.
class _ExtraDetails extends StatelessWidget {
  const _ExtraDetails({super.key, required this.details});

  final LectureDetails details;

  void _onTeacherTap(BuildContext context) {
    HapticService.selection(context.read<SettingsService>().hapticsEnabled);
    if (details.teachers.length == 1) {
      showPersonDetails(context, details.teachers.first);
    } else {
      _showLecturerPicker(context, details.teachers);
    }
  }

  void _showLecturerPicker(BuildContext context, List<Lecturer> teachers) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    showAppSheet<void>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.get('selectLecturer'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListGroup(
              children: [
                for (final teacher in teachers)
                  _InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: teacher.personId != null
                        ? l10n.get('detailLecturer')
                        : '',
                    value: teacher.name,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showPersonDetails(context, teacher);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final teacherNames = details.teachers.map((t) => t.name).join(', ');

    final rows = [
      if (details.teachers.isNotEmpty)
        _InfoRow(
          icon: Icons.person_outline_rounded,
          label: l10n.get('detailLecturer'),
          value: teacherNames,
          onTap: () => _onTeacherTap(context),
        ),
      if (details.credits != null)
        _InfoRow(
          icon: Icons.stars_outlined,
          label: l10n.get('credits'),
          value: details.credits!,
        ),
      if (details.sws != null)
        _InfoRow(
          icon: Icons.hourglass_empty_rounded,
          label: l10n.get('sws'),
          value: details.sws!,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          ListGroup(children: rows),
        ],
        if (details.examDates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l10n.get('examDetailHeader'),
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: 8),
          ListGroup(
            children: [
              for (final exam in details.examDates)
                _InfoRow(
                  icon: Icons.event_outlined,
                  iconColor: scheme.error,
                  label: [exam.day, exam.date]
                      .where((s) => s.isNotEmpty)
                      .join(', '),
                  value: exam.time,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One fact in a [ListGroup]: a small caption above its value.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? scheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (value.isNotEmpty)
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              size: 20,
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }
    return content;
  }
}
