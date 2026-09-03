import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_device_event.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';
import 'storage_native_channel.dart';

class NativeStorageMonitor extends StorageMonitor {
  static const _tag = 'NativeStorageMonitor';
  final _channel = StorageNativeChannel.instance;

  bool? _availableCache;

  @override
  Future<bool> isAvailable() async {
    if (_availableCache != null) return _availableCache!;
    try {
      await _channel.getCapabilities();
      return _availableCache = true;
    } on MissingPluginException {
      return _availableCache = false;
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Native channel probe failed: $e');
      return _availableCache = false;
    }
  }

  @override
  Future<BackendCapabilities> getCapabilities() async {
    try {
      final raw = await _channel.getCapabilities();
      return BackendCapabilities(
        backendName: raw['backendName']?.toString() ?? 'Native',
        canEnumerateDevices: raw['canEnumerateDevices'] == true,
        canReadTemperature: raw['canReadTemperature'] == true,
        canReadHealth: raw['canReadHealth'] == true,
        missingTools:
            (raw['missingTools'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        notes:
            (raw['notes'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
    } on MissingPluginException {
      return const BackendCapabilities(
        backendName: 'Native (unavailable)',
        canEnumerateDevices: false,
        canReadTemperature: false,
        canReadHealth: false,
      );
    }
  }

  @override
  Future<List<StorageDevice>> getDevices() async {
    try {
      final raw = await _channel.getDevices();
      return raw.map(_deviceFromMap).whereType<StorageDevice>().toList();
    } on MissingPluginException {
      return const [];
    } catch (e) {
      AppLogger.instance.error(_tag, 'Native device enumeration failed', e);
      return const [];
    }
  }

  StorageDevice? _deviceFromMap(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return StorageDevice(
      id: id,
      type: _parseDeviceType(m['type']?.toString()),
      interfaceType: _parseInterfaceType(m['interface']?.toString()),
      sensorAvailability: SensorAvailability.unavailable,
      model: m['model']?.toString(),
      manufacturer: m['manufacturer']?.toString(),
      serialNumber: m['serial']?.toString(),
      capacityBytes: (m['capacityBytes'] as num?)?.toInt(),
      isRemovable: m['removable'] == true,
    );
  }

  StorageDeviceType _parseDeviceType(String? v) => switch (v) {
    'nvme' => StorageDeviceType.nvme,
    'ssd' => StorageDeviceType.ssd,
    'hdd' => StorageDeviceType.hdd,
    _ => StorageDeviceType.unknown,
  };

  StorageInterfaceType _parseInterfaceType(String? v) => switch (v) {
    'nvme' => StorageInterfaceType.nvme,
    'sata' => StorageInterfaceType.sata,
    'usb' => StorageInterfaceType.usb,
    'scsi' => StorageInterfaceType.scsi,
    _ => StorageInterfaceType.unknown,
  };

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    Map<String, dynamic>? raw;
    try {
      raw = await _channel.readTemperature(deviceId);
    } on MissingPluginException {
      return null;
    }
    if (raw == null) return null;
    final celsius = (raw['celsius'] as num?)?.toDouble();
    if (celsius == null) return null;

    final timestampMs = (raw['timestampMs'] as num?)?.toInt();
    final timestamp = timestampMs != null
        ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
        : DateTime.now();

    if (!TemperatureUtils.isPlausibleValue(celsius)) {
      return TemperatureReading(
        celsius: celsius,
        timestamp: timestamp,
        source: TemperatureSource(
          backendName: 'native',
          sensorId: raw['sensorId']?.toString() ?? 'composite',
        ),
        isValid: false,
        invalidReason:
            'Implausible temperature from native backend: $celsius°C',
      );
    }

    return TemperatureReading(
      celsius: celsius,
      timestamp: timestamp,
      source: TemperatureSource(
        backendName: 'native',
        sensorId: raw['sensorId']?.toString() ?? 'composite',
      ),
    );
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async {
    try {
      final raw = await _channel.getSensors(deviceId);
      if (raw.isNotEmpty) {
        final now = DateTime.now();
        final sensors = raw
            .map((m) => _sensorFromMap(m, now))
            .whereType<StorageSensor>()
            .toList();
        if (sensors.isNotEmpty) return sensors;
      }
    } on MissingPluginException {
      AppLogger.instance.debug(
        _tag,
        'Native channel missing plugin Implmentaion',
      );
    } catch (e) {
      AppLogger.instance.debug(
        _tag,
        'Native multi-sensor read failed for $deviceId: $e',
      );
    }

    final reading = await readTemperature(deviceId);
    if (reading == null) return const [];
    return [
      StorageSensor(
        id: reading.source.sensorId,
        name: reading.source.sensorId == 'composite'
            ? 'Composite'
            : reading.source.sensorId,
        reading: reading,
        type: TemperatureSensorType.composite,
        isPrimary: true,
      ),
    ];
  }

  StorageSensor? _sensorFromMap(Map<String, dynamic> m, DateTime now) {
    final celsius = (m['celsius'] as num?)?.toDouble();
    if (celsius == null) return null;
    final id = m['id']?.toString() ?? 'sensor';
    final name = m['name']?.toString() ?? id;
    final isPrimary = m['isPrimary'] == true;
    final reading = TemperatureReading(
      celsius: celsius,
      timestamp: now,
      source: TemperatureSource(backendName: 'native', sensorId: id),
      isValid: TemperatureUtils.isPlausibleValue(celsius),
    );
    return StorageSensor(
      id: id,
      name: name,
      reading: reading,
      type: id == 'composite'
          ? TemperatureSensorType.composite
          : TemperatureSensorType.namespace,
      isPrimary: isPrimary,
    );
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    Map<String, dynamic>? raw;
    try {
      raw = await _channel.getHealth(deviceId);
    } on MissingPluginException {
      return null;
    }
    if (raw == null) return null;
    return DeviceHealth(
      status: _parseHealthStatus(raw['status']?.toString()),
      percentageUsed: (raw['percentageUsed'] as num?)?.toInt(),
      availableSparePercent: (raw['availableSparePercent'] as num?)?.toInt(),
      criticalWarning: raw['criticalWarning']?.toString(),
      availableSpareThreshold: (raw['availableSpareThreshold'] as num?)
          ?.toInt(),
      mediaErrors: (raw['mediaErrors'] as num?)?.toInt(),
      powerCycles: (raw['powerCycles'] as num?)?.toInt(),
      powerOnHours: (raw['powerOnHours'] as num?)?.toInt(),
      unsafeShutdowns: (raw['unsafeShutdowns'] as num?)?.toInt(),
      dataUnitsRead: (raw['dataUnitsRead'] as num?)?.toInt(),
      dataUnitsWritten: (raw['dataUnitsWritten'] as num?)?.toInt(),
      smartPassed: raw['smartPassed'] as bool?,
    );
  }

  DeviceHealthStatus _parseHealthStatus(String? v) => switch (v) {
    'healthy' => DeviceHealthStatus.healthy,
    'warning' => DeviceHealthStatus.warning,
    'critical' => DeviceHealthStatus.critical,
    'unavailable' => DeviceHealthStatus.unavailable,
    _ => DeviceHealthStatus.unknown,
  };

  @override
  Future<StorageCapacity> getCapacity(String deviceId) async {
    Map<String, dynamic>? raw;
    try {
      raw = await _channel.getCapacity(deviceId);
    } on MissingPluginException {
      return StorageCapacity.unavailable;
    } catch (e) {
      AppLogger.instance.debug(
        _tag,
        'Native capacity read failed for $deviceId: $e',
      );
      return StorageCapacity.unavailable;
    }
    if (raw == null) return StorageCapacity.unavailable;
    return StorageCapacity(
      availability: SensorAvailability.available,
      totalBytes: (raw['totalBytes'] as num?)?.toInt(),
      usedBytes: (raw['usedBytes'] as num?)?.toInt(),
      freeBytes: (raw['freeBytes'] as num?)?.toInt(),
      allocatedBytes: (raw['allocatedBytes'] as num?)?.toInt(),
      unallocatedBytes: (raw['unallocatedBytes'] as num?)?.toInt(),
    );
  }

  @override
  Future<List<StorageVolume>> getVolumes(String deviceId) async {
    try {
      final raw = await _channel.getVolumes(deviceId);
      return raw.map(_volumeFromMap).whereType<StorageVolume>().toList();
    } on MissingPluginException {
      return const [];
    } catch (e) {
      AppLogger.instance.debug(
        _tag,
        'Native volume enumeration failed for $deviceId: $e',
      );
      return const [];
    }
  }

  StorageVolume? _volumeFromMap(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return StorageVolume(
      id: id,
      mountPoint: m['mountPoint']?.toString(),
      volumeName: m['volumeName']?.toString(),
      filesystem: m['filesystem']?.toString(),
      volumeUuid: m['volumeUuid']?.toString(),
      isReadOnly: m['isReadOnly'] == true,
      isBootVolume: m['isBootVolume'] == true,
      isEncrypted: m['isEncrypted'] as bool?,
      totalBytes: (m['totalBytes'] as num?)?.toInt(),
      usedBytes: (m['usedBytes'] as num?)?.toInt(),
      freeBytes: (m['freeBytes'] as num?)?.toInt(),
    );
  }

  @override
  Stream<StorageDeviceEvent> watchDeviceEvents() {
    return _channel
        .deviceEvents()
        .map(_deviceEventFromMap)
        .where((e) => e != null)
        .cast<StorageDeviceEvent>()
        
        
        
        
        
        .handleError((Object e) {
          if (e is! MissingPluginException) {
            AppLogger.instance.debug(_tag, 'Device event stream error: $e');
          }
        });
  }

  StorageDeviceEvent? _deviceEventFromMap(Map<String, dynamic> m) {
    final deviceId = m['deviceId']?.toString();
    if (deviceId == null || deviceId.isEmpty) return null;
    final kind = switch (m['kind']?.toString()) {
      'added' => StorageDeviceEventKind.added,
      'removed' => StorageDeviceEventKind.removed,
      _ => null,
    };
    if (kind == null) return null;
    return StorageDeviceEvent(kind: kind, deviceId: deviceId);
  }

  @override
  Stream<StorageActivity> watchActivity() {
    return _channel
        .activityEvents()
        .map(_activityFromMap)
        .where((e) => e != null)
        .cast<StorageActivity>()
        .handleError((Object e) {
          if (e is! MissingPluginException) {
            AppLogger.instance.debug(_tag, 'Activity stream error: $e');
          }
        });
  }

  StorageActivity? _activityFromMap(Map<String, dynamic> m) {
    final deviceId = m['deviceId']?.toString();
    if (deviceId == null || deviceId.isEmpty) return null;
    return StorageActivity(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      availability: SensorAvailability.available,
      readBytesPerSecond: (m['readBytesPerSecond'] as num?)?.toDouble(),
      writeBytesPerSecond: (m['writeBytesPerSecond'] as num?)?.toDouble(),
      readOperationsPerSecond: (m['readOpsPerSecond'] as num?)?.toDouble(),
      writeOperationsPerSecond: (m['writeOpsPerSecond'] as num?)?.toDouble(),
      utilizationPercent: (m['utilizationPercent'] as num?)?.toDouble(),
    );
  }
}
