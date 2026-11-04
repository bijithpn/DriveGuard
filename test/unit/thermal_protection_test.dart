import 'package:driveguard/application/prediction/trend_analyzer.dart';
import 'package:driveguard/application/protection/process_controller.dart';
import 'package:driveguard/application/protection/thermal_cause_analyzer.dart';
import 'package:driveguard/application/protection/thermal_guard.dart';
import 'package:driveguard/application/protection/thermal_models.dart';
import 'package:driveguard/application/protection/thermal_protection_service.dart';
import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/domain/entities/storage_activity.dart';
import 'package:driveguard/domain/entities/storage_capacity.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/entities/temperature_thresholds.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_notification_service.dart';
import '../mocks/fake_system_actions.dart';

StorageDevice device({StorageCapacity? capacity}) => StorageDevice(
  id: 'd1',
  type: StorageDeviceType.nvme,
  interfaceType: StorageInterfaceType.nvme,
  sensorAvailability: SensorAvailability.available,
  model: 'TestDrive',
  capacity: capacity ?? StorageCapacity.unavailable,
);

List<TrendPoint> flat(double c, {int n = 6}) {
  final t = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < n; i++) TrendPoint(t.add(Duration(seconds: i * 5)), c),
  ];
}

void main() {
  const thresholds = TemperatureThresholds();
  const cfg = ThermalProtectionSettings();

  group('ThermalGuard', () {
    test('single hot reading is not an emergency', () {
      final g = ThermalGuard();
      final a = g.assess(
        celsius: 76,
        recent: flat(76),
        thresholds: thresholds,
        settings: cfg,
      );
      expect(a.stage, ThermalStage.danger);
    });

    test(
      '3 consecutive readings latch emergency, release needs hysteresis',
      () {
        final g = ThermalGuard();
        ThermalAssessment run(double c) => g.assess(
          celsius: c,
          recent: flat(c),
          thresholds: thresholds,
          settings: cfg,
        );
        run(76);
        run(76);
        expect(run(76).stage, ThermalStage.emergency);
        // 72 is below the limit but inside hysteresis → still emergency.
        expect(run(72).stage, ThermalStage.emergency);
        // 69 < 75-5 → released.
        expect(run(69).stage, ThermalStage.elevated);
      },
    );

    test('unmistakable spike is immediate', () {
      final g = ThermalGuard();
      final a = g.assess(
        celsius: 81,
        recent: flat(81),
        thresholds: thresholds,
        settings: cfg,
      );
      expect(a.stage, ThermalStage.emergency);
    });

    test('fast rise that will cross the limit within a minute escalates', () {
      final g = ThermalGuard();
      final t = DateTime(2026, 1, 1);
      // +0.5C every 5s = 6C/min, ending at 72C → 75C in 30s.
      final pts = [
        for (var i = 0; i < 8; i++)
          TrendPoint(t.add(Duration(seconds: i * 5)), 68.5 + i * 0.5),
      ];
      final a = g.assess(
        celsius: 72,
        recent: pts,
        thresholds: thresholds,
        settings: cfg,
      );
      expect(a.stage, ThermalStage.emergency);
      expect(a.reason, contains('Rising'));
    });

    test('below warning is nominal', () {
      final g = ThermalGuard();
      expect(
        g
            .assess(
              celsius: 40,
              recent: flat(40),
              thresholds: thresholds,
              settings: cfg,
            )
            .stage,
        ThermalStage.nominal,
      );
    });
  });

  group('ThermalCauseAnalyzer', () {
    const analyzer = ThermalCauseAnalyzer();
    StorageActivity act({double? w, double? r, double? u}) => StorageActivity(
      deviceId: 'd1',
      timestamp: DateTime(2026),
      availability: SensorAvailability.available,
      writeBytesPerSecond: w,
      readBytesPerSecond: r,
      utilizationPercent: u,
    );

    test('heavy writes are blamed with the busiest process', () {
      final cause = analyzer.analyze(
        device: device(),
        celsius: 72,
        slopePerMinute: 1,
        activity: act(w: 400 * 1024 * 1024),
        processes: const [
          ProcessSample(pid: 42, name: 'ffmpeg', cpuPercent: 80, user: 'me'),
        ],
        currentUser: 'me',
      );
      expect(cause.kind, ThermalCauseKind.heavyWrites);
      expect(cause.culprit?.name, 'ffmpeg');
    });

    test('idle but hot → poor airflow', () {
      final cause = analyzer.analyze(
        device: device(),
        celsius: 72,
        slopePerMinute: 0,
        activity: act(w: 1000, r: 1000, u: 1),
        processes: const [],
      );
      expect(cause.kind, ThermalCauseKind.poorAirflow);
    });

    test('nearly full drive is reported', () {
      final cause = analyzer.analyze(
        device: device(
          capacity: const StorageCapacity(
            availability: SensorAvailability.available,
            totalBytes: 1000,
            usedBytes: 960,
            freeBytes: 40,
          ),
        ),
        celsius: 72,
        slopePerMinute: 0,
        activity: act(w: 0, r: 0),
        processes: const [],
      );
      expect(cause.kind, ThermalCauseKind.nearlyFull);
    });

    test('other users need admin; protected processes are never offered', () {
      expect(
        killAccess(
          const ProcessSample(pid: 5, name: 'x', cpuPercent: 90, user: 'root'),
          currentUser: 'me',
        ),
        KillAccess.needsAdmin,
      );
      expect(
        killAccess(
          const ProcessSample(pid: 5, name: 'kernel_task', cpuPercent: 90),
        ),
        KillAccess.never,
      );
      expect(
        killAccess(const ProcessSample(pid: 1, name: 'launchd', cpuPercent: 1)),
        KillAccess.never,
      );
      expect(
        killAccess(
          const ProcessSample(pid: 4242, name: 'driveguard', cpuPercent: 1),
          ownPid: 4242,
        ),
        KillAccess.never,
      );
    });
  });

  group('ThermalProtectionService', () {
    late FakeActions actions;
    late FakeNotificationService notes;
    late DateTime now;
    late ThermalProtectionService svc;
    const settings = AppSettings(
      thermalProtection: ThermalProtectionSettings(
        shutdownEnabled: true,
        countdownSeconds: 2,
      ),
    );

    setUp(() {
      actions = FakeActions();
      notes = FakeNotificationService();
      now = DateTime(2026, 1, 1);
      svc = ThermalProtectionService(
        actions: actions,
        notifications: notes,
        clock: () => now,
      );
    });
    tearDown(() => svc.dispose());

    Future<void> feed(double c, {AppSettings s = settings}) => svc.onReading(
      device: device(),
      celsius: c,
      recent: flat(c),
      activity: null,
      settings: s,
    );

    test('emergency starts a countdown and notifies with the cause', () async {
      actions.procs = const [
        ProcessSample(pid: 9, name: 'rsync', cpuPercent: 70, user: 'me'),
      ];
      await feed(90);
      expect(svc.state.shutdownScheduled, isTrue);
      expect(svc.state.stage, ThermalStage.emergency);
      expect(notes.shown.single, contains('Main cause'));
      expect(notes.shown.single, contains('shutting down'));
      expect(actions.shutdowns, 0);
    });

    test('cancel stops the countdown and snoozes re-arming', () async {
      await feed(90);
      svc.cancelShutdown();
      expect(svc.state.shutdownScheduled, isFalse);
      await feed(90);
      expect(svc.state.shutdownScheduled, isFalse);
      expect(actions.shutdowns, 0);
    });

    test(
      'shutdown is aborted when the drive cools before the deadline',
      () async {
        await feed(90);
        await feed(40); // cooled
        expect(svc.state.shutdownScheduled, isFalse);
        now = now.add(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(actions.shutdowns, 0);
      },
    );

    test('shutdown happens when it stays hot to the end', () async {
      await feed(90);
      now = now.add(const Duration(seconds: 3));
      for (var i = 0; i < 50 && actions.shutdowns == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(actions.shutdowns, 1);
    });

    test('shutdown never runs when the option is off', () async {
      const off = AppSettings();
      await feed(90, s: off);
      now = now.add(const Duration(minutes: 5));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(svc.state.shutdownScheduled, isFalse);
      expect(actions.shutdowns, 0);
      expect(notes.shown.single, contains('Automatic shutdown is off'));
    });

    test('stopCulprit kills only the identified, terminable process', () async {
      actions.procs = const [
        ProcessSample(pid: 77, name: 'ffmpeg', cpuPercent: 90, user: 'me'),
      ];
      await svc.onReading(
        device: device(),
        celsius: 90,
        recent: flat(90),
        activity: StorageActivity(
          deviceId: 'd1',
          timestamp: now,
          availability: SensorAvailability.available,
          writeBytesPerSecond: 500 * 1024 * 1024,
        ),
        settings: const AppSettings(),
      );
      expect(await svc.quitCulprit('d1'), QuitResult.quit);
      expect(actions.killed, [77]);
    });
  });

  group('ThermalProtectionService safety', () {
    late FakeActions actions;
    late FakeNotificationService notes;
    late DateTime now;
    late ThermalProtectionService svc;
    const settings = AppSettings(
      thermalProtection: ThermalProtectionSettings(
        shutdownEnabled: true,
        countdownSeconds: 2,
      ),
    );

    StorageDevice dev(String id) => StorageDevice(
      id: id,
      type: StorageDeviceType.nvme,
      interfaceType: StorageInterfaceType.nvme,
      sensorAvailability: SensorAvailability.available,
      model: 'Drive $id',
    );

    Future<void> feed(String id, double c, {AppSettings s = settings}) =>
        svc.onReading(
          device: dev(id),
          celsius: c,
          recent: flat(c),
          activity: null,
          settings: s,
        );

    setUp(() {
      actions = FakeActions();
      notes = FakeNotificationService();
      now = DateTime(2026, 1, 1);
      svc = ThermalProtectionService(
        actions: actions,
        notifications: notes,
        clock: () => now,
      );
    });
    tearDown(() => svc.dispose());

    Future<void> waitFor(bool Function() cond) async {
      for (var i = 0; i < 60 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('never shuts down on stale data (e.g. after sleep)', () async {
      await feed('a', 90);
      // The machine "slept" for an hour: the last reading is now ancient.
      now = now.add(const Duration(hours: 1));
      await waitFor(() => !svc.state.shutdownScheduled);
      expect(actions.shutdowns, 0);
      expect(actions.elevatedShutdowns, 0);
      expect(svc.state.message, contains('No fresh temperature'));
    });

    test('resume from sleep cancels a running countdown', () async {
      await feed('a', 90);
      expect(svc.state.shutdownScheduled, isTrue);
      svc.onSystemResume();
      expect(svc.state.shutdownScheduled, isFalse);
      expect(svc.state.message, contains('resumed'));
    });

    test('losing the sensor during a countdown cancels it', () async {
      await feed('a', 90);
      svc.onSensorLost('a');
      expect(svc.state.shutdownScheduled, isFalse);
      expect(svc.state.message, contains('Lost contact'));
      expect(actions.shutdowns, 0);
    });

    test('a cooler second drive cannot hide a drive in emergency', () async {
      await feed('a', 90);
      await feed('b', 40);
      expect(svc.state.deviceId, 'a');
      expect(svc.state.stage, ThermalStage.emergency);
    });

    test('most urgent drive wins when two are hot', () async {
      await feed('b', 72); // danger
      await feed('a', 90, s: const AppSettings()); // emergency, no shutdown
      expect(svc.state.deviceId, 'a');
    });

    test(
      'falls back to the admin shutdown if the normal one is refused',
      () async {
        actions.shutdownOk = false;
        await feed('a', 90);
        now = now.add(const Duration(seconds: 3));
        await waitFor(() => actions.elevatedShutdowns > 0);
        expect(actions.shutdowns, 1);
        expect(actions.elevatedShutdowns, 1);
      },
    );

    test('hot drives make polling faster; cool ones do not', () async {
      expect(svc.anyElevated, isFalse);
      await feed('a', 65);
      expect(svc.anyElevated, isTrue);
      expect(svc.anyEmergency, isFalse);
      await feed('a', 90);
      expect(svc.anyEmergency, isTrue);
      await feed('a', 40);
      expect(svc.anyElevated, isFalse);
    });

    test('long heat exposure triggers a one-time advisory', () async {
      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(seconds: 60));
        await feed('a', 65);
      }
      expect(
        notes.shown.where((e) => e.startsWith('advisory:thermal-stress')),
        hasLength(1),
      );
      expect(svc.stressMinutesFor('a'), greaterThan(30));
    });
  });
}
