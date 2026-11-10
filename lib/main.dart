// The dynamic_color plugin hands out the system palettes as a `CorePalette`,
// which material_color_utilities has deprecated in favour of the
// `DynamicScheme` this code feeds it into. There is no other source for it.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show CorePalette;
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'services/cache_service.dart';
import 'services/log_service.dart';
import 'services/lsf_scraper_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'theme/system_colors.dart';
import 'widgets/expressive.dart';
import 'widgets/splash_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  // Both share the same SharedPreferences instance, so this is one load.
  await Future.wait([settings.loadSettings(), CacheService.instance.init()]);
  unawaited(CacheService.instance.prune());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogService()),
        ChangeNotifierProvider.value(value: settings),
        ProxyProvider<LogService, LsfScraperService>(
          update: (context, logger, previous) =>
              previous ?? LsfScraperService(logger),
          dispose: (_, scraper) => scraper.dispose(),
        ),
        ChangeNotifierProxyProvider2<LsfScraperService, LogService,
            AuthService>(
          create: (context) => AuthService(
            context.read<LsfScraperService>(),
            context.read<LogService>(),
          ),
          update: (context, scraper, logger, auth) =>
              auth ?? AuthService(scraper, logger),
        ),
      ],
      child: const UniweApp(),
    ),
  );
}

class UniweApp extends StatefulWidget {
  const UniweApp({super.key});

  @override
  State<UniweApp> createState() => _UniweAppState();
}

class _UniweAppState extends State<UniweApp> with WidgetsBindingObserver {
  /// The system's Material You palettes, where the platform has them.
  CorePalette? _systemPalette;

  /// Whether the animated logo is still over the app.
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSystemPalette();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have changed wallpaper or colour style in the meantime.
    if (state == AppLifecycleState.resumed) _loadSystemPalette();
  }

  Future<void> _loadSystemPalette() async {
    CorePalette? palette;
    try {
      palette = await DynamicColorPlugin.getCorePalette();
    } catch (_) {
      // No dynamic colour on this platform; the brand colours are used.
    }
    if (!mounted) return;
    if (listEquals(palette?.asList(), _systemPalette?.asList())) return;
    setState(() => _systemPalette = palette);
  }

  @override
  Widget build(BuildContext context) {
    // Select only what the app shell depends on, so toggling an unrelated
    // setting does not rebuild MaterialApp and both themes.
    final useDynamicColor =
        context.select<SettingsService, bool>((s) => s.useDynamicColor);
    final amoledTheme =
        context.select<SettingsService, bool>((s) => s.amoledTheme);
    final themeMode =
        context.select<SettingsService, ThemeMode>((s) => s.themeMode);
    final locale = context.select<SettingsService, Locale>((s) => s.locale);
    final settingsLoaded =
        context.select<SettingsService, bool>((s) => s.isLoaded);
    final isCheckingAuth =
        context.select<AuthService, bool>((a) => a.isChecking);

    final palette = useDynamicColor ? _systemPalette : null;

    final theme = AppTheme.build(AppTheme.colorScheme(
      brightness: Brightness.light,
      systemScheme: palette == null
          ? null
          : colorSchemeFromSystemPalette(palette, Brightness.light),
    ));
    final darkTheme = AppTheme.build(
      AppTheme.colorScheme(
        brightness: Brightness.dark,
        systemScheme: palette == null
            ? null
            : colorSchemeFromSystemPalette(palette, Brightness.dark),
        amoled: amoledTheme,
      ),
      amoled: amoledTheme,
    );

    // While restoring the session, show a shell in the correct theme
    // instead of swapping MaterialApps.
    final isReady = !isCheckingAuth && settingsLoaded;
    final Widget home =
        isReady ? const MainScreen() : const Scaffold(body: LoadingState());

    return MaterialApp(
      title: 'Uniwe',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
      // The Stack stays after the splash is gone, so the navigator below it
      // keeps its place in the tree (and its state).
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          if (_showSplash)
            Positioned.fill(
              child: SplashOverlay(
                ready: isReady,
                onFinished: () => setState(() => _showSplash = false),
              ),
            ),
        ],
      ),
    );
  }
}
