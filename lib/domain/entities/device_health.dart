import '../enums/storage_enums.dart';

class DeviceHealth {
  const DeviceHealth({
    required this.status,
    this.percentageUsed,
    this.availableSparePercent,
    this.criticalWarning,
    this.mediaErrors,
    this.powerCycles,
    this.powerOnHours,
    this.unsafeShutdowns,
    this.lastErrorMessage,
    this.smartPassed,
  });

  final DeviceHealthStatus status;
  final int? percentageUsed;
  final int? availableSparePercent;
  final String? criticalWarning;
  final int? mediaErrors;
  final int? powerCycles;
  final int? powerOnHours;
  final int? unsafeShutdowns;
  final String? lastErrorMessage;
  final bool? smartPassed;

  static const unavailable = DeviceHealth(
    status: DeviceHealthStatus.unavailable,
  );
}
