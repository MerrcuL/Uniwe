import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Material 3 Expressive building blocks that Flutter's material library does
// not ship: the shape-morphing loading indicator, connected button groups,
// segmented list groups and a few small shared pieces.

// ─────────────────────────────────────────────────────────────────────────────
// Shapes
// ─────────────────────────────────────────────────────────────────────────────

/// A soft "cookie"-style shape described by its number of lobes and how deep
/// they are. Zero lobes is a circle.
@immutable
class SoftShape {
  const SoftShape(this.lobes, this.depth);

  final int lobes;
  final double depth;

  static const SoftShape circle = SoftShape(0, 0);
  static const SoftShape oval = SoftShape(2, 0.16);
  static const SoftShape clover = SoftShape(4, 0.11);
  static const SoftShape pentagon = SoftShape(5, 0.06);
  static const SoftShape flower = SoftShape(6, 0.09);
  static const SoftShape sunny = SoftShape(8, 0.08);
  static const SoftShape cookie = SoftShape(9, 0.05);

  /// Radius (0…1) of the outline at [angle].
  double radiusAt(double angle) =>
      (1 + depth * math.cos(lobes * angle)) / (1 + depth);
}

/// Outline of [from] morphed towards [to] by [t], rotated by [rotation].
Path softShapePath(
  Offset center,
  double radius,
  SoftShape from, {
  SoftShape? to,
  double t = 0,
  double rotation = 0,
}) {
  const samples = 96;
  final path = Path();
  for (var i = 0; i < samples; i++) {
    final angle = 2 * math.pi * i / samples;
    var r = from.radiusAt(angle);
    if (to != null) r += (to.radiusAt(angle) - r) * t;
    final point = center +
        Offset(math.cos(angle + rotation), math.sin(angle + rotation)) *
            (radius * r);
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

/// An icon on a soft-shape background; the hero of empty and error states.
class ShapeBadge extends StatelessWidget {
  const ShapeBadge({
    super.key,
    required this.icon,
    this.size = 96,
    this.shape = SoftShape.cookie,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final double size;
  final SoftShape shape;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SoftShapePainter(shape, color ?? scheme.primaryContainer),
        child: Center(
          child: Icon(
            icon,
            size: size * 0.46,
            color: iconColor ?? scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _SoftShapePainter extends CustomPainter {
  const _SoftShapePainter(this.shape, this.color);

  final SoftShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      softShapePath(size.center(Offset.zero), size.shortestSide / 2, shape),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SoftShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading indicator
// ─────────────────────────────────────────────────────────────────────────────

/// The M3 Expressive loading indicator: a shape that keeps rotating while it
/// morphs through a sequence of soft shapes. For waits of unknown, short
/// duration where the classic spinner would be used otherwise.
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.contained = false,
    this.semanticsLabel,
  });

  final double size;
  final Color? color;

  /// Draws the indicator on a tonal circle, for use on top of content.
  final bool contained;
  final String? semanticsLabel;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const List<SoftShape> _sequence = [
    SoftShape.clover,
    SoftShape.cookie,
    SoftShape.pentagon,
    SoftShape.oval,
    SoftShape.sunny,
    SoftShape.flower,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 650 * _sequence.length),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ??
        (widget.contained ? scheme.onPrimaryContainer : scheme.primary);

    Widget indicator = SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LoadingPainter(_controller, _sequence, color),
        ),
      ),
    );

    if (widget.contained) {
      indicator = DecoratedBox(
        decoration: ShapeDecoration(
          color: scheme.primaryContainer,
          shape: const CircleBorder(),
        ),
        child: Padding(
          padding: EdgeInsets.all(widget.size * 0.14),
          child: indicator,
        ),
      );
    }

    return Semantics(
      label: widget.semanticsLabel ??
          MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: indicator,
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter(this.animation, this.sequence, this.color)
      : super(repaint: animation);

  final Animation<double> animation;
  final List<SoftShape> sequence;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final count = sequence.length;
    final progress = animation.value * count;
    final index = progress.floor() % count;
    final eased = Curves.easeInOutCubicEmphasized
        .transform((progress - progress.floor()).clamp(0.0, 1.0));

    // A steady spin plus an eased push with every morph. Both complete whole
    // turns per cycle, so the loop restarts seamlessly.
    final rotation =
        2 * math.pi * (animation.value + (index + eased) / count);

    canvas.drawPath(
      softShapePath(
        size.center(Offset.zero),
        size.shortestSide / 2 * 0.86,
        sequence[index],
        to: sequence[(index + 1) % count],
        t: eased,
        rotation: rotation,
      ),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_LoadingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sequence != sequence;
}

// ─────────────────────────────────────────────────────────────────────────────
// Connected button group
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class ButtonGroupItem<T> {
  const ButtonGroupItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Single-select connected button group — the M3 Expressive successor of the
/// segmented button. Segments share a row with a small gap; the selected one
/// becomes fully rounded and inner corners tighten while a segment is pressed.
class ConnectedButtonGroup<T> extends StatelessWidget {
  const ConnectedButtonGroup({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<ButtonGroupItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 2),
              child: _ConnectedButton(
                label: items[i].label,
                icon: items[i].icon,
                selected: items[i].value == selected,
                isFirst: i == 0,
                isLast: i == items.length - 1,
                onTap: () {
                  if (items[i].value != selected) onChanged(items[i].value);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectedButton extends StatefulWidget {
  const _ConnectedButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_ConnectedButton> createState() => _ConnectedButtonState();
}

class _ConnectedButtonState extends State<_ConnectedButton> {
  static const double _height = 48;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    const outer = Radius.circular(_height / 2);
    final inner = Radius.circular(
      _pressed ? AppShapes.extraSmall : AppShapes.small,
    );
    final radius = widget.selected
        ? const BorderRadius.all(outer)
        : BorderRadiusDirectional.horizontal(
            start: widget.isFirst ? outer : inner,
            end: widget.isLast ? outer : inner,
          ).resolve(Directionality.of(context));

    final foreground =
        widget.selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        duration: AppMotion.spatialFast,
        curve: AppMotion.spatial,
        height: _height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color:
              widget.selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          theme.textTheme.labelLarge?.copyWith(color: foreground),
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

// ─────────────────────────────────────────────────────────────────────────────
// Lists
// ─────────────────────────────────────────────────────────────────────────────

/// Expressive list: related rows sit on their own tonal segments, separated
/// by a hairline gap, and the group as a whole gets large outer corners.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const outer = Radius.circular(AppShapes.largeIncreased);
    const inner = Radius.circular(AppShapes.extraSmall);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Material(
              color: scheme.surfaceContainer,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? outer : inner,
                  bottom: i == children.length - 1 ? outer : inner,
                ),
              ),
              child: children[i],
            ),
          ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States & small pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Full-area empty / error / call-to-action state.
///
/// Always scrollable, so it never overflows on short windows and works as a
/// child of a [RefreshIndicator].
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.shape = SoftShape.cookie,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final SoftShape shape;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShapeBadge(
                      icon: icon,
                      shape: shape,
                      color: isError
                          ? scheme.errorContainer
                          : scheme.primaryContainer,
                      iconColor: isError
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered loading state.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: ExpressiveLoadingIndicator());
  }
}

/// Compact, non-interactive label on a tonal container (prices, tram lines,
/// dietary tags …).
class TonalPill extends StatelessWidget {
  const TonalPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.dense = false,
    this.textStyle,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final bool dense;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (textStyle ??
            (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium))
        ?.copyWith(color: foreground, fontWeight: FontWeight.w600);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.smallRadius,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8,
          vertical: dense ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 12 : 14, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline notice shown when content comes from the cache because the last
/// refresh failed.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: AppShapes.mediumRadius,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One day in a horizontal day selector (timetable week strip, Mensa days).
/// The selected day morphs from a rounded square into a pill.
class DayPill extends StatelessWidget {
  const DayPill({
    super.key,
    required this.weekday,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
    this.semanticLabel,
    this.animate = true,
  });

  static const double height = 60;

  final String weekday;
  final String day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color background;
    final Color foreground;
    final Color secondary;
    if (selected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
      secondary = scheme.onPrimary;
    } else if (isToday) {
      background = scheme.secondaryContainer;
      foreground = scheme.onSecondaryContainer;
      secondary = scheme.onSecondaryContainer;
    } else {
      background = scheme.surfaceContainerHigh;
      foreground = scheme.onSurface;
      secondary = scheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: AnimatedContainer(
        duration: animate ? AppMotion.spatialFast : Duration.zero,
        curve: AppMotion.spatial,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            selected ? height / 2 : AppShapes.large,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekday,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    day,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
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
