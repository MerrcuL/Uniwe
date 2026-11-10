import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/grades.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../app_sheet.dart';
import '../expressive.dart';

/// A readable label for LSF's remark codes ("FNB" → "Free attempt").
String remarkLabel(String code, AppLocalizations l10n) {
  final key = 'remark$code';
  final label = l10n.get(key);
  return label == key ? code : label;
}

/// Opens the details of [result] with the grade distribution of its exam.
///
/// The sheet shows what the overview already knows at once and loads the
/// distribution in place.
Future<void> showExamDetails(BuildContext context, ExamResult result) {
  return showAppSheet<void>(
    context,
    builder: (_) => _ExamDetailsSheet(result: result),
  );
}

class _ExamDetailsSheet extends StatefulWidget {
  const _ExamDetailsSheet({required this.result});

  final ExamResult result;

  @override
  State<_ExamDetailsSheet> createState() => _ExamDetailsSheetState();
}

class _ExamDetailsSheetState extends State<_ExamDetailsSheet> {
  Future<GradeDistribution?>? _distribution;

  @override
  void initState() {
    super.initState();
    if (widget.result.distributionUrl != null) {
      _distribution = context
          .read<AuthService>()
          .fetchDistribution(widget.result)
          .then<GradeDistribution?>((d) => d)
          .catchError((Object _) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final result = widget.result;
    final failed = result.status == ExamStatus.failed;

    final rows = [
      if (result.semester.isNotEmpty)
        _InfoRow(
          icon: Icons.calendar_month_outlined,
          label: l10n.get('detailSemester'),
          value: result.semester,
        ),
      if (result.date.isNotEmpty)
        _InfoRow(
          icon: Icons.event_outlined,
          label: l10n.get('detailExamDate'),
          value: result.date,
        ),
      if (result.credits.isNotEmpty)
        _InfoRow(
          icon: Icons.stars_outlined,
          label: l10n.get('creditsEarned'),
          value: result.credits,
        ),
      if (result.attempt.isNotEmpty)
        _InfoRow(
          icon: Icons.replay_rounded,
          label: l10n.get('detailAttempt'),
          value: result.attempt,
        ),
      if (result.remark.isNotEmpty)
        _InfoRow(
          icon: Icons.info_outline_rounded,
          label: l10n.get('detailRemark'),
          value: remarkLabel(result.remark, l10n),
        ),
      if (result.number.isNotEmpty)
        _InfoRow(
          icon: Icons.tag_rounded,
          label: l10n.get('detailExamNumber'),
          value: result.number,
        ),
    ];

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
            Row(
              children: [
                GradeBlock(result: result, size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TonalPill(
                            label: switch (result.status) {
                              ExamStatus.passed => l10n.get('examPassed'),
                              ExamStatus.failed => l10n.get('examFailed'),
                              ExamStatus.other => result.statusLabel,
                            },
                            background: failed
                                ? scheme.errorContainer
                                : scheme.secondaryContainer,
                            foreground: failed
                                ? scheme.onErrorContainer
                                : scheme.onSecondaryContainer,
                          ),
                          if (result.credits.isNotEmpty)
                            TonalPill(
                              label: l10n
                                  .get('ectsValue')
                                  .replaceAll('{n}', result.credits),
                              background: scheme.surfaceContainerHighest,
                              foreground: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_distribution != null)
              AnimatedSize(
                duration: Durations.long2,
                curve: Curves.easeInOutCubicEmphasized,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: FutureBuilder<GradeDistribution?>(
                  future: _distribution,
                  builder: (context, snapshot) {
                    final Widget stateChild;
                    if (snapshot.connectionState != ConnectionState.done) {
                      stateChild = const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: ExpressiveLoadingIndicator(size: 40),
                        ),
                      );
                    } else {
                      final distribution = snapshot.data;
                      if (distribution == null) {
                        stateChild = Padding(
                          key: const ValueKey('error'),
                          padding: const EdgeInsets.only(top: 16),
                          child: InfoBanner(
                            icon: Icons.bar_chart_rounded,
                            text: l10n.get('distributionUnavailable'),
                          ),
                        );
                      } else {
                        stateChild = Padding(
                          key: const ValueKey('loaded'),
                          padding: const EdgeInsets.only(top: 20),
                          child: DistributionChart(
                            distribution: distribution,
                            yourGrade: result.grade,
                          ),
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
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 20),
              ListGroup(children: rows),
            ],
          ],
        ),
      ),
    );
  }
}

/// The grade in a tonal block: red for a failed exam, the soft accent
/// otherwise, a check mark for passes without a grade.
class GradeBlock extends StatelessWidget {
  const GradeBlock({super.key, required this.result, this.size = 64});

  final ExamResult result;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = result.status == ExamStatus.failed;
    final background = failed
        ? scheme.errorContainer
        : result.isGroup
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer;
    final foreground = failed
        ? scheme.onErrorContainer
        : result.isGroup
            ? scheme.onSurfaceVariant
            : scheme.onPrimaryContainer;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: result.grade.isEmpty
          ? Icon(
              failed
                  ? Icons.close_rounded
                  : result.status == ExamStatus.passed
                      ? Icons.check_rounded
                      : Icons.more_horiz_rounded,
              color: foreground,
            )
          : FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  result.grade,
                  style: (size >= 72
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleLarge)
                      ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
                ),
              ),
            ),
    );
  }
}

/// Horizontal bars, one per grade band, with the student's own band
/// highlighted; participants and class average below.
class DistributionChart extends StatelessWidget {
  const DistributionChart({
    super.key,
    required this.distribution,
    required this.yourGrade,
  });

  final GradeDistribution distribution;
  final String yourGrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final maxCount = distribution.maxCount;
    final participants = distribution.participants;
    final average = distribution.average;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppShapes.largeIncreased),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.get('gradeDistribution'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (participants != null)
                Text(
                  l10n.get('participants').replaceAll('{n}', '$participants'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final band in distribution.bands)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _BandBar(band: band, maxCount: maxCount),
            ),
          if (average != null || yourGrade.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Row(
              children: [
                if (yourGrade.isNotEmpty)
                  Expanded(
                    child: _Figure(
                      value: yourGrade,
                      label: l10n.get('yourGrade'),
                      color: scheme.primary,
                    ),
                  ),
                if (average != null)
                  Expanded(
                    child: _Figure(
                      value: average,
                      label: l10n.get('classAverage'),
                      color: scheme.onSurface,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BandBar extends StatelessWidget {
  const _BandBar({required this.band, required this.maxCount});

  final GradeBand band;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final mine = band.includesYou;
    final nameKey = band.nameKey;
    final name = nameKey == null ? band.label : l10n.get(nameKey);
    final fraction = maxCount == 0 ? 0.0 : band.count / maxCount;
    final barColor = mine ? scheme.primary : scheme.secondaryContainer;

    return Semantics(
      label: '$name ${band.range}: ${band.count}'
          '${mine ? ', ${l10n.get('you')}' : ''}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Long names ("Nicht ausreichend") shrink instead of
                // being cut off.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: mine ? FontWeight.w700 : null,
                      color: mine ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  band.range,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: AppMotion.spatialDefault,
                  curve: Easing.emphasizedDecelerate,
                  builder: (context, value, _) => Container(
                    height: 24,
                    // A sliver stays visible for empty bands.
                    width: 6 + (constraints.maxWidth - 6) * value,
                    decoration: BoxDecoration(
                      color: band.count == 0
                          ? scheme.surfaceContainerHighest
                          : barColor,
                      borderRadius: AppShapes.smallRadius,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (mine) ...[
                  Icon(Icons.person_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 2),
                ],
                Text(
                  '${band.count}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: mine ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
