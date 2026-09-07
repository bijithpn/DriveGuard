/// A single piece of evidence read from a platform's own diagnostic source
/// (Windows Event Log, macOS unified log / panic reports, Linux journal) or
/// from the app's own crash handlers, about the previous boot/shutdown or
/// an application error. Never fabricated — every instance here must trace
/// back to an actual log line, event, or exception the platform/app
/// actually reported.
class SystemDiagnosticEvent {
  const SystemDiagnosticEvent({
    required this.timestamp,
    required this.source,
    required this.category,
    required this.summary,
    this.raw,
    this.errorCode,
  });

  /// When the platform says the event occurred.
  final DateTime timestamp;

  /// Where it came from, e.g. "Windows Event Log (Kernel-Power)",
  /// "macOS panic report", "journalctl", "DriveGuard (app)".
  final String source;

  /// Coarse bucket for correlation, e.g. "shutdown", "kernel-panic",
  /// "storage-error", "thermal", "app-crash", "unknown".
  final String category;

  /// Human-readable one-line summary, safe to show to the user.
  final String summary;

  /// The raw log line/record/stack trace, kept for the diagnostics screen.
  final String? raw;

  /// A machine-readable code when the source actually provides one, e.g. a
  /// Windows bugcheck code (`0x0000009F`) or a Dart exception's runtime
  /// type (`RangeError`, `StateError`, ...) for an app-crash event. `null`
  /// when the source doesn't expose one — never guessed.
  final String? errorCode;

  Map<String, Object?> toMap() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'source': source,
    'category': category,
    'summary': summary,
    'raw': raw,
    'error_code': errorCode,
  };

  factory SystemDiagnosticEvent.fromMap(Map<String, Object?> map) {
    return SystemDiagnosticEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int,
      ),
      source: map['source'] as String,
      category: map['category'] as String,
      summary: map['summary'] as String,
      raw: map['raw'] as String?,
      errorCode: map['error_code'] as String?,
    );
  }
}
