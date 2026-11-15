import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/registered_exam.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/home_widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import '../widgets/expressive.dart';
import '../widgets/info_widgets.dart';

/// The exams the student is registered for ("Angemeldete Prüfungen"), with
/// a countdown to the next one.
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  ExamRegistrations? _registrations;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _registrations = _readCache();
    _load();
  }

  static ExamRegistrations? _readCache() {
    final data = CacheService.instance.read(CacheService.examsKey).data;
    if (data is! Map) return null;
    try {
      return ExamRegistrations.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final registrations =
          await context.read<AuthService>().fetchRegisteredExams();
      unawaited(CacheService.instance
          .save(CacheService.examsKey, registrations.toJson()));
      unawaited(HomeWidgetService.instance.sync());
      if (!mounted) return;
      setState(() {
        _registrations = registrations;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('registeredExams'))),
      body: AnimatedSwitcher(
        duration: AppMotion.effectsDefault,
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final registrations = _registrations;
    if (registrations == null) {
      if (!_hasError) return const LoadingState();
      return StatusMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorExams'),
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    final today = Dates.today();
    final upcoming = registrations.upcoming(today);
    final past = registrations.past(today);
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
                text: l10n.get('errorExams'),
              ),
            ),
          if (registrations.exams.isEmpty)
            SizedBox(
              height: 400,
              child: StatusMessage(
                icon: Icons.assignment_outlined,
                shape: SoftShape.flower,
                title: l10n.get('examsEmpty'),
                message: [
                  l10n.get('examsEmptyMessage'),
                  ...registrations.programs,
                ].join('\n\n'),
              ),
            )
          else ...[
            if (upcoming.isNotEmpty)
              _NextExamCard(exam: upcoming.first, today: today),
            if (upcoming.isNotEmpty) ...[
              SectionHeader(
                l10n.get('examsUpcoming'),
                icon: Icons.event_outlined,
              ),
              ListGroup(
                children: [
                  for (final exam in upcoming)
                    _ExamTile(exam: exam, today: today),
                ],
              ),
            ],
            if (past.isNotEmpty) ...[
              SectionHeader(
                l10n.get('examsPast'),
                icon: Icons.history_rounded,
              ),
              ListGroup(
                children: [
                  for (final exam in past)
                    _ExamTile(exam: exam, today: today, past: true),
                ],
              ),
            ],
          ],
          FootNote(l10n.get('examsHint')),
        ],
      ),
    );
  }
}

/// The next exam, large: its name and how many days are left.
class _NextExamCard extends StatelessWidget {
  const _NextExamCard({required this.exam, required this.today});

  final RegisteredExam exam;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final days = exam.daysUntil(today);
    final day = exam.day;

    return SummaryCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('nextExam'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exam.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  day == null
                      ? l10n.get('examDateOpen')
                      : Formats.fullDate(day, locale),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (days != null) ...[
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$days',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                Text(
                  l10n.get(days == 1 ? 'dayLeft' : 'daysLeft'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
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

class _ExamTile extends StatelessWidget {
  const _ExamTile({
    required this.exam,
    required this.today,
    this.past = false,
  });

  final RegisteredExam exam;
  final DateTime today;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final days = exam.daysUntil(today);

    final facts = [
      if (exam.number.isNotEmpty)
        l10n.get('examNumber').replaceAll('{n}', exam.number),
      if (exam.examiner.isNotEmpty) exam.examiner,
      if (exam.semester.isNotEmpty) exam.semester,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DateBlock(
            date: exam.day,
            placeholder: Icons.hourglass_empty_rounded,
            background: past ? scheme.surfaceContainerHighest : null,
            foreground: past ? scheme.onSurfaceVariant : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam.name, style: theme.textTheme.titleMedium),
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
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!past)
                        TonalPill(
                          dense: true,
                          icon: Icons.schedule_rounded,
                          label: days == null
                              ? l10n.get('examDateOpen')
                              : l10n.inDays(days),
                          background: days != null && days <= 7
                              ? scheme.errorContainer
                              : scheme.secondaryContainer,
                          foreground: days != null && days <= 7
                              ? scheme.onErrorContainer
                              : scheme.onSecondaryContainer,
                        ),
                      if (exam.period.isNotEmpty)
                        TonalPill(
                          dense: true,
                          label: l10n
                              .get('examPeriod')
                              .replaceAll('{n}', exam.period),
                          background: scheme.surfaceContainerHighest,
                          foreground: scheme.onSurfaceVariant,
                        ),
                      if (exam.attempt.isNotEmpty && exam.attempt != '1')
                        TonalPill(
                          dense: true,
                          label: l10n
                              .get('examAttempt')
                              .replaceAll('{n}', exam.attempt),
                          background: scheme.surfaceContainerHighest,
                          foreground: scheme.onSurfaceVariant,
                        ),
                    ],
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
