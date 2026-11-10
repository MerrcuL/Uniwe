import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Shows [builder]'s content in the app's modal bottom sheet.
///
/// Unlike a plain `showModalBottomSheet`, the sheet takes part in Android's
/// predictive back gesture: while the user drags from the screen edge the
/// whole sheet shrinks towards the bottom, previewing the dismissal, and
/// either closes (gesture completed) or springs back (gesture cancelled).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Durations.medium4,
      reverseDuration: Durations.medium1,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    ),
    // The surface is drawn by [_PredictiveBackSheet] so that it can be
    // transformed as one piece together with its content.
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    clipBehavior: Clip.none,
    builder: (sheetContext) => _PredictiveBackSheet(child: builder(sheetContext)),
  );
}

class _PredictiveBackSheet extends StatefulWidget {
  const _PredictiveBackSheet({required this.child});

  final Widget child;

  @override
  State<_PredictiveBackSheet> createState() => _PredictiveBackSheetState();
}

class _PredictiveBackSheetState extends State<_PredictiveBackSheet>
    with WidgetsBindingObserver {
  /// 0 = resting, 1 = back gesture fully pulled.
  double _progress = 0;
  bool _gestureActive = false;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // Only the sheet on top answers the gesture.
    if (!mounted || !(_route?.isCurrent ?? false)) return false;
    setState(() {
      _gestureActive = true;
      _progress = backEvent.progress.clamp(0.0, 1.0);
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureActive || !mounted) return;
    setState(() => _progress = backEvent.progress.clamp(0.0, 1.0));
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureActive || !mounted) return;
    _gestureActive = false;
    // Close from where the preview left the sheet.
    Navigator.of(context).maybePop();
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureActive || !mounted) return;
    setState(() {
      _gestureActive = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _progress),
      // Follow the finger directly; animate only the spring-back.
      duration: _gestureActive ? Duration.zero : Durations.short4,
      curve: Easing.standardDecelerate,
      builder: (context, progress, child) => Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()
          ..translateByDouble(0, progress * 24, 0, 1)
          ..scaleByDouble(1 - 0.1 * progress, 1 - 0.1 * progress, 1, 1),
        child: child,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppShapes.extraLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle (the sheet is still dismissible by dragging).
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(child: widget.child),
          ],
        ),
      ),
    );
  }
}
