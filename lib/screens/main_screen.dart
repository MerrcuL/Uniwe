import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/fade_indexed_stack.dart';
import '../services/settings_service.dart';
import '../services/haptic_service.dart';
import '../services/update_service.dart';

import '../l10n/app_localizations.dart';
import 'timetable_screen.dart';
import 'mensa_screen.dart';
import 'transport_screen.dart';
import 'email_screen.dart';
import 'settings_screen.dart';
import '../main.dart' as import_main;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  DateTime? _lastPressedAt;

  final List<Widget> _screens = const [
    TimetableScreen(),
    MensaScreen(),
    EmailScreen(),
    TransportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    import_main.mainTabNotifier.addListener(_onMainTabChanged);
    _checkForUpdatesOnStartup();
  }


  void _onMainTabChanged() {
    if (mounted) {
      setState(() {
        _selectedIndex = import_main.mainTabNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    import_main.mainTabNotifier.removeListener(_onMainTabChanged);
    super.dispose();
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // Small delay so the UI is fully rendered before the network call
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (updateInfo == null || !updateInfo.updateAvailable) return;

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.system_update, color: theme.colorScheme.primary, size: 32),
        title: Text(l10n.get('updateAvailable')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.get('newVersion')}: ${updateInfo.latestVersion}',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.get('currentVersion')}: ${updateInfo.currentVersion}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (updateInfo.releaseBody.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    updateInfo.releaseBody,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.get('later')),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(updateInfo.releaseUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l10n.get('download')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final settings = context.watch<SettingsService>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.get('pressAgainToExit')),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: FadeIndexedStack(
        index: _selectedIndex,
        duration: settings.animationsEnabled 
            ? const Duration(milliseconds: 400) 
            : Duration.zero,
        animate: settings.animationsEnabled,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        height: settings.hideLabels ? 60 : null,
        labelBehavior: settings.hideLabels
            ? NavigationDestinationLabelBehavior.alwaysHide
            : NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index != _selectedIndex) {
            HapticService.selection(settings.hapticsEnabled);
            setState(() {
              _selectedIndex = index;
            });
          } else {
            import_main.tabRefreshController.add(index);
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l10n.get('timetable'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.restaurant_outlined),
            selectedIcon: const Icon(Icons.restaurant),
            label: l10n.get('mensa'),
          ),
          NavigationDestination(
            icon: GestureDetector(
              onLongPress: () {
                import_main.emailLongPressController.add(null);
                if (_selectedIndex != 2) {
                  HapticService.selection(settings.hapticsEnabled);
                  setState(() {
                    _selectedIndex = 2;
                  });
                }
              },
              child: const Icon(Icons.email_outlined),
            ),
            selectedIcon: GestureDetector(
              onLongPress: () {
                import_main.emailLongPressController.add(null);
              },
              child: const Icon(Icons.email),
            ),
            label: l10n.get('email'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.directions_transit_outlined),
            selectedIcon: Icon(Icons.directions_transit),
            label: 'Transport',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.get('settings'),
          ),
        ],
      ),
    ));
  }
}
