import 'dart:convert';

import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';

class MacOSStorageMonitor extends StorageMonitor {
  static const _tag = 'MacOSStorageMonitor';
  static const _smartctl = 'smartctl';

  final Map<String, String> _bsdNameById = {};

  @override
  Future<bool> isAvailable() async {
    try {
      await SafeProcessRunner.instance.run('system_profiler', [
        '-listDataTypes',
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BackendCapabilities> getCapabilities() async {
    final hasSmartctl = await SafeProcessRunner.instance.exists(
      _smartctl,
      extraPaths: const ['/opt/homebrew/bin', '/usr/local/bin'],
    );
    return BackendCapabilities(
      backendName: 'macOS (system_profiler + smartctl)',
      canEnumerateDevices: true,
      canReadTemperature: hasSmartctl,
      canReadHealth: hasSmartctl,
      missingTools: hasSmartctl ? const [] : const ['smartctl'],
      notes: [
        if (!hasSmartctl)
          'Install smartmontools (e.g. "brew install smartmontools") for SMART/NVMe temperature.',
        'Apple Silicon internal NVMe controllers generally do not expose vendor SMART log pages to user space; temperature will read as unavailable for those devices even with smartctl installed.',
      ],
    );
  }

  @override
  Future<List<StorageDevice>> getDevices() async {
    final devices = <StorageDevice>[];
    _bsdNameById.clear();
    try {
      final result = await SafeProcessRunner.instance.run('system_profiler', [
        'SPNVMeDataType',
        'SPSerialATADataType',
        '-json',
      ], timeout: const Duration(seconds: 10));
      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      devices.addAll(
        _parseCategory(
          json['SPNVMeDataType'],
          StorageDeviceType.nvme,
          StorageInterfaceType.nvme,
        ),
      );
      devices.addAll(
        _parseCategory(
          json['SPSerialATADataType'],
          StorageDeviceType.unknown,
          StorageInterfaceType.sata,
        ),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Device enumeration failed', e);
    }
    return devices;
  }

  List<StorageDevice> _parseCategory(
    dynamic categoryJson,
    StorageDeviceType defaultType,
    StorageInterfaceType interfaceType,
  ) {
    final result = <StorageDevice>[];
    if (categoryJson is! List) return result;
    for (final controller in categoryJson) {
      if (controller is! Map<String, dynamic>) continue;
      final items = controller['_items'];
      final drives = items is List ? items : [controller];
      for (final raw in drives) {
        if (raw is! Map<String, dynamic>) continue;
        final name = raw['_name'] as String?;
        final model = raw['device_model'] as String? ?? name;
        if (model == null) continue;
        final bsdName = raw['bsd_name'] as String?;
        final sizeStr = raw['size'] as String?;
        final isSsd =
            (raw['spsata_ssd'] as String?)?.toLowerCase() == 'yes' ||
            interfaceType == StorageInterfaceType.nvme;
        final type = interfaceType == StorageInterfaceType.nvme
            ? StorageDeviceType.nvme
            : (isSsd ? StorageDeviceType.ssd : StorageDeviceType.hdd);
        final id = 'macos-${bsdName ?? model.hashCode}';
        if (bsdName != null) _bsdNameById[id] = bsdName;
        result.add(
          StorageDevice(
            id: id,
            type: type,
            interfaceType: interfaceType,

            sensorAvailability: SensorAvailability.unavailable,
            model: model,
            manufacturer: _guessManufacturer(model),
            serialNumber: raw['device_serial'] as String?,
            capacityBytes: _parseSize(sizeStr),
          ),
        );
      }
    }
    return result;
  }

  String? _guessManufacturer(String model) {
    const known = [
      'Samsung',
      'Western Digital',
      'WD',
      'Seagate',
      'Crucial',
      'SanDisk',
      'Kingston',
      'Apple',
      'SK hynix',
      'Toshiba',
    ];
    for (final brand in known) {
      if (model.toUpperCase().contains(brand.toUpperCase())) return brand;
    }
    return null;
  }

  int? _parseSize(String? text) {
    if (text == null) return null;
    final match = RegExp(r'([\d.]+)\s*(TB|GB|MB)').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    switch (match.group(2)) {
      case 'TB':
        return (value * 1e12).round();
      case 'GB':
        return (value * 1e9).round();
      default:
        return (value * 1e6).round();
    }
  }

  String? _resolveBsdName(String deviceId) {
    final cached = _bsdNameById[deviceId];
    if (cached != null) return cached;
    const prefix = 'macos-';
    if (!deviceId.startsWith(prefix)) return null;
    final candidate = deviceId.substring(prefix.length);

    if (!RegExp(r'^disk\d+$').hasMatch(candidate)) return null;
    return candidate;
  }

  Future<Map<String, dynamic>?> _smartctlJson(String deviceId) async {
    final bsdName = _resolveBsdName(deviceId);
    if (bsdName == null) return null;
    final hasTool = await SafeProcessRunner.instance.exists(
      _smartctl,
      extraPaths: const ['/opt/homebrew/bin', '/usr/local/bin'],
    );
    if (!hasTool) {
      throw const UnsupportedDeviceException(
        'smartctl-missing',
        'smartctl not installed',
      );
    }
    final result = await SafeProcessRunner.instance.run(
      _smartctl,
      // '-n standby' skips the query instead of spinning up a sleeping HDD
      // to answer it - a routine poll must never force a spin-up cycle.
      ['-a', '-j', '-n', 'standby', '/dev/$bsdName'],
      extraPaths: const ['/opt/homebrew/bin', '/usr/local/bin'],
      requireZeroExit: false,
    );
    try {
      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      if (_isSleeping(json)) return null;
      return json;
    } catch (_) {
      return null;
    }
  }

  /// True if smartctl skipped the read because the drive is spun down.
  bool _isSleeping(Map<String, dynamic> json) {
    final mode = (json['power_mode'] as String?)?.toUpperCase();
    if (mode == 'STANDBY' || mode == 'SLEEP') return true;
    final messages = (json['smartctl'] as Map<String, dynamic>?)?['messages'];
    if (messages is List) {
      final text = messages.map((m) => m['string']).join(' ').toLowerCase();
      if (text.contains('standby') || text.contains('sleep')) return true;
    }
    return false;
  }

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    Map<String, dynamic>? json;
    try {
      json = await _smartctlJson(deviceId);
    } on UnsupportedDeviceException {
      return null;
    }
    if (json == null) return null;

    final smartStatus = json['smartctl'] as Map<String, dynamic>?;
    final messages = smartStatus?['messages'];
    if (messages is List && messages.isNotEmpty) {
      final text = messages.map((m) => m['string']).join(' ').toLowerCase();
      if (text.contains('permission') ||
          text.contains('operation not permitted')) {
        throw PermissionDeniedException(deviceId, 'smartctl: $text');
      }
      if (text.contains('unable to detect device type') ||
          text.contains('not supported')) {
        return null;
      }
    }

    double? celsius;
    final nvmeLog =
        json['nvme_smart_health_information_log'] as Map<String, dynamic>?;
    if (nvmeLog != null && nvmeLog['temperature'] != null) {
      celsius = (nvmeLog['temperature'] as num).toDouble();
    } else {
      final temp = json['temperature'] as Map<String, dynamic>?;
      if (temp != null && temp['current'] != null) {
        celsius = (temp['current'] as num).toDouble();
      }
    }
    if (celsius == null) return null;

    if (!TemperatureUtils.isPlausibleValue(celsius)) {
      throw InvalidReadingException(
        'Implausible temperature from smartctl: $celsius°C',
        deviceId: deviceId,
      );
    }

    return TemperatureReading(
      celsius: celsius,
      timestamp: DateTime.now(),
      source: const TemperatureSource(
        backendName: 'smartctl',
        sensorId: 'composite',
      ),
    );
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async {
    final reading = await readTemperature(deviceId);
    if (reading == null) return const [];
    final sensors = [
      StorageSensor(
        id: 'composite',
        name: 'Composite',
        reading: reading,
        type: TemperatureSensorType.composite,
        isPrimary: true,
      ),
    ];

    Map<String, dynamic>? json;
    try {
      json = await _smartctlJson(deviceId);
    } catch (_) {
      return sensors;
    }
    final nvmeLog =
        json?['nvme_smart_health_information_log'] as Map<String, dynamic>?;
    final extra = nvmeLog?['temperature_sensors'];
    if (extra is List) {
      for (var i = 0; i < extra.length; i++) {
        final celsius = (extra[i] as num?)?.toDouble();
        if (celsius == null || celsius == 0) continue;
        sensors.add(
          StorageSensor(
            id: 'sensor${i + 1}',
            name: 'Sensor ${i + 1}',
            reading: TemperatureReading(
              celsius: celsius,
              timestamp: DateTime.now(),
              source: TemperatureSource(
                backendName: 'smartctl',
                sensorId: 'sensor${i + 1}',
              ),
              isValid: TemperatureUtils.isPlausibleValue(celsius),
            ),
            type: TemperatureSensorType.namespace,
          ),
        );
      }
    }
    return sensors;
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    Map<String, dynamic>? json;
    try {
      json = await _smartctlJson(deviceId);
    } catch (_) {
      return DeviceHealth.unavailable;
    }
    if (json == null) return DeviceHealth.unavailable;

    final nvmeLog =
        json['nvme_smart_health_information_log'] as Map<String, dynamic>?;
    final smartStatus = json['smart_status'] as Map<String, dynamic>?;
    final passed = smartStatus?['passed'] as bool?;

    if (nvmeLog != null) {
      return DeviceHealth(
        status: passed == false
            ? DeviceHealthStatus.critical
            : DeviceHealthStatus.healthy,
        percentageUsed: (nvmeLog['percentage_used'] as num?)?.toInt(),
        availableSparePercent: (nvmeLog['available_spare'] as num?)?.toInt(),
        availableSpareThreshold: (nvmeLog['available_spare_threshold'] as num?)
            ?.toInt(),
        criticalWarning: nvmeLog['critical_warning']?.toString(),
        mediaErrors: (nvmeLog['media_errors'] as num?)?.toInt(),
        powerCycles: (nvmeLog['power_cycles'] as num?)?.toInt(),
        powerOnHours: (nvmeLog['power_on_hours'] as num?)?.toInt(),
        unsafeShutdowns: (nvmeLog['unsafe_shutdowns'] as num?)?.toInt(),
        dataUnitsRead: (nvmeLog['data_units_read'] as num?)?.toInt(),
        dataUnitsWritten: (nvmeLog['data_units_written'] as num?)?.toInt(),
        smartPassed: passed,
      );
    }

    final powerOnTime = json['power_on_time'] as Map<String, dynamic>?;
    final powerCycleCount = json['power_cycle_count'];
    return DeviceHealth(
      status: passed == null
          ? DeviceHealthStatus.unknown
          : (passed ? DeviceHealthStatus.healthy : DeviceHealthStatus.critical),
      powerOnHours: (powerOnTime?['hours'] as num?)?.toInt(),
      powerCycles: (powerCycleCount as num?)?.toInt(),
      smartPassed: passed,
    );
  }
}
