import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/repositories/storage_monitor.dart';

class UnavailableStorageMonitor extends StorageMonitor {
  const UnavailableStorageMonitor({this.reason = 'No backend available'});

  final String reason;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BackendCapabilities> getCapabilities() async => BackendCapabilities(
    backendName: 'Unavailable',
    canEnumerateDevices: false,
    canReadTemperature: false,
    canReadHealth: false,
    notes: [reason],
  );

  @override
  Future<List<StorageDevice>> getDevices() async => const [];

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async => null;

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async => const [];

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async => null;
}
