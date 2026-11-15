import 'dart:async';

import 'package:flutter/widgets.dart';

/// Completes once the page transition of the route around [context] has
/// finished (right away when there is none, or it is already done).
///
/// Heavy work such as creating a web view is started after this, so it does
/// not make the slide-in animation stutter.
Future<void> routeTransitionDone(BuildContext context) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    return Future<void>.value();
  }
  final done = Completer<void>();
  void listener(AnimationStatus status) {
    // Dismissed: the page was closed again before it finished opening.
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      animation.removeStatusListener(listener);
      if (!done.isCompleted) done.complete();
    }
  }

  animation.addStatusListener(listener);
  return done.future;
}

/// Whether the route around [context] is being closed (or already is).
/// Work that would start a web view is skipped then: doing it in the middle
/// of the closing animation makes it stutter.
bool routeIsClosing(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null) return false;
  final status = route.animation?.status;
  return !route.isActive ||
      status == AnimationStatus.reverse ||
      status == AnimationStatus.dismissed;
}
