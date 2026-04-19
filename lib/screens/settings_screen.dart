import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import 'login_screen.dart';
import 'mensa_settings_screen.dart';
import 'about_screen.dart';
import 'log_screen.dart';
import '../services/log_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('settings')),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'Campus'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'WH',
                  label: Text('WH'),
                ),
                ButtonSegment<String>(
                  value: 'TA',
                  label: Text('TA'),
                ),
                ButtonSegment<String>(
                  value: 'TGS',
                  label: Text('TGS'),
                ),
              ],
              selected: <String>{settings.campus},
              onSelectionChanged: (Set<String> newSelection) {
                HapticService.selection(settings.hapticsEnabled);
                settings.updateCampus(newSelection.first);
              },
            ),
          ),
          if (settings.campus == 'TGS')
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
              child: Text(
                Localizations.localeOf(context).languageCode == 'de'
                    ? 'Der Campus TGS ändert nur die Haltestelle in der Transport-Ansicht. Die Mensa bleibt Wilhelminenhof.'
                    : 'The TGS campus only affects the stop in the Transport view. The Mensa remains Wilhelminenhof.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.restaurant_menu, color: Theme.of(context).colorScheme.primary),
            title: Text(Localizations.localeOf(context).languageCode == 'de' ? 'Mensa Einstellungen' : 'Mensa Settings'),
            subtitle: Text(
              Localizations.localeOf(context).languageCode == 'de' 
                ? 'Preise, Ansicht & Kategorien'
                : 'Prices, View & Categories',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              HapticService.confirm(settings.hapticsEnabled);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MensaSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(),
          _buildSectionHeader(context, Localizations.localeOf(context).languageCode == 'de' ? 'Stundenplan' : 'Timetable'),
          SwitchListTile(
            title: Text(l10n.get('showWeekends')),
            value: settings.showWeekends,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateShowWeekends(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('showBreakTime')),
            value: settings.showBreakTime,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateShowBreakTime(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('compactTimetable')),
            value: settings.compactTimetableView,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateCompactTimetableView(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Divider(),
          _buildSectionHeader(context, l10n.get('app')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SegmentedButton<Locale>(
              segments: [
                ButtonSegment<Locale>(
                  value: const Locale('de'),
                  label: Text(l10n.get('german')),
                ),
                ButtonSegment<Locale>(
                  value: const Locale('en'),
                  label: Text(l10n.get('english')),
                ),
              ],
              selected: <Locale>{settings.locale},
              onSelectionChanged: (Set<Locale> newSelection) {
                HapticService.selection(settings.hapticsEnabled);
                settings.updateLocale(newSelection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.get('haptics')),
            value: settings.hapticsEnabled,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(true);
              } else {
                HapticService.toggleOff(true);
              }
              settings.updateHapticsEnabled(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('animations')),
            value: settings.animationsEnabled,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateAnimationsEnabled(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('hideNavigationLabels')),
            value: settings.hideLabels,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateHideLabels(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('lsfOnEmailLongPress')),
            value: settings.lsfOnEmailLongPress,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateLsfOnEmailLongPress(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Divider(),
          _buildSectionHeader(context, l10n.get('theme')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: Text(l10n.get('system')),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text(l10n.get('light')),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text(l10n.get('dark')),
                ),
              ],
              selected: <ThemeMode>{settings.themeMode},
              onSelectionChanged: (Set<ThemeMode> newSelection) {
                HapticService.selection(settings.hapticsEnabled);
                settings.updateThemeMode(newSelection.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(l10n.get('dynamicColor')),
            value: settings.useDynamicColor,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateUseDynamicColor(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          SwitchListTile(
            title: Text(l10n.get('amoledTheme')),
            value: settings.amoledTheme,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateAmoledTheme(value);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),

          const Divider(),
          const SizedBox(height: 16),
          _buildAuthSection(context, l10n, context.watch<AuthService>()),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.get('about')),
            subtitle: Text(
              'Uniwe',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              HapticService.confirm(settings.hapticsEnabled);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildAuthSection(BuildContext context, AppLocalizations l10n, AuthService auth) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();
    if (auth.isAuthenticated) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.username != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        auth.username![0].toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      auth.username!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onLongPress: () {
                HapticService.confirm(settings.hapticsEnabled);
                context.read<LogService>().info('Opening logs via long-press');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogScreen()),
                );
              },
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  HapticService.confirm(settings.hapticsEnabled);
                  context.read<AuthService>().logout();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () {
            HapticService.confirm(settings.hapticsEnabled);
            showLoginDialog(context);
          },
          icon: const Icon(Icons.login),
          label: const Text('Anmelden', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
  }
}
