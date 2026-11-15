import 'dart:async';

import 'package:flutter/foundation.dart';

/// Indices of the top-level destinations, in navigation order.
abstract final class AppTab {
  static const int timetable = 0;
  static const int mensa = 1;
  static const int email = 2;
  static const int transport = 3;
  static const int more = 4;
  static const int lsf = 5;
  static const int moodle = 6;
  static const int grades = 7;
  static const int exams = 8;
  static const int enrolments = 9;
  static const int cancelled = 10;
  static const int semester = 11;
  static const int certificates = 12;

  /// Number of ids above (the size of the tab stack).
  static const int count = 13;
}

/// App-wide UI events shared between the navigation shell and its tabs.
///
/// Lives in its own library so screens do not have to import `main.dart`
/// (which previously created a circular import).
abstract final class AppEvents {
  /// The currently visible top-level tab.
  static final ValueNotifier<int> currentTab = ValueNotifier<int>(0);

  static final StreamController<int> _reselected =
      StreamController<int>.broadcast();
  static final Map<int, Future<bool> Function()> _backHandlers = {};

  /// Emits the tab index when the already-selected destination is tapped
  /// again. Tabs use it as a "refresh" gesture.
  static Stream<int> get tabReselected => _reselected.stream;

  static void reselectTab(int index) => _reselected.add(index);

  static final StreamController<String> _openRequests =
      StreamController<String>.broadcast();

  /// Emits the id of a destination that should be brought on screen, e.g.
  /// because its home screen widget was tapped.
  static Stream<String> get openRequests => _openRequests.stream;

  static void requestOpen(String destinationId) =>
      _openRequests.add(destinationId);

  /// Lets a tab consume the system back gesture (e.g. web view history).
  static void registerBackHandler(int tab, Future<bool> Function() handler) {
    _backHandlers[tab] = handler;
  }

  static void unregisterBackHandler(int tab, Future<bool> Function() handler) {
    if (identical(_backHandlers[tab], handler)) _backHandlers.remove(tab);
  }

  /// Returns true when the tab handled the back gesture itself.
  static Future<bool> handleBack(int tab) async {
    final handler = _backHandlers[tab];
    if (handler == null) return false;
    try {
      return await handler();
    } catch (_) {
      return false;
    }
  }
}
