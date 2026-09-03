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

abstract class StorageMonitor {
  const StorageMonitor();

  Future<bool> isAvailable();

  Future<BackendCapabilities> getCapabilities();

  Future<List<StorageDevice>> getDevices();

  Future<TemperatureReading?> readTemperature(String deviceId);

  Future<List<StorageSensor>> getSensors(String deviceId);

  Future<DeviceHealth?> getHealth(String deviceId);

  Future<StorageCapacity> getCapacity(String deviceId) async =>
      StorageCapacity.unavailable;

  Future<List<StorageVolume>> getVolumes(String deviceId) async => const [];

  Stream<StorageActivity> watchActivity() => const Stream.empty();

  Stream<StorageDeviceEvent> watchDeviceEvents() => const Stream.empty();
}
