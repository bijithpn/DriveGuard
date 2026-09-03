import '../enums/storage_enums.dart';

/// A single time-based sample of real-time disk I/O for one device, as
/// pushed over the `driveguard/storage_activity` EventChannel.
///
/// Values are always derived from `(currentCounter - previousCounter) /
/// elapsedTime` on the native side — never computed from capacity or any
/// static field. When counters are unavailable (e.g. some USB bridges,
/// permission issues) [availability] reflects that instead of emitting
/// zeroes.
class StorageActivity {
  const StorageActivity({
    required this.deviceId,
    required this.timestamp,
    required this.availability,
    this.readBytesPerSecond,
    this.writeBytesPerSecond,
    this.readOperationsPerSecond,
    this.writeOperationsPerSecond,
    this.utilizationPercent,
  });

  final String deviceId;
  final DateTime timestamp;
  final SensorAvailability availability;

  final double? readBytesPerSecond;
  final double? writeBytesPerSecond;
  final double? readOperationsPerSecond;
  final double? writeOperationsPerSecond;

  /// Percentage of the sample window the device was busy servicing I/O,
  /// when the platform exposes it (e.g. Windows `% Disk Time`, Linux
  /// `/sys/block/*/stat` field 10). `null` if not exposed.
  final double? utilizationPercent;
}
