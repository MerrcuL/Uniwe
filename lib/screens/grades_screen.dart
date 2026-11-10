import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grades.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import '../widgets/grades/exam_details_sheet.dart';
import 'certificates_screen.dart';

/// The student's grades from LSF's "Noten- und Klassenspiegel": overall
/// standing, exams by semester (each with its grade distribution) and the
/// module groups.
class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  GradeReport? _report;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report = await context.read<AuthService>().fetchGrades();
      if (!mounted) return;
      setState(() {
        _report = report;
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

  void _openDetails(ExamResult result) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    showExamDetails(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('grades'))),
      body: AnimatedSwitcher(
        duration: AppMotion.effectsDefault,
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final report = _report;
    if (report == null) {
      if (!_hasError) return const LoadingState();
      return StatusMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorGrades'),
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

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
                text: l10n.get('errorGrades'),
              ),
            ),
          if (report.isEmpty)
            SizedBox(
              height: 360,
              child: StatusMessage(
                icon: Icons.grade_outlined,
                shape: SoftShape.flower,
                title: l10n.get('gradesEmpty'),
                message: l10n.get('gradesEmptyMessage'),
              ),
            )
          else ...[
            _Summary(report: report),
            for (final semester in report.bySemester) ...[
              SectionHeader(
                semester.key.isEmpty ? '—' : semester.key,
                icon: Icons.calendar_month_outlined,
              ),
              ListGroup(
                children: [
                  for (final result in semester.value)
                    _ResultTile(
                      result: result,
                      onTap: () => _openDetails(result),
                    ),
                ],
              ),
            ],
            if (report.groups.isNotEmpty) ...[
              SectionHeader(
                l10n.get('moduleGroups'),
                icon: Icons.account_tree_outlined,
              ),
              ListGroup(
                children: [
                  for (final group in report.groups) _ResultTile(result: group),
                ],
              ),
            ],
          ],
          const SizedBox(height: 24),
          ListGroup(
            children: [
              ListTile(
                leading: Icon(
                  Icons.workspace_premium_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(l10n.get('allDocuments')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticService.confirm(
                    context.read<SettingsService>().hapticsEnabled,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CertificatesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Degree programme, LSF's overall average, credits and passed exams.
class _Summary extends StatelessWidget {
  const _Summary({required this.report});

  final GradeReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final passed =
        report.results.where((r) => r.status == ExamStatus.passed).length;
    final average = report.average;
    final credits = report.credits;

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

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppShapes.extraLarge),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final program in report.programs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.school_outlined,
                      size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      program,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (average != null) figure(average, l10n.get('gradeAverage')),
              if (credits != null) figure(credits, l10n.get('creditsEarned')),
              figure('$passed', l10n.get('examsPassed')),
            ],
          ),
        ],
      ),
    );
  }
}

/// One exam or module group: the grade in a tonal block, name and facts
/// beside it. Exams open their details on tap.
class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, this.onTap});

  final ExamResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final facts = [
      if (result.isGroup) l10n.get('moduleGroup'),
      if (!result.isGroup && result.number.isNotEmpty)
        l10n.get('examNumber').replaceAll('{n}', result.number),
      if (result.date.isNotEmpty) result.date,
      if (result.credits.isNotEmpty)
        l10n.get('ectsValue').replaceAll('{n}', result.credits),
      if (result.attempt.isNotEmpty && result.attempt != '1')
        l10n.get('examAttempt').replaceAll('{n}', result.attempt),
    ].join(' · ');

    // A pass is evident from the grade; call out everything else.
    final statusText = switch (result.status) {
      ExamStatus.passed => null,
      ExamStatus.failed => l10n.get('examFailed'),
      ExamStatus.other =>
        result.statusLabel.isEmpty ? null : result.statusLabel,
    };
    final failed = result.status == ExamStatus.failed;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            GradeBlock(result: result),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.name, style: theme.textTheme.titleMedium),
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
                  if (statusText != null || result.remark.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (statusText != null)
                            TonalPill(
                              label: statusText,
                              dense: true,
                              background: failed
                                  ? scheme.errorContainer
                                  : scheme.surfaceContainerHighest,
                              foreground: failed
                                  ? scheme.onErrorContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          if (result.remark.isNotEmpty)
                            TonalPill(
                              label: remarkLabel(result.remark, l10n),
                              dense: true,
                              background: scheme.secondaryContainer,
                              foreground: scheme.onSecondaryContainer,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
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
