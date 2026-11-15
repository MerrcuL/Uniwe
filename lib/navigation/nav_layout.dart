import 'package:flutter/foundation.dart';

/// Where a destination is shown.
enum NavSection { bar, menu, hidden }

/// Ids of every destination of the app. Kept apart from the screens so the
/// settings can store a layout without importing the UI.
abstract final class NavIds {
  static const String timetable = 'timetable';
  static const String mensa = 'mensa';
  static const String email = 'email';
  static const String transport = 'transport';
  static const String lsf = 'lsf';
  static const String moodle = 'moodle';
  static const String grades = 'grades';
  static const String exams = 'exams';
  static const String enrolments = 'enrolments';
  static const String cancelled = 'cancelled';
  static const String semester = 'semester';
  static const String certificates = 'certificates';

  static const List<String> all = [
    timetable,
    mensa,
    email,
    transport,
    lsf,
    moodle,
    grades,
    exams,
    enrolments,
    cancelled,
    semester,
    certificates,
  ];

  /// LSF and Moodle are full-screen browsers; they only open from the menu.
  static const Set<String> menuOnly = {lsf, moodle};
}

/// The user's arrangement of the navigation bar and the menu.
///
/// The menu itself always is the last item of the bar and is not part of
/// the layout; neither are the settings at the bottom of the menu.
@immutable
class NavLayout {
  const NavLayout._(this.bar, this.menu, this.hidden);

  /// The bar holds the menu plus at most this many destinations.
  static const int maxBarItems = 4;

  static const NavLayout standard = NavLayout._(
    [NavIds.timetable, NavIds.mensa, NavIds.transport],
    [
      NavIds.lsf,
      NavIds.email,
      NavIds.moodle,
      NavIds.grades,
      NavIds.exams,
      NavIds.enrolments,
      NavIds.cancelled,
      NavIds.semester,
      NavIds.certificates,
    ],
    [],
  );

  final List<String> bar;
  final List<String> menu;
  final List<String> hidden;

  /// Builds a valid layout from stored lists: unknown and duplicate ids are
  /// dropped, destinations that are new to this version join the menu, and
  /// the bar keeps between one and [maxBarItems] tab-capable entries.
  factory NavLayout.normalized({
    required List<String> bar,
    required List<String> menu,
    required List<String> hidden,
  }) {
    final seen = <String>{};
    List<String> clean(List<String> ids) => [
          for (final id in ids)
            if (NavIds.all.contains(id) && seen.add(id)) id,
        ];

    final newBar = clean(bar);
    final newMenu = clean(menu);
    final newHidden = clean(hidden);

    final misplaced =
        newBar.where((id) => NavIds.menuOnly.contains(id)).toList();
    newBar.removeWhere(misplaced.contains);
    final overflow = newBar.length > maxBarItems
        ? newBar.sublist(maxBarItems)
        : const <String>[];
    if (overflow.isNotEmpty) newBar.removeRange(maxBarItems, newBar.length);
    newMenu.insertAll(0, [...misplaced, ...overflow]);

    for (final id in NavIds.all) {
      if (seen.add(id)) newMenu.add(id);
    }

    if (newBar.isEmpty) {
      // The bar never consists of the menu alone.
      final fallback = [...newMenu, ...newHidden]
          .firstWhere((id) => !NavIds.menuOnly.contains(id));
      newMenu.remove(fallback);
      newHidden.remove(fallback);
      newBar.add(fallback);
    }

    return NavLayout._(
      List.unmodifiable(newBar),
      List.unmodifiable(newMenu),
      List.unmodifiable(newHidden),
    );
  }

  List<String> items(NavSection section) => switch (section) {
        NavSection.bar => bar,
        NavSection.menu => menu,
        NavSection.hidden => hidden,
      };

  NavSection sectionOf(String id) {
    if (bar.contains(id)) return NavSection.bar;
    if (hidden.contains(id)) return NavSection.hidden;
    return NavSection.menu;
  }

  /// Why [id] cannot be moved to [section], or null if it can.
  NavMoveProblem? problemWithMove(String id, NavSection section) {
    final from = sectionOf(id);
    if (section == NavSection.bar) {
      if (NavIds.menuOnly.contains(id)) return NavMoveProblem.menuOnly;
      if (from != NavSection.bar && bar.length >= maxBarItems) {
        return NavMoveProblem.barFull;
      }
    } else if (from == NavSection.bar && bar.length <= 1) {
      return NavMoveProblem.barEmpty;
    }
    return null;
  }

  /// This layout with [id] moved to [index] of [section] (the end when
  /// omitted). Returns `this` when the move is not allowed.
  NavLayout move(String id, NavSection section, [int? index]) {
    if (!NavIds.all.contains(id)) return this;
    if (problemWithMove(id, section) != null) return this;
    final lists = {
      NavSection.bar: [...bar],
      NavSection.menu: [...menu],
      NavSection.hidden: [...hidden],
    };
    for (final list in lists.values) {
      list.remove(id);
    }
    final target = lists[section]!;
    target.insert((index ?? target.length).clamp(0, target.length), id);
    return NavLayout._(
      List.unmodifiable(lists[NavSection.bar]!),
      List.unmodifiable(lists[NavSection.menu]!),
      List.unmodifiable(lists[NavSection.hidden]!),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavLayout &&
      listEquals(other.bar, bar) &&
      listEquals(other.menu, menu) &&
      listEquals(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(bar),
        Object.hashAll(menu),
        Object.hashAll(hidden),
      );
}

enum NavMoveProblem {
  /// The bar already holds [NavLayout.maxBarItems] destinations.
  barFull,

  /// It would leave the bar with the menu alone.
  barEmpty,

  /// LSF and Moodle cannot be tabs.
  menuOnly,
}
