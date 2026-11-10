import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniwe/l10n/app_localizations.dart';
import 'package:uniwe/services/auth_service.dart';
import 'package:uniwe/services/cache_service.dart';
import 'package:uniwe/services/log_service.dart';
import 'package:uniwe/services/lsf_scraper_service.dart';
import 'package:uniwe/services/secure_storage_service.dart';
import 'package:uniwe/services/settings_service.dart';
import 'package:uniwe/theme/app_theme.dart';

/// In-memory stand-in for the platform keystore.
class FakeSecureStorage extends SecureStorageService {
  FakeSecureStorage({this.username, this.password});

  String? username;
  String? password;

  @override
  Future<void> saveCredentials(String username, String password) async {
    this.username = username;
    this.password = password;
  }

  @override
  Future<Map<String, String?>> getCredentials() async =>
      {'username': username, 'password': password};

  @override
  Future<void> deleteCredentials() async {
    username = null;
    password = null;
  }

  @override
  Future<bool> hasCredentials() async =>
      (username ?? '').isNotEmpty && (password ?? '').isNotEmpty;
}

/// A client whose every request fails like a device without connectivity.
http.Client offlineClient() =>
    MockClient((request) async => throw http.ClientException('offline'));

http.Client jsonClient(Object? Function(http.Request request) handler) {
  return MockClient((request) async {
    final body = handler(request);
    if (body == null) return http.Response('not found', 404);
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

class TestApp {
  TestApp._(this.settings, this.auth, this.scraper, this.logger);

  final SettingsService settings;
  final AuthService auth;
  final LsfScraperService scraper;
  final LogService logger;

  /// Creates the app services on top of mocked preferences. [prefs] may seed
  /// settings as well as cache entries.
  static Future<TestApp> create({
    Map<String, Object> prefs = const {},
    bool signedIn = false,
    http.Client? lsfClient,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final settings = SettingsService();
    await settings.loadSettings();
    await CacheService.instance.resetForTesting();

    final logger = LogService();
    final scraper = LsfScraperService(logger, client: lsfClient ?? offlineClient());
    final auth = AuthService(
      scraper,
      logger,
      storage: signedIn
          ? FakeSecureStorage(username: 's0123456', password: 'secret')
          : FakeSecureStorage(),
    );
    return TestApp._(settings, auth, scraper, logger);
  }

  Widget wrap(
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: logger),
        ChangeNotifierProvider.value(value: settings),
        Provider.value(value: scraper),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(AppTheme.colorScheme(brightness: brightness)),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('de')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    );
  }
}

/// Cache entries in the on-disk format of [CacheService].
Map<String, Object> cacheEntry(String key, Object json, {DateTime? at}) => {
      '__data_$key': jsonEncode(json),
      '__ts_$key': (at ?? DateTime.now()).toIso8601String(),
    };
