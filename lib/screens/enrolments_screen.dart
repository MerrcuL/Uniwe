import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/enrolment.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/expressive.dart';
import '../widgets/info_widgets.dart';
import 'lsf_browser_screen.dart';

/// LSF's wording of an enrolment state in the app language.
String enrolmentStatusLabel(EnrolmentStatus status, AppLocalizations l10n) {
  final lower = status.label.toLowerCase();
  if (lower.contains('zugelassen')) return l10n.get('enrolAdmitted');
  if (lower.contains('abgelehnt')) return l10n.get('enrolRejected');
  if (lower.contains('angemeldet')) return l10n.get('enrolRegistered');
  if (lower.contains('storniert') || lower.contains('abgemeldet')) {
    return l10n.get('enrolWithdrawn');
  }
  return status.label;
}

/// The courses of the current semester and whether the student got a place
/// in them ("Belegübersicht").
class EnrolmentsScreen extends StatefulWidget {
  const EnrolmentsScreen({super.key});

  @override
  State<EnrolmentsScreen> createState() => _EnrolmentsScreenState();
}

class _EnrolmentsScreenState extends State<EnrolmentsScreen> {
  List<Enrolment>? _enrolments;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _enrolments = _readCache();
    _load();
  }

  static List<Enrolment>? _readCache() {
    final data = CacheService.instance.read(CacheService.enrolmentsKey).data;
    if (data is! List) return null;
    try {
      return [
        for (final e in data)
          Enrolment.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final enrolments = await context.read<AuthService>().fetchEnrolments();
      unawaited(CacheService.instance.save(
        CacheService.enrolmentsKey,
        [for (final e in enrolments) e.toJson()],
      ));
      if (!mounted) return;
      setState(() {
        _enrolments = enrolments;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  void _retry() {
    setState(() => _hasError = false);
    _load();
  }

  void _open(Enrolment enrolment) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    showAppSheet<void>(
      context,
      builder: (_) => _EnrolmentSheet(enrolment: enrolment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('enrolments'))),
      body: AnimatedSwitcher(
        duration: AppMotion.effectsDefault,
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final enrolments = _enrolments;
    if (enrolments == null) {
      if (!_hasError) return const LoadingState();
      return StatusMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorEnrolments'),
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    final bySemester = <String, List<Enrolment>>{};
    for (final e in enrolments) {
      (bySemester[e.semester] ??= []).add(e);
    }
    final admitted =
        enrolments.where((e) => e.status?.positive ?? false).length;
    final gutter = AppSpacing.gutter(context);

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
                text: l10n.get('errorEnrolments'),
              ),
            ),
          if (enrolments.isEmpty)
            SizedBox(
              height: 400,
              child: StatusMessage(
                icon: Icons.fact_check_outlined,
                shape: SoftShape.flower,
                title: l10n.get('enrolmentsEmpty'),
                message: l10n.get('enrolmentsEmptyMessage'),
              ),
            )
          else ...[
            _Summary(total: enrolments.length, admitted: admitted),
            for (final entry in bySemester.entries) ...[
              SectionHeader(
                entry.key.isEmpty ? '—' : entry.key,
                icon: Icons.calendar_month_outlined,
              ),
              ListGroup(
                children: [
                  for (final enrolment in entry.value)
                    _EnrolmentTile(
                      enrolment: enrolment,
                      onTap: () => _open(enrolment),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.admitted});

  final int total;
  final int admitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    Widget figure(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        );

    return SummaryCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          figure('$total', l10n.get('enrolCourses')),
          figure('$admitted', l10n.get('enrolAdmitted')),
          if (total - admitted > 0)
            figure('${total - admitted}', l10n.get('enrolOpen')),
        ],
      ),
    );
  }
}

({Color background, Color foreground, IconData icon}) _statusStyle(
  BuildContext context,
  EnrolmentStatus? status,
) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = SemanticColors.of(context);
  if (status == null) {
    return (
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      icon: Icons.more_horiz_rounded,
    );
  }
  if (status.positive) {
    return (
      background: semantic.successContainer,
      foreground: semantic.onSuccessContainer,
      icon: Icons.check_rounded,
    );
  }
  if (status.isRejected) {
    return (
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      icon: Icons.close_rounded,
    );
  }
  return (
    background: semantic.warningContainer,
    foreground: semantic.onWarningContainer,
    icon: Icons.hourglass_top_rounded,
  );
}

class _EnrolmentTile extends StatelessWidget {
  const _EnrolmentTile({required this.enrolment, required this.onTap});

  final Enrolment enrolment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final status = enrolment.status;
    final style = _statusStyle(context, status);

    final facts = [
      if (status != null && status.group.isNotEmpty) status.group,
      if (enrolment.number.isNotEmpty) enrolment.number,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: AppShapes.largeRadius,
              ),
              child: Icon(style.icon, color: style.foreground),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(enrolment.title, style: theme.textTheme.titleMedium),
                  if (facts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        facts,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TonalPill(
                        dense: true,
                        label: enrolmentStatusLabel(status, l10n),
                        background: style.background,
                        foreground: style.foreground,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything LSF knows about one enrolment: its states and the dates of
/// the course.
class _EnrolmentSheet extends StatelessWidget {
  const _EnrolmentSheet({required this.enrolment});

  final Enrolment enrolment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final publishId = enrolment.publishId;

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
            Text(enrolment.title, style: theme.textTheme.headlineSmall),
            if (enrolment.number.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  enrolment.number,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (enrolment.statuses.isNotEmpty) ...[
              const SizedBox(height: 16),
              ListGroup(
                children: [
                  for (final status in enrolment.statuses)
                    Builder(builder: (context) {
                      final style = _statusStyle(context, status);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: style.background,
                          foregroundColor: style.foreground,
                          child: Icon(style.icon),
                        ),
                        title: Text(enrolmentStatusLabel(status, l10n)),
                        subtitle: Text([
                          if (status.group.isNotEmpty) status.group,
                          if (status.date.isNotEmpty) status.date,
                        ].join(' · ')),
                      );
                    }),
                ],
              ),
            ],
            if (enrolment.dates.isNotEmpty) ...[
              SectionHeader(
                l10n.get('enrolDates'),
                icon: Icons.schedule_outlined,
              ),
              ListGroup(
                children: [
                  for (final date in enrolment.dates) _DateRow(date: date),
                ],
              ),
            ],
            if (publishId != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: () {
                  HapticService.confirm(
                    context.read<SettingsService>().hapticsEnabled,
                  );
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => LsfBrowserScreen(publishId: publishId),
                    ),
                  );
                },
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

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date});

  final EnrolmentDate date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = SemanticColors.of(context);
    final when = [
      if (date.day.isNotEmpty) date.day,
      if (date.time.isNotEmpty) date.time,
    ].join(' ');
    final cancelled = date.note.toLowerCase().contains('aus');
    final details = [
      if (date.rhythm.isNotEmpty) date.rhythm,
      if (date.duration.isNotEmpty) date.duration,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  when.isEmpty ? '—' : when,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (date.note.isNotEmpty)
                TonalPill(
                  dense: true,
                  label: date.note,
                  background: cancelled
                      ? scheme.errorContainer
                      : semantic.successContainer,
                  foreground: cancelled
                      ? scheme.onErrorContainer
                      : semantic.onSuccessContainer,
                ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                details,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (date.room.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: IconLine(
                icon: Icons.location_on_outlined,
                label: date.room,
              ),
            ),
          if (date.lecturer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconLine(
                icon: Icons.person_outline_rounded,
                label: date.lecturer,
              ),
            ),
        ],
      ),
    );
  }
}
