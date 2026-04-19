import 'dart:developer';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../utils/iso_week.dart';

import '../l10n/app_localizations.dart';
import '../models/timetable_event.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/settings_service.dart';
import '../services/haptic_service.dart';
import 'login_screen.dart';
import 'lsf_browser_screen.dart';
import '../main.dart' as import_main;

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late bool _isWeekView;
  bool _isLoading = false;
  bool _showWeekends = false;

  IsoWeek _currentWeek = IsoWeek.current();
  final Map<String, List<TimetableEvent>> _weeklyEvents = {};
  DateTime? _lastFetched;
  bool _networkFailed = false;
  bool? _wasAuthenticated;

  // FIX 4: _slideDirection is now always set BEFORE setState to avoid frame-timing races.
  // +1 = forward (next week), -1 = back (previous week)
  int _slideDirection = 1;

  DateTime _lastSwipe = DateTime.now();
  int _lastTabIndex = 0;
  
  StreamSubscription<int>? _tabRefreshSubscription;

  List<String> get _days => _showWeekends
      ? [
          'Montag',
          'Dienstag',
          'Mittwoch',
          'Donnerstag',
          'Freitag',
          'Samstag',
          'Sonntag'
        ]
      : ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];

  @override
  void initState() {
    super.initState();

    _tabRefreshSubscription = import_main.tabRefreshController.stream.listen((index) {
      if (index == 0 && mounted) {
        final haptics = context.read<SettingsService>().hapticsEnabled;
        HapticService.confirm(haptics);
        _forceRefresh();
      }
    });

    final settings = context.read<SettingsService>();
    _showWeekends = settings.showWeekends;
    _isWeekView = settings.timetableIsWeekView;
    _wasAuthenticated = context.read<AuthService>().isAuthenticated;
    int currentDayIndex = DateTime.now().weekday - 1;

    if (!_showWeekends && currentDayIndex > 4) {
      currentDayIndex = 0;
      _currentWeek = _currentWeek.next;
    } else if (_showWeekends && currentDayIndex > 6) {
      currentDayIndex = 0;
    }

    _tabController = TabController(
        length: _showWeekends ? 7 : 5,
        vsync: this,
        initialIndex: currentDayIndex.clamp(0, (_showWeekends ? 7 : 5) - 1));
    _lastTabIndex = currentDayIndex;
    _tabController.addListener(_handleTabChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDataForWeek(_currentWeek);
    });
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging ||
        _tabController.index != _lastTabIndex) {
      if (_tabController.index != _lastTabIndex) {
        final settings = context.read<SettingsService>();
        HapticService.selection(settings.hapticsEnabled);
        _lastTabIndex = _tabController.index;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthService>(context);
    final isAuthenticated = auth.isAuthenticated;

    if (isAuthenticated && (_wasAuthenticated == false)) {
      final weekStr = '${_currentWeek.weekNumber}_${_currentWeek.year}';
      final hasData = _weeklyEvents.containsKey(weekStr) &&
          _weeklyEvents[weekStr]!.isNotEmpty;

      if (!hasData && !_isLoading) {
        _fetchDataForWeek(_currentWeek);
      }
    }
    _wasAuthenticated = isAuthenticated;
  }

  @override
  void dispose() {
    _tabRefreshSubscription?.cancel();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  List<String> _getShortDays(BuildContext context) {
    if (Localizations.localeOf(context).languageCode == 'de') {
      return _showWeekends
          ? ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
          : ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
    }
    return _showWeekends
        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  }

  String _translateSubjectType(String raw, BuildContext context,
      {bool isExam = false}) {
    final l10n = AppLocalizations.of(context);
    if (isExam) return l10n.get('examLabel');
    if (Localizations.localeOf(context).languageCode == 'de') return raw;
    final lower = raw.toLowerCase();
    if (lower.contains('vorlesung')) return 'Lecture';
    if (lower.contains('übung')) return 'Exercise';
    if (lower.contains('seminaristischer lehrvortrag')) {
      return 'Seminar Lecture';
    }
    if (lower.contains('praktikum')) return 'Practical Course';
    return raw;
  }

  String _translateFrequency(String raw, BuildContext context) {
    final lower = raw.toLowerCase();
    final isDe = Localizations.localeOf(context).languageCode == 'de';

    if (lower.contains('wöch')) return isDe ? 'wöchentlich' : 'weekly';
    if (lower.contains('einzelt')) {
      return isDe ? 'Einzeltermin' : 'Single event';
    }
    if (lower.contains('14-täg')) return isDe ? '14-täglich' : 'bi-weekly';
    if (lower.contains('unger. w')) {
      return isDe ? 'ungerade Woche' : 'odd weeks';
    }
    if (lower.contains('ger. w')) return isDe ? 'gerade Woche' : 'even weeks';
    return raw;
  }

  Future<void> _fetchDataForWeek(IsoWeek targetWeek,
      {bool skipCache = false}) async {
    final weekStr = '${targetWeek.weekNumber}_${targetWeek.year}';
    final cacheKey = CacheService.weekKey(weekStr);
    final cache = CacheService.instance;

    if (!skipCache) {
      final cached = await cache.load(cacheKey);
      if (cached.data != null) {
        final events = (cached.data as List)
            .map((e) => TimetableEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (mounted) {
          setState(() {
            _weeklyEvents[weekStr] = events;
            _lastFetched = cached.timestamp;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = true);
      }
    }

    if (!mounted) return;
    final auth = context.read<AuthService>();
    try {
      final rawEvents = await auth.fetchTimetable(weekStr);
      if (rawEvents.isNotEmpty) {
        await cache.save(cacheKey, rawEvents.map((e) => e.toJson()).toList());
        if (mounted) {
          setState(() {
            _weeklyEvents[weekStr] = rawEvents;
            _lastFetched = DateTime.now();
            _networkFailed = false;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _networkFailed = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      log('Error fetching timetable: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _networkFailed = true;
        });
      }
    }
  }

  Future<void> _shiftWeek(int offset, {bool preserveDay = false}) async {
    IsoWeek targetWeek = _currentWeek;
    int targetDayIndex = _tabController.index;

    if (offset > 0) {
      targetWeek = _currentWeek.next;
      if (!preserveDay) targetDayIndex = 0;
    } else if (offset < 0) {
      targetWeek = _currentWeek.previous;
      if (!preserveDay) targetDayIndex = _tabController.length - 1;
    } else {
      targetWeek = IsoWeek.current();
      targetDayIndex = DateTime.now().weekday - 1;
      if (!_showWeekends && targetDayIndex > 4) {
        targetDayIndex = 0;
        targetWeek = targetWeek.next;
      } else if (_showWeekends && targetDayIndex > 6) {
        targetDayIndex = 0;
      }
    }

    // Pre-load cache so the animation starts with data
    final weekStr = '${targetWeek.weekNumber}_${targetWeek.year}';
    final cached =
        await CacheService.instance.load(CacheService.weekKey(weekStr));
    List<TimetableEvent>? cachedEvents;
    if (cached.data != null) {
      cachedEvents = (cached.data as List)
          .map((e) => TimetableEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // FIX 1 + FIX 4: Compute direction BEFORE setState so transitionBuilder always
    // reads the correct value in the same build frame that setState triggers.
    // For offset == 0 ("go to today"), compare the target week against the current
    // week instead of blindly assuming forward.
    final int newDirection;
    if (offset > 0) {
      newDirection = 1;
    } else if (offset < 0) {
      newDirection = -1;
    } else {
      // Navigating to today: slide forward if today's week is the same or ahead,
      // slide backward if today's week is behind the currently displayed week.
      final bool targetIsAheadOrSame = targetWeek.year > _currentWeek.year ||
          (targetWeek.year == _currentWeek.year &&
              targetWeek.weekNumber >= _currentWeek.weekNumber);
      newDirection = targetIsAheadOrSame ? 1 : -1;
    }
    _slideDirection = newDirection;

    if (mounted) {
      setState(() {
        _currentWeek = targetWeek;
        if (cachedEvents != null) {
          _weeklyEvents[weekStr] = cachedEvents;
          _lastFetched = cached.timestamp;
          _networkFailed = false;
        }
        if (!_isWeekView && (offset != 0 || !preserveDay)) {
          final int targetIndex =
              targetDayIndex.clamp(0, _tabController.length - 1);

          // Only swap if the day index is actually changing
          if (_tabController.index != targetIndex) {
            // 1. Unlink the old controller but keep it alive for the exiting view
            final oldController = _tabController;
            oldController.removeListener(_handleTabChange);

            // 2. Create a fresh controller for the entering view
            _tabController = TabController(
              length: _showWeekends ? 7 : 5,
              vsync: this,
              initialIndex: targetIndex,
            );
            _lastTabIndex = targetIndex;
            _tabController.addListener(_handleTabChange);

            // 3. Dispose the old controller after the 500ms slide animation finishes
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted) oldController.dispose();
            });
          }
        }
      });
    }

    _fetchDataForWeek(_currentWeek, skipCache: true);
  }

  Future<void> _forceRefresh() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final weekStr = '${_currentWeek.weekNumber}_${_currentWeek.year}';
    final cacheKey = CacheService.weekKey(weekStr);
    final auth = context.read<AuthService>();
    try {
      final rawEvents = await auth.fetchTimetable(weekStr);

      if (rawEvents.isNotEmpty) {
        await CacheService.instance.save(
          cacheKey,
          rawEvents.map((e) => e.toJson()).toList(),
        );
        if (mounted) {
          setState(() {
            _weeklyEvents[weekStr] = rawEvents;
            _lastFetched = DateTime.now();
            _networkFailed = false;
            _isLoading = false;
          });
        }
      } else {
        final hasExisting = _weeklyEvents.containsKey(weekStr) &&
            _weeklyEvents[weekStr]!.isNotEmpty;
        if (mounted) {
          setState(() {
            _isLoading = false;
            _networkFailed = hasExisting;
          });
          if (hasExisting) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).get('errorNetwork')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      log('Force refresh failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _networkFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aktualisierung fehlgeschlagen.')),
        );
      }
    }
  }

  String _formatDateShort(DateTime date) {
    return DateFormat('dd.MM').format(date);
  }

  List<TimetableEvent> _getEventsForDay(String day) {
    final weekStr = '${_currentWeek.weekNumber}_${_currentWeek.year}';
    final events = _weeklyEvents[weekStr] ?? [];
    return events
        .where((e) => e.day.toLowerCase() == day.toLowerCase())
        .toList();
  }

  void _updateTabController(bool showWeekends) {
    _showWeekends = showWeekends;
    int currentDayIndex = DateTime.now().weekday - 1;
    bool weekAdvanced = false;

    if (!_showWeekends && currentDayIndex > 4) {
      currentDayIndex = 0;
      if (_currentWeek == IsoWeek.current()) {
        _currentWeek = _currentWeek.next;
        weekAdvanced = true;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabController.removeListener(_handleTabChange);
      _tabController.dispose();
      setState(() {
        _tabController = TabController(
            length: _showWeekends ? 7 : 5,
            vsync: this,
            initialIndex:
                currentDayIndex.clamp(0, (_showWeekends ? 7 : 5) - 1));
        _lastTabIndex = _tabController.index;
        _tabController.addListener(_handleTabChange);
        if (weekAdvanced) {
          _fetchDataForWeek(_currentWeek);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDe = Localizations.localeOf(context).languageCode == 'de';

    final showWeekends =
        context.select<SettingsService, bool>((s) => s.showWeekends);
    final hapticsEnabled =
        context.select<SettingsService, bool>((s) => s.hapticsEnabled);
    final animationsEnabled =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);

    if (showWeekends != _showWeekends) {
      _updateTabController(showWeekends);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('timetable')),
        centerTitle: true,
        leading: IconButton(
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          tooltip: isDe ? 'Aktualisieren' : 'Refresh',
          onPressed: _isLoading
              ? null
              : () {
                  HapticService.confirm(hapticsEnabled);
                  _forceRefresh();
                },
        ),
        actions: [
          if (_networkFailed &&
              _lastFetched != null &&
              DateTime.now().difference(_lastFetched!).inMinutes > 30)
            Tooltip(
              message:
                  'Zuletzt aktualisiert: ${DateFormat('HH:mm').format(_lastFetched!)}',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Go to today',
            onPressed: () {
              HapticService.confirm(hapticsEnabled);
              _shiftWeek(0);
            },
          ),
          IconButton(
            icon: Icon(_isWeekView ? Icons.view_day : Icons.calendar_view_week),
            tooltip:
                _isWeekView ? 'Switch to Day View' : 'Switch to Grid Week View',
            onPressed: () {
              HapticService.selection(hapticsEnabled);
              setState(() {
                _isWeekView = !_isWeekView;
              });
              context.read<SettingsService>().updateTimetableIsWeekView(_isWeekView);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() > 100) {
                      HapticService.selection(hapticsEnabled);
                      _shiftWeek(v > 0 ? -1 : 1, preserveDay: true);
                    }
                  },
                  child: Material(
                    color: theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () {
                              HapticService.selection(hapticsEnabled);
                              _shiftWeek(-1, preserveDay: true);
                            },
                            icon: Icon(Icons.chevron_left,
                                color: theme.colorScheme.onSecondaryContainer),
                            style: IconButton.styleFrom(
                                backgroundColor: theme.colorScheme.surface),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticService.selection(hapticsEnabled);
                                _shiftWeek(0);
                              },
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                      "${_formatDateShort(_currentWeek.day(0))} - ${_formatDateShort(_currentWeek.day(4))}",
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme
                                                  .onSecondaryContainer)),
                                  const SizedBox(height: 2),
                                  Text(
                                      "${l10n.get('weekTitle')} ${_currentWeek.weekNumber}, ${_currentWeek.year}",
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSecondaryContainer)),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              HapticService.selection(hapticsEnabled);
                              _shiftWeek(1, preserveDay: true);
                            },
                            icon: Icon(Icons.chevron_right,
                                color: theme.colorScheme.onSecondaryContainer),
                            style: IconButton.styleFrom(
                                backgroundColor: theme.colorScheme.surface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        // FIX 5: Shorter duration for the mode toggle — it's not a content slide,
        // so it doesn't need to travel as far visually.
        duration: animationsEnabled
            ? const Duration(milliseconds: 350)
            : Duration.zero,
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) {
          if (!animationsEnabled) return child;
          // FIX 3: Add a subtle scale so the view-mode toggle feels intentional
          // rather than a plain crossfade that could be mistaken for a content
          // update. The scale goes 0.97 → 1.0, barely perceptible but adds depth.
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey('body_$_isWeekView'),
          child: _buildBody(l10n),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);
    final animationsEnabled =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);

    if (!auth.isAuthenticated) {
      return KeyedSubtree(
          key: const ValueKey('login_cta'), child: _buildLoginCta(l10n));
    }

    final weekStr = '${_currentWeek.weekNumber}_${_currentWeek.year}';
    final hasData = _weeklyEvents.containsKey(weekStr) &&
        _weeklyEvents[weekStr]!.isNotEmpty;

    if (_isLoading && !hasData) {
      return const Center(
          key: ValueKey('loading'), child: CircularProgressIndicator());
    }

    if (_networkFailed && !hasData && !_isLoading) {
      return KeyedSubtree(
          key: const ValueKey('retry'), child: _buildRetryState(l10n));
    }

    // Shared animation constants — FIX 2: unified 500 ms duration and symmetric
    // easeInOutCubic curve on both switchers so week-grid and day-list feel identical.
    const animDuration = Duration(milliseconds: 500);
    const animCurve = Curves.easeInOutCubic;

    if (_isWeekView) {
      final weekKey =
          ValueKey('week_grid_${_currentWeek.weekNumber}_${_currentWeek.year}');
      return ClipRect(
        key: const ValueKey('WeekView'),
        child: AnimatedSwitcher(
          duration: animationsEnabled ? animDuration : Duration.zero,
          switchInCurve: animCurve,
          switchOutCurve: animCurve,
          layoutBuilder: (currentChild, previousChildren) {
            return ColoredBox(
              color: theme.colorScheme.surface,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.antiAlias,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
            );
          },
          transitionBuilder: (child, animation) {
            if (!animationsEnabled) return child;

            final isEntering = (child.key == weekKey); // or dayWeekKey

            // Fix: Use 0.99 instead of 1.0 to create a sub-pixel overlap
            final startOffset = _slideDirection >= 0
                ? const Offset(0.99, 0.0)
                : const Offset(-0.99, 0.0);
            final endOffset = _slideDirection >= 0
                ? const Offset(-0.99, 0.0)
                : const Offset(0.99, 0.0);

            return SlideTransition(
              position: Tween<Offset>(
                begin: isEntering ? startOffset : endOffset,
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: animCurve)),
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surface),
                child: SizedBox.expand(child: child),
              ),
            );
          },
          child: KeyedSubtree(
            key: weekKey,
            child: RepaintBoundary(child: _build2DCustomWeekGrid(l10n)),
          ),
        ),
      );
    } else {
      final dayWeekKey =
          ValueKey('day_list_${_currentWeek.weekNumber}_${_currentWeek.year}');
      return ClipRect(
        key: const ValueKey('DayView'),
        child: AnimatedSwitcher(
          // FIX 2: was 725 ms — now matches the week grid at 500 ms.
          duration: animationsEnabled ? animDuration : Duration.zero,
          switchInCurve: animCurve,
          switchOutCurve: animCurve,
          layoutBuilder: (currentChild, previousChildren) {
            return ColoredBox(
              color: theme.colorScheme.surface,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.antiAlias,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
            );
          },
          transitionBuilder: (child, animation) {
            if (!animationsEnabled) return child;

            final isEntering = (child.key == dayWeekKey); // or dayWeekKey

            // Fix: Use 0.99 instead of 1.0 to create a sub-pixel overlap
            final startOffset = _slideDirection >= 0
                ? const Offset(0.99, 0.0)
                : const Offset(-0.99, 0.0);
            final endOffset = _slideDirection >= 0
                ? const Offset(-0.99, 0.0)
                : const Offset(0.99, 0.0);

            return SlideTransition(
              position: Tween<Offset>(
                begin: isEntering ? startOffset : endOffset,
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: animCurve)),
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surface),
                child: SizedBox.expand(child: child),
              ),
            );
          },
          child: KeyedSubtree(
            key: dayWeekKey,
            child: RepaintBoundary(
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    tabs: _getShortDays(context)
                        .map((day) => Tab(text: day))
                        .toList(),
                  ),
                  Expanded(child: _buildDayView(l10n)),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildRetryState(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final hapticsEnabled =
        context.select<SettingsService, bool>((s) => s.hapticsEnabled);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              l10n.get('errorNetwork'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                HapticService.confirm(hapticsEnabled);
                _fetchDataForWeek(_currentWeek);
              },
              icon: const Icon(Icons.refresh),
              label: Text(Localizations.localeOf(context).languageCode == 'de'
                  ? 'Erneut versuchen'
                  : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginCta(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final hapticsEnabled =
        context.select<SettingsService, bool>((s) => s.hapticsEnabled);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school_outlined,
                size: 48,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.get('scheduleUnavailable'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('scheduleLoginPrompt'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                HapticService.confirm(hapticsEnabled);
                final success = await showLoginDialog(context);
                if (success && mounted) {
                  _fetchDataForWeek(_currentWeek);
                }
              },
              icon: const Icon(Icons.login),
              label: Text(l10n.get('loginButton')),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _timeToMinutes(String t) {
    try {
      final parts = t.split(':');
      return (int.parse(parts[0].trim()) * 60) + int.parse(parts[1].trim());
    } catch (_) {
      return 0;
    }
  }

  Widget _build2DCustomWeekGrid(AppLocalizations l10n) {
    int startHour = 8;
    int endHour = 20;

    final weekStr = '${_currentWeek.weekNumber}_${_currentWeek.year}';
    final eventsList = _weeklyEvents[weekStr] ?? [];

    if (eventsList.isNotEmpty) {
      int minMins = 24 * 60;
      int maxMins = 0;
      for (var e in eventsList) {
        if (e.time.contains('-')) {
          final parts = e.time.split('-');
          int start = _timeToMinutes(parts[0]);
          int end = _timeToMinutes(parts[1]);
          if (start < minMins) minMins = start;
          if (end > maxMins) maxMins = end;
        }
      }

      startHour = ((minMins / 60).floor() - 1).clamp(0, 24);
      endHour = ((maxMins / 60).ceil() + 1).clamp(0, 24);
      if (startHour >= endHour) {
        startHour = 8;
        endHour = 20;
      }
    }

    final int displayRangeHours = endHour - startHour;
    final theme = Theme.of(context);
    final shortDays = _getShortDays(context);

    return LayoutBuilder(builder: (context, constraints) {
      final settings = context.watch<SettingsService>();
      const double timeColumnWidth = 45.0;
      final double dayColumnWidth =
          (constraints.maxWidth - timeColumnWidth) / _days.length;
      const double headerHeight = 50.0;
      final double gridHeight = constraints.maxHeight - headerHeight;
      final double safeGridHeight = gridHeight > 100 ? gridHeight : 400.0;
      final double pixelsPerHour = safeGridHeight / displayRangeHours;
      final double totalGridHeight = safeGridHeight;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 500) {
            _shiftWeek(-1);
          } else if (v < -500) {
            _shiftWeek(1);
          }
        },
        child: Column(
          children: [
            Container(
              height: 50,
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5))),
                color: theme.colorScheme.surface,
              ),
              child: Row(
                children: [
                  const SizedBox(width: timeColumnWidth),
                  ...List.generate(_days.length, (index) {
                    final targetDate = _currentWeek.day(index);
                    final isToday = targetDate.day == DateTime.now().day &&
                        targetDate.month == DateTime.now().month &&
                        targetDate.year == DateTime.now().year;

                    return SizedBox(
                      width: dayColumnWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(shortDays[index],
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: isToday
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Container(
                            decoration: isToday
                                ? BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle)
                                : null,
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              targetDate.day.toString(),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isToday
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: totalGridHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: timeColumnWidth,
                        child: Stack(
                          children:
                              List.generate(displayRangeHours + 1, (index) {
                            final currentHour = startHour + index;
                            return Positioned(
                              top: (index * pixelsPerHour) - 8,
                              left: 0,
                              right: 8,
                              child: Text(
                                "${currentHour.toString().padLeft(2, '0')}:00",
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                    fontSize: 10),
                              ),
                            );
                          }),
                        ),
                      ),
                      ...List.generate(_days.length, (dayIndex) {
                        final String dayName = _days[dayIndex];
                        final List<TimetableEvent> eventsToday =
                            _getEventsForDay(dayName);
                        final List<Widget> positionedEvents = [];

                        if (eventsToday.isNotEmpty) {
                          eventsToday.sort((a, b) {
                            if (!a.time.contains('-') ||
                                !b.time.contains('-')) {
                              return 0;
                            }
                            final aStart = _timeToMinutes(a.time.split('-')[0]);
                            final bStart = _timeToMinutes(b.time.split('-')[0]);
                            return aStart.compareTo(bStart);
                          });

                          final List<List<TimetableEvent>> clusters = [];
                          final List<int> clusterMaxEnd = [];

                          for (var ev in eventsToday) {
                            if (!ev.time.contains('-')) continue;
                            final evStart =
                                _timeToMinutes(ev.time.split('-')[0]);
                            final evEnd = _timeToMinutes(ev.time.split('-')[1]);

                            bool placed = false;
                            for (int ci = 0; ci < clusters.length; ci++) {
                              if (evStart < clusterMaxEnd[ci]) {
                                clusters[ci].add(ev);
                                if (evEnd > clusterMaxEnd[ci]) {
                                  clusterMaxEnd[ci] = evEnd;
                                }
                                placed = true;
                                break;
                              }
                            }
                            if (!placed) {
                              clusters.add([ev]);
                              clusterMaxEnd.add(evEnd);
                            }
                          }

                          for (var cluster in clusters) {
                            final int clusterSize = cluster.length;
                            final double widthPerItem =
                                dayColumnWidth / clusterSize;

                            for (int i = 0; i < clusterSize; i++) {
                              final ev = cluster[i];
                              final parts = ev.time.split('-');
                              final startMins = _timeToMinutes(parts[0]);
                              final endMins = _timeToMinutes(parts[1]);

                              final startFraction =
                                  (startMins / 60.0) - startHour;
                              final durationFraction =
                                  (endMins - startMins) / 60.0;

                              final double topOffset =
                                  startFraction * pixelsPerHour;
                              final double itemHeight =
                                  durationFraction * pixelsPerHour;

                              positionedEvents.add(Positioned(
                                top: topOffset,
                                left: i * widthPerItem,
                                width: widthPerItem,
                                height: itemHeight,
                                child: GestureDetector(
                                  onTap: () {
                                    HapticService.confirm(
                                        settings.hapticsEnabled);
                                    _showEventDetails(context, ev);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                        right: 2, bottom: 2, left: 1),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: ev.isExam
                                          ? theme.colorScheme.errorContainer
                                          : theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: ev.isExam
                                              ? theme.colorScheme.error
                                                  .withValues(alpha: 0.5)
                                              : theme.colorScheme.primary
                                                  .withValues(alpha: 0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _cleanTitle(ev.title),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: ev.isExam
                                                ? theme.colorScheme
                                                    .onErrorContainer
                                                : theme.colorScheme
                                                    .onPrimaryContainer,
                                            height: 1.1,
                                          ),
                                          maxLines: (itemHeight / 15).floor(),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (itemHeight > 40) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            ev.room,
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: ev.isExam
                                                  ? theme.colorScheme
                                                      .onErrorContainer
                                                      .withValues(alpha: 0.8)
                                                  : theme.colorScheme
                                                      .onPrimaryContainer
                                                      .withValues(alpha: 0.8),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                              ));
                            }
                          }
                        }

                        return SizedBox(
                          width: dayColumnWidth,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ...List.generate(displayRangeHours + 1, (index) {
                                return Positioned(
                                  top: index * pixelsPerHour,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.2),
                                  ),
                                );
                              }),
                              ...positionedEvents,
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildDayView(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Ignore vertical scrolling entirely
        if (notification.metrics.axis != Axis.horizontal) return false;

        if (DateTime.now().difference(_lastSwipe).inMilliseconds < 400) {
          return false;
        }

        final settings = context.read<SettingsService>();

        // With BouncingScrollPhysics, edge drags register as out-of-bounds updates
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;

          // Swipe right on Monday (pixels go slightly negative)
          if (metrics.pixels < -5 && _tabController.index == 0) {
            _lastSwipe = DateTime.now();
            HapticService.selection(settings.hapticsEnabled);
            _shiftWeek(-1, preserveDay: false);
            return true;
          }

          // Swipe left on Friday/Sunday (pixels go slightly past max)
          if (metrics.pixels > metrics.maxScrollExtent + 5 &&
              _tabController.index == _tabController.length - 1) {
            _lastSwipe = DateTime.now();
            HapticService.selection(settings.hapticsEnabled);
            _shiftWeek(1, preserveDay: false);
            return true;
          }
        }

        return false;
      },
      child: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        children: _days.map((day) {
          final eventsList = _getEventsForDay(day);

          if (eventsList.isEmpty) {
            return _buildEmptyState(l10n);
          }

          eventsList.sort((a, b) => a.time.compareTo(b.time));

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: eventsList.length,
            itemBuilder: (context, index) {
              final ev = eventsList[index];
              Widget card = _buildEventCard(ev, settings);

              if (settings.showBreakTime && index < eventsList.length - 1) {
                final nextEv = eventsList[index + 1];
                if (ev.time.contains('-') && nextEv.time.contains('-')) {
                  final evEndMins = _timeToMinutes(ev.time.split('-')[1]);
                  final nextStartMins =
                      _timeToMinutes(nextEv.time.split('-')[0]);
                  final diff = nextStartMins - evEndMins;

                  if (diff > 0) {
                    final pauseWord = l10n.get('pauseText');
                    final breakWord = l10n.get('breakText');
                    String text;
                    if (diff >= 60) {
                      final h = diff ~/ 60;
                      final m = diff % 60;
                      text =
                          m > 0 ? '${h}h ${m}m $pauseWord' : '${h}h $pauseWord';
                    } else {
                      text = '$diff $breakWord';
                    }

                    card = Column(
                      children: [
                        card,
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.emoji_food_beverage,
                                  size: 14, color: theme.colorScheme.outline),
                              const SizedBox(width: 8),
                              Text(text,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                }
              }
              return card;
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            l10n.get('noClasses'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.get('enjoyFreeTime'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  static final _titleCleanRegex = RegExp(r'\s*\([^)]*\)$');

  Widget _buildEventCard(TimetableEvent event, SettingsService settings) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isCompact = settings.compactTimetableView;
    final isExam = event.isExam;

    final cardColor = isExam
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.6)
        : theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
    final timeColor = isExam
        ? theme.colorScheme.error.withValues(alpha: 0.3)
        : theme.colorScheme.primaryContainer;
    final timeTextColor = isExam
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticService.confirm(settings.hapticsEnabled);
          _showEventDetails(context, event);
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: isCompact ? 70 : 80,
                color: timeColor,
                padding: EdgeInsets.symmetric(
                    vertical: isCompact ? 12 : 16, horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      event.time.contains('-')
                          ? event.time.split('-').first.trim()
                          : event.time,
                      style: (isCompact
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: timeTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: isCompact ? 14 : 16,
                      color: timeTextColor.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.time.contains('-')
                          ? event.time.split('-').last.trim()
                          : '',
                      style: (isCompact
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: timeTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 12.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _cleanTitle(event.title),
                        style: (isCompact
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.titleMedium)
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        maxLines: isCompact ? 2 : null,
                        overflow: isCompact ? TextOverflow.ellipsis : null,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: isCompact ? 14 : 16,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.room,
                              style: (isCompact
                                      ? theme.textTheme.bodySmall
                                      : theme.textTheme.bodyMedium)
                                  ?.copyWith(
                                      color: theme
                                          .colorScheme.onSecondaryContainer),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (!isCompact) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.class_,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _translateSubjectType(event.type, context,
                                    isExam: event.isExam),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        theme.colorScheme.onSecondaryContainer),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (event.frequency.isNotEmpty)
                              Chip(
                                label: Text(_translateFrequency(
                                    event.frequency, context)),
                                backgroundColor: theme.colorScheme.surface,
                                labelStyle: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 12,
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(
                                    color: theme.colorScheme.outlineVariant),
                              ),
                            if (event.isOverlapping)
                              Chip(
                                label: Text(l10n.get('overlappingLabel')),
                                backgroundColor:
                                    Colors.orange.withValues(alpha: 0.15),
                                labelStyle: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(
                                    color:
                                        Colors.orange.withValues(alpha: 0.3)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEventDetails(
      BuildContext context, TimetableEvent event) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthService>();
    Map<String, dynamic>? details;
    if (event.publishId != null) {
      try {
        details = await auth.fetchLectureDetails(event.publishId!);
      } catch (_) {}
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final teachers =
            details != null ? (details['teachers'] as List).join(', ') : null;
        final exams = details != null ? details['exam_dates'] as List : [];
        final hasExtra = (teachers != null && teachers.isNotEmpty) ||
            (details?['credits'] != null) ||
            (details?['sws'] != null) ||
            exams.isNotEmpty;

        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(_cleanTitle(event.title),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildDetailRow(ctx, Icons.access_time, event.time),
                const SizedBox(height: 8),
                _buildDetailRow(ctx, Icons.location_on, event.room),
                const SizedBox(height: 8),
                _buildDetailRow(
                    ctx,
                    Icons.class_,
                    _translateSubjectType(event.type, ctx,
                        isExam: event.isExam)),
                const SizedBox(height: 8),
                _buildDetailRow(ctx, Icons.repeat,
                    _translateFrequency(event.frequency, ctx)),
                if (hasExtra) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  if (teachers != null && teachers.isNotEmpty) ...[
                    _buildDetailRow(ctx, Icons.person, teachers),
                    const SizedBox(height: 8),
                  ],
                  if (details?['credits'] != null) ...[
                    _buildDetailRow(ctx, Icons.stars,
                        '${l10n.locale.languageCode == "de" ? "Credits" : "Credits"}: ${details!["credits"]}'),
                    const SizedBox(height: 8),
                  ],
                  if (details?['sws'] != null) ...[
                    _buildDetailRow(ctx, Icons.schedule,
                        '${l10n.locale.languageCode == "de" ? "SWS" : "SWS"}: ${details!["sws"]}'),
                    const SizedBox(height: 8),
                  ],
                  if (exams.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l10n.get('examDetailHeader'),
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...exams.map((ex) {
                      if (ex is Map) {
                        final d = ex['day'] ?? '';
                        final t = ex['time'] ?? '';
                        final date = ex['date'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.event_available,
                                  size: 16,
                                  color: theme.colorScheme.error
                                      .withValues(alpha: 0.7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text("$d, $date  |  $t",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text("• $ex", style: theme.textTheme.bodyMedium),
                      );
                    }),
                  ],
                ],
                if (event.publishId != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticService.selection(theme.platform == TargetPlatform.iOS);
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => LsfBrowserScreen(publishId: event.publishId!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open in LSF'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }

  String _cleanTitle(String title) {
    return title.replaceAll(_titleCleanRegex, '').trim();
  }
}
