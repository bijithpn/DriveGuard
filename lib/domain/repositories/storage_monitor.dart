import '../entities/device_health.dart';
import '../entities/storage_device.dart';
import '../entities/temperature_reading.dart';

/// Capabilities a concrete backend actually supports on the running
/// machine. The application layer uses this to explain *why* something is
/// unavailable instead of silently omitting it.
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

  /// External executables this backend wanted but could not find
  /// (e.g. "smartctl", "nvme"). Surfaced in Settings -> Advanced.
  final List<String> missingTools;
  final List<String> notes;
}

/// Platform-independent contract every OS backend (and the mock backend)
/// implements. The Flutter/application layer must never import a
/// platform-specific class directly - only this abstraction.
abstract class StorageMonitor {
  /// True once this backend has verified it can talk to the OS (tool
  /// present, API reachable) - checked once at startup, not per-poll.
  Future<bool> isAvailable();

  Future<BackendCapabilities> getCapabilities();

  /// Full device enumeration. Called at startup and on the periodic
  /// hardware-change scan. A single device that fails to parse must be
  /// dropped with a logged warning, not abort the whole scan.
  Future<List<StorageDevice>> getDevices();

  /// One-shot temperature read for a single device. Returns null (never
  /// throws for the "no sensor" case) when the device structurally has no
  /// exposed sensor; throws a [StorageMonitorException] subtype for actual
  /// failures (permission, command failure, etc.) so the monitoring
  /// service can distinguish and record them.
  Future<TemperatureReading?> readTemperature(String deviceId);

  Future<List<StorageSensor>> getSensors(String deviceId);

  Future<DeviceHealth?> getHealth(String deviceId);
}
