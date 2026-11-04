import '../enums/incident_enums.dart';
import 'system_diagnostic_event.dart';

class DeviceIncidentStat {
  const DeviceIncidentStat({
    required this.deviceId,
    required this.deviceName,
    this.lastCelsius,
    this.maxCelsius,
    this.warningExceeded = false,
    this.criticalExceeded = false,
    this.criticalDuration = Duration.zero,
    this.alertTriggered = false,
  });

  final String deviceId;
  final String deviceName;
  final double? lastCelsius;
  final double? maxCelsius;
  final bool warningExceeded;
  final bool criticalExceeded;
  final Duration criticalDuration;
  final bool alertTriggered;

  Map<String, Object?> toMap() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'last_celsius': lastCelsius,
    'max_celsius': maxCelsius,
    'warning_exceeded': warningExceeded ? 1 : 0,
    'critical_exceeded': criticalExceeded ? 1 : 0,
    'critical_duration_ms': criticalDuration.inMilliseconds,
    'alert_triggered': alertTriggered ? 1 : 0,
  };

  factory DeviceIncidentStat.fromMap(Map<String, Object?> map) {
    return DeviceIncidentStat(
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String,
      lastCelsius: (map['last_celsius'] as num?)?.toDouble(),
      maxCelsius: (map['max_celsius'] as num?)?.toDouble(),
      warningExceeded: (map['warning_exceeded'] as int? ?? 0) != 0,
      criticalExceeded: (map['critical_exceeded'] as int? ?? 0) != 0,
      criticalDuration: Duration(
        milliseconds: map['critical_duration_ms'] as int? ?? 0,
      ),
      alertTriggered: (map['alert_triggered'] as int? ?? 0) != 0,
    );
  }
}

class ShutdownIncident {
  const ShutdownIncident({
    required this.id,
    required this.sessionId,
    required this.detectedAt,
    required this.classification,
    required this.correlationLevel,
    required this.summary,
    this.estimatedShutdownAt,
    this.startupAt,
    this.primaryDeviceId,
    this.deviceStats = const [],
    this.timeline = const [],
    this.diagnosticEvents = const [],
    this.notificationShown = false,
    this.fingerprint,
  });

  final String id;

  /// Hash identifying the real-world event (see [IncidentFingerprint]); two
  /// incidents with the same fingerprint are the same event.
  final String? fingerprint;

  final String sessionId;

  final DateTime detectedAt;
  final DateTime? estimatedShutdownAt;
  final DateTime? startupAt;
  final ShutdownClassification classification;
  final CorrelationLevel correlationLevel;

  final String summary;

  final String? primaryDeviceId;
  final List<DeviceIncidentStat> deviceStats;

  final List<TimelineSample> timeline;
  final List<SystemDiagnosticEvent> diagnosticEvents;
  final bool notificationShown;

  bool get isUnexpected =>
      classification != ShutdownClassification.cleanAppExit &&
      classification != ShutdownClassification.osShutdownClean &&
      classification != ShutdownClassification.osRebootClean;

  /// error: the system itself went down abnormally (or strong thermal link).
  /// warning: the machine restarted but the cause is unknown.
  /// info: only the app session ended (crash / forced quit / dev restart).
  IncidentSeverity get severity {
    switch (classification) {
      case ShutdownClassification.kernelPanic:
      case ShutdownClassification.bsod:
      case ShutdownClassification.osShutdownUnexpected:
      case ShutdownClassification.possiblePowerLoss:
        return IncidentSeverity.error;
      case ShutdownClassification.unknown:
        return correlationLevel == CorrelationLevel.high ||
                correlationLevel == CorrelationLevel.moderate
            ? IncidentSeverity.error
            : IncidentSeverity.warning;
      case ShutdownClassification.appSessionEndedUnexpectedly:
        return correlationLevel == CorrelationLevel.none
            ? IncidentSeverity.info
            : IncidentSeverity.warning;
      case ShutdownClassification.cleanAppExit:
      case ShutdownClassification.osShutdownClean:
      case ShutdownClassification.osRebootClean:
        return IncidentSeverity.info;
    }
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'detected_at': detectedAt.millisecondsSinceEpoch,
    'estimated_shutdown_at': estimatedShutdownAt?.millisecondsSinceEpoch,
    'startup_at': startupAt?.millisecondsSinceEpoch,
    'classification': classification.name,
    'correlation_level': correlationLevel.name,
    'summary': summary,
    'primary_device_id': primaryDeviceId,
    'notification_shown': notificationShown ? 1 : 0,
    'fingerprint': fingerprint,
  };

  factory ShutdownIncident.fromMap(
    Map<String, Object?> map, {
    List<DeviceIncidentStat> deviceStats = const [],
    List<TimelineSample> timeline = const [],
    List<SystemDiagnosticEvent> diagnosticEvents = const [],
  }) {
    return ShutdownIncident(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      detectedAt: DateTime.fromMillisecondsSinceEpoch(
        map['detected_at'] as int,
      ),
      estimatedShutdownAt: map['estimated_shutdown_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['estimated_shutdown_at'] as int,
            )
          : null,
      startupAt: map['startup_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['startup_at'] as int)
          : null,
      classification: ShutdownClassification.values.firstWhere(
        (v) => v.name == map['classification'],
        orElse: () => ShutdownClassification.unknown,
      ),
      correlationLevel: CorrelationLevel.values.firstWhere(
        (v) => v.name == map['correlation_level'],
        orElse: () => CorrelationLevel.none,
      ),
      summary: map['summary'] as String,
      primaryDeviceId: map['primary_device_id'] as String?,
      notificationShown: (map['notification_shown'] as int? ?? 0) != 0,
      fingerprint: map['fingerprint'] as String?,
      deviceStats: deviceStats,
      timeline: timeline,
      diagnosticEvents: diagnosticEvents,
    );
  }
}

class TimelineSample {
  const TimelineSample({
    required this.timestamp,
    required this.celsius,
    this.label,
  });

  final DateTime timestamp;
  final double celsius;

  final String? label;
}
