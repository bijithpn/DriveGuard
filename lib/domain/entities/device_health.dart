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

  /// The spare-capacity percentage below which the device itself considers
  /// the "Available Spare" critical warning bit warranted (NVMe SMART/Health
  /// log byte 4). `null` when not reported - never assume a universal
  /// threshold across vendors.
  final int? availableSpareThreshold;
  final String? criticalWarning;
  final int? mediaErrors;
  final int? powerCycles;
  final int? powerOnHours;
  final int? unsafeShutdowns;

  /// Lifetime data units read/written, in NVMe's native unit: 1000 * 512
  /// bytes = 512,000 bytes per unit (NVMe base spec 5.14.1.3). Kept as the
  /// raw counter rather than a pre-multiplied byte count so a caller can see
  /// exactly what the device reported; use [totalBytesRead]/
  /// [totalBytesWritten] for the derived byte value.
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
