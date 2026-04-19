import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/settings_service.dart';
import '../services/transport_service.dart';
import '../models/transport_arrival.dart';
import '../services/haptic_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' as import_main;

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  final TransportService _transportService = TransportService();
  
  List<TransportArrival> _arrivals = [];
  bool _isLoading = true;
  String _errorMessage = '';
  DateTime? _lastUpdated;
  Timer? _refreshTimer;
  String _cachedCampus = '';
  StreamSubscription<int>? _tabRefreshSubscription;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadDepartures(false));
    
    _tabRefreshSubscription = import_main.tabRefreshController.stream.listen((index) {
      if (index == 3 && mounted) {
        final haptics = context.read<SettingsService>().hapticsEnabled;
        HapticService.confirm(haptics);
        _loadDepartures(true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentCampus = context.watch<SettingsService>().campus;
    if (_cachedCampus != currentCampus) {
      _cachedCampus = currentCampus;
      _loadDepartures(true);
    }
  }

  @override
  void dispose() {
    _tabRefreshSubscription?.cancel();
    _refreshTimer?.cancel();
    _transportService.dispose();
    super.dispose();
  }

  Future<void> _loadDepartures(bool showLoader) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    final stopId = _getStopIdForCampus(_cachedCampus);
    final results = await _transportService.fetchDepartures(stopId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (results.isEmpty) {
          _errorMessage = AppLocalizations.of(context).get('noDepartures');
        } else {
          _arrivals = results;
          _lastUpdated = DateTime.now();
        }
      });
    }
  }

  String _getStopIdForCampus(String campus) {
    switch (campus) {
      case 'TA': return '900162004';
      case 'TGS': return '900181504';
      case 'WH': default: return '900181503';
    }
  }

  String _getDirectionCategory(TransportArrival arrival, String campus) {
    final origin = arrival.originName.toLowerCase();
    final dir = arrival.direction.toLowerCase();
    
    if (campus == 'TA') {
      if (origin.contains('marksburgstr')) return 'S Friedrichsfelde Ost';
      if (origin.isNotEmpty && (origin.contains('tierpark') || origin.contains('neuwieder'))) return 'S Schöneweide';
      
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
      if (origin.contains('firlstr') || origin.contains('rathenaustr')) return 'S Köpenick';
      if (origin.isNotEmpty && (origin.contains('ostendstr') || origin.contains('weiskopffstr'))) return 'S Schöneweide';
      
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final haptics = context.select<SettingsService, bool>((s) => s.hapticsEnabled);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              HapticService.selection(haptics);
              _loadDepartures(true);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          HapticService.selection(haptics);
          await _loadDepartures(true);
        },
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading && _arrivals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty && _arrivals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_transit_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(_errorMessage, style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    final categorized = <String, List<TransportArrival>>{};
    for (var arr in _arrivals) {
      final cat = _getDirectionCategory(arr, _cachedCampus);
      categorized.putIfAbsent(cat, () => []).add(arr);
    }

    final sortedCategories = categorized.keys.toList()..sort((a, b) {
      if (a == 'S Schöneweide') return -1;
      if (b == 'S Schöneweide') return 1;
      return a.compareTo(b);
    });

    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: CustomScrollView(
        slivers: [
          if (_lastUpdated != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.update, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '${l10n.get('lastUpdated')}: ${DateFormat('HH:mm').format(_lastUpdated!)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          for (var cat in sortedCategories) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0, left: 4.0, top: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      cat,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final arrList = categorized[cat]!.take(4).toList();
                  if (index >= arrList.length) return const SizedBox.shrink();
                  final arr = arrList[index];
                  return _buildArrivalCard(arr, theme);
                },
                childCount: categorized[cat]!.take(4).length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }

  Widget _buildArrivalCard(TransportArrival arrival, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = (arrival.actualTime.difference(now).inSeconds / 60).round();
    
    // Formatting the relative time
    String relativeTime;
    if (diff <= 0) {
      relativeTime = l10n.get('now');
    } else {
      relativeTime = 'in $diff min';
    }

    // Calculate real time shift
    final delayMin = (arrival.actualTime.difference(arrival.scheduledTime).inSeconds / 60).round();
    final hasTimeShift = delayMin != 0;
    final isSignificantDelay = delayMin > 5;
    final timeColor = diff <= 0 
        ? Colors.orange 
        : (isSignificantDelay ? theme.colorScheme.error : theme.colorScheme.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.secondaryContainer.withAlpha(100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                arrival.lineName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
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
                        DateFormat('HH:mm').format(arrival.scheduledTime),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (hasTimeShift) ...[
                        const SizedBox(width: 6),
                        Text(
                          delayMin > 0 ? '+$delayMin min' : '$delayMin min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isSignificantDelay ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_right_alt_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          arrival.direction.isNotEmpty ? arrival.direction : l10n.get('unknownDirection'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  relativeTime,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: timeColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
