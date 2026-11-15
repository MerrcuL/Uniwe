import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import '../navigation/nav_layout.dart';
import '../services/haptic_service.dart';
import '../services/home_widget_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/fade_indexed_stack.dart';
import '../widgets/floating_tab_bar.dart';
import '../widgets/update_dialog.dart';
import 'more_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Window width from which the navigation bar becomes a navigation rail.
  static const double _railBreakpoint = 600;

  int _selectedIndex = AppEvents.currentTab.value;
  DateTime? _lastBackPressedAt;
  StreamSubscription<String>? _openSubscription;

  @override
  void initState() {
    super.initState();
    AppEvents.currentTab.addListener(_onTabChanged);
    _openSubscription = AppEvents.openRequests.listen(_open);
    _checkForUpdatesOnStartup();
    // Taps on home screen widgets arrive as open requests.
    HomeWidgetService.instance.listenForLaunches();
  }

  @override
  void dispose() {
    AppEvents.currentTab.removeListener(_onTabChanged);
    _openSubscription?.cancel();
    super.dispose();
  }

  /// Brings a destination on screen: its tab if it has one, else as a page
  /// on top (unless that page is what the user is looking at already).
  void _open(String id) {
    if (!mounted) return;
    final destination = Destinations.maybeById(id);
    if (destination == null) return;
    final navigator = Navigator.of(context);
    if (context.read<SettingsService>().navLayout.bar.contains(id)) {
      navigator.popUntil((route) => route.isFirst);
      AppEvents.currentTab.value = destination.tab;
      return;
    }
    if (_openedId == id && navigator.canPop()) return;
    navigator.popUntil((route) => route.isFirst);
    _openedId = id;
    Destinations.push(context, destination);
  }

  /// The destination last opened as a page by [_open].
  String? _openedId;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hideLabels =
        context.select<SettingsService, bool>((s) => s.hideLabels);
    final animationsEnabled =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);
    final useRail = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    final layout =
        context.select<SettingsService, NavLayout>((s) => s.navLayout);
    final barDestinations = [
      for (final id in layout.bar) Destinations.byId(id),
    ];
    final tabs = [for (final d in barDestinations) d.tab, AppTab.more];
    // The open tab was just moved out of the bar.
    if (!tabs.contains(_selectedIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppEvents.currentTab.value = AppTab.more;
      });
    }
    final barIndex =
        tabs.contains(_selectedIndex) ? tabs.indexOf(_selectedIndex) : tabs.length - 1;

    // Icon and label of every item of the bar, the menu last.
    final items = [
      for (final d in barDestinations)
        FloatingTabItem(
          icon: d.icon,
          selectedIcon: d.selectedIcon,
          label: d.title(l10n),
        ),
      FloatingTabItem(
        icon: Icons.menu_rounded,
        selectedIcon: Icons.menu_rounded,
        label: l10n.get('menu'),
      ),
    ];

    // One slot per [AppTab]; only destinations of the bar are built (and
    // those only once visited), so a tab that left the bar lets go of its
    // state.
    final screens = List<Widget>.filled(AppTab.count, const SizedBox.shrink());
    for (final d in barDestinations) {
      screens[d.tab] = KeyedSubtree(
        key: ValueKey(d.id),
        child: d.buildTab(context),
      );
    }
    screens[AppTab.more] = const MoreScreen();

    final content = FadeIndexedStack(
      index: tabs.contains(_selectedIndex) ? _selectedIndex : AppTab.more,
      duration: Durations.medium2,
      animate: animationsEnabled,
      children: screens,
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
                        for (final item in items)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
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
                items: items,
              ),
      ),
    );
  }
}
