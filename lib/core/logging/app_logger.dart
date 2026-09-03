import 'dart:collection';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  LogEntry(this.level, this.tag, this.message, this.timestamp, [this.error]);

  final LogLevel level;
  final String tag;
  final String message;
  final DateTime timestamp;
  final Object? error;

  @override
  String toString() {
    final ts = timestamp.toIso8601String();
    final lvl = level.name.toUpperCase().padRight(7);
    final suffix = error != null ? ' | $error' : '';
    return '$ts [$lvl] $tag: $message$suffix';
  }
}

/// Structured, in-memory-ring-buffered application logger.
///
/// Section 30 requires: log key lifecycle events, never log sensitive
/// identifiers (serial numbers) by default, and expose a diagnostic export.
/// This is intentionally simple - no third-party logging dependency is
/// justified for a single-process desktop app.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 2000;
  final Queue<LogEntry> _entries = Queue<LogEntry>();

  /// When false (default), callers must not pass serial numbers/identifiers
  /// into log messages. This flag only widens what *diagnostic export*
  /// includes, matching Settings -> Advanced -> Diagnostic logging.
  bool verboseDiagnostics = false;

  void debug(String tag, String message) => _log(LogLevel.debug, tag, message);
  void info(String tag, String message) => _log(LogLevel.info, tag, message);
  void warning(String tag, String message) =>
      _log(LogLevel.warning, tag, message);
  void error(String tag, String message, [Object? error]) =>
      _log(LogLevel.error, tag, message, error);

  void _log(LogLevel level, String tag, String message, [Object? error]) {
    final entry = LogEntry(level, tag, message, DateTime.now(), error);
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    // ignore: avoid_print
    print(entry);
  }

  List<LogEntry> recent({int? limit}) {
    final list = _entries.toList();
    if (limit == null || limit >= list.length) return list;
    return list.sublist(list.length - limit);
  }

  String exportAsText() => recent().map((e) => e.toString()).join('\n');
}
