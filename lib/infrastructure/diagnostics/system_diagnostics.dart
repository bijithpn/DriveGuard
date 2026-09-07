import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';

class PreviousBootDiagnosis {
  const PreviousBootDiagnosis({
    required this.classification,
    required this.events,
    this.shutdownAt,
  });

  final ShutdownClassification classification;
  final List<SystemDiagnosticEvent> events;

  final DateTime? shutdownAt;
}

abstract interface class SystemDiagnostics {
  String get backendName;

  Future<bool> isAvailable();

  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  });
}
