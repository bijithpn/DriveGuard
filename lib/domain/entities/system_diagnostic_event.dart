class SystemDiagnosticEvent {
  const SystemDiagnosticEvent({
    required this.timestamp,
    required this.source,
    required this.category,
    required this.summary,
    this.raw,
    this.errorCode,
  });

  final DateTime timestamp;

  final String source;

  final String category;

  final String summary;

  final String? raw;

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
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      source: map['source'] as String,
      category: map['category'] as String,
      summary: map['summary'] as String,
      raw: map['raw'] as String?,
      errorCode: map['error_code'] as String?,
    );
  }
}
