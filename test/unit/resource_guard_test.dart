import 'package:driveguard/application/alerts/ssd_life_advisor.dart';
import 'package:driveguard/application/protection/process_controller.dart';
import 'package:driveguard/application/protection/resource_guard_service.dart';
import 'package:driveguard/application/protection/thermal_models.dart';
import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/domain/entities/device_health.dart';
import 'package:driveguard/domain/entities/storage_activity.dart';
import 'package:driveguard/domain/entities/storage_capacity.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_notification_service.dart';
import '../mocks/fake_system_actions.dart';

const gb = 1024 * 1024 * 1024;
const mb = 1024 * 1024;

MemorySnapshot mem({
  double availPct = 50,
  double swapGb = 0,
  int totalGb = 16,
}) => MemorySnapshot(
  totalBytes: totalGb * gb,
  availableBytes: (totalGb * gb * availPct / 100).round(),
  swapUsedBytes: (swapGb * gb).round(),
  swapTotalBytes: 16 * gb,
);

StorageDevice ssd({DeviceHealth? health, StorageCapacity? capacity}) =>
    StorageDevice(
      id: 'd1',
      type: StorageDeviceType.nvme,
      interfaceType: StorageInterfaceType.nvme,
      sensorAvailability: SensorAvailability.available,
      model: 'Test NVMe',
      health: health ?? DeviceHealth.unavailable,
      capacity: capacity ?? StorageCapacity.unavailable,
    );

void main() {
  group('assessMemory', () {
    test('plenty of RAM is fine even with leftover swap', () {
      expect(assessMemory(mem(availPct: 40, swapGb: 3)).severity, isNull);
    });
    test('under 10% available is a warning, under 5% critical', () {
      expect(assessMemory(mem(availPct: 8)).severity, ResourceSeverity.warning);
      expect(
        assessMemory(mem(availPct: 3)).severity,
        ResourceSeverity.critical,
      );
    });
    test('big swap only matters together with pressure or growth', () {
      expect(assessMemory(mem(availPct: 30, swapGb: 6)).severity, isNull);
      expect(
        assessMemory(mem(availPct: 18, swapGb: 6)).severity,
        ResourceSeverity.warning,
      );
      expect(
        assessMemory(
          mem(availPct: 30, swapGb: 2),
          swapGrowthBytesPerMin: 400.0 * mb,
        ).severity,
        ResourceSeverity.warning,
      );
    });
    test('an active alert has hysteresis (no flicker around 10%)', () {
      expect(assessMemory(mem(availPct: 12)).severity, isNull);
      expect(
        assessMemory(mem(availPct: 12), active: true).severity,
        ResourceSeverity.warning,
      );
      expect(assessMemory(mem(availPct: 20), active: true).severity, isNull);
    });
  });

  group('ResourceGuardService', () {
    late FakeActions actions;
    late FakeNotificationService notes;
    late DateTime now;
    late ResourceGuardService guard;
    var settings = const AppSettings();
    var devices = <StorageDevice>[];

    setUp(() {
      actions = FakeActions();
      notes = FakeNotificationService();
      now = DateTime(2026, 1, 1, 12);
      settings = const AppSettings();
      devices = [ssd()];
      guard = ResourceGuardService(
        actions: actions,
        notifications: notes,
        devices: () => devices,
        settings: () => settings,
        clock: () => now,
      );
    });
    tearDown(() => guard.dispose());

    test(
      'low memory raises one alert naming the biggest app, notifies once',
      () async {
        actions.memory = mem(availPct: 4, swapGb: 6);
        actions.procs = const [
          ProcessSample(
            pid: 10,
            name: 'Chrome',
            cpuPercent: 5,
            user: 'me',
            rssBytes: 6 * gb,
          ),
        ];
        await guard.tick();
        expect(guard.current, hasLength(1));
        final a = guard.current.single;
        expect(a.severity, ResourceSeverity.critical);
        expect(a.culprit?.name, 'Chrome');
        expect(a.detail, contains('Chrome'));
        expect(notes.shown, hasLength(1));

        await guard.tick(); // same condition → no duplicate notification
        expect(notes.shown, hasLength(1));

        actions.memory = mem(availPct: 60);
        await guard.tick();
        expect(guard.current, isEmpty);
      },
    );

    test('never offers a protected system process as the culprit', () async {
      actions.memory = mem(availPct: 3);
      actions.procs = const [
        ProcessSample(
          pid: 1,
          name: 'kernel_task',
          cpuPercent: 1,
          rssBytes: 9 * gb,
        ),
        ProcessSample(
          pid: 20,
          name: 'Slack',
          cpuPercent: 1,
          user: 'me',
          rssBytes: 2 * gb,
        ),
      ];
      await guard.tick();
      expect(guard.current.single.culprit?.name, 'Slack');
    });

    test('does nothing when disabled', () async {
      settings = const AppSettings(resourceGuardEnabled: false);
      actions.memory = mem(availPct: 2);
      await guard.tick();
      expect(guard.current, isEmpty);
      expect(notes.shown, isEmpty);
    });

    test(
      'sustained heavy writes are detected with a measured writer',
      () async {
        // 40 MB/s for 6 minutes, sampled every 5s.
        var t = now;
        for (var i = 0; i < 72; i++) {
          t = t.add(const Duration(seconds: 5));
          guard.recordActivity(
            StorageActivity(
              deviceId: 'd1',
              timestamp: t,
              availability: SensorAvailability.available,
              writeBytesPerSecond: 40.0 * mb,
            ),
          );
        }
        now = t;
        actions.memory = mem();
        actions.procs = const [
          ProcessSample(
            pid: 7,
            name: 'rsync',
            cpuPercent: 10,
            user: 'me',
            writeBytesPerSecond: 38.0 * mb,
          ),
        ];
        await guard.tick();
        final alert = guard.current.firstWhere((a) => a.id == 'writes:d1');
        expect(alert.kind, ResourceAlertKind.heavyWrites);
        expect(alert.culprit?.name, 'rsync');
        expect(alert.detail, contains('Confirmed source: rsync'));
      },
    );

    test('short write bursts do not alert (needs 5 min of coverage)', () async {
      var t = now;
      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(seconds: 5));
        guard.recordActivity(
          StorageActivity(
            deviceId: 'd1',
            timestamp: t,
            availability: SensorAvailability.available,
            writeBytesPerSecond: 300.0 * mb,
          ),
        );
      }
      now = t;
      expect(guard.averageWriteRate('d1'), isNull);
    });

    test('gaps (sleep) are not counted as written data', () {
      guard.recordActivity(
        StorageActivity(
          deviceId: 'd1',
          timestamp: now,
          availability: SensorAvailability.available,
          writeBytesPerSecond: 500.0 * mb,
        ),
      );
      guard.recordActivity(
        StorageActivity(
          deviceId: 'd1',
          timestamp: now.add(const Duration(hours: 3)),
          availability: SensorAvailability.available,
          writeBytesPerSecond: 500.0 * mb,
        ),
      );
      expect(guard.averageWriteRate('d1'), isNull);
    });
  });

  group('ProcessController', () {
    late FakeActions actions;
    late ProcessController ctl;
    const p = ProcessSample(
      pid: 50,
      name: 'ffmpeg',
      cpuPercent: 90,
      user: 'me',
    );

    setUp(() {
      actions = FakeActions()..procs = const [p];
      ctl = ProcessController(
        actions,
        waitForExit: const Duration(milliseconds: 600),
      );
    });

    test('quits an own process and confirms it is gone', () async {
      expect(await ctl.quit(p), QuitResult.quit);
      expect(actions.killed, [50]);
    });

    test('reports stillRunning when the app ignores a graceful quit', () async {
      actions.alive.add(50);
      // terminateProcess in the fake removes it; emulate an ignoring app.
      final stubborn = _Stubborn(actions);
      final c = ProcessController(
        stubborn,
        waitForExit: const Duration(milliseconds: 500),
      );
      expect(await c.quit(p), QuitResult.stillRunning);
    });

    test('other users\' processes require explicit admin consent', () async {
      const root = ProcessSample(
        pid: 60,
        name: 'mdworker',
        cpuPercent: 80,
        user: 'root',
      );
      actions.procs = const [root];
      expect(await ctl.quit(root), QuitResult.denied);
      expect(actions.killed, isEmpty);
      expect(await ctl.quit(root, admin: true), QuitResult.quit);
    });

    test(
      'never touches a pid that was recycled by a different program',
      () async {
        actions.procs = const [
          ProcessSample(pid: 50, name: 'Photos', cpuPercent: 1, user: 'me'),
        ];
        expect(await ctl.quit(p), QuitResult.notAllowed);
        expect(actions.killed, isEmpty);
      },
    );

    test('protected processes are refused outright', () async {
      const k = ProcessSample(pid: 2, name: 'kernel_task', cpuPercent: 90);
      expect(await ctl.quit(k, admin: true), QuitResult.notAllowed);
    });
  });

  group('SsdLifeAdvisor', () {
    const advisor = SsdLifeAdvisor();

    test('wear thresholds escalate 80 → 90', () {
      final w80 = advisor.evaluate(
        ssd(
          health: const DeviceHealth(
            status: DeviceHealthStatus.healthy,
            percentageUsed: 82,
          ),
        ),
      );
      expect(w80.single.id, 'wear-80');
      final w90 = advisor.evaluate(
        ssd(
          health: const DeviceHealth(
            status: DeviceHealthStatus.healthy,
            percentageUsed: 93,
          ),
        ),
      );
      expect(w90.single.id, 'wear-90');
      expect(w90.single.severity, AdvisorySeverity.critical);
    });

    test('healthy drive produces no advice', () {
      expect(
        advisor.evaluate(
          ssd(
            health: const DeviceHealth(
              status: DeviceHealthStatus.healthy,
              percentageUsed: 10,
              availableSparePercent: 100,
              availableSpareThreshold: 10,
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('spare at threshold is critical, near threshold a warning', () {
      Advisory only(int spare) => advisor
          .evaluate(
            ssd(
              health: DeviceHealth(
                status: DeviceHealthStatus.healthy,
                availableSparePercent: spare,
                availableSpareThreshold: 10,
              ),
            ),
          )
          .single;
      expect(only(10).id, 'spare-crit');
      expect(only(18).id, 'spare-warn');
    });

    test('new unsafe shutdowns are reported with the delta', () {
      final a = advisor.evaluate(
        ssd(
          health: const DeviceHealth(
            status: DeviceHealthStatus.healthy,
            unsafeShutdowns: 7,
          ),
        ),
        previous: const DeviceHealth(
          status: DeviceHealthStatus.healthy,
          unsafeShutdowns: 5,
        ),
      );
      expect(a.single.title, contains('2 unsafe shutdowns'));
      // First reading (no baseline) must not alert.
      expect(
        advisor.evaluate(
          ssd(
            health: const DeviceHealth(
              status: DeviceHealthStatus.healthy,
              unsafeShutdowns: 7,
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('free-space advice only for SSDs at 80%+ used', () {
      const cap = StorageCapacity(
        availability: SensorAvailability.available,
        totalBytes: 1000,
        usedBytes: 850,
        freeBytes: 150,
      );
      expect(advisor.evaluate(ssd(capacity: cap)).single.id, 'free-space-80');
      const hdd = StorageDevice(
        id: 'h',
        type: StorageDeviceType.hdd,
        interfaceType: StorageInterfaceType.sata,
        sensorAvailability: SensorAvailability.available,
        capacity: cap,
      );
      expect(advisor.evaluate(hdd), isEmpty);
    });
  });
}

/// An app that ignores a graceful quit: the process stays alive.
class _Stubborn extends FakeActions {
  _Stubborn(FakeActions base) {
    procs = base.procs;
  }
  @override
  Future<bool> isProcessAlive(int pid) async => true;
}
