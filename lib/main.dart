import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/lsf_scraper_service.dart';
import 'services/log_service.dart';
import 'screens/main_screen.dart';

import 'dart:async';

final ValueNotifier<int> mainTabNotifier = ValueNotifier<int>(0);
final StreamController<int> tabRefreshController = StreamController<int>.broadcast();
final StreamController<void> emailLongPressController = StreamController<void>.broadcast();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.loadSettings();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogService()),
        ChangeNotifierProvider.value(value: settings),
        ProxyProvider<LogService, LsfScraperService>(
          update: (context, logger, _) => LsfScraperService(logger),
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

class UniweApp extends StatelessWidget {
  const UniweApp({super.key});

  static const _seedColor = Color(0xFF76B900);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final auth = context.watch<AuthService>();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final ColorScheme lightColorScheme;
        final ColorScheme darkColorScheme;

        if (settings.useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null) {
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized().copyWith(
                surface: Color.lerp(darkDynamic.surface, Colors.black, 0.1),
              );
        } else {
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
          ).copyWith(primary: _seedColor);

          final baseDark = ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          );
          darkColorScheme = baseDark.copyWith(
            primary: _seedColor,
            surface: Color.lerp(baseDark.surface, Colors.black, 0.1),
          );
        }

        const appBarTheme = AppBarTheme(
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0.0,
        );

        final theme = ThemeData(
          colorScheme: lightColorScheme,
          useMaterial3: true,
          fontFamily: 'Inter',
          appBarTheme: appBarTheme,
        );

        final darkTheme = ThemeData(
          colorScheme: settings.amoledTheme
              ? darkColorScheme.copyWith(
                  surface: Colors.black,
                  surfaceContainer: const Color(0xFF121212),
                  surfaceContainerHigh: const Color(0xFF1A1A1A),
                  surfaceContainerHighest: const Color(0xFF222222),
                  surfaceContainerLow: const Color(0xFF0A0A0A),
                  surfaceContainerLowest: const Color(0xFF050505),
                )
              : darkColorScheme,
          scaffoldBackgroundColor:
              settings.amoledTheme ? Colors.black : darkColorScheme.surface,
          useMaterial3: true,
          fontFamily: 'Inter',
          appBarTheme: appBarTheme.copyWith(
            backgroundColor: settings.amoledTheme ? Colors.black : null,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: settings.amoledTheme ? Colors.black : null,
            indicatorColor: settings.amoledTheme
                ? darkColorScheme.primary.withValues(alpha: 0.2)
                : null,
          ),
        );

        // While checking auth, show a shell so we don't have a double-MaterialApp rebuild
        // but ensure it uses the CORRECT theme from the start.
        final Widget home;
        if (auth.isChecking || !settings.isLoaded) {
          home =
              const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else {
          home = const MainScreen();
        }

        return MaterialApp(
          title: 'Uniwe',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: theme,
          darkTheme: darkTheme,
          locale: settings.locale,
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        );
      },
    );
  }
}
