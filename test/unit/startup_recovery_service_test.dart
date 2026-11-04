import 'package:driveguard/application/incidents/startup_recovery_service.dart';
import 'package:driveguard/domain/entities/monitoring_session.dart';
import 'package:driveguard/domain/entities/shutdown_incident.dart';
import 'package:driveguard/domain/enums/incident_enums.dart';
import 'package:driveguard/infrastructure/diagnostics/system_diagnostics.dart';
import 'package:driveguard/infrastructure/persistence/app_database.dart';
import 'package:driveguard/infrastructure/persistence/incident_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDiagnostics implements SystemDiagnostics {
  _FakeDiagnostics(this.result);
  PreviousBootDiagnosis result;
  int calls = 0;

  @override
  String get backendName => 'fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  }) async {
    calls++;
    return result;
  }
}

void main() {
  late IncidentRepository repo;
  final heartbeat = DateTime(2026, 11, 4, 18, 0);

  setUp(() async {
    repo = IncidentRepository(await AppDatabase.openInMemoryForTesting());
  });

  Future<void> seedSession(
    String id,
    DateTime start, {
    bool clean = false,
  }) async {
    await repo.createSession(
      MonitoringSession(
        id: id,
        startedAt: start,
        operatingSystem: 'macos',
        appVersion: '1.0.0',
        pollingIntervalSeconds: 5,
      ),
    );
    await repo.heartbeat(id, heartbeat);
    if (clean) await repo.markSessionClosed(id, heartbeat);
  }

  StartupRecoveryService service(_FakeDiagnostics diag, {DateTime? bootedAt}) =>
      StartupRecoveryService(
        repository: repo,
        diagnostics: diag,
        bootTimeProvider: () async => bootedAt,
      );

  Future<ShutdownIncident?> recover(StartupRecoveryService s, String cur) =>
      s.recoverPreviousSession(
        currentSessionId: cur,
        warningCelsiusFor: (_) => 60,
        criticalCelsiusFor: (_) => 70,
      );

  const unknownDiag = PreviousBootDiagnosis(
    classification: ShutdownClassification.unknown,
    events: [],
  );

  test('previous session ended cleanly -> no incident', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17), clean: true);
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final diag = _FakeDiagnostics(unknownDiag);
    expect(await recover(service(diag), 'b'), isNull);
    expect(await repo.listIncidents(), isEmpty);
  });

  test('app-only stop (same boot) -> INFO, OS logs never scanned', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final diag = _FakeDiagnostics(
      const PreviousBootDiagnosis(
        classification: ShutdownClassification.osShutdownUnexpected,
        events: [],
      ),
    );
    final inc = await recover(
      service(diag, bootedAt: DateTime(2026, 11, 3)),
      'b',
    );
    expect(
      inc!.classification,
      ShutdownClassification.appSessionEndedUnexpectedly,
    );
    expect(inc.severity, IncidentSeverity.info);
    expect(diag.calls, 0);
  });

  test('machine rebooted + kernel panic -> ERROR', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final diag = _FakeDiagnostics(
      const PreviousBootDiagnosis(
        classification: ShutdownClassification.kernelPanic,
        events: [],
      ),
    );
    final inc = await recover(
      service(diag, bootedAt: DateTime(2026, 11, 4, 18, 30)),
      'b',
    );
    expect(inc!.severity, IncidentSeverity.error);
    expect(diag.calls, 1);
  });

  test('machine rebooted, cause unknown -> WARNING', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final inc = await recover(
      service(
        _FakeDiagnostics(unknownDiag),
        bootedAt: DateTime(2026, 11, 4, 18, 30),
      ),
      'b',
    );
    expect(inc!.severity, IncidentSeverity.warning);
  });

  test('the same unclean session is never reported twice', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final s = service(
      _FakeDiagnostics(unknownDiag),
      bootedAt: DateTime(2026, 11, 4, 18, 30),
    );
    expect(await recover(s, 'b'), isNotNull);
    // "Restart": same previous session evaluated again.
    expect(await recover(s, 'b'), isNull);
    expect(await repo.listIncidents(), hasLength(1));
  });

  test(
    'a relaunch loop collapses into one incident, not one per launch',
    () async {
      // One unclean session, then the machine rebooted; the app is then
      // relaunched repeatedly, each launch dying before its first heartbeat.
      await seedSession('a', DateTime(2026, 11, 4, 17));
      final boot = DateTime(2026, 11, 4, 18, 30);
      final s = service(_FakeDiagnostics(unknownDiag), bootedAt: boot);
      for (final id in ['b', 'c', 'd', 'e', 'f']) {
        await repo.createSession(
          MonitoringSession(
            id: id,
            startedAt: DateTime(
              2026,
              11,
              4,
              19,
            ).add(Duration(seconds: id.codeUnitAt(0))),
            operatingSystem: 'macos',
            appVersion: '1.0.0',
            pollingIntervalSeconds: 5,
          ),
        );
        await recover(s, id);
      }
      // The reboot after 'a' + one burst of dying relaunches b..e.
      final incidents = await repo.listIncidents();
      expect(incidents, hasLength(2));
      expect(
        incidents.where(
          (i) =>
              i.classification ==
              ShutdownClassification.appSessionEndedUnexpectedly,
        ),
        hasLength(1),
      );
    },
  );

  test('restarts of the app on the same boot never blame the OS', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    final s = service(
      _FakeDiagnostics(
        const PreviousBootDiagnosis(
          classification: ShutdownClassification.osShutdownUnexpected,
          events: [],
        ),
      ),
      bootedAt: DateTime(2026, 11, 3),
    );
    for (final id in ['b', 'c', 'd']) {
      await repo.createSession(
        MonitoringSession(
          id: id,
          startedAt: DateTime(
            2026,
            11,
            4,
            19,
          ).add(Duration(seconds: id.codeUnitAt(0))),
          operatingSystem: 'macos',
          appVersion: '1.0.0',
          pollingIntervalSeconds: 5,
        ),
      );
      await recover(s, id);
    }
    // 'a' (18:00) and the burst b..c (19:00) are two events; never OS-blamed.
    final incidents = await repo.listIncidents();
    expect(incidents, hasLength(2));
    expect(
      incidents.every(
        (i) =>
            i.classification ==
            ShutdownClassification.appSessionEndedUnexpectedly,
      ),
      isTrue,
    );
  });

  test('notification_shown persists so the popup is one-time', () async {
    await seedSession('a', DateTime(2026, 11, 4, 17));
    await seedSession('b', DateTime(2026, 11, 4, 19));
    final inc = await recover(
      service(
        _FakeDiagnostics(unknownDiag),
        bootedAt: DateTime(2026, 11, 4, 18, 30),
      ),
      'b',
    );
    expect(inc!.notificationShown, isFalse);
    await repo.markIncidentNotificationShown(inc.id);
    expect((await repo.listIncidents()).single.notificationShown, isTrue);
  });

  test('severity mapping', () {
    ShutdownIncident mk(
      ShutdownClassification c, [
      CorrelationLevel l = CorrelationLevel.none,
    ]) => ShutdownIncident(
      id: 'x',
      sessionId: 's',
      detectedAt: DateTime(2026),
      classification: c,
      correlationLevel: l,
      summary: '',
    );
    expect(mk(ShutdownClassification.bsod).severity, IncidentSeverity.error);
    expect(
      mk(ShutdownClassification.possiblePowerLoss).severity,
      IncidentSeverity.error,
    );
    expect(
      mk(ShutdownClassification.unknown, CorrelationLevel.high).severity,
      IncidentSeverity.error,
    );
    expect(
      mk(ShutdownClassification.unknown).severity,
      IncidentSeverity.warning,
    );
    expect(
      mk(ShutdownClassification.appSessionEndedUnexpectedly).severity,
      IncidentSeverity.info,
    );
  });
}
