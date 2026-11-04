import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/boot_time.dart';
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
    Future<DateTime?> Function()? bootTimeProvider,
  }) : _bootTimeProvider = bootTimeProvider ?? BootTime.current,
       _repository = repository,
       _diagnostics = diagnostics ?? SystemDiagnosticsFactory.create(),
       _engine = engine,
       _uuid = uuid ?? const Uuid();

  static const _tag = 'StartupRecoveryService';

  final IncidentRepository _repository;
  final SystemDiagnostics _diagnostics;
  final IncidentCorrelationEngine _engine;
  final Uuid _uuid;
  final Future<DateTime?> Function() _bootTimeProvider;

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

    // If the OS booted *before* the last heartbeat, the machine never went
    // down: only the app stopped (crash, forced quit, dev restart). Skip the
    // slow OS log scan and don't blame the system.
    final bootedAt = await _bootTime();
    final heartbeat = previous.lastHeartbeatAt;
    // A session that died before its first heartbeat is judged by its start.
    final lastActive = heartbeat ?? previous.startedAt;
    final sameBoot =
        bootedAt != null &&
        bootedAt.isBefore(lastActive.subtract(const Duration(seconds: 30)));

    PreviousBootDiagnosis diagnosis;
    try {
      diagnosis = sameBoot
          ? const PreviousBootDiagnosis(
              classification: ShutdownClassification.osShutdownClean,
              events: [],
            )
          : await _diagnostics.diagnosePreviousBoot(
              approximateShutdownTime: heartbeat,
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
      currentBootAt: bootedAt,
    );
    if (incident == null) return null;

    final saved = await _repository.saveIncidentIfNew(
      incident,
      diagnosis.events,
    );
    if (!saved) {
      // Same real-world event already recorded (and presented) — never
      // re-surface it, even if a different session noticed it.
      AppLogger.instance.info(
        _tag,
        'Duplicate incident ${incident.fingerprint} ignored',
      );
      return null;
    }
    AppLogger.instance.warning(
      _tag,
      'Incident recorded: ${incident.classification.name} / '
      '${incident.correlationLevel.name}',
    );
    return incident;
  }

  Future<DateTime?> _bootTime() => _bootTimeProvider();

  Future<void> markShown(String incidentId) =>
      _repository.markIncidentNotificationShown(incidentId);
}
