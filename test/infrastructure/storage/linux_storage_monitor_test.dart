import 'dart:convert';
import 'dart:io';

import 'package:driveguard/core/errors/storage_exceptions.dart';
import 'package:driveguard/core/utils/safe_process_runner.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/infrastructure/storage/linux_storage_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRunner extends SafeProcessRunner {
  _FakeRunner({this.smartctlJson, this.tools = const {}}) : super.forTest();

  final Object? smartctlJson;
  final Set<String> tools;

  @override
  Future<bool> exists(
    String executable, {
    List<String> extraPaths = const [],
  }) async => tools.contains(executable);

  @override
  Future<ProcessResult2> run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 6),
    bool requireZeroExit = true,
    List<String> extraPaths = const [],
  }) async => ProcessResult2(jsonEncode(smartctlJson ?? {}), '', 0);
}

void _write(Directory root, String rel, String content) {
  final f = File('${root.path}/$rel')..createSync(recursive: true);
  f.writeAsStringSync(content);
}

void main() {
  late Directory sys;
  late SafeProcessRunner original;

  setUp(() {
    original = SafeProcessRunner.instance;
    SafeProcessRunner.instance = _FakeRunner();
    sys = Directory.systemTemp.createTempSync('fake_sys');

    // NVMe drive with hwmon temp (47.5 C)
    _write(sys, 'block/nvme0n1/removable', '0\n');
    _write(sys, 'block/nvme0n1/size', '1953525168\n');
    _write(sys, 'class/nvme/nvme0/model', 'Samsung SSD 980 PRO\n');
    _write(sys, 'class/nvme/nvme0/hwmon3/temp1_input', '47500\n');

    // Rotational SATA HDD
    _write(sys, 'block/sda/removable', '0\n');
    _write(sys, 'block/sda/size', '1953525168\n');
    _write(sys, 'block/sda/queue/rotational', '1\n');
    _write(sys, 'block/sda/device/model', 'WDC WD10EZEX\n');
    _write(sys, 'block/sda/device/serial', 'WD-123\n');

    // Removable USB stick, SSD-like
    _write(sys, 'block/sdb/removable', '1\n');
    _write(sys, 'block/sdb/size', '62500000\n');
    _write(sys, 'block/sdb/queue/rotational', '0\n');

    // Must be ignored
    _write(sys, 'block/loop0/removable', '0\n');
    _write(sys, 'block/zram0/removable', '0\n');
    _write(sys, 'block/dm-0/removable', '0\n');
  });

  tearDown(() {
    SafeProcessRunner.instance = original;
    sys.deleteSync(recursive: true);
  });

  test('enumerates real drives and skips loop/zram/dm devices', () async {
    final devices = await LinuxStorageMonitor(sysRoot: sys.path).getDevices();
    final byId = {for (final d in devices) d.id: d};

    expect(byId.keys.toSet(), {'linux-nvme0n1', 'linux-sda', 'linux-sdb'});

    expect(byId['linux-nvme0n1']!.type, StorageDeviceType.nvme);
    expect(byId['linux-nvme0n1']!.model, 'Samsung SSD 980 PRO');
    expect(byId['linux-nvme0n1']!.capacityBytes, 1953525168 * 512);

    expect(byId['linux-sda']!.type, StorageDeviceType.hdd);
    expect(byId['linux-sda']!.serialNumber, 'WD-123');

    expect(byId['linux-sdb']!.isRemovable, isTrue);
    expect(byId['linux-sdb']!.interfaceType, StorageInterfaceType.usb);
  });

  test('reads NVMe temperature from hwmon (milli-degrees)', () async {
    final reading = await LinuxStorageMonitor(
      sysRoot: sys.path,
    ).readTemperature('linux-nvme0n1');
    expect(reading?.celsius, 47.5);
    expect(reading?.source.backendName, 'sysfs-hwmon');
  });

  test('falls back to smartctl when hwmon is absent', () async {
    SafeProcessRunner.instance = _FakeRunner(
      tools: {'smartctl'},
      smartctlJson: {
        'temperature': {'current': 38},
      },
    );
    final reading = await LinuxStorageMonitor(
      sysRoot: sys.path,
    ).readTemperature('linux-sda');
    expect(reading?.celsius, 38.0);
    expect(reading?.source.backendName, 'smartctl');
  });

  test('returns null for a sleeping drive instead of waking it', () async {
    SafeProcessRunner.instance = _FakeRunner(
      tools: {'smartctl'},
      smartctlJson: {'power_mode': 'STANDBY'},
    );
    expect(
      await LinuxStorageMonitor(sysRoot: sys.path).readTemperature('linux-sda'),
      isNull,
    );
  });

  test('smartctl permission failure surfaces as PermissionDenied', () async {
    SafeProcessRunner.instance = _FakeRunner(
      tools: {'smartctl'},
      smartctlJson: {
        'smartctl': {
          'messages': [
            {'string': 'Permission denied'},
          ],
        },
      },
    );
    expect(
      LinuxStorageMonitor(sysRoot: sys.path).readTemperature('linux-sda'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('no hwmon and no tools yields null, not a fabricated value', () async {
    expect(
      await LinuxStorageMonitor(sysRoot: sys.path).readTemperature('linux-sda'),
      isNull,
    );
  });

  test('implausible hwmon values are skipped', () async {
    _write(sys, 'class/nvme/nvme0/hwmon3/temp1_input', '900000\n');
    final reading = await LinuxStorageMonitor(
      sysRoot: sys.path,
    ).readTemperature('linux-nvme0n1');
    expect(reading, isNull);
  });
}
