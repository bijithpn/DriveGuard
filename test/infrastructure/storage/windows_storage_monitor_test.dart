import 'dart:convert';

import 'package:driveguard/core/errors/storage_exceptions.dart';
import 'package:driveguard/core/utils/safe_process_runner.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/infrastructure/storage/windows_storage_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers PowerShell calls by recognising which script was sent.
class _FakePowerShell extends SafeProcessRunner {
  _FakePowerShell({this.enumerate, this.reliability, this.raw})
    : super.forTest();

  final Object? enumerate;
  final Object? reliability;
  final String? raw; // overrides stdout for every call (malformed output)
  final scripts = <String>[];

  @override
  Future<bool> exists(
    String executable, {
    List<String> extraPaths = const [],
  }) async => true;

  @override
  Future<ProcessResult2> run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 6),
    bool requireZeroExit = true,
    List<String> extraPaths = const [],
  }) async {
    final script = args.last;
    scripts.add(script);
    if (raw != null) return ProcessResult2(raw!, '', 0);
    Object? out;
    if (script.contains('ForEach-Object')) {
      out = enumerate;
    } else if (script.contains('Get-StorageReliabilityCounter')) {
      out = reliability;
    }
    return ProcessResult2(out == null ? '' : jsonEncode(out), '', 0);
  }
}

void main() {
  late SafeProcessRunner original;
  setUp(() => original = SafeProcessRunner.instance);
  tearDown(() => SafeProcessRunner.instance = original);

  test(
    'maps NVMe / SATA SSD / HDD / USB disks from MSFT_PhysicalDisk',
    () async {
      SafeProcessRunner.instance = _FakePowerShell(
        enumerate: [
          {
            'DeviceId': '0',
            'FriendlyName': 'Samsung SSD 980',
            'BusType': 'NVMe',
            'MediaType': 'SSD',
            'Size': 1000204886016,
            'SerialNumber': 'S1',
          },
          {
            'DeviceId': '1',
            'FriendlyName': 'WDC WD10EZEX',
            'BusType': 'SATA',
            'MediaType': 'HDD',
            'Size': '1000204886016',
          },
          {
            'DeviceId': '2',
            'FriendlyName': 'Crucial MX500',
            'BusType': 'SATA',
            'MediaType': 'SSD',
          },
          {
            'DeviceId': '3',
            'FriendlyName': 'Flash Drive',
            'BusType': 'USB',
            'MediaType': 'Unspecified',
          },
        ],
      );
      final devices = await WindowsStorageMonitor().getDevices();
      final byId = {for (final d in devices) d.id: d};

      expect(byId['windows-0']!.type, StorageDeviceType.nvme);
      expect(byId['windows-0']!.capacityBytes, 1000204886016);
      expect(byId['windows-1']!.type, StorageDeviceType.hdd);
      expect(byId['windows-1']!.capacityBytes, 1000204886016);
      expect(byId['windows-2']!.type, StorageDeviceType.ssd);
      expect(byId['windows-3']!.interfaceType, StorageInterfaceType.usb);
      expect(byId['windows-3']!.isRemovable, isTrue);
    },
  );

  test(
    'a single disk (PowerShell emits an object, not an array) still works',
    () async {
      SafeProcessRunner.instance = _FakePowerShell(
        enumerate: {
          'DeviceId': '0',
          'FriendlyName': 'Only Disk',
          'BusType': 'NVMe',
        },
      );
      expect(await WindowsStorageMonitor().getDevices(), hasLength(1));
    },
  );

  test(
    'empty or malformed enumeration yields no devices, not a crash',
    () async {
      SafeProcessRunner.instance = _FakePowerShell();
      expect(await WindowsStorageMonitor().getDevices(), isEmpty);
      SafeProcessRunner.instance = _FakePowerShell(raw: 'not json {');
      expect(await WindowsStorageMonitor().getDevices(), isEmpty);
    },
  );

  test('reads temperature from the reliability counter', () async {
    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {'Temperature': 41},
    );
    final r = await WindowsStorageMonitor().readTemperature('windows-0');
    expect(r?.celsius, 41.0);
  });

  test('zero / missing temperature is unavailable, never fabricated', () async {
    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {'Temperature': 0},
    );
    expect(await WindowsStorageMonitor().readTemperature('windows-0'), isNull);
    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {'Temperature': null},
    );
    expect(await WindowsStorageMonitor().readTemperature('windows-0'), isNull);
  });

  test('implausible temperature is rejected', () async {
    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {'Temperature': 300},
    );
    expect(
      WindowsStorageMonitor().readTemperature('windows-0'),
      throwsA(isA<InvalidReadingException>()),
    );
  });

  test('device ids that could inject into the script are refused', () async {
    final fake = _FakePowerShell(reliability: {'Temperature': 41});
    SafeProcessRunner.instance = fake;
    expect(
      WindowsStorageMonitor().readTemperature("windows-0'; Remove-Item x #"),
      throwsA(isA<NativeBackendException>()),
    );
    expect(fake.scripts, isEmpty);
  });

  test('health: wear and uncorrected read errors drive status', () async {
    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {
        'Wear': 12,
        'ReadErrorsUncorrected': 3,
        'PowerOnHours': 900,
      },
    );
    final h = await WindowsStorageMonitor().getHealth('windows-0');
    expect(h?.percentageUsed, 12);
    expect(h?.mediaErrors, 3);
    expect(h?.powerOnHours, 900);
    expect(h?.status, DeviceHealthStatus.warning);

    SafeProcessRunner.instance = _FakePowerShell(
      reliability: {'Wear': 5, 'ReadErrorsUncorrected': 0},
    );
    expect(
      (await WindowsStorageMonitor().getHealth('windows-0'))?.status,
      DeviceHealthStatus.healthy,
    );
  });
}
