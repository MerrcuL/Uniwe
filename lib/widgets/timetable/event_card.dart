import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/timetable_event.dart';
import '../../theme/app_theme.dart';
import '../../utils/timetable_text.dart';
import '../expressive.dart';

/// One class in the day list.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.compact,
    required this.onTap,
  });

  final TimetableEvent event;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    final isExam = event.isExam;

    // Exams take the error roles for the whole card so they cannot be missed.
    final cardColor = isExam ? scheme.errorContainer : scheme.surfaceContainer;
    final onCard = isExam ? scheme.onErrorContainer : scheme.onSurface;
    final onCardMuted =
        isExam ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    final accent = isExam ? scheme.error : scheme.primary;
    final timeColor = isExam ? scheme.error : scheme.primaryContainer;
    final onTime = isExam ? scheme.onError : scheme.onPrimaryContainer;

    final typeLabel = TimetableText.eventType(event, l10n);
    final frequency = TimetableText.frequency(event.frequency, l10n);

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Row(
            children: [
              _TimeBlock(
                start: event.startLabel,
                end: event.endLabel,
                background: timeColor,
                foreground: onTime,
                compact: compact,
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.cleanTitle,
                      style: (compact ? text.titleSmall : text.titleMedium)
                          ?.copyWith(color: onCard),
                      maxLines: compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (event.room.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _IconLine(
                        icon: Icons.location_on_outlined,
                        label: event.room,
                        iconColor: accent,
                        textColor: onCardMuted,
                        dense: compact,
                      ),
                    ],
                    if (!compact) ...[
                      if (typeLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _IconLine(
                          icon: isExam
                              ? Icons.assignment_late_outlined
                              : Icons.class_outlined,
                          label: typeLabel,
                          iconColor: accent,
                          textColor: onCardMuted,
                        ),
                      ],
                      if (frequency.isNotEmpty || event.isOverlapping) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (frequency.isNotEmpty)
                              TonalPill(
                                label: frequency,
                                icon: Icons.repeat_rounded,
                                background: isExam
                                    ? scheme.surface
                                    : scheme.surfaceContainerHighest,
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
                      ],
                    ] else if (event.isOverlapping) ...[
                      const SizedBox(height: 6),
                      TonalPill(
                        dense: true,
                        label: l10n.get('overlappingLabel'),
                        background: semantic.warningContainer,
                        foreground: semantic.onWarningContainer,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.start,
    required this.end,
    required this.background,
    required this.foreground,
    required this.compact,
  });

  final String start;
  final String end;
  final Color background;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: compact ? 64 : 72,
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12, horizontal: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.largeRadius,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              start,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: (compact ? text.titleSmall : text.titleMedium)
                  ?.copyWith(color: foreground),
            ),
            if (end.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Container(
                  width: 12,
                  height: 2,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Text(
                end,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: (compact ? text.titleSmall : text.titleMedium)
                    ?.copyWith(color: foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: dense ? 14 : 16, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: (dense ? text.bodySmall : text.bodyMedium)
                ?.copyWith(color: textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The "45 min break" marker between two classes.
class BreakIndicator extends StatelessWidget {
  const BreakIndicator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_food_beverage_outlined, size: 14, color: color),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
