import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/monitoring_session.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/enums/incident_enums.dart';
import '../../infrastructure/diagnostics/system_diagnostics.dart';
import '../../infrastructure/diagnostics/system_diagnostics_factory.dart';
import '../../infrastructure/persistence/incident_repository.dart';
import 'incident_correlation_engine.dart';





class StartupRecoveryService {
  StartupRecoveryService({
    required IncidentRepository repository,
    SystemDiagnostics? diagnostics,
    IncidentCorrelationEngine engine = const IncidentCorrelationEngine(),
    Uuid? uuid,
  }) : _repository = repository,
       _diagnostics = diagnostics ?? SystemDiagnosticsFactory.create(),
       _engine = engine,
       _uuid = uuid ?? const Uuid();

  static const _tag = 'StartupRecoveryService';

  final IncidentRepository _repository;
  final SystemDiagnostics _diagnostics;
  final IncidentCorrelationEngine _engine;
  final Uuid _uuid;

  
  
  
  Future<MonitoringSession> startNewSession({
    required String appVersion,
    required Duration pollingInterval,
  }) async {
    final session = MonitoringSession(
      id: _uuid.v4(),
      startedAt: DateTime.now(),
      operatingSystem: Platform.operatingSystem,
      appVersion: appVersion,
      pollingIntervalSeconds: pollingInterval.inSeconds,
    );
    await _repository.createSession(session);
    return session;
  }

  
  
  
  
  
  Future<ShutdownIncident?> recoverPreviousSession({
    required String currentSessionId,
    required double Function(String deviceId) warningCelsiusFor,
    required double Function(String deviceId) criticalCelsiusFor,
  }) async {
    final previous = await _repository.previousSession(
      excludeId: currentSessionId,
    );
    if (previous == null) {
      AppLogger.instance.info(_tag, 'No previous session found');
      return null;
    }
    if (previous.endedCleanly) {
      AppLogger.instance.info(_tag, 'Previous session ended cleanly');
      return null;
    }

    final existing = await _repository.incidentBySessionId(previous.id);
    if (existing != null) {
      AppLogger.instance.info(
        _tag,
        'Incident already recorded for session ${previous.id}',
      );
      return null;
    }

    AppLogger.instance.warning(
      _tag,
      'Previous session ${previous.id} did not end cleanly — investigating',
    );

    PreviousBootDiagnosis diagnosis;
    try {
      diagnosis = await _diagnostics.diagnosePreviousBoot(
        approximateShutdownTime: previous.lastHeartbeatAt,
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Platform diagnostics failed', e);
      diagnosis = const PreviousBootDiagnosis(
        classification: ShutdownClassification.unknown,
        events: [],
      );
    }

    final allSamples = await _repository.samplesForSession(previous.id);
    final byDevice = <String, List<PreIncidentSample>>{};
    for (final s in allSamples) {
      byDevice.putIfAbsent(s.deviceId, () => []).add(s);
    }

    final incident = _engine.analyze(
      previousSession: previous,
      diagnosis: diagnosis,
      samplesByDevice: byDevice,
      warningCelsiusFor: warningCelsiusFor,
      criticalCelsiusFor: criticalCelsiusFor,
      newIncidentId: _uuid.v4(),
      now: DateTime.now(),
    );
    if (incident == null) return null;

    final saved = await _repository.saveIncidentIfNew(
      incident,
      diagnosis.events,
    );
    if (!saved) {
      return _repository.incidentBySessionId(previous.id);
    }
    AppLogger.instance.warning(
      _tag,
      'Incident recorded: ${incident.classification.name} / '
      '${incident.correlationLevel.name}',
    );
    return incident;
  }

  Future<void> markShown(String incidentId) =>
      _repository.markIncidentNotificationShown(incidentId);
}
