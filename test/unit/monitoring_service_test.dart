import 'package:driveguard/application/monitoring/monitoring_service.dart';
import 'package:driveguard/application/monitoring/temperature_history_store.dart';
import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/core/errors/storage_exceptions.dart';
import 'package:driveguard/domain/entities/device_health.dart';
import 'package:driveguard/domain/entities/storage_capacity.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/entities/storage_volume.dart';
import 'package:driveguard/domain/entities/temperature_reading.dart';
import 'package:driveguard/domain/entities/temperature_thresholds.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/repositories/storage_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_notification_service.dart';

/// A tiny scriptable [StorageMonitor] so monitoring-service behaviour
/// (failure isolation, discovery, alerts) can be tested without spinning
/// up real timers or touching the OS.
class _ScriptedMonitor extends StorageMonitor {
  List<StorageDevice> devices;
  final Map<String, Object> nextReadingOrError = {};
  final Map<String, StorageCapacity> nextCapacity = {};
  final Map<String, List<StorageVolume>> nextVolumes = {};
  final Map<String, DeviceHealth> nextHealth = {};
  final Map<String, int> readTemperatureCallCount = {};

  _ScriptedMonitor(this.devices);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BackendCapabilities> getCapabilities() async =>
      const BackendCapabilities(
        backendName: 'scripted',
        canEnumerateDevices: true,
        canReadTemperature: true,
        canReadHealth: true,
      );

  @override
  Future<List<StorageDevice>> getDevices() async => devices;

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    readTemperatureCallCount[deviceId] =
        (readTemperatureCallCount[deviceId] ?? 0) + 1;
    final scripted = nextReadingOrError[deviceId];
    if (scripted is StorageMonitorException) throw scripted;
    if (scripted is double) {
      return TemperatureReading(
        celsius: scripted,
        timestamp: DateTime.now(),
        source: const TemperatureSource(
          backendName: 'scripted',
          sensorId: 'composite',
        ),
      );
    }
    return null;
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async => const [];

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async =>
      nextHealth[deviceId] ?? DeviceHealth.unavailable;

  @override
  Future<StorageCapacity> getCapacity(String deviceId) async =>
      nextCapacity[deviceId] ?? StorageCapacity.unavailable;

  @override
  Future<List<StorageVolume>> getVolumes(String deviceId) async =>
      nextVolumes[deviceId] ?? const [];
}

StorageDevice _device(String id) => StorageDevice(
  id: id,
  type: StorageDeviceType.nvme,
  interfaceType: StorageInterfaceType.nvme,
  sensorAvailability: SensorAvailability.unavailable,
  model: id,
);

void main() {
  test(
    'a failing device does not stop other devices from being polled',
    () async {
      final backend = _ScriptedMonitor([_device('good'), _device('bad')]);
      backend.nextReadingOrError['good'] = 42.0;
      backend.nextReadingOrError['bad'] = const PermissionDeniedException(
        'bad',
      );

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final devices = {for (final d in service.currentDevices) d.id: d};
      expect(devices['good']!.primaryTemperature?.celsius, 42.0);
      expect(devices['good']!.monitoringStatus, MonitoringStatus.active);
      expect(
        devices['bad']!.sensorAvailability,
        SensorAvailability.permissionDenied,
      );
      expect(
        devices['bad']!.monitoringStatus,
        MonitoringStatus.permissionDenied,
      );

      await service.dispose();
    },
  );

  test(
    'a null reading is reported as unavailable, never fabricated as 0',
    () async {
      final backend = _ScriptedMonitor([_device('no-sensor')]);
      // no entry in nextReadingOrError -> readTemperature returns null

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );
      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final device = service.currentDevices.single;
      expect(device.primaryTemperature, isNull);
      expect(device.sensorAvailability, SensorAvailability.unsupported);
      expect(device.monitoringStatus, MonitoringStatus.sensorUnavailable);

      await service.dispose();
    },
  );

  test(
    'device disconnect is reflected, then removed after the next scan if still absent',
    () async {
      final backend = _ScriptedMonitor([_device('removable')]);
      backend.nextReadingOrError['removable'] = 30.0;

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );
      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.currentDevices.length, 1);

      backend.devices = [];
      await service.rescan();
      expect(
        service.currentDevices.single.monitoringStatus,
        MonitoringStatus.disconnected,
      );

      await service.rescan();
      expect(service.currentDevices, isEmpty);

      await service.dispose();
    },
  );

  test('reconnecting a previously disconnected device restores it', () async {
    final device = _device('external');
    final backend = _ScriptedMonitor([device]);
    backend.nextReadingOrError['external'] = 33.0;

    final service = MonitoringService(
      backend: backend,
      notifications: FakeNotificationService(),
      historyStore: TemperatureHistoryStore(),
    );
    await service.start(const AppSettings());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    backend.devices = [];
    await service.rescan();
    expect(
      service.currentDevices.single.monitoringStatus,
      MonitoringStatus.disconnected,
    );

    backend.devices = [device];
    await service.rescan();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      service.currentDevices.single.monitoringStatus,
      isNot(MonitoringStatus.disconnected),
    );

    await service.dispose();
  });

  test('capacity and volumes are refreshed alongside discovery', () async {
    final device = _device('with-capacity');
    final backend = _ScriptedMonitor([device]);
    backend.nextReadingOrError['with-capacity'] = 30.0;
    backend.nextCapacity['with-capacity'] = const StorageCapacity(
      availability: SensorAvailability.available,
      totalBytes: 1000,
      usedBytes: 400,
    );
    backend.nextVolumes['with-capacity'] = const [
      StorageVolume(
        id: 'vol-1',
        mountPoint: '/',
        totalBytes: 1000,
        usedBytes: 400,
      ),
    ];

    final service = MonitoringService(
      backend: backend,
      notifications: FakeNotificationService(),
      historyStore: TemperatureHistoryStore(),
    );

    await service.start(const AppSettings());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final result = service.currentDevices.single;
    expect(result.capacity.isValid, isTrue);
    expect(result.capacity.usagePercent, 40.0);
    expect(result.volumes, hasLength(1));
    expect(result.volumes.single.mountPoint, '/');

    await service.dispose();
  });

  test(
    'a device with no capacity support keeps reporting unavailable, never zero',
    () async {
      final backend = _ScriptedMonitor([_device('no-capacity')]);
      backend.nextReadingOrError['no-capacity'] = 30.0;
      // nextCapacity/nextVolumes left empty - base StorageMonitor defaults apply.

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = service.currentDevices.single;
      expect(result.capacity.isValid, isFalse);
      expect(result.capacity.availability, SensorAvailability.unavailable);
      expect(result.volumes, isEmpty);

      await service.dispose();
    },
  );

  test(
    'a rapid temperature rise triggers a rapid-rise notification, independent of the warning threshold',
    () async {
      final backend = _ScriptedMonitor([_device('spiking')]);
      backend.nextReadingOrError['spiking'] = 30.0;
      final notifications = FakeNotificationService();

      final service = MonitoringService(
        backend: backend,
        notifications: notifications,
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(
        const AppSettings(
          pollingInterval: Duration(milliseconds: 15),
          rapidRiseWindow: Duration(milliseconds: 80),
          rapidRiseDeltaCelsius: 5,
          notificationCooldown: Duration(seconds: 30),
          // Keep this well above 30°C so the ordinary warning/critical path
          // never fires - this test is only about the rise-rate path.
          globalThresholds: TemperatureThresholds(
            warningCelsius: 90,
            criticalCelsius: 100,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      backend.nextReadingOrError['spiking'] = 45.0; // +15°C jump
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        notifications.shown.any((s) => s.startsWith('rapid-rise:spiking:')),
        isTrue,
      );
      // The absolute-threshold path must not have fired for this jump -
      // 45°C is still well under the 90°C warning threshold configured above.
      expect(
        notifications.shown.any(
          (s) => s.startsWith('warning:') || s.startsWith('critical:'),
        ),
        isFalse,
      );

      await service.dispose();
    },
  );

  test(
    'a SMART health downgrade triggers a health alert notification',
    () async {
      final backend = _ScriptedMonitor([_device('degrading')]);
      backend.nextReadingOrError['degrading'] = 30.0;
      backend.nextHealth['degrading'] = const DeviceHealth(
        status: DeviceHealthStatus.healthy,
        percentageUsed: 4,
      );
      final notifications = FakeNotificationService();

      final service = MonitoringService(
        backend: backend,
        notifications: notifications,
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(
        const AppSettings(
          healthPollingInterval: Duration(milliseconds: 20),
          notificationCooldown: Duration(seconds: 30),
        ),
      );
      // The first health poll (fired once from start()) only seeds
      // _lastKnownHealth - nothing to compare against yet.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      backend.nextHealth['degrading'] = const DeviceHealth(
        status: DeviceHealthStatus.warning,
        percentageUsed: 4,
        mediaErrors: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        notifications.shown.any((s) => s.startsWith('health-warning:')),
        isTrue,
      );

      await service.dispose();
    },
  );

  test(
    'a sudden wear jump triggers a health alert even without a status change',
    () async {
      final backend = _ScriptedMonitor([_device('wearing')]);
      backend.nextReadingOrError['wearing'] = 30.0;
      backend.nextHealth['wearing'] = const DeviceHealth(
        status: DeviceHealthStatus.healthy,
        percentageUsed: 4,
      );
      final notifications = FakeNotificationService();

      final service = MonitoringService(
        backend: backend,
        notifications: notifications,
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(
        const AppSettings(
          healthPollingInterval: Duration(milliseconds: 20),
          notificationCooldown: Duration(seconds: 30),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      backend.nextHealth['wearing'] = const DeviceHealth(
        status: DeviceHealthStatus.healthy,
        percentageUsed: 9, // +5, above the default 3-point jump threshold
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        notifications.shown.any(
          (s) => s.startsWith('health-warning:') && s.contains('Wear'),
        ),
        isTrue,
      );

      await service.dispose();
    },
  );

  test(
    'a spinning HDD is never re-polled faster than the spin-down safety '
    'floor, even when reinitialized repeatedly',
    () async {
      final hdd = StorageDevice(
        id: 'hdd-1',
        type: StorageDeviceType.hdd,
        interfaceType: StorageInterfaceType.sata,
        sensorAvailability: SensorAvailability.unavailable,
        model: 'hdd-1',
      );
      final backend = _ScriptedMonitor([hdd]);
      backend.nextReadingOrError['hdd-1'] = 35.0;

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.readTemperatureCallCount['hdd-1'], 1);

      // Forcing extra poll cycles immediately must not touch the drive
      // again until the safety floor elapses - an aggressive polling
      // setting must never be able to hammer a spinning disk.
      await service.reinitializeAfterResume();
      await service.reinitializeAfterResume();
      expect(backend.readTemperatureCallCount['hdd-1'], 1);

      await service.dispose();
    },
  );

  test(
    'a non-spinning device (NVMe/SSD) is re-polled normally on '
    'reinitialize, unaffected by the HDD spin-down safety floor',
    () async {
      final device = _device('nvme-1');
      final backend = _ScriptedMonitor([device]);
      backend.nextReadingOrError['nvme-1'] = 35.0;

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(const AppSettings());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.readTemperatureCallCount['nvme-1'], 1);

      await service.reinitializeAfterResume();
      expect(backend.readTemperatureCallCount['nvme-1'], 2);

      await service.dispose();
    },
  );

  test(
    'refreshNow polls a single device immediately without waiting for the '
    'next timer tick',
    () async {
      final device = _device('nvme-1');
      final backend = _ScriptedMonitor([device]);
      backend.nextReadingOrError['nvme-1'] = 40.0;

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
        // A polling interval long enough that nothing would happen from
        // the timer within this test's lifetime.
      );

      await service.start(
        const AppSettings(pollingInterval: Duration(minutes: 5)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.readTemperatureCallCount['nvme-1'], 1);

      backend.nextReadingOrError['nvme-1'] = 41.0;
      await service.refreshNow(deviceId: 'nvme-1');
      expect(backend.readTemperatureCallCount['nvme-1'], 2);
      expect(
        service.currentDevices
            .firstWhere((d) => d.id == 'nvme-1')
            .primaryTemperature
            ?.celsius,
        41.0,
      );

      await service.dispose();
    },
  );

  test('refreshNow works even while monitoring is paused', () async {
    final device = _device('nvme-1');
    final backend = _ScriptedMonitor([device]);
    backend.nextReadingOrError['nvme-1'] = 40.0;

    final service = MonitoringService(
      backend: backend,
      notifications: FakeNotificationService(),
      historyStore: TemperatureHistoryStore(),
    );

    await service.start(const AppSettings());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    service.pause();

    backend.nextReadingOrError['nvme-1'] = 55.0;
    await service.refreshNow(deviceId: 'nvme-1');
    expect(
      service.currentDevices
          .firstWhere((d) => d.id == 'nvme-1')
          .primaryTemperature
          ?.celsius,
      55.0,
    );

    await service.dispose();
  });

  test(
    'refreshNow with no deviceId refreshes every connected device',
    () async {
      final a = _device('a');
      final b = _device('b');
      final backend = _ScriptedMonitor([a, b]);
      backend.nextReadingOrError['a'] = 30.0;
      backend.nextReadingOrError['b'] = 31.0;

      final service = MonitoringService(
        backend: backend,
        notifications: FakeNotificationService(),
        historyStore: TemperatureHistoryStore(),
      );

      await service.start(
        const AppSettings(pollingInterval: Duration(minutes: 5)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.readTemperatureCallCount['a'], 1);
      expect(backend.readTemperatureCallCount['b'], 1);

      await service.refreshNow();
      expect(backend.readTemperatureCallCount['a'], 2);
      expect(backend.readTemperatureCallCount['b'], 2);

      await service.dispose();
    },
  );
}
