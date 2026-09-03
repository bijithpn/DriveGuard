import 'package:driveguard/application/monitoring/monitoring_service.dart';
import 'package:driveguard/application/monitoring/temperature_history_store.dart';
import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/core/errors/storage_exceptions.dart';
import 'package:driveguard/domain/entities/device_health.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/entities/temperature_reading.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/repositories/storage_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_notification_service.dart';

/// A tiny scriptable [StorageMonitor] so monitoring-service behaviour
/// (failure isolation, discovery, alerts) can be tested without spinning
/// up real timers or touching the OS.
class _ScriptedMonitor implements StorageMonitor {
  List<StorageDevice> devices;
  final Map<String, Object> nextReadingOrError = {};

  _ScriptedMonitor(this.devices);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BackendCapabilities> getCapabilities() async => const BackendCapabilities(
        backendName: 'scripted',
        canEnumerateDevices: true,
        canReadTemperature: true,
        canReadHealth: true,
      );

  @override
  Future<List<StorageDevice>> getDevices() async => devices;

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    final scripted = nextReadingOrError[deviceId];
    if (scripted is StorageMonitorException) throw scripted;
    if (scripted is double) {
      return TemperatureReading(
        celsius: scripted,
        timestamp: DateTime.now(),
        source: const TemperatureSource(backendName: 'scripted', sensorId: 'composite'),
      );
    }
    return null;
  }

  @override
  Future<List<StorageSensor>> getSensors(String deviceId) async => const [];

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async => DeviceHealth.unavailable;
}

StorageDevice _device(String id) => StorageDevice(
      id: id,
      type: StorageDeviceType.nvme,
      interfaceType: StorageInterfaceType.nvme,
      sensorAvailability: SensorAvailability.unavailable,
      model: id,
    );

void main() {
  test('a failing device does not stop other devices from being polled', () async {
    final backend = _ScriptedMonitor([_device('good'), _device('bad')]);
    backend.nextReadingOrError['good'] = 42.0;
    backend.nextReadingOrError['bad'] = const PermissionDeniedException('bad');

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
    expect(devices['bad']!.sensorAvailability, SensorAvailability.permissionDenied);
    expect(devices['bad']!.monitoringStatus, MonitoringStatus.permissionDenied);

    await service.dispose();
  });

  test('a null reading is reported as unavailable, never fabricated as 0', () async {
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
  });

  test('device disconnect is reflected, then removed after the next scan if still absent', () async {
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
    expect(service.currentDevices.single.monitoringStatus, MonitoringStatus.disconnected);

    await service.rescan();
    expect(service.currentDevices, isEmpty);

    await service.dispose();
  });

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
    expect(service.currentDevices.single.monitoringStatus, MonitoringStatus.disconnected);

    backend.devices = [device];
    await service.rescan();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.currentDevices.single.monitoringStatus, isNot(MonitoringStatus.disconnected));

    await service.dispose();
  });
}
