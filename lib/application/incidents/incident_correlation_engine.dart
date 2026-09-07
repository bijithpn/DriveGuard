import '../../domain/entities/monitoring_session.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import '../../infrastructure/diagnostics/system_diagnostics.dart';










class IncidentCorrelationEngine {
  const IncidentCorrelationEngine();

  
  
  
  
  
  
  
  
  ShutdownIncident? analyze({
    required MonitoringSession previousSession,
    required PreviousBootDiagnosis diagnosis,
    required Map<String, List<PreIncidentSample>> samplesByDevice,
    required double Function(String deviceId) warningCelsiusFor,
    required double Function(String deviceId) criticalCelsiusFor,
    required String newIncidentId,
    required DateTime now,
  }) {
    if (previousSession.endedCleanly) return null;

    final classification = _classify(previousSession, diagnosis);

    
    
    if (classification == ShutdownClassification.appSessionEndedUnexpectedly) {
      return ShutdownIncident(
        id: newIncidentId,
        sessionId: previousSession.id,
        detectedAt: now,
        estimatedShutdownAt: previousSession.lastHeartbeatAt,
        startupAt: now,
        classification: classification,
        correlationLevel: CorrelationLevel.none,
        summary:
            'Previous monitoring session ended unexpectedly, but the '
            'operating system shut down normally afterward — this looks '
            'like an application crash or forced quit, not a system-level '
            'event.',
        primaryDeviceId: null,
        deviceStats: const [],
        timeline: const [],
        diagnosticEvents: diagnosis.events,
      );
    }

    final estimatedShutdownAt =
        diagnosis.shutdownAt ?? previousSession.lastHeartbeatAt;

    final stats = <DeviceIncidentStat>[];
    for (final entry in samplesByDevice.entries) {
      final deviceId = entry.key;
      final samples = entry.value;
      if (samples.isEmpty) continue;
      final warning = warningCelsiusFor(deviceId);
      final critical = criticalCelsiusFor(deviceId);

      double max = samples.first.celsius;
      var criticalDuration = Duration.zero;
      DateTime? criticalStart;
      for (final s in samples) {
        if (s.celsius > max) max = s.celsius;
        if (s.celsius >= critical) {
          criticalStart ??= s.timestamp;
        } else if (criticalStart != null) {
          criticalDuration += s.timestamp.difference(criticalStart);
          criticalStart = null;
        }
      }
      if (criticalStart != null) {
        criticalDuration += samples.last.timestamp.difference(criticalStart);
      }
      stats.add(
        DeviceIncidentStat(
          deviceId: deviceId,
          deviceName: samples.last.deviceName,
          lastCelsius: samples.last.celsius,
          maxCelsius: max,
          warningExceeded: max >= warning,
          criticalExceeded: max >= critical,
          criticalDuration: criticalDuration,
          alertTriggered: max >= warning,
        ),
      );
    }

    
    DeviceIncidentStat? primary;
    for (final s in stats) {
      if (s.maxCelsius == null) continue;
      if (primary == null || s.maxCelsius! > primary.maxCelsius!) {
        primary = s;
      }
    }

    final correlation = _correlate(
      classification: classification,
      primary: primary,
      diagnosticEvents: diagnosis.events,
    );

    final timeline = primary != null
        ? _buildTimeline(
            samplesByDevice[primary.deviceId] ?? const [],
            warningCelsiusFor(primary.deviceId),
            criticalCelsiusFor(primary.deviceId),
            estimatedShutdownAt,
          )
        : const <TimelineSample>[];

    return ShutdownIncident(
      id: newIncidentId,
      sessionId: previousSession.id,
      detectedAt: now,
      estimatedShutdownAt: estimatedShutdownAt,
      startupAt: now,
      classification: classification,
      correlationLevel: correlation,
      summary: _summarize(
        classification: classification,
        correlation: correlation,
        primary: primary,
      ),
      primaryDeviceId: primary?.deviceId,
      deviceStats: stats,
      timeline: timeline,
      diagnosticEvents: diagnosis.events,
    );
  }

  ShutdownClassification _classify(
    MonitoringSession session,
    PreviousBootDiagnosis diagnosis,
  ) {
    switch (diagnosis.classification) {
      case ShutdownClassification.osShutdownClean:
      case ShutdownClassification.osRebootClean:
        
        
        return ShutdownClassification.appSessionEndedUnexpectedly;
      case ShutdownClassification.kernelPanic:
      case ShutdownClassification.bsod:
      case ShutdownClassification.osShutdownUnexpected:
      case ShutdownClassification.possiblePowerLoss:
        return diagnosis.classification;
      case ShutdownClassification.unknown:
      case ShutdownClassification.cleanAppExit:
      case ShutdownClassification.appSessionEndedUnexpectedly:
        
        
        
        return ShutdownClassification.unknown;
    }
  }

  CorrelationLevel _correlate({
    required ShutdownClassification classification,
    required DeviceIncidentStat? primary,
    required List<SystemDiagnosticEvent> diagnosticEvents,
  }) {
    if (primary == null || primary.maxCelsius == null) {
      return CorrelationLevel.none;
    }
    if (!primary.warningExceeded) return CorrelationLevel.none;

    final corroborating = diagnosticEvents.any(
      (e) =>
          e.category == 'storage-error' ||
          e.category == 'kernel-panic' ||
          e.category == 'thermal',
    );
    final osLevelUnexpected =
        classification == ShutdownClassification.osShutdownUnexpected ||
        classification == ShutdownClassification.kernelPanic ||
        classification == ShutdownClassification.bsod ||
        classification == ShutdownClassification.possiblePowerLoss;

    if (primary.criticalExceeded && osLevelUnexpected && corroborating) {
      return CorrelationLevel.high;
    }
    if (primary.criticalExceeded) {
      return CorrelationLevel.moderate;
    }
    return CorrelationLevel.low;
  }

  List<TimelineSample> _buildTimeline(
    List<PreIncidentSample> samples,
    double warningCelsius,
    double criticalCelsius,
    DateTime? shutdownAt,
  ) {
    if (samples.isEmpty) return const [];
    final result = <TimelineSample>[];
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      String label;
      if (s.celsius >= criticalCelsius) {
        label = 'Critical';
      } else if (s.celsius >= warningCelsius) {
        label = 'Warning';
      } else {
        label = 'Normal';
      }
      if (i == samples.length - 1) label = 'Last reading';
      result.add(
        TimelineSample(timestamp: s.timestamp, celsius: s.celsius, label: label),
      );
    }
    if (shutdownAt != null) {
      result.add(
        TimelineSample(
          timestamp: shutdownAt,
          celsius: samples.last.celsius,
          label: 'Shutdown',
        ),
      );
    }
    return result;
  }

  String _summarize({
    required ShutdownClassification classification,
    required CorrelationLevel correlation,
    required DeviceIncidentStat? primary,
  }) {
    final shutdownWord = classification == ShutdownClassification.kernelPanic
        ? 'kernel panic'
        : classification == ShutdownClassification.bsod
        ? 'system error (BSOD)'
        : 'unexpected shutdown';

    if (correlation == CorrelationLevel.none || primary?.maxCelsius == null) {
      return 'An $shutdownWord occurred. No unusual storage temperature was '
          'observed beforehand.';
    }

    final temp = primary!.maxCelsius!.toStringAsFixed(0);
    final name = primary.deviceName;

    switch (correlation) {
      case CorrelationLevel.low:
        return '$name was slightly elevated ($temp°C) shortly before the '
            '$shutdownWord. No strong thermal correlation was established.';
      case CorrelationLevel.moderate:
        return '$name exceeded your configured critical temperature '
            '(reached $temp°C) shortly before the $shutdownWord.';
      case CorrelationLevel.high:
        return 'A critical storage-temperature event on $name ($temp°C) '
            'occurred immediately before the $shutdownWord, and platform '
            'diagnostics reported related evidence around the same time.';
      case CorrelationLevel.none:
        return 'An $shutdownWord occurred. No thermal correlation was '
            'detected.';
    }
  }
}
