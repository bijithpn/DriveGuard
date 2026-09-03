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
  }) async {
    final result = await SafeProcessRunner.instance.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], requireZeroExit: false);
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
      if (raw is! Map<String, dynamic>) return DeviceHealth.unavailable;
      final wear = raw['Wear'];
      final readErrors = (raw['ReadErrorsUncorrected'] as num?)?.toInt();
      return DeviceHealth(
        status: (readErrors != null && readErrors > 0)
            ? DeviceHealthStatus.warning
            : DeviceHealthStatus.healthy,
        percentageUsed: wear is num ? wear.toInt() : null,
        mediaErrors: readErrors,
        powerOnHours: (raw['PowerOnHours'] as num?)?.toInt(),
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'health read failed: $e');
      return DeviceHealth.unavailable;
    }
  }
}
