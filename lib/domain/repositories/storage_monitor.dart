import '../entities/device_health.dart';
import '../entities/storage_activity.dart';
import '../entities/storage_capacity.dart';
import '../entities/storage_device.dart';
import '../entities/storage_device_event.dart';
import '../entities/storage_volume.dart';
import '../entities/temperature_reading.dart';

class BackendCapabilities {
  const BackendCapabilities({
    required this.backendName,
    required this.canEnumerateDevices,
    required this.canReadTemperature,
    required this.canReadHealth,
    this.missingTools = const [],
    this.notes = const [],
  });

  final String backendName;
  final bool canEnumerateDevices;
  final bool canReadTemperature;
  final bool canReadHealth;

  final List<String> missingTools;
  final List<String> notes;
}

/// Base storage backend contract. Concrete backends `extend` this (not
/// `implements`) so new capability-reporting methods below can ship with a
/// default "unsupported" implementation without breaking every existing
/// backend at once — a backend opts in by overriding only what it can
/// actually provide.
abstract class StorageMonitor {
  const StorageMonitor();

  Future<bool> isAvailable();

  Future<BackendCapabilities> getCapabilities();

  Future<List<StorageDevice>> getDevices();

  Future<TemperatureReading?> readTemperature(String deviceId);

  Future<List<StorageSensor>> getSensors(String deviceId);

  Future<DeviceHealth?> getHealth(String deviceId);

  /// Capacity/usage for the physical disk. Default: unavailable — override
  /// once the native backend supports it (see STORAGE_MONITORING.md Phase
  /// 3-5).
  Future<StorageCapacity> getCapacity(String deviceId) async =>
      StorageCapacity.unavailable;

  /// Mounted filesystem volumes on this physical disk. Default: empty.
  Future<List<StorageVolume>> getVolumes(String deviceId) async => const [];

  /// Real-time disk I/O activity, one event per device per sample. Default:
  /// an empty stream — backends that can't push activity leave callers to
  /// treat activity as unsupported rather than receiving fabricated zeros.
  Stream<StorageActivity> watchActivity() => const Stream.empty();

  /// Native hot-plug push notifications. Default: an empty stream —
  /// `MonitoringService` falls back to polled discovery when this backend
  /// never emits.
  Stream<StorageDeviceEvent> watchDeviceEvents() => const Stream.empty();
}
