import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/haptic_service.dart';

class MensaSettingsScreen extends StatefulWidget {
  const MensaSettingsScreen({super.key});

  @override
  State<MensaSettingsScreen> createState() => _MensaSettingsScreenState();
}

class _MensaSettingsScreenState extends State<MensaSettingsScreen> {
  late List<_CategoryItem> _categories;

  @override
  void initState() {
    super.initState();
    _categories = [
      _CategoryItem('Essen', 'Main Dishes', 'Hauptgerichte', Icons.restaurant),
      _CategoryItem('Beilagen', 'Side Dishes', 'Beilagen', Icons.rice_bowl),
      _CategoryItem('Suppen', 'Soups', 'Suppen', Icons.soup_kitchen),
      _CategoryItem('Salat', 'Salads', 'Salate', Icons.eco),
      _CategoryItem('Dessert', 'Desserts', 'Desserts', Icons.icecream),
      _CategoryItem('Aktionen', 'Specials', 'Aktionen', Icons.star_outline),
      _CategoryItem('Vorspeisen', 'Starters', 'Vorspeisen', Icons.tapas),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsService>();
      final savedOrder = settings.mensaCategoryOrder;
      if (savedOrder.isNotEmpty) {
        final reordered = <_CategoryItem>[];
        for (var key in savedOrder) {
          final match = _categories.where((c) => c.key == key);
          if (match.isNotEmpty) reordered.add(match.first);
        }
        for (var cat in _categories) {
          if (!reordered.contains(cat)) reordered.add(cat);
        }
        setState(() => _categories = reordered);
      }
    });
  }

  void _saveOrder() {
    final settings = context.read<SettingsService>();
    settings.updateMensaCategoryOrder(_categories.map((c) => c.key).toList());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    final isDe = Localizations.localeOf(context).languageCode == 'de';

    return Scaffold(
      appBar: AppBar(
        title: Text(isDe ? 'Mensa Einstellungen' : 'Mensa Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, isDe ? 'Preiskategorie' : 'Price Category'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment<String>(
                  value: 'students',
                  label: Text(isDe ? 'Stud.' : 'Student'),
                ),
                ButtonSegment<String>(
                  value: 'employees',
                  label: Text(isDe ? 'Bedienst.' : 'Staff'),
                ),
                ButtonSegment<String>(
                  value: 'others',
                  label: Text(isDe ? 'Gäste' : 'Guests'),
                ),
              ],
              selected: <String>{settings.mensaPriceCategory},
              onSelectionChanged: (Set<String> newSelection) {
                HapticService.selection(settings.hapticsEnabled);
                settings.updateMensaPriceCategory(newSelection.first);
              },
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

          _buildSectionHeader(context, isDe ? 'Ansicht' : 'View'),
          SwitchListTile(
            title: Text(isDe ? 'Kompakte Ansicht' : 'Compact View'),
            subtitle: Text(
              isDe 
                ? 'Nur Gericht, Tags und Preis anzeigen' 
                : 'Show only dish name, tags, and price',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            value: settings.compactMensaView,
            onChanged: (value) {
              if (value) {
                HapticService.toggleOn(settings.hapticsEnabled);
              } else {
                HapticService.toggleOff(settings.hapticsEnabled);
              }
              settings.updateCompactMensaView(value);
            },
            activeThumbColor: theme.colorScheme.primary,
          ),

          const SizedBox(height: 24),
          const Divider(),

          _buildSectionHeader(context, isDe ? 'Kategorienreihenfolge' : 'Category Order'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              isDe ? 'Ziehen zum Umsortieren' : 'Drag to reorder',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) {
                  HapticService.selection(settings.hapticsEnabled);
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _categories.removeAt(oldIndex);
                    _categories.insert(newIndex, item);
                  });
                  _saveOrder();
                },
                children: [
                  for (int i = 0; i < _categories.length; i++)
                    ListTile(
                      key: ValueKey(_categories[i].key),
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text('${i + 1}', style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        )),
                      ),
                      title: Text(isDe ? _categories[i].labelDe : _categories[i].labelEn),
                      trailing: Icon(Icons.drag_handle, color: theme.colorScheme.outline),
                      dense: true,
                    ),
                ],
              ),
            ),
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
}

class _CategoryItem {
  final String key;
  final String labelEn;
  final String labelDe;
  final IconData icon;
  _CategoryItem(this.key, this.labelEn, this.labelDe, this.icon);
}
