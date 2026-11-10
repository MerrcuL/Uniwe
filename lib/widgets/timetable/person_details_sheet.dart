import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/lecture_details.dart';
import '../../models/person_details.dart';
import '../../screens/lsf_browser_screen.dart';
import '../../services/auth_service.dart';
import '../../services/haptic_service.dart';
import '../../services/settings_service.dart';
import '../app_sheet.dart';
import '../expressive.dart';

/// Opens the details of [lecturer] in a modal bottom sheet.
Future<void> showPersonDetails(BuildContext context, Lecturer lecturer) {
  return showAppSheet<void>(
    context,
    builder: (_) => _PersonDetailsSheet(lecturer: lecturer),
  );
}

class _PersonDetailsSheet extends StatefulWidget {
  const _PersonDetailsSheet({required this.lecturer});

  final Lecturer lecturer;

  @override
  State<_PersonDetailsSheet> createState() => _PersonDetailsSheetState();
}

class _PersonDetailsSheetState extends State<_PersonDetailsSheet> {
  Future<PersonDetails?>? _details;

  @override
  void initState() {
    super.initState();
    final personId = widget.lecturer.personId;
    if (personId != null) {
      _details = context
          .read<AuthService>()
          .fetchPersonDetails(personId)
          .then<PersonDetails?>((d) => d)
          .catchError((Object _) => null);
    }
  }

  void _openInLsf() {
    final personId = widget.lecturer.personId;
    if (personId == null) return;
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LsfBrowserScreen(personId: personId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return AnimatedSize(
      duration: Durations.long2,
      curve: Curves.easeInOutCubicEmphasized,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.lecturer.personId == null) ...[
                Text(
                  widget.lecturer.name,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                TonalPill(
                  label: l10n.get('detailLecturer'),
                  icon: Icons.person_outline_rounded,
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
                const SizedBox(height: 16),
                InfoBanner(
                  icon: Icons.info_outline_rounded,
                  text: l10n.get('detailsUnavailable'),
                ),
              ] else
                FutureBuilder<PersonDetails?>(
                  future: _details,
                  builder: (context, snapshot) {
                    final done =
                        snapshot.connectionState == ConnectionState.done;
                    final details = snapshot.data;
                    final displayName =
                        details?.displayName ?? widget.lecturer.name;

                    final Widget stateChild;
                    if (!done) {
                      stateChild = const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: ExpressiveLoadingIndicator(size: 40),
                        ),
                      );
                    } else if (details == null) {
                      stateChild = Padding(
                        key: const ValueKey('error'),
                        padding: const EdgeInsets.only(top: 16),
                        child: InfoBanner(
                          icon: Icons.cloud_off_outlined,
                          text: l10n.get('detailsUnavailable'),
                        ),
                      );
                    } else {
                      stateChild = _PersonDetailsContent(
                        key: const ValueKey('loaded'),
                        details: details,
                        onOpenInLsf: _openInLsf,
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.headlineSmall,
                        ),
                        AnimatedSwitcher(
                          duration: Durations.medium4,
                          reverseDuration: Durations.short4,
                          switchInCurve: Easing.emphasizedDecelerate,
                          switchOutCurve: Easing.emphasizedAccelerate,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.03),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: stateChild,
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonDetailsContent extends StatelessWidget {
  const _PersonDetailsContent({
    super.key,
    required this.details,
    required this.onOpenInLsf,
  });

  final PersonDetails details;
  final VoidCallback onOpenInLsf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final status = details.status;

    final contactRows = [
      if (details.email != null)
        _PersonInfoRow(
          icon: Icons.mail_outline_rounded,
          label: l10n.get('detailEmail'),
          value: details.email!,
          onTap: () {
            launchUrl(Uri.parse('mailto:${details.email}'));
          },
        ),
      if (details.phone != null)
        _PersonInfoRow(
          icon: Icons.phone_outlined,
          label: l10n.get('phone'),
          value: details.phone!,
          onTap: () {
            launchUrl(Uri.parse('tel:${details.phone}'));
          },
        ),
      if (details.office != null)
        _PersonInfoRow(
          icon: Icons.meeting_room_outlined,
          label: l10n.get('office'),
          value: details.office!,
        ),
      if (details.address != null)
        _PersonInfoRow(
          icon: Icons.location_on_outlined,
          label: l10n.get('address'),
          value: details.address!,
        ),
      if (details.consultationHours != null)
        _PersonInfoRow(
          icon: Icons.schedule_outlined,
          label: l10n.get('consultationHours'),
          value: details.consultationHours!,
        ),
      if (details.homepage != null)
        _PersonInfoRow(
          icon: Icons.language_rounded,
          label: l10n.get('homepage'),
          value: details.homepage!.toString(),
          onTap: () {
            launchUrl(
              details.homepage!,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null || details.remark != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (status != null)
                  TonalPill(
                    label: status,
                    icon: Icons.badge_outlined,
                    background: scheme.primaryContainer,
                    foreground: scheme.onPrimaryContainer,
                  ),
                if (details.remark != null)
                  TonalPill(
                    label: details.remark!,
                    icon: Icons.info_outline_rounded,
                    background: scheme.surfaceContainerHighest,
                    foreground: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        if (contactRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          ListGroup(children: contactRows),
        ],
        if (details.functions.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader(
            l10n.get('rolesAndFunctions'),
            icon: Icons.work_outline_rounded,
          ),
          const SizedBox(height: 8),
          ListGroup(
            children: [
              for (final fn in details.functions)
                _PersonInfoRow(
                  icon: Icons.account_balance_outlined,
                  label: fn.institution,
                  value: fn.role,
                ),
            ],
          ),
        ],
        if (details.courses.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader(
            l10n.get('courses'),
            icon: Icons.school_outlined,
          ),
          const SizedBox(height: 8),
          ListGroup(
            children: [
              for (final course in details.courses)
                _PersonInfoRow(
                  icon: Icons.class_outlined,
                  label: course.semester,
                  value: course.title,
                  onTap: course.lectureId != null
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LsfBrowserScreen(
                                publishId: course.lectureId,
                              ),
                            ),
                          );
                        }
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onOpenInLsf,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(l10n.get('openInLsf')),
        ),
      ],
    );
  }
}

class _PersonInfoRow extends StatelessWidget {
  const _PersonInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
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
