import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import 'about_screen.dart';
import 'log_screen.dart';
import 'login_screen.dart';
import 'mensa_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();
    final gutter = AppSpacing.gutter(context);

    void selection() => HapticService.selection(settings.hapticsEnabled);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('settings'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            gutter, 0, gutter, AppSpacing.bottomInset(context, spacing: 32)),
        children: [
          const _AccountSection(),

          SectionHeader(l10n.get('language')),
          ConnectedButtonGroup<String>(
            items: [
              ButtonGroupItem(value: 'de', label: l10n.get('german')),
              ButtonGroupItem(value: 'en', label: l10n.get('english')),
            ],
            selected: settings.locale.languageCode,
            onChanged: (code) {
              selection();
              settings.updateLocale(Locale(code));
            },
          ),

          SectionHeader(l10n.get('campus')),
          ConnectedButtonGroup<String>(
            items: const [
              ButtonGroupItem(value: 'WH', label: 'WH'),
              ButtonGroupItem(value: 'TA', label: 'TA'),
              ButtonGroupItem(value: 'TGS', label: 'TGS'),
            ],
            selected: settings.campus,
            onChanged: (campus) {
              selection();
              settings.updateCampus(campus);
            },
          ),
          if (settings.campus == 'TGS')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.get('campusTgsNote'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          ListGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.restaurant_menu_rounded),
                title: Text(l10n.get('mensaSettings')),
                subtitle: Text(l10n.get('mensaSettingsSubtitle')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticService.confirm(settings.hapticsEnabled);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MensaSettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          SectionHeader(l10n.get('timetable')),
          ListGroup(
            children: [
              _SwitchTile(
                icon: Icons.weekend_outlined,
                title: l10n.get('showWeekends'),
                value: settings.showWeekends,
                onChanged: settings.updateShowWeekends,
              ),
              _SwitchTile(
                icon: Icons.emoji_food_beverage_outlined,
                title: l10n.get('showBreakTime'),
                value: settings.showBreakTime,
                onChanged: settings.updateShowBreakTime,
              ),
            ],
          ),

          SectionHeader(l10n.get('theme')),
          ConnectedButtonGroup<ThemeMode>(
            items: [
              ButtonGroupItem(
                value: ThemeMode.system,
                label: l10n.get('system'),
                icon: Icons.brightness_auto_outlined,
              ),
              ButtonGroupItem(
                value: ThemeMode.light,
                label: l10n.get('light'),
                icon: Icons.light_mode_outlined,
              ),
              ButtonGroupItem(
                value: ThemeMode.dark,
                label: l10n.get('dark'),
                icon: Icons.dark_mode_outlined,
              ),
            ],
            selected: settings.themeMode,
            onChanged: (mode) {
              selection();
              settings.updateThemeMode(mode);
            },
          ),
          const SizedBox(height: 12),
          ListGroup(
            children: [
              _SwitchTile(
                icon: Icons.palette_outlined,
                title: l10n.get('dynamicColor'),
                value: settings.useDynamicColor,
                onChanged: settings.updateUseDynamicColor,
              ),
              _SwitchTile(
                icon: Icons.contrast_rounded,
                title: l10n.get('amoledTheme'),
                value: settings.amoledTheme,
                onChanged: settings.updateAmoledTheme,
              ),
            ],
          ),

          SectionHeader(l10n.get('app')),
          ListGroup(
            children: [
              _SwitchTile(
                icon: Icons.density_small_rounded,
                title: l10n.get('compactView'),
                subtitle: l10n.get('compactViewSubtitle'),
                value: settings.compactView,
                onChanged: settings.updateCompactView,
              ),
              _SwitchTile(
                icon: Icons.vibration_rounded,
                title: l10n.get('haptics'),
                value: settings.hapticsEnabled,
                // Always give feedback for this one, so turning haptics on
                // (or off) is felt immediately.
                forceHaptics: true,
                onChanged: settings.updateHapticsEnabled,
              ),
              _SwitchTile(
                icon: Icons.animation_rounded,
                title: l10n.get('animations'),
                value: settings.animationsEnabled,
                onChanged: settings.updateAnimationsEnabled,
              ),
              _SwitchTile(
                icon: Icons.mail_outline_rounded,
                title: l10n.get('emailInNavBar'),
                subtitle: l10n.get('emailInNavBarSubtitle'),
                value: settings.emailInNavBar,
                onChanged: settings.updateEmailInNavBar,
              ),
              _SwitchTile(
                icon: Icons.label_off_outlined,
                title: l10n.get('hideNavigationLabels'),
                value: settings.hideLabels,
                onChanged: settings.updateHideLabels,
              ),
            ],
          ),

          const SizedBox(height: 24),
          ListGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.get('about')),
                subtitle: const Text('Uniwe'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticService.confirm(settings.hapticsEnabled);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
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

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.forceHaptics = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool forceHaptics;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: (newValue) {
        final enabled =
            forceHaptics || context.read<SettingsService>().hapticsEnabled;
        if (newValue) {
          HapticService.toggleOn(enabled);
        } else {
          HapticService.toggleOff(enabled);
        }
        onChanged(newValue);
      },
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  void _openLogs(BuildContext context) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    context.read<LogService>().info('Opening logs via long-press');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogScreen()),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthService>();
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text(l10n.get('logoutConfirmTitle')),
        content: Text(l10n.get('logoutConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.get('logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAuthenticated =
        context.select<AuthService, bool>((a) => a.isAuthenticated);
    final username = context.select<AuthService, String?>((a) => a.username);

    final Widget tile;
    if (isAuthenticated) {
      final name = (username == null || username.isEmpty) ? null : username;
      tile = ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: name == null
              ? const Icon(Icons.person_outline_rounded)
              : Text(
                  name[0].toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
        ),
        title: Text(name ?? l10n.get('account')),
        subtitle: Text(l10n.get('signedIn')),
        // The diagnostic log stays a hidden long-press, as before.
        onLongPress: () => _openLogs(context),
        trailing: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _confirmLogout(context),
          onLongPress: () => _openLogs(context),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(l10n.get('logout')),
        ),
      );
    } else {
      tile = ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          child: const Icon(Icons.person_outline_rounded),
        ),
        title: Text(l10n.get('loginTitle')),
        subtitle: Text(l10n.get('scheduleLoginPrompt')),
        onLongPress: () => _openLogs(context),
        trailing: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () {
            HapticService.confirm(
              context.read<SettingsService>().hapticsEnabled,
            );
            showLoginDialog(context);
          },
          child: Text(l10n.get('login')),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListGroup(children: [tile]),
    );
  }
}
