import 'package:driveguard/application/incidents/incident_correlation_engine.dart';
import 'package:driveguard/domain/entities/monitoring_session.dart';
import 'package:driveguard/domain/entities/system_diagnostic_event.dart';
import 'package:driveguard/domain/enums/incident_enums.dart';
import 'package:driveguard/infrastructure/diagnostics/system_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = IncidentCorrelationEngine();
  const warning = 60.0;
  const critical = 70.0;

  MonitoringSession session({
    required bool endedCleanly,
    DateTime? lastHeartbeatAt,
  }) {
    return MonitoringSession(
      id: 'session-1',
      startedAt: DateTime(2026, 9, 7, 10, 0),
      operatingSystem: 'linux',
      appVersion: '1.0.0',
      pollingIntervalSeconds: 5,
      endedCleanly: endedCleanly,
      lastHeartbeatAt: lastHeartbeatAt,
    );
  }

  List<PreIncidentSample> samples(List<(String, double)> pointsFromMinute10) {
    final base = DateTime(2026, 9, 7, 10, 0);
    return pointsFromMinute10
        .map(
          (e) => PreIncidentSample(
            sessionId: 'session-1',
            deviceId: 'nvme0',
            deviceName: 'Samsung 990 PRO',
            timestamp: base.add(_parseOffset(e.$1)),
            celsius: e.$2,
          ),
        )
        .toList();
  }

  test('clean session end never produces an incident', () {
    final result = engine.analyze(
      previousSession: session(endedCleanly: true),
      diagnosis: const PreviousBootDiagnosis(
        classification: ShutdownClassification.osShutdownClean,
        events: [],
      ),
      samplesByDevice: const {},
      warningCelsiusFor: (_) => warning,
      criticalCelsiusFor: (_) => critical,
      newIncidentId: 'incident-1',
      now: DateTime(2026, 9, 7, 10, 20),
    );
    expect(result, isNull);
  });

  test(
    'app crash test: unclosed session but OS shut down cleanly is reported '
    'as an app-level event, never a system shutdown',
    () {
      final result = engine.analyze(
        previousSession: session(
          endedCleanly: false,
          lastHeartbeatAt: DateTime(2026, 9, 7, 10, 6, 10),
        ),
        diagnosis: PreviousBootDiagnosis(
          classification: ShutdownClassification.osShutdownClean,
          events: [
            SystemDiagnosticEvent(
              timestamp: DateTime(2026, 9, 7, 10, 30),
              source: 'test',
              category: 'shutdown-clean',
              summary: 'clean shutdown',
            ),
          ],
        ),
        samplesByDevice: {
          'nvme0': samples([('10:06', 79.0)]),
        },
        warningCelsiusFor: (_) => warning,
        criticalCelsiusFor: (_) => critical,
        newIncidentId: 'incident-2',
        now: DateTime(2026, 9, 7, 10, 32),
      );

      expect(result, isNotNull);
      expect(
        result!.classification,
        ShutdownClassification.appSessionEndedUnexpectedly,
      );
      expect(result.correlationLevel, CorrelationLevel.none);
      expect(
        result.summary,
        isNot(contains('Samsung')),
        reason: 'must not claim a thermal cause for an app-level event',
      );
    },
  );

  test(
    'critical test scenario: sustained critical temperature shortly before '
    'an unexpected OS shutdown is at least a moderate correlation',
    () {
      final result = engine.analyze(
        previousSession: session(
          endedCleanly: false,
          lastHeartbeatAt: DateTime(2026, 9, 7, 10, 6, 10),
        ),
        diagnosis: PreviousBootDiagnosis(
          classification: ShutdownClassification.osShutdownUnexpected,
          shutdownAt: DateTime(2026, 9, 7, 10, 6, 14),
          events: [
            SystemDiagnosticEvent(
              timestamp: DateTime(2026, 9, 7, 10, 6, 14),
              source: 'test',
              category: 'shutdown',
              summary: 'Kernel-Power 41',
            ),
          ],
        ),
        samplesByDevice: {
          'nvme0': samples([
            ('10:00', 48.0),
            ('10:01', 50.0),
            ('10:02', 55.0),
            ('10:03', 64.0),
            ('10:04', 68.0),
            ('10:05', 72.0),
            ('10:06', 79.0),
          ]),
        },
        warningCelsiusFor: (_) => warning,
        criticalCelsiusFor: (_) => critical,
        newIncidentId: 'incident-3',
        now: DateTime(2026, 9, 7, 10, 8, 5),
      );

      expect(result, isNotNull);
      expect(
        result!.classification,
        ShutdownClassification.osShutdownUnexpected,
      );
      expect(result.primaryDeviceId, 'nvme0');
      expect(result.deviceStats.single.maxCelsius, 79.0);
      expect(result.deviceStats.single.criticalExceeded, isTrue);
      expect(
        result.correlationLevel,
        anyOf(CorrelationLevel.moderate, CorrelationLevel.high),
      );
      expect(result.summary, isNot(contains('caused')));
    },
  );

  test(
    'power loss test: recovers previous session data with no clean-shutdown '
    'evidence at all',
    () {
      final result = engine.analyze(
        previousSession: session(
          endedCleanly: false,
          lastHeartbeatAt: DateTime(2026, 9, 7, 10, 6, 10),
        ),
        diagnosis: const PreviousBootDiagnosis(
          classification: ShutdownClassification.possiblePowerLoss,
          events: [],
        ),
        samplesByDevice: {
          'nvme0': samples([('10:06', 79.0)]),
        },
        warningCelsiusFor: (_) => warning,
        criticalCelsiusFor: (_) => critical,
        newIncidentId: 'incident-4',
        now: DateTime(2026, 9, 7, 10, 9),
      );

      expect(result, isNotNull);
      expect(
        result!.classification,
        ShutdownClassification.possiblePowerLoss,
      );
      expect(result.deviceStats.single.lastCelsius, 79.0);
      // No corroborating diagnostic events -> capped at moderate, never high.
      expect(result.correlationLevel, isNot(CorrelationLevel.high));
    },
  );

  test('no elevated temperature at all yields CorrelationLevel.none', () {
    final result = engine.analyze(
      previousSession: session(
        endedCleanly: false,
        lastHeartbeatAt: DateTime(2026, 9, 7, 10, 6, 10),
      ),
      diagnosis: const PreviousBootDiagnosis(
        classification: ShutdownClassification.osShutdownUnexpected,
        events: [],
      ),
      samplesByDevice: {
        'nvme0': samples([('10:00', 42.0), ('10:06', 44.0)]),
      },
      warningCelsiusFor: (_) => warning,
      criticalCelsiusFor: (_) => critical,
      newIncidentId: 'incident-5',
      now: DateTime(2026, 9, 7, 10, 9),
    );

    expect(result, isNotNull);
    expect(result!.correlationLevel, CorrelationLevel.none);
  });

  test('deviceStats picks the hottest device as primary', () {
    final result = engine.analyze(
      previousSession: session(
        endedCleanly: false,
        lastHeartbeatAt: DateTime(2026, 9, 7, 10, 6, 10),
      ),
      diagnosis: const PreviousBootDiagnosis(
        classification: ShutdownClassification.osShutdownUnexpected,
        events: [],
      ),
      samplesByDevice: {
        'cool-drive': [
          PreIncidentSample(
            sessionId: 'session-1',
            deviceId: 'cool-drive',
            deviceName: 'Cool Drive',
            timestamp: DateTime(2026, 9, 7, 10, 6),
            celsius: 40.0,
          ),
        ],
        'hot-drive': [
          PreIncidentSample(
            sessionId: 'session-1',
            deviceId: 'hot-drive',
            deviceName: 'Hot Drive',
            timestamp: DateTime(2026, 9, 7, 10, 6),
            celsius: 81.0,
          ),
        ],
      },
      warningCelsiusFor: (_) => warning,
      criticalCelsiusFor: (_) => critical,
      newIncidentId: 'incident-6',
      now: DateTime(2026, 9, 7, 10, 9),
    );

    expect(result!.primaryDeviceId, 'hot-drive');
  });
}

Duration _parseOffset(String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  final seconds = parts.length > 2 ? int.parse(parts[2]) : 0;
  return Duration(hours: hour - 10, minutes: minute, seconds: seconds);
}
