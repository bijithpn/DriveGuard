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

  test('a diagnostic event with an error code and stack trace round-trips '
      'through the database unchanged', () async {
    await repo.createSession(
      MonitoringSession(
        id: 's1',
        startedAt: DateTime(2026, 9, 7),
        operatingSystem: 'macos',
        appVersion: '1.0.0',
        pollingIntervalSeconds: 5,
      ),
    );

    const stackTrace = 'Exception: boom\n#0 main (main.dart:10)\n#1 zone';
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
  });

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

  test('purgeDuplicateIncidents keeps one row per legacy event', () async {
    final db = await AppDatabase.openInMemoryForTesting();
    final r = IncidentRepository(db);
    final t = DateTime(2026, 11, 4, 15, 20, 5);
    for (var i = 0; i < 5; i++) {
      await db.db.insert('incidents', {
        'id': 'dup$i',
        'session_id': 's$i',
        'detected_at': t.add(Duration(seconds: i * 3)).millisecondsSinceEpoch,
        'classification': 'osShutdownUnexpected',
        'correlation_level': 'none',
        'summary': 'x',
      });
    }
    await db.db.insert('incidents', {
      'id': 'other',
      'session_id': 'sx',
      'detected_at': DateTime(2026, 11, 4, 18, 38).millisecondsSinceEpoch,
      'classification': 'appSessionEndedUnexpectedly',
      'correlation_level': 'none',
      'summary': 'y',
    });

    expect(await r.purgeDuplicateIncidents(), 4);
    final left = await r.listIncidents();
    expect(left.map((i) => i.id), containsAll(['dup0', 'other']));
    expect(left, hasLength(2));
    expect(await r.purgeDuplicateIncidents(), 0);
  });

  test(
    'saveIncidentIfNew refuses the same event seen by another session',
    () async {
      ShutdownIncident make(String id, String session) => ShutdownIncident(
        id: id,
        sessionId: session,
        detectedAt: DateTime(2026, 11, 4, 15, 20),
        classification: ShutdownClassification.osShutdownUnexpected,
        correlationLevel: CorrelationLevel.none,
        summary: 's',
        fingerprint: 'same-event',
      );
      expect(await repo.saveIncidentIfNew(make('a', 's1'), const []), isTrue);
      expect(await repo.saveIncidentIfNew(make('b', 's2'), const []), isFalse);
      expect(await repo.listIncidents(), hasLength(1));
    },
  );
}
