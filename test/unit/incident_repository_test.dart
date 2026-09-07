import 'package:driveguard/domain/entities/monitoring_session.dart';
import 'package:driveguard/domain/entities/shutdown_incident.dart';
import 'package:driveguard/domain/entities/system_diagnostic_event.dart';
import 'package:driveguard/domain/enums/incident_enums.dart';
import 'package:driveguard/infrastructure/persistence/app_database.dart';
import 'package:driveguard/infrastructure/persistence/incident_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late IncidentRepository repo;

  setUp(() async {
    final db = await AppDatabase.openInMemoryForTesting();
    repo = IncidentRepository(db);
  });

  test(
    'a diagnostic event with an error code and stack trace round-trips '
    'through the database unchanged',
    () async {
      await repo.createSession(
        MonitoringSession(
          id: 's1',
          startedAt: DateTime(2026, 9, 7),
          operatingSystem: 'macos',
          appVersion: '1.0.0',
          pollingIntervalSeconds: 5,
        ),
      );

      final stackTrace = 'Exception: boom\n#0 main (main.dart:10)\n#1 zone';
      await repo.recordDiagnosticEvents('s1', [
        SystemDiagnosticEvent(
          timestamp: DateTime(2026, 9, 7, 10, 6),
          source: 'DriveGuard (Flutter error)',
          category: 'app-crash',
          summary: 'Exception: boom',
          raw: stackTrace,
          errorCode: 'RangeError',
        ),
      ]);

      final incident = ShutdownIncident(
        id: 'i1',
        sessionId: 's1',
        detectedAt: DateTime(2026, 9, 7, 10, 8),
        classification: ShutdownClassification.appSessionEndedUnexpectedly,
        correlationLevel: CorrelationLevel.none,
        summary: 'test',
      );
      final saved = await repo.saveIncidentIfNew(incident, const []);
      expect(saved, isTrue);

      final detail = await repo.incidentDetail('i1');
      expect(detail, isNotNull);
      expect(detail!.diagnosticEvents, hasLength(1));
      final event = detail.diagnosticEvents.single;
      expect(event.category, 'app-crash');
      expect(event.errorCode, 'RangeError');
      expect(event.raw, stackTrace);
      expect(event.summary, 'Exception: boom');
    },
  );

  test('saveIncidentIfNew refuses a duplicate for the same session', () async {
    await repo.createSession(
      MonitoringSession(
        id: 's2',
        startedAt: DateTime(2026, 9, 7),
        operatingSystem: 'linux',
        appVersion: '1.0.0',
        pollingIntervalSeconds: 5,
      ),
    );

    final first = ShutdownIncident(
      id: 'i2',
      sessionId: 's2',
      detectedAt: DateTime(2026, 9, 7),
      classification: ShutdownClassification.unknown,
      correlationLevel: CorrelationLevel.none,
      summary: 'first',
    );
    final second = ShutdownIncident(
      id: 'i2-again',
      sessionId: 's2',
      detectedAt: DateTime(2026, 9, 7),
      classification: ShutdownClassification.unknown,
      correlationLevel: CorrelationLevel.none,
      summary: 'second',
    );

    expect(await repo.saveIncidentIfNew(first, const []), isTrue);
    expect(await repo.saveIncidentIfNew(second, const []), isFalse);

    final incidents = await repo.listIncidents();
    expect(incidents, hasLength(1));
    expect(incidents.single.summary, 'first');
  });
}
