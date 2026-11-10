import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import 'certificates_screen.dart';
import 'email_screen.dart';
import 'grades_screen.dart';
import 'login_screen.dart';
import 'lsf_browser_screen.dart';
import 'moodle_screen.dart';
import 'settings_screen.dart';

/// The "menu" destination: every part of the app that has no tab of its own,
/// with the settings pinned to the bottom.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _haptic(BuildContext context) =>
      HapticService.confirm(context.read<SettingsService>().hapticsEnabled);

  /// Opens a page that needs the HTW account, offering to sign in first.
  Future<void> _openSignedIn(BuildContext context, WidgetBuilder page) async {
    _haptic(context);
    final navigator = Navigator.of(context);
    if (!context.read<AuthService>().isAuthenticated) {
      final signedIn = await showLoginDialog(context);
      if (!signedIn) return;
    }
    navigator.push(MaterialPageRoute(builder: page));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = AppSpacing.gutter(context);
    final emailInNavBar =
        context.select<SettingsService, bool>((s) => s.emailInNavBar);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('menu'))),
      // Settings sit at the bottom of the screen while there is room; on
      // short windows the whole menu scrolls instead.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                0,
                gutter,
                AppSpacing.bottomInset(context, spacing: AppSpacing.md),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(l10n.get('services')),
                      ListGroup(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.school_outlined),
                            title: const Text('LSF'),
                            subtitle: Text(l10n.get('lsfSubtitle')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openSignedIn(
                              context,
                              (_) => const LsfBrowserScreen(),
                            ),
                          ),
                          if (!emailInNavBar)
                            ListTile(
                              leading: const Icon(Icons.mail_outline_rounded),
                              title: Text(l10n.get('email')),
                              subtitle: Text(l10n.get('emailSubtitle')),
                              trailing:
                                  const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                _haptic(context);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const EmailScreen(standalone: true),
                                  ),
                                );
                              },
                            ),
                          ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: const Text('Moodle'),
                            subtitle: Text(l10n.get('moodleSubtitle')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openSignedIn(
                              context,
                              (_) => const MoodleScreen(),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.grade_outlined),
                            title: Text(l10n.get('grades')),
                            subtitle: Text(l10n.get('gradesSubtitle')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openSignedIn(
                              context,
                              (_) => const GradesScreen(),
                            ),
                          ),
                          ListTile(
                            leading:
                                const Icon(Icons.workspace_premium_outlined),
                            title: Text(l10n.get('certificates')),
                            subtitle: Text(l10n.get('certificatesSubtitle')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openSignedIn(
                              context,
                              (_) => const CertificatesScreen(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: ListGroup(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: Text(l10n.get('settings')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            _haptic(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
