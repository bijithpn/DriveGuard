import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_device_event.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/repositories/storage_monitor.dart';

class FallbackStorageMonitor extends StorageMonitor {
  FallbackStorageMonitor({required this.native, required this.legacy});

  final StorageMonitor native;
  final StorageMonitor legacy;

  static const _tag = 'FallbackStorageMonitor';

  bool? _nativeAvailable;

  Future<bool> _isNativeAvailable() async =>
      _nativeAvailable ??= await native.isAvailable();

  @override
  Future<bool> isAvailable() async =>
      await _isNativeAvailable() || await legacy.isAvailable();

  @override
  Future<BackendCapabilities> getCapabilities() async {
    final legacyCaps = await legacy.getCapabilities();
    if (!await _isNativeAvailable()) return legacyCaps;
    final nativeCaps = await native.getCapabilities();
    return BackendCapabilities(
      backendName:
          '${nativeCaps.backendName} + ${legacyCaps.backendName} (fallback)',
      canEnumerateDevices:
          nativeCaps.canEnumerateDevices || legacyCaps.canEnumerateDevices,
      canReadTemperature:
          nativeCaps.canReadTemperature || legacyCaps.canReadTemperature,
      canReadHealth: nativeCaps.canReadHealth || legacyCaps.canReadHealth,
      missingTools: legacyCaps.missingTools,
      notes: [...nativeCaps.notes, ...legacyCaps.notes],
    );
  }

  @override
  Future<List<StorageDevice>> getDevices() async {
    if (await _isNativeAvailable()) {
      try {
        final nativeDevices = await native.getDevices();
        if (nativeDevices.isNotEmpty) return nativeDevices;
      } catch (e) {
        AppLogger.instance.warning(
          _tag,
          'Native enumeration failed, using legacy: $e',
        );
      }
    }
    return legacy.getDevices();
  }

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    if (await _isNativeAvailable()) {
      try {
        final reading = await native.readTemperature(deviceId);
        if (reading != null) return reading;
      } catch (e) {
        AppLogger.instance.debug(
          _tag,
          'Native temperature read failed for $deviceId: $e',
        );
      }
    }
    return legacy.readTemperature(deviceId);
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async {
    if (await _isNativeAvailable()) {
      final sensors = await native.getSensors(deviceId);
      if (sensors.isNotEmpty) return sensors;
    }
    return legacy.getSensors(deviceId);
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    if (await _isNativeAvailable()) {
      try {
        final health = await native.getHealth(deviceId);
        if (health != null) return health;
      } catch (e) {
        AppLogger.instance.debug(
          _tag,
          'Native health read failed for $deviceId: $e',
        );
      }
    }
    return legacy.getHealth(deviceId);
  }

  @override
  Future<StorageCapacity> getCapacity(String deviceId) async {
    if (await _isNativeAvailable()) {
      final capacity = await native.getCapacity(deviceId);
      if (capacity.isValid) return capacity;
    }
    return legacy.getCapacity(deviceId);
  }

  @override
  Future<List<StorageVolume>> getVolumes(String deviceId) async {
    if (await _isNativeAvailable()) {
      final volumes = await native.getVolumes(deviceId);
      if (volumes.isNotEmpty) return volumes;
    }
    return legacy.getVolumes(deviceId);
  }

  /// The legacy CLI-shelling backends never push hot-plug events (nothing
  /// to fall back to); this only ever reflects native's stream, which is
  /// itself an empty stream on a platform/build without native hot-plug
  /// support.
  @override
  Stream<StorageDeviceEvent> watchDeviceEvents() => native.watchDeviceEvents();

  /// Same rationale as [watchDeviceEvents] - only native can push activity
  /// samples; legacy CLI backends have nothing to fall back to.
  @override
  Stream<StorageActivity> watchActivity() => native.watchActivity();
}
