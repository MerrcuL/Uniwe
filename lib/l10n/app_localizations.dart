import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'appTitle': 'Uniwe',
      'timetable': 'Timetable',
      'mensa': 'Mensa',
      'email': 'E-Mails',
      'settings': 'Settings',
      'noClasses': 'No classes today!',
      'enjoyFreeTime': 'Enjoy your free time.',
      'showBreakTime': 'Show Break Times',
      'haptics': 'Haptic Feedback',
      'animations': 'Animations',
      'hideNavigationLabels': 'Hide Navigation Labels',
      'app': 'App',
      'language': 'Language',
      'theme': 'Theme',
      'system': 'System',
      'light': 'Light',
      'dark': 'Dark',
      'english': 'English',
      'german': 'German',
      'dynamicColor': 'Dynamic Colors',
      'amoledTheme': 'AMOLED Theme',
      'showWeekends': 'Show Weekends',
      'weekTitle': 'Week',
      'breakText': 'min Break',
      'pauseText': 'Break',
      'exams': 'Exams',
      'examLabel': 'Exam',
      'examDetailHeader': 'Exam Dates',
      'errorNetwork': 'Network error while fetching the schedule.',
      'errorUpdate': 'Failed to update.',
      'offlineCache': 'Offline. Showing cached data.',
      'login': 'Log in',
      'logout': 'Log out',
      'loginTitle': 'HTW LSF Login',
      'loginSubtitle': 'Sign in with your HTW credentials',
      'loginButton': 'Sign in',
      'password': 'Password',
      'loginFieldsEmpty': 'Please fill in all fields',
      'loginStorageNote':
          'Your credentials are stored securely and encrypted on your device.',
      'learnMore': 'Learn more',
      'scheduleUnavailable': 'Timetable unavailable',
      'scheduleLoginPrompt': 'Sign in with your HTW credentials.',
      'overlappingLabel': 'Overlapping',
      'compactTimetable': 'Compact View',
      'emailNotifications': 'Email Notifications',
      'emailCheckInterval': 'Check Interval',
      'minutes15': '15 min',
      'minutes30': '30 min',
      'minutes60': '1 hour',
      'hours4': '4 hours',
      'hours8': '8 hours',
      'about': 'About',
      'version': 'Version',
      'appDescription': 'A free, open-source app for university students.',
      'checkForUpdates': 'Check for Updates',
      'checkForUpdatesSubtitle': 'Check if a newer version is available on GitHub',
      'sourceCode': 'Source Code',
      'licenses': 'Licenses',
      'licensesSubtitle': 'Open-source licenses used in this app',
      'acknowledgements': 'Acknowledgements',
      'updateAvailable': 'Update Available',
      'newVersion': 'New version',
      'currentVersion': 'Current version',
      'download': 'Download',
      'later': 'Later',
      'upToDate': 'You are on the latest version!',
      'updateCheckFailed': 'Could not check for updates. Please try later.',
      'flutterDesc': 'UI framework by Google',
      'openMensaDesc': 'Open API for canteen menus',
      'enoughMailDesc': 'IMAP/SMTP mail library for Dart',
      'bvgApiDesc': 'Public transport data REST API',
      'madeWithLove': 'Made with ❤️ for HTW Berlin students',
      'pressAgainToExit': 'Swipe back again to exit',
      'lastUpdated': 'Last updated',
      'lsfOnEmailLongPress': 'LSF on Email Tab Long-Press',
      'now': 'now',
      'unknownDirection': 'Unknown direction',
      'noDepartures': 'No departures found.',
    },
    'de': {
      'appTitle': 'Uniwe',
      'timetable': 'Stundenplan',
      'mensa': 'Mensa',
      'email': 'E-Mails',
      'settings': 'Einstellungen',
      'noClasses': 'Heute keine Vorlesungen!',
      'enjoyFreeTime': 'Genieße deine Freizeit.',
      'showBreakTime': 'Pausenzeiten anzeigen',
      'haptics': 'Haptisches Feedback',
      'animations': 'Animationen',
      'hideNavigationLabels': 'Navigationstexte ausblenden',
      'app': 'App',
      'language': 'Sprache',
      'theme': 'Thema',
      'system': 'System',
      'light': 'Hell',
      'dark': 'Dunkel',
      'english': 'Englisch',
      'german': 'Deutsch',
      'dynamicColor': 'Dynamische Farben',
      'amoledTheme': 'AMOLED Design',
      'showWeekends': 'Wochenenden anzeigen',
      'weekTitle': 'Woche',
      'breakText': 'Min Pause',
      'pauseText': 'Pause',
      'exams': 'Prüfungen',
      'examLabel': 'Prüfung',
      'examDetailHeader': 'Prüfungstermine',
      'errorNetwork': 'Netzwerkfehler beim Abrufen des Stundenplans.',
      'errorUpdate': 'Aktualisierung fehlgeschlagen.',
      'offlineCache': 'Offline. Zeige zwischengespeicherte Daten.',
      'login': 'Anmelden',
      'logout': 'Abmelden',
      'loginTitle': 'HTW LSF Login',
      'loginSubtitle': 'Melde dich mit deinen HTW-Zugangsdaten an',
      'loginButton': 'Anmelden',
      'password': 'Passwort',
      'loginFieldsEmpty': 'Bitte alle Felder ausfüllen',
      'loginStorageNote':
          'Deine Zugangsdaten werden sicher & lokal verschlüsselt auf deinem Gerät gespeichert.',
      'learnMore': 'Mehr erfahren',
      'scheduleUnavailable': 'Stundenplan nicht verfügbar',
      'scheduleLoginPrompt': 'Melde dich mit deinen HTW-Zugangsdaten an.',
      'overlappingLabel': 'Überlappend',
      'compactTimetable': 'Kompakte Ansicht',
      'emailNotifications': 'E-Mail-Benachrichtigungen',
      'emailCheckInterval': 'Abfrageintervall',
      'minutes15': '15 Min',
      'minutes30': '30 Min',
      'minutes60': '1 Std',
      'hours4': '4 Std',
      'hours8': '8 Std',
      'about': 'Über',
      'version': 'Version',
      'appDescription': 'Eine freie, quelloffene App für Studierende.',
      'checkForUpdates': 'Nach Updates suchen',
      'checkForUpdatesSubtitle': 'Prüfen, ob eine neuere Version auf GitHub verfügbar ist',
      'sourceCode': 'Quellcode',
      'licenses': 'Lizenzen',
      'licensesSubtitle': 'Open-Source-Lizenzen dieser App',
      'acknowledgements': 'Danksagungen',
      'updateAvailable': 'Update verfügbar',
      'newVersion': 'Neue Version',
      'currentVersion': 'Aktuelle Version',
      'download': 'Herunterladen',
      'later': 'Später',
      'upToDate': 'Du nutzt die aktuelle Version!',
      'updateCheckFailed': 'Update-Prüfung fehlgeschlagen. Bitte versuche es später.',
      'flutterDesc': 'UI-Framework von Google',
      'openMensaDesc': 'Offene API für Mensa-Speisepläne',
      'enoughMailDesc': 'IMAP/SMTP-Mail-Bibliothek für Dart',
      'bvgApiDesc': 'ÖPNV-Daten REST API',
      'madeWithLove': 'Mit ❤️ für HTW Berlin Studierende gemacht',
      'pressAgainToExit': 'Zum Beenden erneut wischen/zurückgehen',
      'lastUpdated': 'Zuletzt aktualisiert',
      'lsfOnEmailLongPress': 'LSF bei E-Mail Tab Gedrückthalten',
      'now': 'jetzt',
      'unknownDirection': 'Richtung unbekannt',
      'noDepartures': 'Keine Abfahrten gefunden.',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'de'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
