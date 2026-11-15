import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import '../navigation/nav_layout.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import 'settings_screen.dart';

/// The "menu" destination: every part of the app the user did not put into
/// the navigation bar (or hide), with the settings pinned to the bottom.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _haptic(BuildContext context) =>
      HapticService.confirm(context.read<SettingsService>().hapticsEnabled);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = AppSpacing.gutter(context);
    final layout =
        context.select<SettingsService, NavLayout>((s) => s.navLayout);
    final items = [for (final id in layout.menu) Destinations.byId(id)];

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
                  if (items.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(l10n.get('services')),
                        ListGroup(
                          children: [
                            for (final destination in items)
                              ListTile(
                                leading: Icon(
                                  destination.menuIcon ?? destination.icon,
                                ),
                                title: Text(destination.title(l10n)),
                                subtitle: destination.subtitleKey == null
                                    ? null
                                    : Text(
                                        l10n.get(destination.subtitleKey!),
                                      ),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () {
                                  _haptic(context);
                                  Destinations.push(context, destination);
                                },
                              ),
                          ],
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
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
