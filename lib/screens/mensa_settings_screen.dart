import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/mensa_category.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';

class MensaSettingsScreen extends StatefulWidget {
  const MensaSettingsScreen({super.key});

  @override
  State<MensaSettingsScreen> createState() => _MensaSettingsScreenState();
}

class _MensaSettingsScreenState extends State<MensaSettingsScreen> {
  late List<MensaCategory> _categories;

  @override
  void initState() {
    super.initState();
    _categories = MensaCategory.ordered(
      context.read<SettingsService>().mensaCategoryOrder,
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    final settings = context.read<SettingsService>();
    HapticService.selection(settings.hapticsEnabled);
    setState(() {
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex.clamp(0, _categories.length), item);
    });
    settings.updateMensaCategoryOrder(_categories.map((c) => c.key).toList());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final gutter = AppSpacing.gutter(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('mensaSettings'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            gutter, 0, gutter, AppSpacing.bottomInset(context, spacing: 32)),
        children: [
          SectionHeader(l10n.get('priceCategory')),
          ConnectedButtonGroup<String>(
            items: [
              ButtonGroupItem(
                  value: 'students', label: l10n.get('priceStudents')),
              ButtonGroupItem(
                  value: 'employees', label: l10n.get('priceEmployees')),
              ButtonGroupItem(value: 'others', label: l10n.get('priceGuests')),
            ],
            selected: settings.mensaPriceCategory,
            onChanged: (category) {
              HapticService.selection(settings.hapticsEnabled);
              settings.updateMensaPriceCategory(category);
            },
          ),
          SectionHeader(l10n.get('categoryOrder')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.get('dragToReorder'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Card(
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: _reorder,
              children: [
                for (int i = 0; i < _categories.length; i++)
                  ListTile(
                    key: ValueKey(_categories[i].key),
                    leading: Icon(_categories[i].icon, color: scheme.primary),
                    title:
                        Text(_categories[i].label(german: l10n.isGerman)),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
