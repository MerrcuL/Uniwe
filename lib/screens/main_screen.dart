import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/fade_indexed_stack.dart';
import '../widgets/floating_tab_bar.dart';
import '../widgets/update_dialog.dart';
import 'email_screen.dart';
import 'mensa_screen.dart';
import 'more_screen.dart';
import 'timetable_screen.dart';
import 'transport_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.labelKey);

  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}

class _MainScreenState extends State<MainScreen> {
  /// Window width from which the navigation bar becomes a navigation rail.
  static const double _railBreakpoint = 600;

  // Order must match [AppTab].
  static const List<_Destination> _destinations = [
    _Destination(
        Icons.calendar_month_outlined, Icons.calendar_month, 'timetable'),
    _Destination(Icons.restaurant_outlined, Icons.restaurant, 'mensa'),
    _Destination(Icons.email_outlined, Icons.email, 'email'),
    _Destination(
        Icons.directions_transit_outlined, Icons.directions_transit, 'transport'),
    _Destination(Icons.menu_rounded, Icons.menu_rounded, 'menu'),
  ];

  static const List<Widget> _screens = [
    TimetableScreen(),
    MensaScreen(),
    EmailScreen(),
    TransportScreen(),
    MoreScreen(),
  ];

  int _selectedIndex = AppEvents.currentTab.value;
  DateTime? _lastBackPressedAt;

  @override
  void initState() {
    super.initState();
    AppEvents.currentTab.addListener(_onTabChanged);
    _checkForUpdatesOnStartup();
  }

  @override
  void dispose() {
    AppEvents.currentTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && _selectedIndex != AppEvents.currentTab.value) {
      setState(() => _selectedIndex = AppEvents.currentTab.value);
    }
  }

  bool get _hapticsEnabled => context.read<SettingsService>().hapticsEnabled;

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      // Tapping the current destination again refreshes it.
      AppEvents.reselectTab(index);
      return;
    }
    HapticService.selection(_hapticsEnabled);
    AppEvents.currentTab.value = index;
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // Small delay so the UI is fully rendered before the network call
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (updateInfo == null || !updateInfo.updateAvailable) return;

    showUpdateDialog(context, updateInfo);
  }

  Future<void> _onBack() async {
    // Give the visible tab the first chance (web view history).
    if (await AppEvents.handleBack(_selectedIndex)) return;
    if (!mounted) return;

    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last != null && now.difference(last) <= const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressedAt = now;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('pressAgainToExit')),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget _icon(int tab, {required bool selected}) {
    final destination = _destinations[tab];
    return Icon(selected ? destination.selectedIcon : destination.icon);
  }

  /// The tabs shown in the bar, by [AppTab] id.
  static List<int> _visibleTabs({required bool emailInNavBar}) => [
        AppTab.timetable,
        AppTab.mensa,
        if (emailInNavBar) AppTab.email,
        AppTab.transport,
        AppTab.more,
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hideLabels =
        context.select<SettingsService, bool>((s) => s.hideLabels);
    final animationsEnabled =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);
    final useRail = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    final emailInNavBar =
        context.select<SettingsService, bool>((s) => s.emailInNavBar);
    final tabs = _visibleTabs(emailInNavBar: emailInNavBar);
    // The e-mail tab was just moved into the menu while it was open.
    if (!tabs.contains(_selectedIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppEvents.currentTab.value = AppTab.more;
      });
    }
    final barIndex =
        tabs.contains(_selectedIndex) ? tabs.indexOf(_selectedIndex) : tabs.length - 1;

    final content = FadeIndexedStack(
      index: _selectedIndex,
      duration: Durations.medium2,
      animate: animationsEnabled,
      children: _screens,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        // The bar floats over the content; screens pad their scrollables
        // with the inset the scaffold reports for it.
        extendBody: !useRail,
        body: useRail
            ? Row(
                children: [
                  SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: barIndex,
                      onDestinationSelected: (i) =>
                          _onDestinationSelected(tabs[i]),
                      groupAlignment: 0,
                      labelType: hideLabels
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (final tab in tabs)
                          NavigationRailDestination(
                            icon: _icon(tab, selected: false),
                            selectedIcon: _icon(tab, selected: true),
                            label: Text(l10n.get(_destinations[tab].labelKey)),
                          ),
                      ],
                    ),
                  ),
                  // Report the width that is actually left next to the rail,
                  // so screens size their gutters from it.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                        ),
                        child: content,
                      ),
                    ),
                  ),
                ],
              )
            : content,
        bottomNavigationBar: useRail
            ? null
            : FloatingTabBar(
                selectedIndex: barIndex,
                showLabels: !hideLabels,
                animate: animationsEnabled,
                onSelected: (i) => _onDestinationSelected(tabs[i]),
                onReselected: (i) => _onDestinationSelected(tabs[i]),
                onScrubbedOver: () =>
                    HapticService.selection(_hapticsEnabled),
                items: [
                  for (final tab in tabs)
                    FloatingTabItem(
                      icon: _destinations[tab].icon,
                      selectedIcon: _destinations[tab].selectedIcon,
                      label: l10n.get(_destinations[tab].labelKey),
                    ),
                ],
              ),
      ),
    );
  }
}
