import '../l10n/app_localizations.dart';
import '../models/timetable_event.dart';

/// LSF only speaks German; these map its vocabulary to the app language.
abstract final class TimetableText {
  static String eventType(TimetableEvent event, AppLocalizations l10n) {
    if (event.isExam) return l10n.get('examLabel');
    final raw = event.type;
    if (l10n.isGerman) return raw;
    final lower = raw.toLowerCase();
    if (lower.contains('seminaristischer lehrvortrag')) {
      return 'Seminar Lecture';
    }
    if (lower.contains('vorlesung')) return 'Lecture';
    if (lower.contains('übung')) return 'Exercise';
    if (lower.contains('praktikum')) return 'Practical Course';
    return raw;
  }

  static String frequency(String raw, AppLocalizations l10n) {
    final lower = raw.toLowerCase();
    final de = l10n.isGerman;

    if (lower.contains('wöch')) return de ? 'wöchentlich' : 'weekly';
    if (lower.contains('einzelt')) return de ? 'Einzeltermin' : 'Single event';
    if (lower.contains('14-täg')) return de ? '14-täglich' : 'bi-weekly';
    // "unger. W" must be tested before "ger. W", which it contains.
    if (lower.contains('unger. w')) return de ? 'ungerade Woche' : 'odd weeks';
    if (lower.contains('ger. w')) return de ? 'gerade Woche' : 'even weeks';
    return raw;
  }

  /// "45 min Break" / "1h 30m Break" for a gap of [minutes] between classes.
  static String breakLabel(int minutes, AppLocalizations l10n) {
    if (minutes < 60) return '$minutes ${l10n.get('breakText')}';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final pause = l10n.get('pauseText');
    return m > 0 ? '${h}h ${m}m $pause' : '${h}h $pause';
  }
}
