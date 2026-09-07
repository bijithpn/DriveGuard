/// A single piece of evidence read from a platform's own diagnostic source
/// (Windows Event Log, macOS unified log / panic reports, Linux journal)
/// about the previous boot/shutdown. Never fabricated — every instance here
/// must trace back to an actual log line or event the platform reported.
class SystemDiagnosticEvent {
  const SystemDiagnosticEvent({
    required this.timestamp,
    required this.source,
    required this.category,
    required this.summary,
    this.raw,
  });

  /// When the platform says the event occurred.
  final DateTime timestamp;

  /// Where it came from, e.g. "Windows Event Log (Kernel-Power)",
  /// "macOS panic report", "journalctl".
  final String source;

  /// Coarse bucket for correlation, e.g. "shutdown", "kernel-panic",
  /// "storage-error", "thermal", "unknown".
  final String category;

  /// Human-readable one-line summary, safe to show to the user.
  final String summary;

  /// The raw log line/record, kept for the diagnostics screen only.
  final String? raw;

  Map<String, Object?> toMap() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'source': source,
    'category': category,
    'summary': summary,
    'raw': raw,
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
    );
  }
}
