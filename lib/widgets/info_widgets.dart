import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import 'expressive.dart';
import '../screens/login_screen.dart';

// Pieces shared by the LSF overview screens (exams, enrolments, cancelled
// classes, semester dates).

/// The hero card at the top of an overview: a large tonal container.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.child, this.color, this.onTap});

  final Widget child;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: color ?? scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppShapes.extraLarge)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );
  }
}

/// A day in a tonal block: "12" over "Feb". Without a [date] it shows
/// [placeholder] instead.
class DateBlock extends StatelessWidget {
  const DateBlock({
    super.key,
    required this.date,
    this.placeholder = Icons.event_outlined,
    this.background,
    this.foreground,
    this.size = 56,
  });

  final DateTime? date;
  final IconData placeholder;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final fg = foreground ?? scheme.onPrimaryContainer;
    final date = this.date;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size / 3.5),
      ),
      child: date == null
          ? Icon(placeholder, color: fg)
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${date.day}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: fg, height: 1.05),
                  ),
                  Text(
                    Formats.monthShort(date, locale),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A start and end time in a tonal block, as on the timetable cards.
class TimeBlock extends StatelessWidget {
  const TimeBlock({
    super.key,
    required this.start,
    required this.end,
    required this.background,
    required this.foreground,
  });

  final String start;
  final String end;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final style =
        Theme.of(context).textTheme.titleSmall?.copyWith(color: foreground);
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.largeRadius,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(start, maxLines: 1, softWrap: false, style: style),
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
              Text(end, maxLines: 1, softWrap: false, style: style),
            ],
          ],
        ),
      ),
    );
  }
}

/// An icon with a line of text, for the facts under a title.
class IconLine extends StatelessWidget {
  const IconLine({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: scheme.primary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color ?? scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small muted note under a list.
class FootNote extends StatelessWidget {
  const FootNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Shows [child] to a signed-in user and a sign-in prompt to everyone else.
///
/// Wraps the LSF screens when they are tabs of the navigation bar, where
/// (unlike in the menu) nothing asks to sign in before they open.
class SignedInGate extends StatelessWidget {
  const SignedInGate({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isAuthenticated =
        context.select<AuthService, bool>((a) => a.isAuthenticated);
    if (isAuthenticated) return child;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StatusMessage(
        icon: icon,
        title: l10n.get('loginRequired'),
        message: l10n.get('scheduleLoginPrompt'),
        action: FilledButton.icon(
          onPressed: () {
            HapticService.confirm(
              context.read<SettingsService>().hapticsEnabled,
            );
            showLoginDialog(context);
          },
          icon: const Icon(Icons.login_rounded),
          label: Text(l10n.get('loginButton')),
        ),
      ),
    );
  }
}
