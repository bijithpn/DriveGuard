import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/repositories/storage_monitor.dart';

/// Composes the native backend with the legacy CLI-based backend for the
/// same OS, per docs/architecture.md's "Native -> CLI fallback ->
/// unavailable" chain (spec section 7).
///
/// Both backends for a given platform mint device IDs in the same
/// "`<platform>-<native-disk-identifier>`" scheme (e.g. `macos-disk0`,
/// `linux-nvme0n1`, `windows-3`), so a device discovered by one is
/// addressable on the other without a translation table. This is a
/// convention enforced by each backend's constructor, not a coincidence -
/// see the platform monitor files for the exact scheme.
///
/// Enumeration prefers whichever backend returns a non-empty list (native
/// first, since it doesn't depend on an external tool being installed);
/// per-device temperature/health independently try native first, then the
/// CLI backend, so a native backend that enumerates but can't read SMART
/// (e.g. macOS IOKit without a private entitlement) still gets real
/// temperature data from smartctl.
class FallbackStorageMonitor implements StorageMonitor {
  FallbackStorageMonitor({required this.native, required this.legacy});

  final StorageMonitor native;
  final StorageMonitor legacy;

  static const _tag = 'FallbackStorageMonitor';

  bool? _nativeAvailable;

  Future<bool> _isNativeAvailable() async => _nativeAvailable ??= await native.isAvailable();

  @override
  Future<bool> isAvailable() async => await _isNativeAvailable() || await legacy.isAvailable();

  @override
  Future<BackendCapabilities> getCapabilities() async {
    final legacyCaps = await legacy.getCapabilities();
    if (!await _isNativeAvailable()) return legacyCaps;
    final nativeCaps = await native.getCapabilities();
    return BackendCapabilities(
      backendName: '${nativeCaps.backendName} + ${legacyCaps.backendName} (fallback)',
      canEnumerateDevices: nativeCaps.canEnumerateDevices || legacyCaps.canEnumerateDevices,
      canReadTemperature: nativeCaps.canReadTemperature || legacyCaps.canReadTemperature,
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
        AppLogger.instance.warning(_tag, 'Native enumeration failed, using legacy: $e');
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
        AppLogger.instance.debug(_tag, 'Native temperature read failed for $deviceId: $e');
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
        AppLogger.instance.debug(_tag, 'Native health read failed for $deviceId: $e');
      }
    }
    return legacy.getHealth(deviceId);
  }
}
