import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';

/// What a platform's own diagnostics could establish about the previous
/// boot/shutdown, within the window the caller asked about.
class PreviousBootDiagnosis {
  const PreviousBootDiagnosis({
    required this.classification,
    required this.events,
    this.shutdownAt,
  });

  final ShutdownClassification classification;
  final List<SystemDiagnosticEvent> events;

  /// Best estimate of when the OS actually stopped, if the logs say.
  final DateTime? shutdownAt;
}

/// Reads platform-native diagnostics (event log / unified log / journal)
/// about the previous boot, without ever inferring a storage-related cause
/// itself — that correlation happens in `IncidentCorrelationEngine`, fed by
/// [events] here plus the app's own telemetry.
///
/// Implementations use whatever diagnostic utility each OS ships with
/// (`wevtutil`, `log`, `journalctl`) via `SafeProcessRunner` — isolated
/// behind this interface so the rest of the app never depends on a specific
/// platform mechanism. If the utility is unavailable, implementations return
/// [ShutdownClassification.unknown] with an empty event list rather than
/// guessing.
abstract interface class SystemDiagnostics {
  /// A short name for the diagnostics screen, e.g. "Windows Event Log
  /// (wevtutil)", "macOS unified log", "systemd journal (journalctl)".
  String get backendName;

  /// Whether the underlying utility/API is available on this machine.
  Future<bool> isAvailable();

  /// Investigates the previous boot/shutdown, looking specifically in the
  /// window around [approximateShutdownTime] (the last heartbeat of the
  /// unclosed session) when one is known, else scans the previous boot as a
  /// whole.
  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  });
}
