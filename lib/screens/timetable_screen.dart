import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../models/timetable_event.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../services/timetable_store.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import '../utils/timetable_text.dart';
import '../widgets/date_pager.dart';
import '../widgets/expressive.dart';
import '../widgets/timetable/event_card.dart';
import '../widgets/timetable/event_details_sheet.dart';
import '../widgets/timetable/week_grid.dart';
import 'login_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const double _weekBarHeight = 56;
  static const double _dayStripHeight = DayPill.height + 16;

  late final AuthService _auth;
  late final TimetableStore _store;

  /// The selected day. May be a weekend day while weekends are hidden; always
  /// read it through [_effectiveDate].
  late final ValueNotifier<DateTime> _selected;

  late bool _isWeekView;
  late bool _wasAuthenticated;
  DateTime? _requestedDate;
  StreamSubscription<int>? _reselectSubscription;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _auth = context.read<AuthService>();
    _store = TimetableStore(fetch: _auth.fetchTimetable);
    _isWeekView = settings.timetableIsWeekView;
    _wasAuthenticated = _auth.isAuthenticated;

    _selected = ValueNotifier<DateTime>(
      Dates.skipWeekend(Dates.today(), showWeekends: settings.showWeekends),
    )..addListener(_onSelectionChanged);

    _auth.addListener(_onAuthChanged);

    _reselectSubscription = AppEvents.tabReselected.listen((index) {
      if (index == AppTab.timetable && mounted) {
        HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
        _forceRefresh();
      }
    });
  }

  @override
  void dispose() {
    _reselectSubscription?.cancel();
    _auth.removeListener(_onAuthChanged);
    _selected.dispose();
    _store.dispose();
    super.dispose();
  }

  bool get _showWeekends => context.read<SettingsService>().showWeekends;

  DateTime get _effectiveDate =>
      Dates.skipWeekend(_selected.value, showWeekends: _showWeekends);

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    final isAuthenticated = _auth.isAuthenticated;
    if (isAuthenticated == _wasAuthenticated) return;
    _wasAuthenticated = isAuthenticated;
    if (isAuthenticated) {
      _requestedDate = null; // load again for the new account
      if (mounted) setState(() {});
    } else {
      // Never keep one account's timetable around for the next.
      _store.clear();
    }
  }

  /// Makes sure the visible week (and the neighbour the user can peek into
  /// by swiping) is loaded. Cheap to call repeatedly.
  void _ensureLoaded() {
    if (!mounted || !_auth.isAuthenticated) return;
    final date = _effectiveDate;
    final week = IsoWeek.fromDate(date);
    _store.refresh(week);

    if (!_isWeekView) {
      final lastDay = _showWeekends ? DateTime.sunday : DateTime.friday;
      if (date.weekday == lastDay) _store.refresh(week.next);
      if (date.weekday == DateTime.monday) _store.refresh(week.previous);
    }
  }

  Future<void> _forceRefresh() async {
    if (!_auth.isAuthenticated) return;
    final ok = await _store.refresh(
      IsoWeek.fromDate(_effectiveDate),
      force: true,
    );
    if (!ok && mounted && _auth.isAuthenticated) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).get('errorUpdate')),
          ),
        );
    }
  }

  void _haptic() =>
      HapticService.selection(context.read<SettingsService>().hapticsEnabled);

  void _shiftWeek(int delta) {
    _haptic();
    final d = _effectiveDate;
    _selected.value = DateTime(d.year, d.month, d.day + 7 * delta);
  }

  void _goToToday() {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    _selected.value =
        Dates.skipWeekend(Dates.today(), showWeekends: _showWeekends);
  }

  void _selectDay(DateTime date) {
    if (Dates.isSameDay(date, _effectiveDate)) return;
    _haptic();
    _selected.value = date;
  }

  void _toggleView() {
    _haptic();
    setState(() => _isWeekView = !_isWeekView);
    context.read<SettingsService>().updateTimetableIsWeekView(_isWeekView);
  }

  void _openEvent(TimetableEvent event) {
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    showEventDetails(context, event);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showWeekends =
        context.select<SettingsService, bool>((s) => s.showWeekends);
    final animationsEnabled =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);
    final isAuthenticated =
        context.select<AuthService, bool>((a) => a.isAuthenticated);

    final dayCount = showWeekends ? 7 : 5;
    final date =
        Dates.skipWeekend(_selected.value, showWeekends: showWeekends);
    final week = IsoWeek.fromDate(date);

    // Covers every way the visible day can change (swipe, arrows, "today",
    // the weekend setting, signing in) in one place.
    if (isAuthenticated && date != _requestedDate) {
      _requestedDate = date;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
    }

    final viewSwitchDuration =
        animationsEnabled ? Durations.long2 : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('timetable')),
        actions: [
          if (isAuthenticated) ...[
            IconButton(
              icon: const Icon(Icons.today_outlined),
              tooltip: l10n.get('goToToday'),
              onPressed: _goToToday,
            ),
            IconButton(
              icon: Icon(_isWeekView
                  ? Icons.view_agenda_outlined
                  : Icons.calendar_view_week_outlined),
              tooltip: l10n.get(_isWeekView ? 'dayView' : 'weekView'),
              onPressed: _toggleView,
            ),
            ListenableBuilder(
              listenable: _store,
              builder: (context, _) {
                final loading = _store.isLoading(week);
                return IconButton(
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: l10n.get('refresh'),
                  onPressed: loading
                      ? null
                      : () {
                          HapticService.confirm(
                            context.read<SettingsService>().hapticsEnabled,
                          );
                          _forceRefresh();
                        },
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: !isAuthenticated
          ? _buildLoginCta(l10n)
          : Column(
              children: [
                _WeekBar(
                  week: week,
                  dayCount: dayCount,
                  onPrevious: () => _shiftWeek(-1),
                  onNext: () => _shiftWeek(1),
                  onLabelTap: _goToToday,
                ),
                // The day strip folds away while the views cross-fade, so
                // the grid glides up into its place instead of jumping.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _isWeekView ? 0 : 1),
                  duration: viewSwitchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  builder: (context, visible, child) => ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: visible.clamp(0.0, 1.0),
                      child: Opacity(
                        opacity: visible.clamp(0.0, 1.0),
                        child: child,
                      ),
                    ),
                  ),
                  child: IgnorePointer(
                    ignoring: _isWeekView,
                    child: _DayStrip(
                      week: week,
                      dayCount: dayCount,
                      selected: date,
                      animate: animationsEnabled,
                      onSelect: _selectDay,
                    ),
                  ),
                ),
                _OfflineNotice(store: _store, week: week),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: viewSwitchDuration,
                    // A calm, overlapping cross-fade: the old view is still
                    // fading out while the new one settles in.
                    switchInCurve: Easing.standardDecelerate,
                    switchOutCurve: Easing.standardAccelerate,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.985, end: 1)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: _isWeekView
                        ? DatePager(
                            key: ValueKey('week_$dayCount'),
                            selected: _selected,
                            animate: animationsEnabled,
                            onUserPaged: _haptic,
                            pageOf: (d) => IsoWeek.fromDate(Dates.skipWeekend(
                              d,
                              showWeekends: showWeekends,
                            )).index,
                            // Keep the weekday when paging by week.
                            dateOf: (page, current) {
                              final weekday = Dates.skipWeekend(
                                current,
                                showWeekends: showWeekends,
                              ).weekday;
                              return IsoWeek.fromIndex(page).day(weekday - 1);
                            },
                            pageBuilder: (context, page) =>
                                _buildWeekPage(IsoWeek.fromIndex(page), dayCount),
                          )
                        : DatePager(
                            key: ValueKey('day_$dayCount'),
                            selected: _selected,
                            animate: animationsEnabled,
                            onUserPaged: _haptic,
                            pageOf: (d) => Dates.dayPage(d, dayCount),
                            dateOf: (page, _) =>
                                Dates.dateOfDayPage(page, dayCount),
                            pageBuilder: (context, page) => _buildDayPage(
                              Dates.dateOfDayPage(page, dayCount),
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLoginCta(AppLocalizations l10n) {
    return StatusMessage(
      icon: Icons.school_outlined,
      title: l10n.get('scheduleUnavailable'),
      message: l10n.get('scheduleLoginPrompt'),
      action: FilledButton.icon(
        onPressed: () {
          HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
          showLoginDialog(context);
        },
        icon: const Icon(Icons.login_rounded),
        label: Text(l10n.get('loginButton')),
      ),
    );
  }

  /// Loading and error placeholders shared by both views. Returns null when
  /// the week has data to show.
  Widget? _buildPlaceholder(IsoWeek week, WeekSchedule? schedule) {
    if (schedule != null) return null;
    if (_store.hasFailed(week) && !_store.isLoading(week)) {
      final l10n = AppLocalizations.of(context);
      return StatusMessage(
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorNetwork'),
        action: FilledButton.tonalIcon(
          onPressed: () {
            HapticService.confirm(
              context.read<SettingsService>().hapticsEnabled,
            );
            _store.refresh(week, force: true);
          },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }
    return const LoadingState();
  }

  Widget _buildWeekPage(IsoWeek week, int dayCount) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final schedule = _store.schedule(week);
        final placeholder = _buildPlaceholder(week, schedule);
        if (placeholder != null) return placeholder;
        return WeekGrid(
          week: week,
          schedule: schedule!,
          dayCount: dayCount,
          onEventTap: _openEvent,
          onDayTap: (day) {
            _haptic();
            _selected.value = day;
            setState(() => _isWeekView = false);
            context.read<SettingsService>().updateTimetableIsWeekView(false);
          },
        );
      },
    );
  }

  Widget _buildDayPage(DateTime date) {
    final week = IsoWeek.fromDate(date);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final schedule = _store.schedule(week);
        final placeholder = _buildPlaceholder(week, schedule);
        if (placeholder != null) return placeholder;

        final l10n = AppLocalizations.of(context);
        final events = schedule!.byDay[date.weekday - 1];
        return RefreshIndicator(
          onRefresh: _forceRefresh,
          child: events.isEmpty
              ? StatusMessage(
                  icon: Icons.celebration_outlined,
                  shape: SoftShape.flower,
                  title: l10n.get('noClasses'),
                  message: l10n.get('enjoyFreeTime'),
                )
              : _DayEventList(events: events, onEventTap: _openEvent),
        );
      },
    );
  }
}

class _DayEventList extends StatelessWidget {
  const _DayEventList({required this.events, required this.onEventTap});

  final List<TimetableEvent> events;
  final ValueChanged<TimetableEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact =
        context.select<SettingsService, bool>((s) => s.compactView);
    final showBreaks =
        context.select<SettingsService, bool>((s) => s.showBreakTime);
    final gutter = AppSpacing.gutter(context);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          gutter, 8, gutter, AppSpacing.bottomInset(context)),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final card = EventCard(
          event: event,
          compact: compact,
          onTap: () => onEventTap(event),
        );
        if (index == events.length - 1) return card;

        // Gap to the next class; overlapping classes have none.
        final end = event.endMinutes;
        final nextStart = events[index + 1].startMinutes;
        final gap = (end != null && nextStart != null) ? nextStart - end : 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card,
            if (showBreaks && gap > 0)
              BreakIndicator(label: TimetableText.breakLabel(gap, l10n))
            else
              SizedBox(height: compact ? 8 : 12),
          ],
        );
      },
    );
  }
}

/// "‹  09.11. – 13.11. · Week 46  ›"
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.dayCount,
    required this.onPrevious,
    required this.onNext,
    required this.onLabelTap,
  });

  final IsoWeek week;
  final int dayCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLabelTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: _TimetableScreenState._weekBarHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 100) return;
          velocity > 0 ? onPrevious() : onNext();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPrevious,
                tooltip: l10n.get('previousWeek'),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Tooltip(
                  message: l10n.get('goToToday'),
                  child: InkWell(
                    onTap: onLabelTap,
                    borderRadius: AppShapes.largeRadius,
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${Formats.dayMonth(week.day(0))} – ${Formats.dayMonth(week.day(dayCount - 1))}',
                            maxLines: 1,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${l10n.get('weekTitle')} ${week.weekNumber} · ${week.year}',
                            maxLines: 1,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: onNext,
                tooltip: l10n.get('nextWeek'),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.week,
    required this.dayCount,
    required this.selected,
    required this.animate,
    required this.onSelect,
  });

  final IsoWeek week;
  final int dayCount;
  final DateTime selected;
  final bool animate;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final today = Dates.today();

    return SizedBox(
      height: _TimetableScreenState._dayStripHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            for (var d = 0; d < dayCount; d++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: DayPill(
                    weekday: Formats.weekdayShort(week.day(d), locale),
                    day: week.day(d).day.toString(),
                    selected: Dates.isSameDay(week.day(d), selected),
                    isToday: Dates.isSameDay(week.day(d), today),
                    semanticLabel: Formats.fullDate(week.day(d), locale),
                    animate: animate,
                    onTap: () => onSelect(week.day(d)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tells the user they are looking at cached data after a failed refresh.
class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.store, required this.week});

  final TimetableStore store;
  final IsoWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final schedule = store.schedule(week);
        final show = schedule != null &&
            store.hasFailed(week) &&
            !store.isLoading(week);
        final fetchedAt = schedule?.fetchedAt;

        return AnimatedSize(
          duration: Durations.medium2,
          curve: Easing.standard,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: InfoBanner(
                    icon: Icons.cloud_off_outlined,
                    text: fetchedAt == null
                        ? l10n.get('offlineCache')
                        : '${l10n.get('offlineCache')} '
                            '${l10n.get('lastUpdated')}: ${Formats.timestamp(fetchedAt)}',
                  ),
                ),
        );
      },
    );
  }
}
