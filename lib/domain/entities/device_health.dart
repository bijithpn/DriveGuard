import '../enums/storage_enums.dart';

/// SMART/NVMe health snapshot. Every field is nullable because most fields
/// are backend- and device-dependent - a missing field must render as
/// "Not available", never a fabricated 0 or "OK".
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

  static const unavailable = DeviceHealth(status: DeviceHealthStatus.unavailable);
}
