import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

@immutable
class FloatingTabItem {
  const FloatingTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// A floating, pill-shaped tab bar in the style of current iOS apps.
///
/// The selected tab is marked by a capsule that covers the whole item (icon
/// and label) and glides to the next tab. The bar can also be scrubbed:
/// press anywhere on it and slide sideways — the capsule follows the finger
/// and the tab under it is opened on release.
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.onReselected,
    this.onScrubbedOver,
    this.showLabels = true,
    this.animate = true,
  });

  final List<FloatingTabItem> items;
  final int selectedIndex;

  /// A different tab was chosen (by tap or by releasing a scrub on it).
  final ValueChanged<int> onSelected;

  /// The current tab was tapped again.
  final ValueChanged<int>? onReselected;

  /// The capsule moved over another tab while scrubbing (for haptics).
  final VoidCallback? onScrubbedOver;

  final bool showLabels;
  final bool animate;

  static const double _maxWidth = 480;
  static const double _inner = 4;

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar> {
  /// Finger position (x, relative to the items row) while scrubbing.
  double? _scrubX;
  int? _scrubIndex;

  int _indexAt(double x, double itemWidth) =>
      (x / itemWidth).floor().clamp(0, widget.items.length - 1);

  void _scrubTo(double x, double itemWidth) {
    final index = _indexAt(x, itemWidth);
    if (_scrubIndex != null && index != _scrubIndex) {
      widget.onScrubbedOver?.call();
    }
    setState(() {
      _scrubX = x;
      _scrubIndex = index;
    });
  }

  void _endScrub({required bool commit}) {
    final index = _scrubIndex;
    setState(() {
      _scrubX = null;
      _scrubIndex = null;
    });
    if (commit && index != null && index != widget.selectedIndex) {
      widget.onSelected(index);
    }
  }

  void _tap(int index) {
    if (index == widget.selectedIndex) {
      widget.onReselected?.call(index);
    } else {
      widget.onSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = widget.showLabels ? 64.0 : 56.0;
    final count = widget.items.length;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FloatingTabBar._maxWidth),
            child: Material(
              color: scheme.surfaceContainerHigh,
              shadowColor: scheme.shadow,
              elevation: 3,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(FloatingTabBar._inner),
                child: SizedBox(
                  height: height - 2 * FloatingTabBar._inner,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / count;
                      final scrubX = _scrubX;
                      final scrubbing = scrubX != null;

                      // While scrubbing the capsule is centred on the finger;
                      // otherwise it rests on the selected tab.
                      final left = scrubbing
                          ? (scrubX - itemWidth / 2)
                              .clamp(0.0, constraints.maxWidth - itemWidth)
                          : widget.selectedIndex * itemWidth;
                      final highlighted = _scrubIndex ?? widget.selectedIndex;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) =>
                            _tap(_indexAt(d.localPosition.dx, itemWidth)),
                        onHorizontalDragStart: (d) =>
                            _scrubTo(d.localPosition.dx, itemWidth),
                        onHorizontalDragUpdate: (d) =>
                            _scrubTo(d.localPosition.dx, itemWidth),
                        onHorizontalDragEnd: (_) => _endScrub(commit: true),
                        onHorizontalDragCancel: () => _endScrub(commit: false),
                        // Press-and-hold, then slide.
                        onLongPressStart: (d) =>
                            _scrubTo(d.localPosition.dx, itemWidth),
                        onLongPressMoveUpdate: (d) =>
                            _scrubTo(d.localPosition.dx, itemWidth),
                        onLongPressEnd: (_) => _endScrub(commit: true),
                        onLongPressCancel: () => _endScrub(commit: false),
                        child: Stack(
                          children: [
                            AnimatedPositioned(
                              duration: (scrubbing || !widget.animate)
                                  ? Duration.zero
                                  : AppMotion.spatialDefault,
                              curve: AppMotion.spatial,
                              left: left,
                              top: 0,
                              bottom: 0,
                              width: itemWidth,
                              child: AnimatedScale(
                                // The capsule swells a little while held.
                                scale: scrubbing ? 1.06 : 1,
                                duration: widget.animate
                                    ? AppMotion.effectsDefault
                                    : Duration.zero,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: scheme.secondaryContainer,
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < count; i++)
                                  SizedBox(
                                    width: itemWidth,
                                    child: _TabItem(
                                      item: widget.items[i],
                                      selected: i == highlighted,
                                      showLabel: widget.showLabels,
                                      animate: widget.animate,
                                      onTap: () => _tap(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.animate,
    required this.onTap,
  });

  final FloatingTabItem item;
  final bool selected;
  final bool showLabel;
  final bool animate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color =
        selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final duration = animate ? AppMotion.effectsDefault : Duration.zero;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: duration,
                builder: (context, value, _) => Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 24,
                  color: value,
                ),
              ),
              if (showLabel) ...[
                const SizedBox(height: 2),
                // Long labels ("Stundenplan") shrink rather than clip.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    style: (theme.textTheme.labelSmall ?? const TextStyle())
                        .copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                    child: Text(item.label, maxLines: 1, softWrap: false),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
