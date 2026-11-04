import 'dart:convert';

import 'package:driveguard/core/errors/storage_exceptions.dart';
import 'package:driveguard/core/utils/safe_process_runner.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/infrastructure/storage/macos_storage_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays canned command output instead of spawning processes.
class _FakeRunner extends SafeProcessRunner {
  _FakeRunner(this.onRun, {this.hasSmartctl = true}) : super.forTest();

  final ProcessResult2 Function(String exe, List<String> args) onRun;
  final bool hasSmartctl;

  @override
  Future<bool> exists(
    String executable, {
    List<String> extraPaths = const [],
  }) async => executable == 'smartctl' ? hasSmartctl : true;

  @override
  Future<ProcessResult2> run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 6),
    bool requireZeroExit = true,
    List<String> extraPaths = const [],
  }) async => onRun(executable, args);
}

ProcessResult2 _ok(Object json) => ProcessResult2(jsonEncode(json), '', 0);

const _profiler = {
  'SPNVMeDataType': [
    {
      '_name': 'spnvme_controller',
      '_items': [
        {
          '_name': 'Samsung SSD 980 PRO 1TB',
          'device_model': 'Samsung SSD 980 PRO 1TB',
          'bsd_name': 'disk0',
          'size': '1 TB',
          'device_serial': 'S5GXNX0',
        },
      ],
    },
  ],
  'SPSerialATADataType': [
    {
      '_name': 'sata',
      '_items': [
        {
          '_name': 'WDC WD10EZEX',
          'device_model': 'WDC WD10EZEX',
          'bsd_name': 'disk2',
          'size': '931.51 GB',
          'spsata_ssd': 'no',
        },
      ],
    },
  ],
};

void main() {
  late SafeProcessRunner original;
  setUp(() => original = SafeProcessRunner.instance);
  tearDown(() => SafeProcessRunner.instance = original);

  void useRunner(
    Object Function(String exe, List<String> args) handler, {
    bool hasSmartctl = true,
  }) {
    SafeProcessRunner.instance = _FakeRunner(
      (exe, args) => _ok(handler(exe, args)),
      hasSmartctl: hasSmartctl,
    );
  }

  test('parses NVMe and SATA devices from system_profiler', () async {
    useRunner((_, _) => _profiler);
    final devices = await MacOSStorageMonitor().getDevices();

    expect(devices.map((d) => d.id), ['macos-disk0', 'macos-disk2']);
    final nvme = devices.first;
    expect(nvme.type, StorageDeviceType.nvme);
    expect(nvme.manufacturer, 'Samsung');
    expect(nvme.serialNumber, 'S5GXNX0');
    expect(nvme.capacityBytes, 1000000000000);
    final hdd = devices.last;
    expect(hdd.type, StorageDeviceType.hdd);
    expect(hdd.capacityBytes, 931510000000);
  });

  test('reads NVMe temperature from smartctl JSON', () async {
    useRunner((exe, _) => exe == 'smartctl'
        ? {
            'nvme_smart_health_information_log': {'temperature': 47},
          }
        : _profiler);
    final monitor = MacOSStorageMonitor();
    await monitor.getDevices();
    final reading = await monitor.readTemperature('macos-disk0');
    expect(reading?.celsius, 47.0);
  });

  test('falls back to ATA temperature.current', () async {
    useRunner((exe, _) => exe == 'smartctl'
        ? {
            'temperature': {'current': 36},
          }
        : _profiler);
    final reading = await MacOSStorageMonitor().readTemperature('macos-disk2');
    expect(reading?.celsius, 36.0);
  });

  test('returns null (not a reading) when the drive is in standby', () async {
    useRunner((exe, _) => {'power_mode': 'STANDBY'});
    expect(await MacOSStorageMonitor().readTemperature('macos-disk2'), isNull);
  });

  test('returns null when smartctl is not installed', () async {
    useRunner((_, _) => _profiler, hasSmartctl: false);
    expect(await MacOSStorageMonitor().readTemperature('macos-disk0'), isNull);
  });

  test('permission errors from smartctl surface as PermissionDenied', () async {
    useRunner((_, _) => {
      'smartctl': {
        'messages': [
          {'string': 'Smartctl open device: /dev/disk0 failed: Operation not permitted'},
        ],
      },
    });
    expect(
      MacOSStorageMonitor().readTemperature('macos-disk0'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('implausible temperatures are rejected', () async {
    useRunner((_, _) => {
      'temperature': {'current': 500},
    });
    expect(
      MacOSStorageMonitor().readTemperature('macos-disk2'),
      throwsA(isA<InvalidReadingException>()),
    );
  });

  test('rejects device ids that are not plain diskN names', () async {
    useRunner((_, _) => {
      'temperature': {'current': 30},
    });
    expect(
      await MacOSStorageMonitor().readTemperature('macos-../../etc/passwd'),
      isNull,
    );
  });
}
