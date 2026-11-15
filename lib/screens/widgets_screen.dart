import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/haptic_service.dart';
import '../services/home_widget_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';
import '../widgets/info_widgets.dart';

/// The home screen widgets the app offers, with a shortcut to add them.
class WidgetsScreen extends StatefulWidget {
  const WidgetsScreen({super.key});

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen> {
  static const _entries = [
    (
      kind: HomeWidgetKind.nextClass,
      icon: Icons.schedule_rounded,
      title: 'widgetNextClass',
      subtitle: 'widgetNextClassSubtitle',
    ),
    (
      kind: HomeWidgetKind.today,
      icon: Icons.view_agenda_outlined,
      title: 'widgetToday',
      subtitle: 'widgetTodaySubtitle',
    ),
    (
      kind: HomeWidgetKind.mensa,
      icon: Icons.restaurant_outlined,
      title: 'widgetMensa',
      subtitle: 'widgetMensaSubtitle',
    ),
    (
      kind: HomeWidgetKind.semester,
      icon: Icons.date_range_outlined,
      title: 'widgetSemester',
      subtitle: 'widgetSemesterSubtitle',
    ),
  ];

  /// Whether the launcher can add a widget on request.
  bool _canPin = false;

  @override
  void initState() {
    super.initState();
    final service = HomeWidgetService.instance;
    service.canPin().then((value) {
      if (mounted && value != _canPin) setState(() => _canPin = value);
    });
    // Whoever looks at this page is about to add a widget: have it filled.
    service.sync();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gutter = AppSpacing.gutter(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('homeWidgets'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          AppSpacing.bottomInset(context, spacing: 32),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              l10n.get(_canPin ? 'widgetsHintPin' : 'widgetsHintManual'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          ListGroup(
            children: [
              for (final entry in _entries)
                ListTile(
                  contentPadding:
                      const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: AppShapes.largeRadius,
                    ),
                    child: Icon(entry.icon, color: scheme.onPrimaryContainer),
                  ),
                  title: Text(l10n.get(entry.title)),
                  subtitle: Text(l10n.get(entry.subtitle)),
                  trailing: !_canPin
                      ? null
                      : IconButton.filledTonal(
                          tooltip: l10n.get('widgetAdd'),
                          icon: const Icon(Icons.add_rounded),
                          onPressed: () {
                            HapticService.confirm(
                              context.read<SettingsService>().hapticsEnabled,
                            );
                            HomeWidgetService.instance.requestPin(entry.kind);
                          },
                        ),
                ),
            ],
          ),
          FootNote(l10n.get('widgetsNote')),
        ],
      ),
    );
  }
}
