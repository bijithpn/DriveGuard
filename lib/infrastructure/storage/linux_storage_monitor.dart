import 'dart:convert';
import 'dart:io';

import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';

/// Linux backend.
///
/// Enumeration: `/sys/block` (always present, no permissions needed, no
/// external tool dependency) - filters out loop/ram/virtual devices.
///
/// Temperature, in priority order:
///  1. sysfs hwmon (`/sys/class/nvme/<dev>/device/hwmon*/temp1_input`) -
///     kernel-native, no external tool, works unprivileged when exposed.
///  2. `nvme-cli` (`nvme smart-log`) for NVMe devices when hwmon isn't
///     exposed - checked for presence first.
///  3. `smartctl` for SATA/USB-bridged devices - checked for presence
///     first, and permission failures (common without root/disk group)
///     are surfaced explicitly rather than silently ignored.
class LinuxStorageMonitor implements StorageMonitor {
  static const _tag = 'LinuxStorageMonitor';

  @override
  Future<bool> isAvailable() async => Directory('/sys/block').existsSync();

  @override
  Future<BackendCapabilities> getCapabilities() async {
    final hasSmartctl = await SafeProcessRunner.instance.exists('smartctl');
    final hasNvmeCli = await SafeProcessRunner.instance.exists('nvme');
    return BackendCapabilities(
      backendName: 'Linux (sysfs + smartctl/nvme-cli)',
      canEnumerateDevices: true,
      canReadTemperature: true, // sysfs alone can satisfy this for many NVMe
      canReadHealth: hasSmartctl || hasNvmeCli,
      missingTools: [
        if (!hasSmartctl) 'smartctl',
        if (!hasNvmeCli) 'nvme (nvme-cli)',
      ],
      notes: [
        if (!hasSmartctl && !hasNvmeCli)
          'Install smartmontools and/or nvme-cli for SATA SMART and full NVMe health data.',
        'Reading SMART attributes for SATA/USB devices typically requires root or membership in the "disk" group.',
      ],
    );
  }

  @override
  Future<List<StorageDevice>> getDevices() async {
    final devices = <StorageDevice>[];
    final blockDir = Directory('/sys/block');
    if (!blockDir.existsSync()) return devices;

    for (final entry in blockDir.listSync()) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (RegExp(r'^(loop|ram|zram|dm-|sr|fd)').hasMatch(name)) continue;
      // Partitions have a numeric suffix and a parent whole-disk entry;
      // skip them - we monitor whole physical devices only.
      final removableFile = File('/sys/block/$name/removable');
      final isRemovable =
          removableFile.existsSync() && removableFile.readAsStringSync().trim() == '1';

      final isNvme = name.startsWith('nvme');
      final model = _readSysfsString('/sys/block/$name/device/model') ??
          _readSysfsString('/sys/class/nvme/${_nvmeControllerName(name)}/model');
      final serial = _readSysfsString('/sys/block/$name/device/serial');
      final sizeSectors = _readSysfsString('/sys/block/$name/size');
      final capacityBytes =
          sizeSectors != null ? (int.tryParse(sizeSectors) ?? 0) * 512 : null;
      final rotational = _readSysfsString('/sys/block/$name/queue/rotational');

      StorageDeviceType type;
      StorageInterfaceType interfaceType;
      if (isNvme) {
        type = StorageDeviceType.nvme;
        interfaceType = StorageInterfaceType.nvme;
      } else if (name.startsWith('sd') || name.startsWith('hd')) {
        interfaceType = StorageInterfaceType.sata;
        type = rotational == '1' ? StorageDeviceType.hdd : StorageDeviceType.ssd;
      } else {
        type = StorageDeviceType.unknown;
        interfaceType = StorageInterfaceType.unknown;
      }
      if (isRemovable && interfaceType == StorageInterfaceType.sata) {
        interfaceType = StorageInterfaceType.usb;
      }

      devices.add(StorageDevice(
        id: 'linux-$name',
        type: type,
        interfaceType: interfaceType,
        sensorAvailability: SensorAvailability.unavailable,
        model: model,
        serialNumber: serial,
        capacityBytes: capacityBytes,
        isRemovable: isRemovable,
      ));
    }
    return devices;
  }

  String? _readSysfsString(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  String _sysName(String deviceId) => deviceId.replaceFirst('linux-', '');

  /// Extracts the NVMe controller name ("nvme0") from a namespace block
  /// device name ("nvme0n1"). Naively splitting on 'n' breaks because
  /// "nvme" itself contains an 'n' - this matches the numeric controller
  /// index explicitly instead.
  String _nvmeControllerName(String blockDeviceName) {
    final match = RegExp(r'^(nvme\d+)n\d+$').firstMatch(blockDeviceName);
    return match?.group(1) ?? blockDeviceName;
  }

  Future<double?> _readHwmonCelsius(String sysName) async {
    // /sys/block/<dev>/device is a symlink to the underlying controller
    // device (the NVMe PCI device, or the SCSI/ATA device) for both NVMe
    // namespaces and SATA/USB disks alike - hwmon subdirectories appear
    // under that same path in both cases, so no NVMe-specific path is
    // needed here.
    final hwmonRoot = Directory('/sys/block/$sysName/device');
    if (!hwmonRoot.existsSync()) return null;
    try {
      for (final entry in hwmonRoot.listSync()) {
        if (!entry.path.contains('hwmon')) continue;
        final hwmonDir = Directory(entry.path);
        if (!hwmonDir.existsSync()) continue;
        for (final f in hwmonDir.listSync()) {
          if (RegExp(r'temp\d+_input$').hasMatch(f.path)) {
            final raw = _readSysfsString(f.path);
            if (raw == null) continue;
            final milli = int.tryParse(raw);
            if (milli == null) continue;
            return milli / 1000.0;
          }
        }
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'hwmon read failed for $sysName: $e');
    }
    return null;
  }

  Future<double?> _readNvmeCliCelsius(String sysName) async {
    final hasTool = await SafeProcessRunner.instance.exists('nvme');
    if (!hasTool) return null;
    try {
      final result = await SafeProcessRunner.instance
          .run('nvme', ['smart-log', '/dev/$sysName', '-o', 'json'], requireZeroExit: false);
      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      final temp = json['temperature'];
      if (temp is num) return temp.toDouble() - 273; // some builds report Kelvin
      return null;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'nvme-cli read failed for $sysName: $e');
      return null;
    }
  }

  Future<double?> _readSmartctlCelsius(String sysName, {required bool throwOnPermission}) async {
    final hasTool = await SafeProcessRunner.instance.exists('smartctl');
    if (!hasTool) return null;
    final result = await SafeProcessRunner.instance
        .run('smartctl', ['-a', '-j', '/dev/$sysName'], requireZeroExit: false);
    Map<String, dynamic> json;
    try {
      json = jsonDecode(result.stdout) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final messages = (json['smartctl'] as Map<String, dynamic>?)?['messages'];
    if (messages is List && messages.isNotEmpty) {
      final text = messages.map((m) => m['string']).join(' ').toLowerCase();
      if (throwOnPermission && (text.contains('permission') || text.contains('denied'))) {
        throw PermissionDeniedException(sysName, 'smartctl: $text');
      }
    }
    final temp = json['temperature'] as Map<String, dynamic>?;
    if (temp != null && temp['current'] != null) {
      return (temp['current'] as num).toDouble();
    }
    return null;
  }

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    final sysName = _sysName(deviceId);
    double? celsius = await _readHwmonCelsius(sysName);
    String source = 'sysfs-hwmon';

    if (celsius == null && sysName.startsWith('nvme')) {
      celsius = await _readNvmeCliCelsius(sysName);
      source = 'nvme-cli';
    }
    if (celsius == null) {
      celsius = await _readSmartctlCelsius(sysName, throwOnPermission: true);
      source = 'smartctl';
    }
    if (celsius == null) return null;

    if (!TemperatureUtils.isPlausibleValue(celsius)) {
      throw InvalidReadingException(
        'Implausible temperature ($source): $celsius°C',
        deviceId: deviceId,
      );
    }

    return TemperatureReading(
      celsius: celsius,
      timestamp: DateTime.now(),
      source: TemperatureSource(backendName: source, sensorId: 'composite'),
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

    // NVMe drives can expose several distinct sensors (spec section 12).
    // nvme-cli's `smart-log -o json` reports these as individual
    // "temperature_sensor_N" keys alongside the composite reading.
    final sysName = _sysName(deviceId);
    if (sysName.startsWith('nvme') && await SafeProcessRunner.instance.exists('nvme')) {
      try {
        final result = await SafeProcessRunner.instance
            .run('nvme', ['smart-log', '/dev/$sysName', '-o', 'json'], requireZeroExit: false);
        final json = jsonDecode(result.stdout) as Map<String, dynamic>;
        for (var i = 1; i <= 8; i++) {
          final raw = json['temperature_sensor_$i'];
          if (raw is! num) continue;
          // nvme-cli reports these in Kelvin, same as the composite field.
          var celsius = raw.toDouble();
          if (celsius > 200) celsius -= 273; // Kelvin, matching _readNvmeCliCelsius's convention
          if (celsius == 0) continue;
          sensors.add(StorageSensor(
            id: 'sensor$i',
            name: 'Sensor $i',
            reading: TemperatureReading(
              celsius: celsius,
              timestamp: DateTime.now(),
              source: TemperatureSource(backendName: 'nvme-cli', sensorId: 'sensor$i'),
              isValid: TemperatureUtils.isPlausibleValue(celsius),
            ),
            type: TemperatureSensorType.namespace,
          ));
        }
      } catch (e) {
        AppLogger.instance.debug(_tag, 'multi-sensor nvme-cli read failed for $sysName: $e');
      }
    }
    return sensors;
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    final sysName = _sysName(deviceId);
    if (sysName.startsWith('nvme')) {
      final hasTool = await SafeProcessRunner.instance.exists('nvme');
      if (!hasTool) return DeviceHealth.unavailable;
      try {
        final result = await SafeProcessRunner.instance
            .run('nvme', ['smart-log', '/dev/$sysName', '-o', 'json'], requireZeroExit: false);
        final json = jsonDecode(result.stdout) as Map<String, dynamic>;
        return DeviceHealth(
          status: (json['critical_warning'] as num?) == 0
              ? DeviceHealthStatus.healthy
              : DeviceHealthStatus.warning,
          percentageUsed: (json['percentage_used'] as num?)?.toInt(),
          availableSparePercent: (json['avail_spare'] as num?)?.toInt(),
          criticalWarning: json['critical_warning']?.toString(),
          mediaErrors: (json['media_errors'] as num?)?.toInt(),
          powerCycles: (json['power_cycles'] as num?)?.toInt(),
          powerOnHours: (json['power_on_hours'] as num?)?.toInt(),
          unsafeShutdowns: (json['unsafe_shutdowns'] as num?)?.toInt(),
        );
      } catch (e) {
        AppLogger.instance.debug(_tag, 'nvme health read failed: $e');
        return DeviceHealth.unavailable;
      }
    }

    final hasSmartctl = await SafeProcessRunner.instance.exists('smartctl');
    if (!hasSmartctl) return DeviceHealth.unavailable;
    try {
      final result = await SafeProcessRunner.instance
          .run('smartctl', ['-a', '-j', '/dev/$sysName'], requireZeroExit: false);
      final json = jsonDecode(result.stdout) as Map<String, dynamic>;
      final passed = (json['smart_status'] as Map<String, dynamic>?)?['passed'] as bool?;
      final powerOnTime = json['power_on_time'] as Map<String, dynamic>?;
      return DeviceHealth(
        status: passed == null
            ? DeviceHealthStatus.unknown
            : (passed ? DeviceHealthStatus.healthy : DeviceHealthStatus.critical),
        powerOnHours: (powerOnTime?['hours'] as num?)?.toInt(),
        powerCycles: (json['power_cycle_count'] as num?)?.toInt(),
        smartPassed: passed,
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'smartctl health read failed: $e');
      return DeviceHealth.unavailable;
    }
  }
}
