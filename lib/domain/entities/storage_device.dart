import '../enums/storage_enums.dart';
import 'device_health.dart';
import 'storage_capacity.dart';
import 'storage_volume.dart';
import 'temperature_reading.dart';

class StorageDevice {
  const StorageDevice({
    required this.id,
    required this.type,
    required this.interfaceType,
    required this.sensorAvailability,
    this.model,
    this.manufacturer,
    this.serialNumber,
    this.firmwareVersion,
    this.capacityBytes,
    this.isRemovable = false,
    this.primaryTemperature,
    this.sensors = const [],
    this.health = DeviceHealth.unavailable,
    this.capacity = StorageCapacity.unavailable,
    this.volumes = const [],
    this.monitoringStatus = MonitoringStatus.initializing,
    this.lastUpdated,
    this.lastError,
  });

  final String id;

  final StorageDeviceType type;
  final StorageInterfaceType interfaceType;
  final SensorAvailability sensorAvailability;

  final String? model;
  final String? manufacturer;
  final String? serialNumber;
  final String? firmwareVersion;

  
  
  
  final int? capacityBytes;
  final bool isRemovable;

  final TemperatureReading? primaryTemperature;
  final List<StorageSensor> sensors;

  final DeviceHealth health;

  
  
  
  final StorageCapacity capacity;

  
  
  
  final List<StorageVolume> volumes;

  final MonitoringStatus monitoringStatus;
  final DateTime? lastUpdated;
  final String? lastError;

  String get displayName => model?.trim().isNotEmpty == true
      ? model!
      : '${type.name.toUpperCase()} (${id.substring(0, id.length.clamp(0, 8))})';

  StorageDevice copyWith({
    StorageDeviceType? type,
    StorageInterfaceType? interfaceType,
    SensorAvailability? sensorAvailability,
    String? model,
    String? manufacturer,
    String? serialNumber,
    String? firmwareVersion,
    int? capacityBytes,
    bool? isRemovable,
    TemperatureReading? primaryTemperature,
    bool clearTemperature = false,
    List<StorageSensor>? sensors,
    DeviceHealth? health,
    StorageCapacity? capacity,
    List<StorageVolume>? volumes,
    MonitoringStatus? monitoringStatus,
    DateTime? lastUpdated,
    String? lastError,
    bool clearLastError = false,
  }) {
    return StorageDevice(
      id: id,
      type: type ?? this.type,
      interfaceType: interfaceType ?? this.interfaceType,
      sensorAvailability: sensorAvailability ?? this.sensorAvailability,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      serialNumber: serialNumber ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      capacityBytes: capacityBytes ?? this.capacityBytes,
      isRemovable: isRemovable ?? this.isRemovable,
      primaryTemperature: clearTemperature
          ? null
          : (primaryTemperature ?? this.primaryTemperature),
      sensors: sensors ?? this.sensors,
      health: health ?? this.health,
      capacity: capacity ?? this.capacity,
      volumes: volumes ?? this.volumes,
      monitoringStatus: monitoringStatus ?? this.monitoringStatus,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
