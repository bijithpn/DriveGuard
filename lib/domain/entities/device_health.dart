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
    this.reallocatedSectorCount,
    this.reallocatedEventCount,
    this.currentPendingSectorCount,
    this.offlineUncorrectableCount,
    this.ssdLifeLeftPercent,
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

  // ATA/SATA SMART attributes (ids 5, 196, 197, 198) not covered by the NVMe
  // health log above. See docs/superpowers/specs/2026-09-09-smart-attributes-design.md.
  final int? reallocatedSectorCount;
  final int? reallocatedEventCount;
  final int? currentPendingSectorCount;
  final int? offlineUncorrectableCount;
  final int? ssdLifeLeftPercent;

  static const _bytesPerDataUnit = 512000;

  int? get totalBytesRead =>
      dataUnitsRead == null ? null : dataUnitsRead! * _bytesPerDataUnit;
  int? get totalBytesWritten =>
      dataUnitsWritten == null ? null : dataUnitsWritten! * _bytesPerDataUnit;

  /// True when any ATA SMART sector/error count is known and non-zero —
  /// the classic early-warning signs of imminent drive failure.
  bool get hasAtaWarningSigns =>
      (reallocatedSectorCount ?? 0) > 0 ||
      (reallocatedEventCount ?? 0) > 0 ||
      (currentPendingSectorCount ?? 0) > 0 ||
      (offlineUncorrectableCount ?? 0) > 0;

  static const unavailable = DeviceHealth(
    status: DeviceHealthStatus.unavailable,
  );
}
