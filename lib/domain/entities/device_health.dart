import '../enums/storage_enums.dart';

class DeviceHealth {
  const DeviceHealth({
    required this.status,
    this.percentageUsed,
    this.availableSparePercent,
    this.availableSpareThreshold,
    this.criticalWarning,
    this.mediaErrors,
    this.powerCycles,
    this.powerOnHours,
    this.unsafeShutdowns,
    this.dataUnitsRead,
    this.dataUnitsWritten,
    this.lastErrorMessage,
    this.smartPassed,
  });

  final DeviceHealthStatus status;
  final int? percentageUsed;
  final int? availableSparePercent;

  final int? availableSpareThreshold;
  final String? criticalWarning;
  final int? mediaErrors;
  final int? powerCycles;
  final int? powerOnHours;
  final int? unsafeShutdowns;

  final int? dataUnitsRead;
  final int? dataUnitsWritten;

  final String? lastErrorMessage;
  final bool? smartPassed;

  static const _bytesPerDataUnit = 512000;

  int? get totalBytesRead =>
      dataUnitsRead == null ? null : dataUnitsRead! * _bytesPerDataUnit;
  int? get totalBytesWritten =>
      dataUnitsWritten == null ? null : dataUnitsWritten! * _bytesPerDataUnit;

  static const unavailable = DeviceHealth(
    status: DeviceHealthStatus.unavailable,
  );
}
