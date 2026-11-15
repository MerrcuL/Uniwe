import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import '../navigation/nav_layout.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';

/// One row of the flat, reorderable list: a section heading, a destination,
/// or the placeholder of an empty section.
@immutable
class _Row {
  const _Row.header(this.section)
      : id = null,
        isPlaceholder = false;
  const _Row.item(this.section, String this.id) : isPlaceholder = false;
  const _Row.placeholder(this.section)
      : id = null,
        isPlaceholder = true;

  final NavSection section;
  final String? id;
  final bool isPlaceholder;

  bool get isHeader => id == null && !isPlaceholder;

  Key get key => ValueKey(
        id ?? '${isPlaceholder ? 'placeholder' : 'header'}_${section.name}',
      );
}

/// Lets the user arrange the navigation bar and the menu: drag a
/// destination to reorder it or to move it between the bar, the menu and
/// the hidden ones.
class NavigationSettingsScreen extends StatelessWidget {
  const NavigationSettingsScreen({super.key});

  static List<_Row> _rows(NavLayout layout) => [
        for (final section in NavSection.values) ...[
          _Row.header(section),
          if (layout.items(section).isEmpty)
            _Row.placeholder(section)
          else
            for (final id in layout.items(section)) _Row.item(section, id),
        ],
      ];

  void _explain(BuildContext context, NavMoveProblem problem) {
    final l10n = AppLocalizations.of(context);
    final message = switch (problem) {
      NavMoveProblem.barFull => l10n
          .get('navBarFull')
          .replaceAll('{n}', '${NavLayout.maxBarItems}'),
      NavMoveProblem.barEmpty => l10n.get('navBarEmpty'),
      NavMoveProblem.menuOnly => l10n.get('navMenuOnly'),
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Moves [id] to [section] (at [index] within it), or says why not.
  void _move(
    BuildContext context,
    String id,
    NavSection section, [
    int? index,
  ]) {
    final settings = context.read<SettingsService>();
    final layout = settings.navLayout;
    final problem = layout.problemWithMove(id, section);
    if (problem != null) {
      HapticService.selection(settings.hapticsEnabled);
      _explain(context, problem);
      return;
    }
    HapticService.confirm(settings.hapticsEnabled);
    settings.updateNavLayout(layout.move(id, section, index));
  }

  void _onReorder(BuildContext context, int oldIndex, int newIndex) {
    final layout = context.read<SettingsService>().navLayout;
    final rows = _rows(layout);
    final id = rows[oldIndex].id;
    if (id == null) return;

    final without = [...rows]..removeAt(oldIndex);
    // The section is the last heading above the drop position; the index is
    // the number of destinations between that heading and the position.
    var section = NavSection.bar;
    var index = 0;
    for (var i = 0; i < newIndex && i < without.length; i++) {
      final row = without[i];
      if (row.isHeader) {
        section = row.section;
        index = 0;
      } else if (row.id != null) {
        index++;
      }
    }
    _move(context, id, section, index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsService>();
    final layout = settings.navLayout;
    final rows = _rows(layout);
    final gutter = AppSpacing.gutter(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('navigation')),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: l10n.get('resetToDefault'),
            onPressed: layout == NavLayout.standard
                ? null
                : () {
                    HapticService.confirm(settings.hapticsEnabled);
                    settings.updateNavLayout(NavLayout.standard);
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          AppSpacing.bottomInset(context, spacing: 32),
        ),
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                l10n.get('navigationHint'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            ListGroup(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.label_off_outlined),
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
                ),
              ],
            ),
          ],
        ),
        itemCount: rows.length,
        onReorderStart: (_) =>
            HapticService.selection(settings.hapticsEnabled),
        // (The new index already accounts for the removed row.)
        onReorderItem: (oldIndex, newIndex) =>
            _onReorder(context, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Material(
            color: Colors.transparent,
            elevation: 6 * Curves.easeOut.transform(animation.value),
            shadowColor: Theme.of(context).colorScheme.shadow,
            borderRadius: AppShapes.largeIncreasedRadius,
            child: child,
          ),
        ),
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.isHeader) {
            return _SectionTitle(
              key: row.key,
              section: row.section,
              count: layout.items(row.section).length,
            );
          }
          if (row.isPlaceholder) {
            return _Placeholder(key: row.key, section: row.section);
          }

          final previous = rows[index - 1];
          final next = index + 1 < rows.length ? rows[index + 1] : null;
          return _DestinationRow(
            key: row.key,
            index: index,
            destination: Destinations.byId(row.id!),
            section: row.section,
            isFirst: previous.id == null,
            isLast: next == null || next.id == null,
            onMove: (section) => _move(context, row.id!, section),
          );
        },
      ),
    );
  }
}

String _sectionLabel(NavSection section, AppLocalizations l10n) =>
    l10n.get(switch (section) {
      NavSection.bar => 'navSectionBar',
      NavSection.menu => 'navSectionMenu',
      NavSection.hidden => 'navSectionHidden',
    });

IconData _sectionIcon(NavSection section) => switch (section) {
      NavSection.bar => Icons.dock_outlined,
      NavSection.menu => Icons.menu_rounded,
      NavSection.hidden => Icons.visibility_off_outlined,
    };

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({super.key, required this.section, required this.count});

  final NavSection section;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = _sectionLabel(section, l10n);
    return SectionHeader(
      section == NavSection.bar
          ? '$label · $count/${NavLayout.maxBarItems}'
          : label,
      icon: _sectionIcon(section),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.section});

  final NavSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: AppShapes.largeIncreasedRadius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        l10n.get('navDropHere'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A destination in the list, shaped like a row of a [ListGroup]: large
/// outer corners on the first and last row of its section.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    super.key,
    required this.index,
    required this.destination,
    required this.section,
    required this.isFirst,
    required this.isLast,
    required this.onMove,
  });

  final int index;
  final AppDestination destination;
  final NavSection section;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<NavSection> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    const outer = Radius.circular(AppShapes.largeIncreased);
    const inner = Radius.circular(AppShapes.extraSmall);
    final hidden = section == NavSection.hidden;

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 2),
      child: Material(
        color: scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: isFirst ? outer : inner,
            bottom: isLast ? outer : inner,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          leading: Icon(
            destination.menuIcon != null && section != NavSection.bar
                ? destination.menuIcon
                : destination.icon,
            color: hidden ? scheme.outline : null,
          ),
          title: Text(
            destination.title(l10n),
            style: hidden ? TextStyle(color: scheme.onSurfaceVariant) : null,
          ),
          subtitle: destination.canBeTab
              ? null
              : Text(l10n.get('navMenuOnlyShort')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<NavSection>(
                tooltip: l10n.get('navMoveTo'),
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: onMove,
                itemBuilder: (context) => [
                  for (final target in NavSection.values)
                    if (target != section)
                      PopupMenuItem(
                        value: target,
                        child: Row(
                          children: [
                            Icon(_sectionIcon(target), size: 20),
                            const SizedBox(width: 12),
                            Text(_sectionLabel(target, l10n)),
                          ],
                        ),
                      ),
                ],
              ),
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: l10n.get('dragToReorder'),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
