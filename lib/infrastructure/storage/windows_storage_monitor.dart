import 'dart:async';
import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';

class WindowsStorageMonitor extends StorageMonitor {
  static const _tag = 'WindowsStorageMonitor';

  static const _enumerateScript = r'''
Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk |
  ForEach-Object {
    $disk = $_
    [PSCustomObject]@{
      DeviceId = $disk.DeviceId
      FriendlyName = $disk.FriendlyName
      Manufacturer = $disk.Manufacturer
      SerialNumber = $disk.SerialNumber
      MediaType = $disk.MediaType
      BusType = $disk.BusType
      Size = $disk.Size
      SpindleSpeed = $disk.SpindleSpeed
    }
  } | ConvertTo-Json -Compress
''';

  static final RegExp _validDeviceId = RegExp(r'^[0-9A-Za-z_.\-]{1,64}$');

  static String _reliabilityScript(String deviceId) =>
      '''
\$disk = Get-CimInstance -Namespace root\\Microsoft\\Windows\\Storage -ClassName MSFT_PhysicalDisk | Where-Object { \$_.DeviceId -eq '${deviceId.replaceAll("'", "''")}' }
if (\$null -eq \$disk) { exit 2 }
\$counter = \$disk | Get-StorageReliabilityCounter
[PSCustomObject]@{
  Temperature = \$counter.Temperature
  TemperatureMax = \$counter.TemperatureMax
  Wear = \$counter.Wear
  ReadErrorsUncorrected = \$counter.ReadErrorsUncorrected
  PowerOnHours = \$counter.PowerOnHours
} | ConvertTo-Json -Compress
''';

  Future<Object?> _runPowerShellJson(
    String script, {
    String? deviceIdForError,
    Duration timeout = AppConstants.externalCommandTimeout,
  }) async {
    final result = await SafeProcessRunner.instance.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ],
      timeout: timeout,
      requireZeroExit: false,
    );
    final text = result.stdout.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (e) {
      throw CommandExecutionException(
        'Failed to parse PowerShell output: $e',
        deviceId: deviceIdForError,
      );
    }
  }

  @override
  Future<bool> isAvailable() async =>
      SafeProcessRunner.instance.exists('powershell');

  @override
  Future<BackendCapabilities> getCapabilities() async {
    final hasPowerShell = await SafeProcessRunner.instance.exists('powershell');
    return BackendCapabilities(
      backendName: 'Windows (Storage Management WMI via PowerShell)',
      canEnumerateDevices: hasPowerShell,
      canReadTemperature: hasPowerShell,
      canReadHealth: hasPowerShell,
      missingTools: hasPowerShell ? const [] : const ['powershell'],
      notes: [
        'Uses MSFT_PhysicalDisk / Get-StorageReliabilityCounter (Storage Management WMI), not raw DeviceIoControl.',
        'Not yet verified on physical Windows hardware - see docs/platform-support.md.',
        'Some third-party RAID/USB-bridge controllers do not surface reliability counters; those disks will show "Temperature unavailable".',
      ],
    );
  }

  @override
  Future<List<StorageDevice>> getDevices() async {
    final devices = <StorageDevice>[];
    try {
      final raw = await _runPowerShellJson(_enumerateScript);
      final list = raw is List ? raw : (raw == null ? [] : [raw]);
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final deviceId = item['DeviceId']?.toString();
        if (deviceId == null) continue;
        final busType = (item['BusType'] ?? '').toString().toLowerCase();
        final mediaType = (item['MediaType'] ?? '').toString().toLowerCase();

        StorageInterfaceType interfaceType;
        if (busType.contains('nvme')) {
          interfaceType = StorageInterfaceType.nvme;
        } else if (busType.contains('sata') || busType.contains('ata')) {
          interfaceType = StorageInterfaceType.sata;
        } else if (busType.contains('usb')) {
          interfaceType = StorageInterfaceType.usb;
        } else if (busType.contains('scsi') || busType.contains('raid')) {
          interfaceType = StorageInterfaceType.scsi;
        } else {
          interfaceType = StorageInterfaceType.unknown;
        }

        StorageDeviceType type;
        if (interfaceType == StorageInterfaceType.nvme) {
          type = StorageDeviceType.nvme;
        } else if (mediaType.contains('ssd')) {
          type = StorageDeviceType.ssd;
        } else if (mediaType.contains('hdd')) {
          type = StorageDeviceType.hdd;
        } else {
          type = StorageDeviceType.unknown;
        }

        devices.add(
          StorageDevice(
            id: 'windows-$deviceId',
            type: type,
            interfaceType: interfaceType,
            sensorAvailability: SensorAvailability.unavailable,
            model: item['FriendlyName']?.toString(),
            manufacturer: item['Manufacturer']?.toString(),
            serialNumber: item['SerialNumber']?.toString(),
            capacityBytes: int.tryParse(item['Size']?.toString() ?? ''),
            isRemovable: interfaceType == StorageInterfaceType.usb,
          ),
        );
      }
    } catch (e) {
      AppLogger.instance.error(_tag, 'Device enumeration failed', e);
    }
    return devices;
  }

  String _rawId(String deviceId) => deviceId.replaceFirst('windows-', '');

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    final rawId = _rawId(deviceId);
    if (!_validDeviceId.hasMatch(rawId)) {
      throw NativeBackendException(
        'Refusing to query an unexpected DeviceId shape',
        deviceId: deviceId,
      );
    }
    Object? raw;
    try {
      raw = await _runPowerShellJson(
        _reliabilityScript(rawId),
        deviceIdForError: deviceId,
      );
    } on CommandExecutionException {
      rethrow;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('access') && message.contains('denied')) {
        throw PermissionDeniedException(deviceId, e.toString());
      }
      AppLogger.instance.warning(
        _tag,
        'Reliability counter read failed for $deviceId: $e',
      );
      return null;
    }
    if (raw is! Map<String, dynamic>) return null;
    final temp = raw['Temperature'];
    if (temp == null) return null;
    final celsius = (temp as num).toDouble();
    if (celsius <= 0) return null;

    if (!TemperatureUtils.isPlausibleValue(celsius)) {
      throw InvalidReadingException(
        'Implausible temperature from StorageReliabilityCounter: $celsius°C',
        deviceId: deviceId,
      );
    }

    return TemperatureReading(
      celsius: celsius,
      timestamp: DateTime.now(),
      source: const TemperatureSource(
        backendName: 'StorageReliabilityCounter',
        sensorId: 'composite',
      ),
    );
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async {
    final reading = await readTemperature(deviceId);
    if (reading == null) return const [];
    return [
      StorageSensor(
        id: 'composite',
        name: 'Composite',
        reading: reading,
        type: TemperatureSensorType.composite,
        isPrimary: true,
      ),
    ];
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    final rawId = _rawId(deviceId);
    if (!_validDeviceId.hasMatch(rawId)) return DeviceHealth.unavailable;
    try {
      final raw = await _runPowerShellJson(
        _reliabilityScript(rawId),
        deviceIdForError: deviceId,
      );
      if (raw is Map<String, dynamic> && raw['Wear'] != null) {
        final wear = raw['Wear'];
        final readErrors = (raw['ReadErrorsUncorrected'] as num?)?.toInt();
        return DeviceHealth(
          status: (readErrors != null && readErrors > 0)
              ? DeviceHealthStatus.warning
              : DeviceHealthStatus.healthy,
          percentageUsed: wear is num ? wear.toInt() : null,
          mediaErrors: readErrors,
          powerOnHours: (raw['PowerOnHours'] as num?)?.toInt(),
          smartPassed: (readErrors == null || readErrors == 0),
        );
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'reliability counter read failed: $e');
    }

    // Fallback: Query Win32_DiskDrive for status when non-admin/WMI reliability counters are unavailable
    try {
      final script =
          'Get-CimInstance Win32_DiskDrive | '
          'Where-Object { \$_.Index -eq $rawId } | '
          'Select-Object Status | ConvertTo-Json -Compress';
      final diskRaw = await _runPowerShellJson(script);
      if (diskRaw is Map<String, dynamic>) {
        final statusStr = (diskRaw['Status'] ?? '').toString().toUpperCase();
        return DeviceHealth(
          status: statusStr == 'OK'
              ? DeviceHealthStatus.healthy
              : (statusStr.contains('BAD') || statusStr.contains('PRED FAIL'))
                  ? DeviceHealthStatus.critical
                  : DeviceHealthStatus.warning,
          smartPassed: statusStr == 'OK',
        );
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Win32_DiskDrive fallback health read failed: $e');
    }

    return DeviceHealth.unavailable;
  }

  @override
  Future<StorageCapacity> getCapacity(String deviceId) async {
    final rawId = _rawId(deviceId);
    try {
      // Find drive letters matching this physical disk index
      final script =
          'Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | '
          'Where-Object { \$_.Name -match "^$rawId\\s" } | '
          'Select-Object Name | ConvertTo-Json -Compress';
      final raw = await _runPowerShellJson(script);
      if (raw == null) return StorageCapacity.unavailable;
      final name = raw is Map ? (raw['Name'] ?? '').toString() : '';
      final letters = RegExp(r'([A-Z]):').allMatches(name).map((m) => m.group(1)!).toList();
      if (letters.isEmpty) return StorageCapacity.unavailable;

      final letterFilter = letters.map((l) => "\$_.DeviceID -eq '$l:'").join(' -or ');
      final volScript =
          "Get-CimInstance Win32_LogicalDisk | "
          "Where-Object { $letterFilter } | "
          "Select-Object Size, FreeSpace | ConvertTo-Json -Compress";
      final volRaw = await _runPowerShellJson(volScript);
      if (volRaw == null) return StorageCapacity.unavailable;
      final vols = volRaw is List ? volRaw : [volRaw];
      int total = 0;
      int free = 0;
      for (final v in vols) {
        if (v is! Map) continue;
        total += (v['Size'] as num?)?.toInt() ?? 0;
        free += (v['FreeSpace'] as num?)?.toInt() ?? 0;
      }
      if (total == 0) return StorageCapacity.unavailable;
      return StorageCapacity(
        availability: SensorAvailability.available,
        totalBytes: total,
        usedBytes: total - free,
        freeBytes: free,
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'getCapacity failed for $deviceId: $e');
      return StorageCapacity.unavailable;
    }
  }

  @override
  Future<List<StorageVolume>> getVolumes(String deviceId) async {
    final rawId = _rawId(deviceId);
    try {
      final script =
          'Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | '
          'Where-Object { \$_.Name -match "^$rawId\\s" } | '
          'Select-Object Name | ConvertTo-Json -Compress';
      final raw = await _runPowerShellJson(script);
      if (raw == null) return const [];
      final name = raw is Map ? (raw['Name'] ?? '').toString() : '';
      final letters = RegExp(r'([A-Z]):').allMatches(name).map((m) => m.group(1)!).toList();
      if (letters.isEmpty) return const [];

      final letterFilter = letters.map((l) => "\$_.DeviceID -eq '$l:'").join(' -or ');
      final volScript =
          "Get-CimInstance Win32_LogicalDisk | "
          "Where-Object { $letterFilter } | "
          "Select-Object DeviceID, Size, FreeSpace, FileSystem, VolumeName | ConvertTo-Json -Compress";
      final volRaw = await _runPowerShellJson(volScript);
      if (volRaw == null) return const [];
      final vols = volRaw is List ? volRaw : [volRaw];
      final result = <StorageVolume>[];
      for (final v in vols) {
        if (v is! Map<String, dynamic>) continue;
        final devId = v['DeviceID']?.toString();
        if (devId == null) continue;
        final total = (v['Size'] as num?)?.toInt();
        final free = (v['FreeSpace'] as num?)?.toInt();
        final used = (total != null && free != null) ? total - free : null;
        result.add(
          StorageVolume(
            id: devId,
            mountPoint: devId,
            volumeName: (v['VolumeName'] ?? '').toString().isNotEmpty ? v['VolumeName']!.toString() : devId,
            filesystem: v['FileSystem']?.toString(),
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            isBootVolume: devId.toUpperCase().startsWith('C:'),
          ),
        );
      }
      return result;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'getVolumes failed for $deviceId: $e');
      return const [];
    }
  }

  @override
  Stream<StorageActivity> watchActivity() {
    late final StreamController<StorageActivity> controller;
    Timer? timer;
    bool inFlight = false;

    Future<void> pollDiskActivity() async {
      if (inFlight) return;
      inFlight = true;
      try {
        final script =
            r'Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | '
            r'Select-Object Name, DiskReadBytesPerSec, DiskWriteBytesPerSec, PercentDiskTime | '
            r'ConvertTo-Json -Compress';
        final raw = await _runPowerShellJson(
          script,
          timeout: const Duration(seconds: 4),
        );
        if (raw == null) return;
        final list = raw is List ? raw : [raw];
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final name = (item['Name'] ?? '').toString();
          if (name.isEmpty || name == '_Total') continue;
          // Name is typically "0 C: D:" or "1 E:"
          final driveNumMatch = RegExp(r'^(\d+)').firstMatch(name);
          final diskIndex = driveNumMatch?.group(1);
          if (diskIndex == null) continue;

          final deviceId = 'windows-$diskIndex';
          final readBytes = (item['DiskReadBytesPerSec'] as num?)?.toDouble();
          final writeBytes = (item['DiskWriteBytesPerSec'] as num?)?.toDouble();
          final utilPercent = (item['PercentDiskTime'] as num?)?.toDouble();

          if (!controller.isClosed) {
            controller.add(
              StorageActivity(
                deviceId: deviceId,
                timestamp: DateTime.now(),
                availability: SensorAvailability.available,
                readBytesPerSecond: readBytes,
                writeBytesPerSecond: writeBytes,
                utilizationPercent: utilPercent?.clamp(0.0, 100.0),
              ),
            );
          }
        }
      } catch (e) {
        AppLogger.instance.debug(_tag, 'Activity polling failed: $e');
      } finally {
        inFlight = false;
      }
    }

    controller = StreamController<StorageActivity>(
      onListen: () {
        pollDiskActivity();
        timer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => pollDiskActivity(),
        );
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }
}
