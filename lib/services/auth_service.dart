import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

import 'lsf_scraper_service.dart';
import 'secure_storage_service.dart';
import 'log_service.dart';
import 'exceptions.dart';
import '../models/timetable_event.dart';

class AuthService extends ChangeNotifier {
  final SecureStorageService _storage = SecureStorageService();
  final LsfScraperService scraperService;
  final LogService _logger;

  bool _isChecking = true;
  bool _isAuthenticated = false;
  String? _username;

  bool get isChecking => _isChecking;
  bool get isAuthenticated => _isAuthenticated;
  String? get username => _username;

  AuthService(this.scraperService, this._logger) {
    _init();
  }

  Future<void> _init() async {
    final hasCreds = await _storage.hasCredentials();
    if (hasCreds) {
      final creds = await _storage.getCredentials();
      final user = creds['username'];
      final pass = creds['password'];

      if (user != null && pass != null) {
        try {
          _logger.debug('Attempting auto-login for $user');
          final success = await scraperService.login(user, pass);
          if (success) {
            _logger.info('Auto-login successful for $user');
            _isAuthenticated = true;
            _username = user;
          } else {
            _logger.warning('Auto-login failed for $user (credentials probably invalid)');
            // Password changed or invalid, wipe
            await _storage.deleteCredentials();
          }
        } catch (e) {
          _logger.error('Auto-login error (probably offline)', e.toString());
          // Network error or timeout. We still have credentials!
          _isAuthenticated = true; // Assume authenticated offline
          _username = user;
        }
      }
    }
    _isChecking = false;
    notifyListeners();
  }

  Future<String?> login(String username, String password) async {
    _logger.debug('Manual login attempt for $username');
    try {
      final success = await scraperService.login(username, password);
      if (success) {
        _logger.info('Manual login successful for $username');
        await _storage.saveCredentials(username, password);
        _isAuthenticated = true;
        _username = username;
        notifyListeners();
        return null; // No errors
      } else {
        _logger.warning('Manual login failed for $username');
        return 'Login fehlgeschlagen. Bitte Zugangsdaten überprüfen.';
      }
    } catch (e) {
      _logger.error('Manual login error', e.toString());
      return 'Netzwerkfehler: $e';
    }
  }

  Future<void> logout() async {
    _logger.info('User logout: $_username');
    await _storage.deleteCredentials();
    _isAuthenticated = false;
    _username = null;
    notifyListeners();
  }

  /// Runs an action that requires authentication.
  /// If [SessionExpiredException] is thrown, it attempts to re-login up to 3 times.
  Future<T> runWithReauth<T>(Future<T> Function() action) async {
    int attempts = 0;
    while (attempts < 3) {
      try {
        return await action();
      } on SessionExpiredException {
        attempts++;
        _logger.info('Session expired, attempt $attempts/3 to re-login');
        
        final creds = await _storage.getCredentials();
        final user = creds['username'];
        final pass = creds['password'];

        if (user != null && pass != null) {
          final success = await scraperService.login(user, pass);
          if (success) {
            _logger.info('Re-login successful for $user');
            // Continue loop to retry the action
            continue;
          } else {
            _logger.warning('Re-login failed for $user (invalid credentials)');
            // If credentials are invalid, don't bother retrying
            await logout();
            throw SessionExpiredException('Ungültige Zugangsdaten. Bitte erneut anmelden.');
          }
        } else {
          _logger.warning('No credentials found for re-login');
          await logout();
          throw SessionExpiredException('Keine Zugangsdaten gefunden. Bitte erneut anmelden.');
        }
      } catch (e) {
        // Other errors (network, parsing) just bubble up
        rethrow;
      }
    }
    
    // If we reach here, we've failed 3 times
    _logger.warning('Failed to re-authenticate after 3 attempts');
    await logout();
    throw SessionExpiredException('Sitzung abgelaufen. Bitte erneut anmelden.');
  }

  Future<List<TimetableEvent>> fetchTimetable(String targetWeek) {
    return runWithReauth(() => scraperService.fetchTimetable(targetWeek));
  }

  Future<Map<String, dynamic>?> fetchLectureDetails(String publishId) {
    return runWithReauth(() => scraperService.fetchLectureDetails(publishId));
  }

  Future<Map<String, String>?> getWebmailCookies() async {
    final creds = await _storage.getCredentials();
    final user = creds['username'];
    final pass = creds['password'];

    if (user == null || pass == null || user.isEmpty || pass.isEmpty) {
      return null;
    }

    try {
      final loginUrl = Uri.parse('https://webmail.htw-berlin.de/currentNG/');
      final client = http.Client();
      
      _logger.debug('Fetching webmail login page for CSRF tokens');
      final response1 = await client.get(loginUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      });

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

      final postUrl = Uri.parse('https://webmail.htw-berlin.de/currentNG/?_task=login');
      
      _logger.debug('Attempting webmail POST request');
      
      final request = http.Request('POST', postUrl)
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = payload;

      final rawCookie1 = response1.headers['set-cookie'];
      if (rawCookie1 != null) {
        final sessionCookies = <String>[];
        var cookieParts = rawCookie1.split(RegExp(r',\s*(?=[a-zA-Z0-9_-]+\=)'));
        for (var c in cookieParts) {
          int index = c.indexOf(';');
          String cookieKeyValue = (index == -1) ? c : c.substring(0, index);
          sessionCookies.add(cookieKeyValue);
        }
        request.headers['Cookie'] = sessionCookies.join('; ');
      }

      final streamedResponse = await client.send(request);
      final response2 = await http.Response.fromStream(streamedResponse);
      
      if (response2.statusCode == 302 && (response2.headers['location']?.contains('_task=mail') ?? false)) {
        _logger.info('Webmail login successful. Extracting cookies.');
        final cookies = <String, String>{};
        final rawCookie = response2.headers['set-cookie'];
        if (rawCookie != null) {
          var cookieParts = rawCookie.split(RegExp(r',\s*(?=[a-zA-Z0-9_-]+\=)'));
          for (var c in cookieParts) {
            int index = c.indexOf(';');
            String cookieKeyValue = (index == -1) ? c : c.substring(0, index);
            int eqIndex = cookieKeyValue.indexOf('=');
            if (eqIndex != -1) {
               String key = cookieKeyValue.substring(0, eqIndex).trim();
               String value = cookieKeyValue.substring(eqIndex + 1).trim();
               cookies[key] = value;
            }
          }
        }
        return cookies;
      } else {
        _logger.warning('Webmail login failed. Code: ${response2.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.error('Error fetching webmail cookies', e.toString());
      return null;
    }
  }
}
