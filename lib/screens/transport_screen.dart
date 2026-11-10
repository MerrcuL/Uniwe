import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../models/transport_arrival.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../services/transport_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../widgets/expressive.dart';

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key, this.service});

  /// Injectable for tests.
  final TransportService? service;

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 30);
  static const int _maxPerDirection = 4;

  late final TransportService _service = widget.service ?? TransportService();
  late final SettingsService _settings;

  List<TransportArrival> _arrivals = const [];
  bool _isLoading = true;

  /// The last request failed; anything on screen is from an earlier one.
  bool _failed = false;
  DateTime? _lastUpdated;

  String _campus = '';

  /// Bumped when the campus changes so late responses for the previous stop
  /// are ignored.
  int _generation = 0;
  Future<void>? _pending;

  Timer? _refreshTimer;
  StreamSubscription<int>? _reselectSubscription;

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsService>();
    _campus = _settings.campus;
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    AppEvents.currentTab.addListener(_onTabVisibilityChanged);

    _reselectSubscription = AppEvents.tabReselected.listen((index) {
      if (index == AppTab.transport && mounted) {
        HapticService.confirm(_settings.hapticsEnabled);
        _loadDepartures(showLoader: true);
      }
    });

    _updatePollingState();
    _loadDepartures(showLoader: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppEvents.currentTab.removeListener(_onTabVisibilityChanged);
    _settings.removeListener(_onSettingsChanged);
    _reselectSubscription?.cancel();
    _refreshTimer?.cancel();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  bool get _isVisibleTab => AppEvents.currentTab.value == AppTab.transport;

  bool get _isStale =>
      _lastUpdated == null ||
      DateTime.now().difference(_lastUpdated!) >= _pollInterval;

  void _onSettingsChanged() {
    if (_settings.campus == _campus) return;
    _campus = _settings.campus;
    _generation++;
    _pending = null;
    setState(() {
      _arrivals = const [];
      _lastUpdated = null;
      _failed = false;
    });
    _loadDepartures(showLoader: true);
  }

  void _onTabVisibilityChanged() {
    _updatePollingState();
    if (_isVisibleTab && mounted && _isStale) _loadDepartures();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updatePollingState();
      if (_isVisibleTab && mounted && _isStale) _loadDepartures();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  /// Polls only while the tab is on screen.
  void _updatePollingState() {
    if (_isVisibleTab) {
      _refreshTimer ??= Timer.periodic(_pollInterval, (_) => _loadDepartures());
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _loadDepartures({bool showLoader = false}) {
    if (showLoader && mounted && !_isLoading) {
      setState(() => _isLoading = true);
    }
    // Manual refreshes and the poll timer share one request.
    return _pending ??= _fetch(_generation).whenComplete(() => _pending = null);
  }

  Future<void> _fetch(int generation) async {
    try {
      final results =
          await _service.fetchDepartures(_stopIdForCampus(_campus));
      if (!mounted || generation != _generation) return;
      setState(() {
        _arrivals = results;
        _lastUpdated = DateTime.now();
        _failed = false;
        _isLoading = false;
      });
    } catch (e) {
      log('TransportScreen: loading departures failed: $e');
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _isLoading = false;
      });
    }
  }

  static String _stopIdForCampus(String campus) {
    switch (campus) {
      case 'TA':
        return '900162004';
      case 'TGS':
        return '900181504';
      case 'WH':
      default:
        return '900181503';
    }
  }

  static String _directionCategory(TransportArrival arrival, String campus) {
    final origin = arrival.originName.toLowerCase();
    final dir = arrival.direction.toLowerCase();

    if (campus == 'TA') {
      if (origin.contains('marksburgstr')) return 'S Friedrichsfelde Ost';
      if (origin.contains('tierpark') || origin.contains('neuwieder')) {
        return 'S Schöneweide';
      }

      // Fallback if origin is unknown
      if (dir.contains('schöneweide') ||
          dir.contains('adlershof') ||
          dir.contains('johannisthal') ||
          dir.contains('haeckelstr') ||
          dir.contains('sterndamm') ||
          dir.contains('köpenick')) {
        return 'S Schöneweide';
      }
      return 'S Friedrichsfelde Ost';
    } else {
      if (origin.contains('firlstr') || origin.contains('rathenaustr')) {
        return 'S Köpenick';
      }
      if (origin.contains('ostendstr') || origin.contains('weiskopffstr')) {
        return 'S Schöneweide';
      }

      // Fallback if origin is unknown
      if (dir.contains('schöneweide') ||
          dir.contains('haeckelstr') ||
          dir.contains('johannisthal') ||
          dir.contains('sterndamm') ||
          dir.contains('pasedagplatz') ||
          dir.contains('lichtenberg')) {
        return 'S Schöneweide';
      }
      return 'S Köpenick';
    }
  }

  /// Upcoming departures per direction. Trams that have already left are
  /// dropped, so a stale list (offline) never shows them as "now" forever.
  List<MapEntry<String, List<TransportArrival>>> _groupUpcoming(DateTime now) {
    final cutoff = now.subtract(const Duration(seconds: 45));
    // Both directions of the stop are always listed, so that a direction
    // without trams (late at night) reads as "nothing running" rather
    // than looking like it went missing.
    final groups = <String, List<TransportArrival>>{
      'S Schöneweide': [],
      _campus == 'TA' ? 'S Friedrichsfelde Ost' : 'S Köpenick': [],
    };
    for (final arrival in _arrivals) {
      if (arrival.actualTime.isBefore(cutoff)) continue;
      final list =
          groups.putIfAbsent(_directionCategory(arrival, _campus), () => []);
      if (list.length < _maxPerDirection) list.add(arrival);
    }
    return groups.entries.toList()
      ..sort((a, b) {
        if (a.key == b.key) return 0;
        if (a.key == 'S Schöneweide') return -1;
        if (b.key == 'S Schöneweide') return 1;
        return a.key.compareTo(b.key);
      });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('transport')),
        actions: [
          Center(
            child: Tooltip(
              message: 'Campus $_campus',
              triggerMode: TooltipTriggerMode.tap,
              child: TonalPill(
                label: 'Tram $_campus',
                icon: Icons.tram_outlined,
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: _isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: l10n.get('refresh'),
            onPressed: _isLoading
                ? null
                : () {
                    HapticService.selection(_settings.hapticsEnabled);
                    _loadDepartures(showLoader: true);
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_arrivals.isEmpty && _isLoading) return const LoadingState();

    if (_arrivals.isEmpty && _failed) {
      return StatusMessage(
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorTransport'),
        action: FilledButton.tonalIcon(
          onPressed: () {
            HapticService.confirm(_settings.hapticsEnabled);
            _loadDepartures(showLoader: true);
          },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    Future<void> onRefresh() {
      HapticService.selection(_settings.hapticsEnabled);
      return _loadDepartures();
    }

    final now = DateTime.now();
    final groups = _groupUpcoming(now);

    if (groups.every((group) => group.value.isEmpty)) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: StatusMessage(
          icon: Icons.tram_outlined,
          shape: SoftShape.flower,
          title: l10n.get('noDepartures'),
        ),
      );
    }

    final theme = Theme.of(context);
    final gutter = AppSpacing.gutter(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            gutter, 0, gutter, AppSpacing.bottomInset(context)),
        children: [
          if (_failed)
            InfoBanner(
              icon: Icons.cloud_off_outlined,
              text: _lastUpdated == null
                  ? l10n.get('offlineCache')
                  : '${l10n.get('offlineCache')} '
                      '${l10n.get('lastUpdated')}: ${Formats.time(_lastUpdated!)}',
            )
          else if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.update_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${l10n.get('lastUpdated')}: ${Formats.time(_lastUpdated!)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          for (final group in groups) ...[
            SectionHeader(group.key, icon: Icons.arrow_forward_rounded),
            ListGroup(
              children: [
                for (final arrival in group.value)
                  _ArrivalRow(arrival: arrival, now: now),
                if (group.value.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bedtime_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.get('noDeparturesSoon'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.arrival, required this.now});

  final TransportArrival arrival;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);

    final minutes =
        (arrival.actualTime.difference(now).inSeconds / 60).round();
    final delay = arrival.delayMinutes;
    final isSignificantDelay = delay > 5;
    final cancelled = arrival.cancelled;

    final String status;
    final Color statusColor;
    if (cancelled) {
      status = l10n.get('cancelled');
      statusColor = scheme.error;
    } else if (minutes <= 0) {
      status = l10n.get('now');
      statusColor = semantic.warning;
    } else {
      status = l10n.inMinutes(minutes);
      statusColor = isSignificantDelay ? scheme.error : scheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    cancelled ? scheme.errorContainer : scheme.primaryContainer,
                borderRadius: AppShapes.mediumRadius,
              ),
              child: Text(
                arrival.lineName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cancelled
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      Formats.time(arrival.scheduledTime),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (!cancelled && delay != 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        delay > 0 ? '+$delay min' : '$delay min',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isSignificantDelay
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  arrival.direction.isNotEmpty
                      ? arrival.direction
                      : l10n.get('unknownDirection'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status,
            style: theme.textTheme.titleMedium?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}
