import '../../core/logging/app_logger.dart';
import '../../domain/entities/monitoring_session.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import 'app_database.dart';

class IncidentRepository {
  IncidentRepository(this._appDb);

  static const _tag = 'IncidentRepository';
  final AppDatabase _appDb;

  Future<void> createSession(MonitoringSession session) async {
    try {
      await _appDb.db.insert('sessions', session.toMap());
    } catch (e) {
      AppLogger.instance.error(_tag, 'createSession failed', e);
    }
  }

  Future<void> heartbeat(String sessionId, DateTime at) async {
    try {
      await _appDb.db.update(
        'sessions',
        {'last_heartbeat_at': at.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'heartbeat write failed: $e');
    }
  }

  Future<void> markSessionClosed(String sessionId, DateTime at) async {
    try {
      await _appDb.db.update(
        'sessions',
        {'ended_at': at.millisecondsSinceEpoch, 'ended_cleanly': 1},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'markSessionClosed failed: $e');
    }
  }

  Future<MonitoringSession?> previousSession({String? excludeId}) async {
    try {
      final rows = await _appDb.db.query(
        'sessions',
        where: excludeId != null ? 'id != ?' : null,
        whereArgs: excludeId != null ? [excludeId] : null,
        orderBy: 'started_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return MonitoringSession.fromMap(rows.first);
    } catch (e) {
      AppLogger.instance.error(_tag, 'previousSession query failed', e);
      return null;
    }
  }

  Future<void> recordPreIncidentSamples(List<PreIncidentSample> samples) async {
    if (samples.isEmpty) return;
    try {
      final batch = _appDb.db.batch();
      for (final s in samples) {
        batch.insert('pre_incident_samples', s.toMap());
      }
      await batch.commit(noResult: true);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'recordPreIncidentSamples failed: $e');
    }
  }

  Future<List<PreIncidentSample>> samplesForSession(
    String sessionId, {
    String? deviceId,
  }) async {
    try {
      final rows = await _appDb.db.query(
        'pre_incident_samples',
        where: deviceId != null
            ? 'session_id = ? AND device_id = ?'
            : 'session_id = ?',
        whereArgs: deviceId != null ? [sessionId, deviceId] : [sessionId],
        orderBy: 'timestamp ASC',
      );
      return rows.map(PreIncidentSample.fromMap).toList();
    } catch (e) {
      AppLogger.instance.error(_tag, 'samplesForSession failed', e);
      return const [];
    }
  }

  Future<void> recordDiagnosticEvents(
    String sessionId,
    List<SystemDiagnosticEvent> events,
  ) async {
    if (events.isEmpty) return;
    try {
      final batch = _appDb.db.batch();
      for (final e in events) {
        final map = e.toMap();
        map['session_id'] = sessionId;
        batch.insert('diagnostic_events', map);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'recordDiagnosticEvents failed: $e');
    }
  }

  Future<bool> saveIncidentIfNew(
    ShutdownIncident incident,
    List<SystemDiagnosticEvent> diagnosticEvents,
  ) async {
    try {
      final existing = await _appDb.db.query(
        'incidents',
        where: 'session_id = ?',
        whereArgs: [incident.sessionId],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;

      final batch = _appDb.db.batch();
      batch.insert('incidents', incident.toMap());
      for (final stat in incident.deviceStats) {
        final map = stat.toMap();
        map['incident_id'] = incident.id;
        batch.insert('incident_device_stats', map);
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      AppLogger.instance.error(_tag, 'saveIncidentIfNew failed', e);
      return false;
    }
  }

  Future<ShutdownIncident?> incidentBySessionId(String sessionId) async {
    try {
      final rows = await _appDb.db.query(
        'incidents',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return incidentDetail(rows.first['id'] as String);
    } catch (e) {
      AppLogger.instance.error(_tag, 'incidentBySessionId failed', e);
      return null;
    }
  }

  Future<void> markIncidentNotificationShown(String incidentId) async {
    try {
      await _appDb.db.update(
        'incidents',
        {'notification_shown': 1},
        where: 'id = ?',
        whereArgs: [incidentId],
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'markIncidentNotificationShown: $e');
    }
  }

  Future<List<ShutdownIncident>> listIncidents({int limit = 100}) async {
    try {
      final rows = await _appDb.db.query(
        'incidents',
        orderBy: 'detected_at DESC',
        limit: limit,
      );
      return rows.map((r) => ShutdownIncident.fromMap(r)).toList();
    } catch (e) {
      AppLogger.instance.error(_tag, 'listIncidents failed', e);
      return const [];
    }
  }

  Future<ShutdownIncident?> incidentDetail(String incidentId) async {
    try {
      final rows = await _appDb.db.query(
        'incidents',
        where: 'id = ?',
        whereArgs: [incidentId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final incident = rows.first;

      final statRows = await _appDb.db.query(
        'incident_device_stats',
        where: 'incident_id = ?',
        whereArgs: [incidentId],
      );
      final stats = statRows.map(DeviceIncidentStat.fromMap).toList();

      final diagRows = await _appDb.db.query(
        'diagnostic_events',
        where: 'session_id = ?',
        whereArgs: [incident['session_id']],
        orderBy: 'timestamp ASC',
      );
      final diagEvents = diagRows.map(SystemDiagnosticEvent.fromMap).toList();

      final primaryDeviceId = incident['primary_device_id'] as String?;
      var timeline = <TimelineSample>[];
      if (primaryDeviceId != null) {
        final samples = await samplesForSession(
          incident['session_id'] as String,
          deviceId: primaryDeviceId,
        );
        timeline = samples
            .map(
              (s) => TimelineSample(timestamp: s.timestamp, celsius: s.celsius),
            )
            .toList();
      }

      return ShutdownIncident.fromMap(
        incident,
        deviceStats: stats,
        timeline: timeline,
        diagnosticEvents: diagEvents,
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'incidentDetail failed', e);
      return null;
    }
  }
}
