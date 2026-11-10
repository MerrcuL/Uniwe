import 'package:intl/intl.dart';

/// Cached, locale-aware formatters. Creating a [DateFormat] is surprisingly
/// expensive, so they must not be constructed inside `build` methods.
abstract final class Formats {
  static final Map<String, DateFormat> _dateFormats = {};
  static final Map<String, NumberFormat> _priceFormats = {};

  static DateFormat _date(String pattern, [String? locale]) {
    return _dateFormats.putIfAbsent('$pattern|$locale', () {
      try {
        // Formatting once verifies the locale's symbols are actually loaded.
        return DateFormat(pattern, locale)..format(DateTime(2020));
      } catch (_) {
        return DateFormat(pattern);
      }
    });
  }

  /// "Mo", "Di" … / "Mon", "Tue" …
  static String weekdayShort(DateTime date, String locale) =>
      _date('E', locale).format(date).replaceAll('.', '');

  /// "Montag" / "Monday"
  static String weekdayLong(DateTime date, String locale) =>
      _date('EEEE', locale).format(date);

  /// "Montag, 9. November" / "Monday, November 9"
  static String fullDate(DateTime date, String locale) =>
      _date('MMMMEEEEd', locale).format(date);

  /// "14:05"
  static String time(DateTime date) => _date('HH:mm').format(date);

  /// "09.11."
  static String dayMonth(DateTime date) => _date('dd.MM.').format(date);

  /// "2026-11-09" (OpenMensa date keys).
  static String isoDate(DateTime date) => _date('yyyy-MM-dd').format(date);

  /// Time for today's timestamps, date + time otherwise.
  static String timestamp(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return sameDay ? time(date) : '${dayMonth(date)} ${time(date)}';
  }

  /// "2,50 €" / "€2.50"
  static String price(double value, String locale) {
    final format = _priceFormats.putIfAbsent(locale, () {
      try {
        return NumberFormat.currency(
            locale: locale, symbol: '€', decimalDigits: 2);
      } catch (_) {
        return NumberFormat.currency(symbol: '€', decimalDigits: 2);
      }
    });
    return format.format(value);
  }
}
