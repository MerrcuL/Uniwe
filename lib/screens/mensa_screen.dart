import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../models/mensa_category.dart';
import '../models/mensa_meal.dart';
import '../services/cache_service.dart';
import '../services/haptic_service.dart';
import '../services/mensa_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import '../widgets/app_sheet.dart';
import '../widgets/expressive.dart';

class MensaScreen extends StatefulWidget {
  const MensaScreen({super.key, this.service});

  /// Injectable for tests.
  final MensaService? service;

  @override
  State<MensaScreen> createState() => _MensaScreenState();
}

class _MensaScreenState extends State<MensaScreen> {
  static const Duration _freshFor = Duration(minutes: 15);
  static const double _dayPillWidth = 56;
  static const double _dayPillGap = 8;
  static const double _dayStripPadding = 12;

  late final MensaService _service = widget.service ?? MensaService();
  late final SettingsService _settings;
  final ScrollController _dayScrollController = ScrollController();
  PageController _pageController = PageController();

  int _canteenId = -1;

  /// Bumped whenever the canteen changes; responses of older requests are
  /// dropped instead of being shown for the wrong canteen.
  int _generation = 0;

  List<String> _days = const [];
  int _selectedIndex = 0;
  bool _loadingDays = true;
  bool _daysFailed = false;

  final Map<String, List<MensaMeal>> _meals = {};
  final Map<String, DateTime> _mealsFetchedAt = {};
  final Set<String> _loadingMeals = {};
  final Set<String> _failedMeals = {};

  /// The last refresh failed and the screen shows cached data.
  bool _offline = false;
  DateTime? _lastFetched;

  StreamSubscription<int>? _reselectSubscription;

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsService>();
    _settings.addListener(_onSettingsChanged);

    _reselectSubscription = AppEvents.tabReselected.listen((index) {
      if (index == AppTab.mensa && mounted) {
        HapticService.confirm(_settings.hapticsEnabled);
        _refresh();
      }
    });

    _loadDays();
  }

  @override
  void dispose() {
    _reselectSubscription?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _pageController.dispose();
    _dayScrollController.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (_settings.canteenId != _canteenId) _loadDays();
  }

  String? get _selectedDate =>
      _selectedIndex < _days.length ? _days[_selectedIndex] : null;

  bool _isFresh(DateTime? timestamp) =>
      timestamp != null &&
      DateTime.now().difference(timestamp).abs() < _freshFor;

  // ── Data ──────────────────────────────────────────────────────────────────

  /// Loads the open days of the current canteen. Cached days are shown
  /// immediately; the network is only asked when they are not fresh.
  Future<void> _loadDays({bool force = false}) async {
    final canteenChanged = _settings.canteenId != _canteenId;
    if (canteenChanged) _generation++;
    final generation = _generation;
    final canteenId = _canteenId = _settings.canteenId;

    final cache = CacheService.instance;
    final cacheKey = CacheService.mensaDaysKey(canteenId);
    final cached = cache.read(cacheKey);
    final cachedDays = _decodeDays(cached.data);
    final cachedAt = cached.timestamp;
    final cacheIsFromToday =
        cachedDays != null && cachedAt != null && cache.isSameDay(cachedAt);

    setState(() {
      if (canteenChanged) {
        _meals.clear();
        _mealsFetchedAt.clear();
        _loadingMeals.clear();
        _failedMeals.clear();
        _days = const [];
        _selectedIndex = 0;
        _offline = false;
        _lastFetched = null;
      }
      _daysFailed = false;
      if (_days.isEmpty && cacheIsFromToday) {
        _applyDays(cachedDays);
        _lastFetched = cachedAt;
      }
      _loadingDays = _days.isEmpty;
    });

    if (!force && cacheIsFromToday && _isFresh(cachedAt)) {
      setState(() => _loadingDays = false);
      final date = _selectedDate;
      if (date != null) unawaited(_loadMeals(date));
      return;
    }

    try {
      final days = await _service.fetchDays(canteenId);
      if (!mounted || generation != _generation) return;
      unawaited(cache.save(cacheKey, days));
      setState(() {
        _applyDays(days);
        _loadingDays = false;
        _offline = false;
        _lastFetched = DateTime.now();
      });
    } catch (e) {
      log('MensaScreen: loading days failed: $e');
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingDays = false;
        if (_days.isEmpty && cachedDays != null) {
          // Older than today, but better than nothing while offline.
          final today = Formats.isoDate(DateTime.now());
          _applyDays(
            cachedDays.where((d) => d.compareTo(today) >= 0).toList(),
          );
          _lastFetched = cachedAt;
        }
        if (_days.isEmpty) {
          _daysFailed = true;
        } else {
          _offline = true;
        }
      });
    }

    final date = _selectedDate;
    if (date != null) unawaited(_loadMeals(date, force: force));
  }

  /// Replaces the list of days, keeping the selected date when it still
  /// exists and defaulting to today otherwise. Must run inside `setState`.
  void _applyDays(List<String> days) {
    if (listEquals(days, _days)) return;

    final previous = _selectedDate;
    var index = previous != null ? days.indexOf(previous) : -1;
    if (index == -1) index = days.indexOf(Formats.isoDate(DateTime.now()));
    if (index == -1) index = 0;

    _days = days;
    _selectedIndex = index;

    // A PageController's initial page is fixed, so the pager gets a new one.
    final old = _pageController;
    _pageController = PageController(initialPage: index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      _scrollDayIntoView(index, animate: false);
    });
  }

  Future<void> _loadMeals(String date, {bool force = false}) async {
    if (_loadingMeals.contains(date)) return;
    if (!force && !_failedMeals.contains(date) && _isFresh(_mealsFetchedAt[date])) {
      return;
    }

    final generation = _generation;
    final canteenId = _canteenId;
    final cache = CacheService.instance;
    final cacheKey = CacheService.mensaKey(canteenId, date);
    final cached = cache.read(cacheKey);
    final cachedMeals = _decodeMeals(cached.data);
    final cachedAt = cached.timestamp;

    if (_meals[date] == null &&
        cachedMeals != null &&
        cachedAt != null &&
        cache.isSameDay(cachedAt)) {
      _meals[date] = cachedMeals;
      _mealsFetchedAt[date] = cachedAt;
      if (!force && _isFresh(cachedAt)) {
        setState(() => _failedMeals.remove(date));
        return;
      }
    }

    setState(() {
      _loadingMeals.add(date);
      _failedMeals.remove(date);
    });

    try {
      final meals = await _service.fetchMeals(canteenId, date);
      if (!mounted || generation != _generation) return;
      unawaited(cache.save(cacheKey, meals.map((m) => m.toJson()).toList()));
      setState(() {
        _meals[date] = meals;
        _mealsFetchedAt[date] = DateTime.now();
        _loadingMeals.remove(date);
        _offline = false;
        _lastFetched = DateTime.now();
      });
    } catch (e) {
      log('MensaScreen: loading meals for $date failed: $e');
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMeals.remove(date);
        if (_meals[date] == null && cachedMeals != null) {
          _meals[date] = cachedMeals;
          if (cachedAt != null) _lastFetched = cachedAt;
        }
        if (_meals[date] == null) {
          _failedMeals.add(date);
        } else {
          _offline = true;
        }
      });
    }
  }

  Future<void> _refresh() async {
    if (_days.isEmpty) {
      await _loadDays(force: true);
      return;
    }
    final date = _selectedDate;
    if (date != null) await _loadMeals(date, force: true);
  }

  static List<String>? _decodeDays(Object? data) {
    if (data is! List) return null;
    return data.map((d) => d.toString()).toList();
  }

  static List<MensaMeal>? _decodeMeals(Object? data) {
    if (data is! List) return null;
    try {
      return data
          .map((m) => MensaMeal.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ── Day selection ─────────────────────────────────────────────────────────

  void _onPageChanged(int index) {
    if (index >= _days.length) return;
    HapticService.selection(_settings.hapticsEnabled);
    setState(() => _selectedIndex = index);
    _scrollDayIntoView(index);
    _loadMeals(_days[index]);
  }

  void _onDayTapped(int index) {
    if (index == _selectedIndex || !_pageController.hasClients) return;
    if (_settings.animationsEnabled) {
      _pageController.animateToPage(
        index,
        duration: Durations.medium2,
        curve: Easing.emphasizedDecelerate,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  /// Scrolls the day strip so the chip at [index] is centered.
  void _scrollDayIntoView(int index, {bool animate = true}) {
    if (!_dayScrollController.hasClients) return;
    final position = _dayScrollController.position;
    const extent = _dayPillWidth + _dayPillGap;
    final target = (_dayStripPadding +
            index * extent +
            _dayPillWidth / 2 -
            position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);

    if (animate && _settings.animationsEnabled) {
      _dayScrollController.animateTo(
        target,
        duration: Durations.medium2,
        curve: Easing.standard,
      );
    } else {
      _dayScrollController.jumpTo(target);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('mensa')),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: Tooltip(
                message: _canteenId == 2036
                    ? 'Mensa Treskowallee'
                    : 'Mensa Wilhelminenhof',
                triggerMode: TooltipTriggerMode.tap,
                child: TonalPill(
                  label: _canteenId == 2036 ? 'Mensa TA' : 'Mensa WH',
                  icon: Icons.location_on_outlined,
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
        bottom: _days.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(
                  DayPill.height + 16 + _DietFilterBar.height,
                ),
                child: Column(
                  children: [_buildDayStrip(), const _DietFilterBar()],
                ),
              ),
      ),
      body: Column(
        children: [
          if (_offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InfoBanner(
                icon: Icons.cloud_off_outlined,
                text: _lastFetched == null
                    ? l10n.get('offlineCache')
                    : '${l10n.get('offlineCache')} '
                        '${l10n.get('lastUpdated')}: ${Formats.timestamp(_lastFetched!)}',
              ),
            ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildDayStrip() {
    final locale = Localizations.localeOf(context).languageCode;
    final today = Dates.today();
    final animate =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);

    return SizedBox(
      height: DayPill.height + 16,
      child: ListView.separated(
        controller: _dayScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            _dayStripPadding, 4, _dayStripPadding, 12),
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: _dayPillGap),
        itemBuilder: (context, index) {
          final date = DateTime.tryParse(_days[index]) ?? today;
          return SizedBox(
            width: _dayPillWidth,
            child: DayPill(
              weekday: Formats.weekdayShort(date, locale),
              day: date.day.toString(),
              selected: index == _selectedIndex,
              isToday: Dates.isSameDay(date, today),
              semanticLabel: Formats.fullDate(date, locale),
              animate: animate,
              onTap: () => _onDayTapped(index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_days.isEmpty) {
      if (_loadingDays) return const LoadingState();
      if (_daysFailed) {
        return StatusMessage(
          icon: Icons.cloud_off_outlined,
          shape: SoftShape.clover,
          title: l10n.get('errorMensa'),
          action: FilledButton.tonalIcon(
            onPressed: () {
              HapticService.confirm(_settings.hapticsEnabled);
              _loadDays(force: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.get('retry')),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: StatusMessage(
          icon: Icons.restaurant_menu_rounded,
          shape: SoftShape.flower,
          title: l10n.get('mensaClosed'),
          message: l10n.get('mensaClosedHint'),
        ),
      );
    }

    return PageView.builder(
      key: ObjectKey(_pageController),
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: _days.length,
      itemBuilder: (context, index) => _buildMealsPage(l10n, _days[index]),
    );
  }

  Widget _buildMealsPage(AppLocalizations l10n, String date) {
    final meals = _meals[date];

    if (meals == null) {
      if (_failedMeals.contains(date)) {
        return StatusMessage(
          icon: Icons.cloud_off_outlined,
          shape: SoftShape.clover,
          title: l10n.get('errorMensa'),
          action: FilledButton.tonalIcon(
            onPressed: () {
              HapticService.confirm(_settings.hapticsEnabled);
              _loadMeals(date, force: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.get('retry')),
          ),
        );
      }
      return const LoadingState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadMeals(date, force: true),
      child: meals.isEmpty
          ? StatusMessage(
              icon: Icons.no_meals_outlined,
              shape: SoftShape.flower,
              title: l10n.get('noMeals'),
            )
          : _MealList(meals: meals),
    );
  }
}

/// The menu of one day, grouped by category in the user's preferred order.
class _MealList extends StatelessWidget {
  const _MealList({required this.meals});

  final List<MensaMeal> meals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final priceKey =
        context.select<SettingsService, String>((s) => s.mensaPriceCategory);
    final compact =
        context.select<SettingsService, bool>((s) => s.compactView);
    final savedOrder = context
        .select<SettingsService, List<String>>((s) => s.mensaCategoryOrder);
    final hapticsEnabled =
        context.select<SettingsService, bool>((s) => s.hapticsEnabled);
    final dietFilters = context
        .select<SettingsService, Set<String>>((s) => s.mensaDietFilters);

    final visible = meals.where((m) => m.matchesDiet(dietFilters)).toList();
    if (visible.isEmpty) {
      return StatusMessage(
        icon: Icons.filter_alt_off_outlined,
        shape: SoftShape.flower,
        title: l10n.get('noMealsForFilter'),
        action: FilledButton.tonal(
          onPressed: () {
            final settings = context.read<SettingsService>();
            HapticService.selection(settings.hapticsEnabled);
            settings.setMensaDietFilters(const {});
          },
          child: Text(l10n.get('clearFilters')),
        ),
      );
    }

    // Group by API category, then order the groups: known categories by the
    // user's order, unknown ones afterwards in the order the API sent them.
    final order = MensaCategory.ordered(savedOrder);
    final groups = <String, List<MensaMeal>>{};
    for (final meal in visible) {
      groups.putIfAbsent(meal.category, () => []).add(meal);
    }
    final names = groups.keys.toList();
    int rank(String name) {
      final known = MensaCategory.match(name);
      return known == null ? order.length : order.indexOf(known);
    }

    final sorted = List<int>.generate(names.length, (i) => i)
      ..sort((a, b) {
        final byRank = rank(names[a]).compareTo(rank(names[b]));
        return byRank != 0 ? byRank : a.compareTo(b);
      });

    final rows = <Widget>[];
    for (final i in sorted) {
      final name = names[i];
      final known = MensaCategory.match(name);
      rows.add(SectionHeader(
        known?.label(german: l10n.isGerman) ?? name,
        icon: known?.icon ?? Icons.restaurant_rounded,
      ));
      for (final meal in groups[name]!) {
        rows.add(Padding(
          padding: EdgeInsets.only(bottom: compact ? 6 : 10),
          child: _MealCard(
            meal: meal,
            priceKey: priceKey,
            compact: compact,
            onTap: () {
              HapticService.confirm(hapticsEnabled);
              _showMealDetails(context, meal, priceKey);
            },
          ),
        ));
      }
    }

    final gutter = AppSpacing.gutter(context);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          gutter, 0, gutter, AppSpacing.bottomInset(context)),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

/// Diet filter chips under the day strip. Several can be active at once.
class _DietFilterBar extends StatelessWidget {
  const _DietFilterBar();

  static const double height = 48;

  static const List<(String, IconData)> _filters = [
    ('vegetarian', Icons.eco_outlined),
    ('vegan', Icons.spa_outlined),
    ('meat', Icons.kebab_dining_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = context
        .select<SettingsService, Set<String>>((s) => s.mensaDietFilters);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, icon) = _filters[index];
          final selected = active.contains(key);
          return FilterChip(
            label: Text(l10n.get(key)),
            avatar: selected ? null : Icon(icon, size: 18),
            selected: selected,
            onSelected: (_) {
              final settings = context.read<SettingsService>();
              HapticService.selection(settings.hapticsEnabled);
              settings.toggleMensaDietFilter(key);
            },
          );
        },
      ),
    );
  }
}

class _DietPill extends StatelessWidget {
  const _DietPill({required this.meal, this.dense = false});

  final MensaMeal meal;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = SemanticColors.of(context);
    return TonalPill(
      dense: dense,
      label: l10n.get(meal.isVegan ? 'vegan' : 'vegetarian'),
      icon: meal.isVegan ? Icons.spa_outlined : Icons.eco_outlined,
      background: semantic.successContainer,
      foreground: semantic.onSuccessContainer,
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.priceKey,
    required this.compact,
    required this.onTap,
  });

  static const int _maxNotes = 3;

  final MensaMeal meal;
  final String priceKey;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final price = meal.prices[priceKey];
    final hasDiet = meal.isVegan || meal.isVegetarian;

    final pricePill = price == null
        ? null
        : TonalPill(
            label: Formats.price(price, locale),
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
            textStyle: theme.textTheme.titleSmall,
          );

    if (compact) {
      return Card(
        shape: const RoundedRectangleBorder(
          borderRadius: AppShapes.largeRadius,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasDiet || meal.noteCodes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        // Diet tag, then allergens/additives by number only;
                        // the full names are one tap away in the details.
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (hasDiet) _DietPill(meal: meal, dense: true),
                            if (meal.noteCodes.isNotEmpty)
                              Text(
                                meal.noteCodes.join(' · '),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (pricePill != null) ...[
                  const SizedBox(width: 12),
                  pricePill,
                ],
              ],
            ),
          ),
        ),
      );
    }

    final notes = meal.displayNotes;
    final hiddenNotes = notes.length - _maxNotes;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      meal.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (pricePill != null) ...[
                    const SizedBox(width: 12),
                    pricePill,
                  ],
                ],
              ),
              if (hasDiet || notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (hasDiet) _DietPill(meal: meal),
                    for (final note in notes.take(_maxNotes))
                      TonalPill(
                        label: note,
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurfaceVariant,
                      ),
                    if (hiddenNotes > 0)
                      TonalPill(
                        label: '+$hiddenNotes',
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything known about a meal: all price groups and every label, which
/// the cards have to truncate.
void _showMealDetails(BuildContext context, MensaMeal meal, String priceKey) {
  showAppSheet<void>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final l10n = AppLocalizations.of(context);
      final locale = Localizations.localeOf(context).languageCode;
      final notes = meal.displayNotes;

      const priceGroups = [
        ('students', 'priceStudents'),
        ('employees', 'priceEmployees'),
        ('others', 'priceGuests'),
      ];
      final prices = [
        for (final (key, label) in priceGroups)
          if (meal.prices[key] != null) (key, label, meal.prices[key]!),
      ];

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(meal.name, style: theme.textTheme.headlineSmall),
              if (meal.isVegan || meal.isVegetarian) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _DietPill(meal: meal),
                ),
              ],
              if (prices.isNotEmpty) ...[
                const SizedBox(height: 16),
                ListGroup(
                  children: [
                    for (final (key, label, price) in prices)
                      ListTile(
                        dense: true,
                        title: Text(l10n.get(label)),
                        selected: key == priceKey,
                        trailing: Text(
                          Formats.price(price, locale),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: key == priceKey
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  l10n.get('mealNotes'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final note in notes)
                      TonalPill(
                        label: note,
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
