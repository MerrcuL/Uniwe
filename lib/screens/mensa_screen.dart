import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/mensa_service.dart';
import '../services/haptic_service.dart';
import '../services/cache_service.dart';
import '../models/mensa_meal.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../main.dart' as import_main;

class MensaScreen extends StatefulWidget {
  const MensaScreen({super.key});

  @override
  State<MensaScreen> createState() => _MensaScreenState();
}

class _MensaScreenState extends State<MensaScreen> {
  final MensaService _mensaService = MensaService();
  late PageController _pageController;
  final ScrollController _dayScrollController = ScrollController();
  
  List<String> _availableDays = [];
  bool _isLoadingDays = true;
  String? _selectedDate;
  
  // Cache meals to prevent re-fetching on rapid swipes
  Map<String, List<MensaMeal>> _mealsCache = {};
  bool _isLoadingMeals = false;

  bool _networkFailed = false;
  DateTime? _lastFetched;

  int _cachedCanteenId = -1;

  StreamSubscription<int>? _tabRefreshSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    _tabRefreshSubscription = import_main.tabRefreshController.stream.listen((index) {
      if (index == 1 && mounted) {
        final haptics = context.read<SettingsService>().hapticsEnabled;
        HapticService.confirm(haptics);
        if (_selectedDate != null) {
          _loadMeals(_selectedDate!);
        } else {
          _loadDays();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final canteenId = context.read<SettingsService>().canteenId;
    if (canteenId != _cachedCanteenId) {
      _cachedCanteenId = canteenId;
      _loadDays();
    }
  }

  @override
  void dispose() {
    _tabRefreshSubscription?.cancel();
    _pageController.dispose();
    _dayScrollController.dispose();
    _mensaService.dispose();
    super.dispose();
  }

  Future<void> _loadDays() async {
    setState(() {
      _isLoadingDays = true;
      _mealsCache = {};
      _availableDays = [];
    });

    final cacheKey = CacheService.mensaDaysKey(_cachedCanteenId);
    final cache = CacheService.instance;

    final cached = await cache.load(cacheKey);
    final cachedTs = cached.timestamp;
    final isCacheFresh = cachedTs != null && cache.isSameDay(cachedTs);

    void applyDays(List<String> days, DateTime ts) {
      if (!mounted) return;
      setState(() {
        _availableDays = days;
        _isLoadingDays = false;
        _lastFetched = ts;
        
        if (days.isNotEmpty) {
          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          int targetIdx = days.indexOf(todayStr);
          if (targetIdx == -1) targetIdx = 0;

          _selectedDate = days[targetIdx];
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(targetIdx);
            }
          });

          _loadMeals(_selectedDate!);
        }
      });
    }

    if (isCacheFresh && cached.data != null) {
      final days = List<String>.from(cached.data as List);
      applyDays(days, cachedTs);
      
      final stale = DateTime.now().difference(cachedTs).inMinutes >= 15;
      if (!stale) return; // Still fresh, don't re-fetch
    }

    final days = await _mensaService.fetchDays(_cachedCanteenId);
    
    if (days.isNotEmpty) {
      await cache.save(cacheKey, days);
      setState(() => _networkFailed = false);
      applyDays(days, DateTime.now());
    } else if (cached.data != null) {
      // Network failed, fallback unconditionally
      final cachedDays = List<String>.from(cached.data as List);
      setState(() => _networkFailed = true);
      applyDays(cachedDays, cachedTs!);
    } else {
      if (mounted) setState(() { _isLoadingDays = false; _networkFailed = true; });
    }
  }

  Future<void> _loadMeals(String date) async {
    if (_mealsCache.containsKey(date) && _mealsCache[date]!.isNotEmpty) {
       setState(() { _selectedDate = date; });
       return; 
    }

    setState(() {
      _isLoadingMeals = true;
      _selectedDate = date;
    });

    final cacheKey = CacheService.mensaKey(_cachedCanteenId, date);
    final cache = CacheService.instance;

    final cached = await cache.load(cacheKey);
    final cachedTs = cached.timestamp;
    final isCacheFresh = cachedTs != null && cache.isSameDay(cachedTs);

    void applyMeals(List<MensaMeal> meals, DateTime ts) {
      if (!mounted) return;
      setState(() {
        _mealsCache[date] = meals;
        _isLoadingMeals = false;
        _lastFetched = ts;
      });
    }

    if (isCacheFresh && cached.data != null) {
       final meals = (cached.data as List).map((m) => MensaMeal.fromJson(Map<String, dynamic>.from(m))).toList();
       applyMeals(meals, cachedTs);
       
       final stale = DateTime.now().difference(cachedTs).inMinutes >= 15;
       if (!stale) return;
    }

    final meals = await _mensaService.fetchMeals(_cachedCanteenId, date);

    if (meals.isNotEmpty) {
      await cache.save(cacheKey, meals.map((m) => m.toJson()).toList());
      setState(() => _networkFailed = false);
      applyMeals(meals, DateTime.now());
    } else if (cached.data != null) {
      final cachedMeals = (cached.data as List).map((m) => MensaMeal.fromJson(Map<String, dynamic>.from(m))).toList();
      setState(() => _networkFailed = true);
      applyMeals(cachedMeals, cachedTs!);
    } else {
      if (mounted) setState(() { _isLoadingMeals = false; _networkFailed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // No global watches needed here as they are handled in sub-methods
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              title: const Text('Mensa'),
              centerTitle: true,
              floating: true,
              snap: true,
              actions: [
                if (_networkFailed && _lastFetched != null && DateTime.now().difference(_lastFetched!).inMinutes > 30)
                  Tooltip(
                    message: 'Zuletzt aktualisiert: ${DateFormat('HH:mm').format(_lastFetched!)}',
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: _buildDayPaginator(),
              ),
            ),
          ];
        },
        body: _buildBody(),
      ),
    );
  }

  Widget _buildDayPaginator() {
    if (_isLoadingDays) {
      return const SizedBox(
         height: 70, 
         child: Center(child: CircularProgressIndicator())
      );
    }
    
    if (_availableDays.isEmpty) {
      return const SizedBox(height: 70);
    }

    return SizedBox(
      height: 70,
      child: ListView.builder(
        controller: _dayScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _availableDays.length,
        itemBuilder: (context, index) {
          final dateStr = _availableDays[index];
          final dateObj = DateTime.parse(dateStr);
          final isSelected = dateStr == _selectedDate;
          final isToday = dateObj.day == DateTime.now().day && dateObj.month == DateTime.now().month && dateObj.year == DateTime.now().year;

          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                 final hapticsEnabled = context.read<SettingsService>().hapticsEnabled;
                 HapticService.selection(hapticsEnabled);
                 _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: 65,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2),
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                    child: Text(DateFormat('E', 'de').format(dateObj)),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    child: Text(dateObj.day.toString()),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Scrolls the horizontal day chip list so the chip at [index] is centered.
  void _scrollDayChipIntoView(int index) {
    if (!_dayScrollController.hasClients) return;
    // Each chip is 65px wide + 8px total horizontal margin = 73px per item + 12px list padding
    const double itemWidth = 73.0;
    const double listPadding = 12.0;
    final viewportWidth = _dayScrollController.position.viewportDimension;
    final maxScroll = _dayScrollController.position.maxScrollExtent;

    // Target: center the chip in the viewport
    double targetOffset = (index * itemWidth + listPadding) - (viewportWidth / 2) + (itemWidth / 2);
    targetOffset = targetOffset.clamp(0.0, maxScroll);

    _dayScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildBody() {
    if (_isLoadingDays && _availableDays.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_availableDays.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('Mensa geschlossen!', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        final settings = context.read<SettingsService>();
        HapticService.selection(settings.hapticsEnabled);
        final newDate = _availableDays[index];
        _loadMeals(newDate);
        _scrollDayChipIntoView(index);
      },
      itemCount: _availableDays.length,
      itemBuilder: (context, index) {
        final date = _availableDays[index];
        final list = _mealsCache[date];
        
        if (list == null || (_isLoadingMeals && list.isEmpty && _selectedDate == date)) {
          return const Center(child: CircularProgressIndicator());
        }

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_meals, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text('Keine Speisen gefunden.', style: Theme.of(context).textTheme.titleMedium),
              ],
            )
          );
        }

        Map<String, List<MensaMeal>> categorized = {};
        for (var m in list) {
           categorized.putIfAbsent(m.category, () => []).add(m);
        }

        // Sort categories using user's saved order, falling back to default
        final settings = context.read<SettingsService>();
        final priceKey = settings.mensaPriceCategory;
        final isCompact = settings.compactMensaView;
        final userOrder = settings.mensaCategoryOrder;
        
        final defaultOrder = {
          'Essen': 0, 'Hauptgericht': 0, 'essen': 0,
          'Beilage': 1, 'Beilagen': 1, 'beilagen': 1,
          'Suppe': 2, 'Suppen': 2, 'suppen': 2,
          'Salat': 3, 'Salate': 3, 'salat': 3,
          'Dessert': 4, 'Desserts': 4, 'dessert': 4,
          'Aktionen': 5, 'aktionen': 5,
          'Vorspeisen': 6, 'vorspeisen': 6, 'Vorspeise': 6,
        };

        int getOrder(String cat) {
          if (userOrder.isNotEmpty) {
            for (int i = 0; i < userOrder.length; i++) {
              if (cat.toLowerCase().startsWith(userOrder[i].toLowerCase())) return i;
            }
          }
          return defaultOrder[cat] ?? 99;
        }

        final sortedKeys = categorized.keys.toList()
          ..sort((a, b) => getOrder(a).compareTo(getOrder(b)));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedKeys.length,
          itemBuilder: (context, idx) {
            String cat = sortedKeys[idx];
            List<MensaMeal> catMeals = categorized[cat]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
                  child: Text(
                    cat, 
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary, 
                      fontWeight: FontWeight.bold
                    )
                  ),
                ),
                ...catMeals.map((m) => isCompact ? _buildCompactMealCard(m, priceKey) : _buildMealCard(m, priceKey)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMealCard(MensaMeal meal, String priceKey) {
    final isVegan = meal.isVegan;
    final isVeggie = meal.isVegetarian;

    final price = meal.prices[priceKey];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (price != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '€${price.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (isVegan) _buildTag('Vegan', Colors.green, isProminent: true),
                if (!isVegan && isVeggie) _buildTag('Vegetarisch', Colors.lightGreen, isProminent: true),
                ...meal.notes
                    .where((n) => !n.toLowerCase().contains('vegan') && !n.toLowerCase().contains('vegetarisch') && !n.toLowerCase().contains('ovo-lacto'))
                    .take(3)
                    .map((n) => _buildTag(n, Theme.of(context).colorScheme.outlineVariant)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCompactMealCard(MensaMeal meal, String priceKey) {
    final isVegan = meal.isVegan;
    final isVeggie = meal.isVegetarian;
    final price = meal.prices[priceKey];

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isVegan) _buildMiniTag('Vegan', Colors.green, isProminent: true),
                      if (!isVegan && isVeggie) _buildMiniTag('Veggie', Colors.lightGreen, isProminent: true),
                    ],
                  ),
                ],
              ),
            ),
            if (price != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '€${price.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTag(String text, Color baseColor, {bool isProminent = false}) {
    final double scale = isProminent ? 1.25 : 1.0;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6 * scale),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9 * scale,
          color: baseColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color baseColor, {bool isProminent = false}) {
    final double scale = isProminent ? 1.25 : 1.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: baseColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10 * scale,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
