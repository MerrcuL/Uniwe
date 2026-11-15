import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../screens/cancelled_screen.dart';
import '../screens/certificates_screen.dart';
import '../screens/email_screen.dart';
import '../screens/enrolments_screen.dart';
import '../screens/exams_screen.dart';
import '../screens/grades_screen.dart';
import '../screens/login_screen.dart';
import '../screens/lsf_browser_screen.dart';
import '../screens/mensa_screen.dart';
import '../screens/moodle_screen.dart';
import '../screens/semester_screen.dart';
import '../screens/timetable_screen.dart';
import '../screens/transport_screen.dart';
import '../services/auth_service.dart';
import '../widgets/info_widgets.dart';
import 'nav_layout.dart';

/// One place of the app the user can go to: a tab of the navigation bar or
/// an entry of the menu, whichever the user's [NavLayout] says.
@immutable
class AppDestination {
  const AppDestination({
    required this.id,
    required this.tab,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.labelKey,
    this.label,
    this.subtitleKey,
    this.menuIcon,
    this.requiresLogin = false,
  }) : assert(labelKey != null || label != null);

  /// One of [NavIds].
  final String id;

  /// Its [AppTab] index (the slot in the tab stack).
  final int tab;
  final IconData icon;
  final IconData selectedIcon;

  /// The icon in the menu, when it differs from [icon].
  final IconData? menuIcon;
  final String? labelKey;

  /// A proper name that is not translated ("LSF", "Moodle").
  final String? label;
  final String? subtitleKey;

  /// Whether the screen is useless without an HTW session and does not ask
  /// for one itself.
  final bool requiresLogin;

  /// Builds the screen; [standalone] is true when it is pushed as a page of
  /// its own (from the menu) and false when it is a tab.
  final Widget Function(bool standalone) builder;

  bool get canBeTab => !NavIds.menuOnly.contains(id);

  String title(AppLocalizations l10n) => label ?? l10n.get(labelKey!);

  /// The screen as a tab. Screens that need a session get a sign-in prompt
  /// in front, since nothing else asks for it there.
  Widget buildTab(BuildContext context) {
    final screen = builder(false);
    if (!requiresLogin) return screen;
    return SignedInGate(
      title: title(AppLocalizations.of(context)),
      icon: icon,
      child: screen,
    );
  }
}

abstract final class Destinations {
  static final List<AppDestination> all = [
    AppDestination(
      id: NavIds.timetable,
      tab: AppTab.timetable,
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      labelKey: 'timetable',
      subtitleKey: 'timetableSubtitle',
      builder: (_) => const TimetableScreen(),
    ),
    AppDestination(
      id: NavIds.mensa,
      tab: AppTab.mensa,
      icon: Icons.restaurant_outlined,
      selectedIcon: Icons.restaurant,
      labelKey: 'mensa',
      subtitleKey: 'mensaSubtitle',
      builder: (_) => const MensaScreen(),
    ),
    AppDestination(
      id: NavIds.email,
      tab: AppTab.email,
      icon: Icons.email_outlined,
      selectedIcon: Icons.email,
      menuIcon: Icons.mail_outline_rounded,
      labelKey: 'email',
      subtitleKey: 'emailSubtitle',
      builder: (standalone) => EmailScreen(standalone: standalone),
    ),
    AppDestination(
      id: NavIds.transport,
      tab: AppTab.transport,
      icon: Icons.directions_transit_outlined,
      selectedIcon: Icons.directions_transit,
      labelKey: 'transport',
      subtitleKey: 'transportSubtitle',
      builder: (standalone) => TransportScreen(standalone: standalone),
    ),
    AppDestination(
      id: NavIds.lsf,
      tab: AppTab.lsf,
      icon: Icons.school_outlined,
      selectedIcon: Icons.school,
      label: 'LSF',
      subtitleKey: 'lsfSubtitle',
      requiresLogin: true,
      builder: (_) => const LsfBrowserScreen(),
    ),
    AppDestination(
      id: NavIds.moodle,
      tab: AppTab.moodle,
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Moodle',
      subtitleKey: 'moodleSubtitle',
      requiresLogin: true,
      builder: (_) => const MoodleScreen(),
    ),
    AppDestination(
      id: NavIds.grades,
      tab: AppTab.grades,
      icon: Icons.grade_outlined,
      selectedIcon: Icons.grade,
      labelKey: 'grades',
      subtitleKey: 'gradesSubtitle',
      requiresLogin: true,
      builder: (_) => const GradesScreen(),
    ),
    AppDestination(
      id: NavIds.exams,
      tab: AppTab.exams,
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      labelKey: 'exams',
      subtitleKey: 'examsSubtitle',
      requiresLogin: true,
      builder: (_) => const ExamsScreen(),
    ),
    AppDestination(
      id: NavIds.enrolments,
      tab: AppTab.enrolments,
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      labelKey: 'enrolments',
      subtitleKey: 'enrolmentsSubtitle',
      requiresLogin: true,
      builder: (_) => const EnrolmentsScreen(),
    ),
    AppDestination(
      id: NavIds.cancelled,
      tab: AppTab.cancelled,
      icon: Icons.event_busy_outlined,
      selectedIcon: Icons.event_busy,
      labelKey: 'cancelledShort',
      subtitleKey: 'cancelledSubtitle',
      builder: (_) => const CancelledScreen(),
    ),
    AppDestination(
      id: NavIds.semester,
      tab: AppTab.semester,
      icon: Icons.date_range_outlined,
      selectedIcon: Icons.date_range,
      labelKey: 'semester',
      subtitleKey: 'semesterSubtitle',
      builder: (_) => const SemesterScreen(),
    ),
    AppDestination(
      id: NavIds.certificates,
      tab: AppTab.certificates,
      icon: Icons.workspace_premium_outlined,
      selectedIcon: Icons.workspace_premium,
      labelKey: 'certificates',
      subtitleKey: 'certificatesSubtitle',
      requiresLogin: true,
      builder: (_) => const CertificatesScreen(),
    ),
  ];

  static final Map<String, AppDestination> _byId = {
    for (final d in all) d.id: d,
  };

  static AppDestination byId(String id) => _byId[id]!;

  static AppDestination? maybeById(String id) => _byId[id];

  /// Opens [destination] as a page of its own, offering to sign in first
  /// when it needs the HTW account.
  static Future<void> push(
    BuildContext context,
    AppDestination destination,
  ) async {
    final navigator = Navigator.of(context);
    if (destination.requiresLogin &&
        !context.read<AuthService>().isAuthenticated) {
      final signedIn = await showLoginDialog(context);
      if (!signedIn) return;
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => destination.builder(true)),
    );
  }
}
