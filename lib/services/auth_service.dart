import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart' show WebViewCookieManager;

import '../models/grades.dart';
import '../models/lecture_details.dart';
import '../models/person_details.dart';
import '../models/timetable_event.dart';
import '../utils/cookies.dart';
import '../utils/webview_dark_mode.dart' show mobileUserAgent;
import 'cache_service.dart';
import 'exceptions.dart';
import 'log_service.dart';
import 'lsf_scraper_service.dart';
import 'secure_storage_service.dart';

enum LoginResult { success, invalidCredentials, networkError }

class AuthService extends ChangeNotifier {
  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxReauthAttempts = 3;
  static const String _webmailUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  final SecureStorageService _storage;
  final LsfScraperService scraperService;
  final LogService _logger;

  bool _isChecking = true;
  bool _isAuthenticated = false;
  String? _username;
  bool _disposed = false;

  /// The (re-)login currently in flight, shared by everyone who needs a
  /// session so that parallel requests trigger exactly one login.
  Future<bool>? _sessionLogin;

  bool get isChecking => _isChecking;
  bool get isAuthenticated => _isAuthenticated;
  String? get username => _username;

  /// Creates the HTTP client for one Moodle sign-in (replaceable in tests).
  final http.Client Function() _newClient;

  AuthService(
    this.scraperService,
    this._logger, {
    SecureStorageService? storage,
    http.Client Function()? httpClient,
  })  : _storage = storage ?? SecureStorageService(),
        _newClient = httpClient ?? http.Client.new {
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Restores the signed-in state from the stored credentials.
  ///
  /// Only the (local, fast) keystore read blocks the UI. The network login
  /// runs in the background, so the app opens instantly with cached data —
  /// also when offline or when LSF is slow.
  Future<void> _init() async {
    String? user;
    String? pass;
    try {
      final creds = await _storage.getCredentials();
      user = creds['username'];
      pass = creds['password'];
    } catch (e) {
      // A broken keystore must not leave the app stuck on the splash spinner.
      _logger.error('Could not read stored credentials', e.toString());
    }

    final hasCredentials =
        user != null && user.isNotEmpty && pass != null && pass.isNotEmpty;
    if (hasCredentials) {
      _isAuthenticated = true;
      _username = user;
    }
    _isChecking = false;
    _notify();

    if (hasCredentials) unawaited(_warmUpSession(user));
  }

  Future<void> _warmUpSession(String user) async {
    try {
      _logger.debug('Attempting auto-login for $user');
      final success = await _ensureSession();
      if (success) {
        _logger.info('Auto-login successful for $user');
      } else if (_isAuthenticated && _username == user) {
        _logger.warning(
            'Auto-login failed for $user (credentials probably invalid)');
        await logout();
      }
    } catch (e) {
      // Network error or timeout. We still have credentials, stay signed in
      // and keep working from the cache.
      _logger.error('Auto-login error (probably offline)', e.toString());
    }
  }

  /// Logs in with the stored credentials, joining a login that is already
  /// running. Returns false when the credentials are missing or rejected.
  Future<bool> _ensureSession() {
    final running = _sessionLogin;
    if (running != null) return running;

    late final Future<bool> login;
    login = _loginWithStoredCredentials().whenComplete(() {
      if (identical(_sessionLogin, login)) _sessionLogin = null;
    });
    return _sessionLogin = login;
  }

  Future<bool> _loginWithStoredCredentials() async {
    final creds = await _storage.getCredentials();
    final user = creds['username'];
    final pass = creds['password'];
    if (user == null || pass == null || user.isEmpty || pass.isEmpty) {
      _logger.warning('No credentials found for re-login');
      return false;
    }
    return scraperService.login(user, pass);
  }

  Future<LoginResult> login(String username, String password) async {
    _logger.debug('Manual login attempt for $username');
    try {
      final success = await scraperService.login(username, password);
      if (!success) {
        _logger.warning('Manual login failed for $username');
        return LoginResult.invalidCredentials;
      }
      _logger.info('Manual login successful for $username');
      await _storage.saveCredentials(username, password);
      _isAuthenticated = true;
      _username = username;
      _notify();
      return LoginResult.success;
    } catch (e) {
      _logger.error('Manual login error', e.toString());
      return LoginResult.networkError;
    }
  }

  Future<void> logout() async {
    _logger.info('User logout: $_username');
    try {
      await _storage.deleteCredentials();
    } catch (e) {
      _logger.error('Could not delete stored credentials', e.toString());
    }
    scraperService.clearCookies();
    _moodleCookies = null;
    _moodleCookiesAt = null;
    // The web views (LSF, Moodle, web mail) keep their sessions in the
    // platform cookie store; the next account must not inherit them.
    unawaited(_clearWebViewCookies());
    // The cached timetable is personal data: it must not survive a logout or
    // show up for the next account that signs in on this device.
    await CacheService.instance
        .removeWhere((key) => key.startsWith(CacheService.timetablePrefix));
    _isAuthenticated = false;
    _username = null;
    _notify();
  }

  Future<void> _clearWebViewCookies() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // No web view implementation on this platform (e.g. in tests).
    }
  }

  /// Runs an action that requires an LSF session.
  ///
  /// If [SessionExpiredException] is thrown it re-logs in and retries, up to
  /// [_maxReauthAttempts] times. Rejected credentials sign the user out;
  /// network errors simply bubble up.
  Future<T> runWithReauth<T>(Future<T> Function() action) async {
    // Don't race the startup login: without its cookies the action would fail
    // immediately and trigger a second, redundant login.
    final pending = _sessionLogin;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The action below surfaces the underlying problem.
      }
    }

    for (var attempt = 1;; attempt++) {
      try {
        return await action();
      } on SessionExpiredException {
        if (attempt > _maxReauthAttempts) {
          _logger.warning(
              'Failed to re-authenticate after $_maxReauthAttempts attempts');
          rethrow;
        }
        _logger.info(
            'Session expired, attempt $attempt/$_maxReauthAttempts to re-login');

        final success = await _ensureSession();
        if (!success) {
          _logger.warning('Re-login failed (invalid or missing credentials)');
          await logout();
          throw SessionExpiredException('Invalid credentials');
        }
        _logger.info('Re-login successful');
      }
    }
  }

  /// Fetches one week of the timetable.
  ///
  /// LSF's timetable page carries no trace of whether the request was
  /// authenticated: with a session that silently went stale it simply renders
  /// an empty plan. An empty week is therefore only believed after it has
  /// been fetched once more with a freshly established session.
  Future<List<TimetableEvent>> fetchTimetable(String targetWeek) async {
    Future<List<TimetableEvent>> fetch() =>
        runWithReauth(() => scraperService.fetchTimetable(targetWeek));

    final events = await fetch();
    if (events.isNotEmpty) return events;

    _logger.info('Empty timetable for $targetWeek, verifying with a new login');
    if (!await _ensureSession()) {
      _logger.warning('Re-login failed (invalid or missing credentials)');
      await logout();
      throw SessionExpiredException('Invalid credentials');
    }
    return fetch();
  }

  Future<LectureDetails> fetchLectureDetails(String publishId) {
    return runWithReauth(() => scraperService.fetchLectureDetails(publishId));
  }

  Future<PersonDetails> fetchPersonDetails(String personId) {
    return runWithReauth(() => scraperService.fetchPersonDetails(personId));
  }

  Future<GradeReport> fetchGrades() =>
      runWithReauth(scraperService.fetchGrades);

  Future<GradeDistribution?> fetchDistribution(ExamResult result) =>
      runWithReauth(() => scraperService.fetchDistribution(result));

  Future<AchievementDocuments> fetchAchievementDocuments() =>
      runWithReauth(scraperService.fetchAchievementDocuments);

  Future<List<LsfDocument>> fetchDocuments() =>
      runWithReauth(scraperService.fetchDocuments);

  Future<Uint8List> downloadDocument(LsfDocument document) =>
      runWithReauth(() => scraperService.downloadDocument(document));

  /// Makes sure the scraper holds a live LSF session and returns its cookies
  /// (for handing the session to a web view). Returns an empty map on failure.
  Future<Map<String, String>> getLsfCookies() async {
    if (!scraperService.hasSession) {
      try {
        await _ensureSession();
      } catch (e) {
        _logger.error('Could not create LSF session', e.toString());
      }
    }
    return scraperService.cookies;
  }

  static const String moodleHost = 'moodle.htw-berlin.de';

  /// How long a Moodle session is handed out again before signing in anew.
  /// The web view also signs in again by itself if the session ends early.
  static const Duration _moodleSessionReuse = Duration(minutes: 30);

  Map<String, String>? _moodleCookies;
  DateTime? _moodleCookiesAt;
  Future<Map<String, String>?>? _moodleLogin;

  /// Signs in to Moodle with the stored HTW credentials and returns the
  /// session cookies for the web view, or null when that is not possible
  /// (no credentials, rejected, offline).
  ///
  /// A recent session is reused unless [fresh] is set; parallel calls share
  /// one login.
  Future<Map<String, String>?> getMoodleCookies({bool fresh = false}) {
    final cached = _moodleCookies;
    final cachedAt = _moodleCookiesAt;
    if (!fresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _moodleSessionReuse) {
      return Future.value(cached);
    }
    final running = _moodleLogin;
    if (running != null) return running;

    late final Future<Map<String, String>?> login;
    login = _loginToMoodle().whenComplete(() {
      if (identical(_moodleLogin, login)) _moodleLogin = null;
    });
    return _moodleLogin = login;
  }

  Future<Map<String, String>?> _loginToMoodle() async {
    final Map<String, String?> creds;
    try {
      creds = await _storage.getCredentials();
    } catch (e) {
      _logger.error('Could not read stored credentials', e.toString());
      return null;
    }
    final user = creds['username'];
    final pass = creds['password'];
    if (user == null || pass == null || user.isEmpty || pass.isEmpty) {
      return null;
    }

    final client = _newClient();
    try {
      final loginUrl = Uri.https(moodleHost, '/login/index.php');
      final headers = {'User-Agent': mobileUserAgent};

      _logger.debug('Fetching Moodle login page');
      final page =
          await client.get(loginUrl, headers: headers).timeout(_timeout);
      final cookies = <String, String>{};
      mergeSetCookie(page.headers['set-cookie'], cookies);

      final token = parser
          .parse(page.body)
          .querySelector('form#login input[name="logintoken"]')
          ?.attributes['value'];
      if (token == null) {
        _logger.warning('Could not find the Moodle login form');
        return null;
      }

      final request = http.Request('POST', loginUrl)
        ..followRedirects = false
        ..headers.addAll(headers)
        ..headers['Cookie'] = cookieHeader(cookies)
        ..bodyFields = {
          'anchor': '',
          'logintoken': token,
          'username': user,
          'password': pass,
        };
      final response = await http.Response.fromStream(
        await client.send(request).timeout(_timeout),
      ).timeout(_timeout);

      // Success redirects onwards (to `?testsession=` or the dashboard);
      // a rejected login redirects back to the login form.
      final location = response.headers['location'] ?? '';
      final isRedirect = response.statusCode >= 300 && response.statusCode < 400;
      final backToLogin = location.contains('/login/index.php') &&
          !location.contains('testsession=');
      if (!isRedirect || backToLogin) {
        _logger.warning('Moodle login failed. Code: ${response.statusCode}');
        return null;
      }

      mergeSetCookie(response.headers['set-cookie'], cookies);
      _logger.info('Moodle login successful');
      if (!_isAuthenticated || _username != user) return null;
      _moodleCookies = cookies;
      _moodleCookiesAt = DateTime.now();
      return cookies;
    } catch (e) {
      _logger.error('Moodle login error', e.toString());
      return null;
    } finally {
      client.close();
    }
  }

  Future<Map<String, String>?> getWebmailCookies() async {
    final Map<String, String?> creds;
    try {
      creds = await _storage.getCredentials();
    } catch (e) {
      _logger.error('Could not read stored credentials', e.toString());
      return null;
    }
    final user = creds['username'];
    final pass = creds['password'];

    if (user == null || pass == null || user.isEmpty || pass.isEmpty) {
      return null;
    }

    final client = http.Client();
    try {
      final loginUrl = Uri.parse('https://webmail.htw-berlin.de/currentNG/');

      _logger.debug('Fetching webmail login page for CSRF tokens');
      final response1 = await client.get(loginUrl, headers: {
        'User-Agent': _webmailUserAgent,
      }).timeout(_timeout);

      final document = parser.parse(response1.body);
      final form = document.querySelector('form');
      if (form == null) {
        _logger.warning('Could not find webmail login form');
        return null;
      }

      final payload = <String, String>{};
      for (final input in form.querySelectorAll('input[type="hidden"]')) {
        final name = input.attributes['name'];
        final value = input.attributes['value'] ?? '';
        if (name != null) {
          payload[name] = value;
        }
      }

      payload['_user'] = user;
      payload['_pass'] = pass;
      payload['login_username'] = user;
      payload['secretkey'] = pass;
      payload['_task'] = 'login';
      payload['_action'] = 'login';

      final postUrl =
          Uri.parse('https://webmail.htw-berlin.de/currentNG/?_task=login');

      _logger.debug('Attempting webmail POST request');

      final request = http.Request('POST', postUrl)
        ..followRedirects = false
        ..headers['User-Agent'] = _webmailUserAgent
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = payload;

      final cookies = <String, String>{};
      mergeSetCookie(response1.headers['set-cookie'], cookies);
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = cookieHeader(cookies);
      }

      final streamedResponse = await client.send(request).timeout(_timeout);
      final response2 =
          await http.Response.fromStream(streamedResponse).timeout(_timeout);

      if (response2.statusCode == 302 &&
          (response2.headers['location']?.contains('_task=mail') ?? false)) {
        _logger.info('Webmail login successful. Extracting cookies.');
        mergeSetCookie(response2.headers['set-cookie'], cookies);
        return cookies;
      } else {
        _logger.warning('Webmail login failed. Code: ${response2.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.error('Error fetching webmail cookies', e.toString());
      return null;
    } finally {
      client.close();
    }
  }
}
