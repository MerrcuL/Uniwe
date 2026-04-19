import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum LogLevel { info, warning, error, debug }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });

  String get formattedTime => DateFormat('HH:mm:ss.SSS').format(timestamp);
}

class LogService extends ChangeNotifier {
  final List<LogEntry> _logs = [];
  static const int _maxLogs = 500;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String message, {LogLevel level = LogLevel.info, String? details}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      details: details,
    );
    
    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    
    // Also print to console for development
    debugPrint('[${entry.level.name.toUpperCase()}] ${entry.message}${details != null ? '\n$details' : ''}');
    
    notifyListeners();
  }

  void info(String message, [String? details]) => log(message, level: LogLevel.info, details: details);
  void warning(String message, [String? details]) => log(message, level: LogLevel.warning, details: details);
  void error(String message, [String? details]) => log(message, level: LogLevel.error, details: details);
  void debug(String message, [String? details]) => log(message, level: LogLevel.debug, details: details);

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
