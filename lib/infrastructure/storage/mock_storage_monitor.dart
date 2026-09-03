import 'dart:async';
import 'dart:math';

import '../../core/errors/storage_exceptions.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';

class MockStorageMonitor implements StorageMonitor {
  MockStorageMonitor({Random? random}) : _random = random ?? Random(7);

  final Random _random;
  final _MockDeviceState _nvme = _MockDeviceState(
    id: 'mock-nvme-1',
    baseline: 42,
    amplitude: 6,
    periodSeconds: 90,
  );
  final _MockDeviceState _sataSsd = _MockDeviceState(
    id: 'mock-sata-ssd-1',
    baseline: 35,
    amplitude: 4,
    periodSeconds: 140,
  );
  final _MockDeviceState _hdd = _MockDeviceState(
    id: 'mock-hdd-1',
    baseline: 38,
    amplitude: 5,
    periodSeconds: 200,
  );

  bool _usbConnected = true;
  final DateTime _start = DateTime.now();

  void forceTemperature(String deviceId, double celsius) {
    for (final s in [_nvme, _sataSsd, _hdd]) {
      if (s.id == deviceId) s.override = celsius;
    }
  }

  void setUsbConnected(bool connected) => _usbConnected = connected;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BackendCapabilities> getCapabilities() async =>
      const BackendCapabilities(
        backendName: 'Mock',
        canEnumerateDevices: true,
        canReadTemperature: true,
        canReadHealth: true,
        notes: ['Simulated devices for development/demo - not real hardware.'],
      );

  @override
  Future<List<StorageDevice>> getDevices() async {
    final devices = <StorageDevice>[
      StorageDevice(
        id: _nvme.id,
        type: StorageDeviceType.nvme,
        interfaceType: StorageInterfaceType.nvme,
        sensorAvailability: SensorAvailability.available,
        model: 'Samsung 990 PRO 1TB',
        manufacturer: 'Samsung',
        serialNumber: 'MOCKSN0001',
        capacityBytes: 1000000000000,
      ),
      StorageDevice(
        id: _sataSsd.id,
        type: StorageDeviceType.ssd,
        interfaceType: StorageInterfaceType.sata,
        sensorAvailability: SensorAvailability.available,
        model: 'WD Blue 3D NAND 500GB',
        manufacturer: 'Western Digital',
        serialNumber: 'MOCKSN0002',
        capacityBytes: 500000000000,
      ),
      StorageDevice(
        id: _hdd.id,
        type: StorageDeviceType.hdd,
        interfaceType: StorageInterfaceType.sata,
        sensorAvailability: SensorAvailability.available,
        model: 'Seagate Barracuda 2TB',
        manufacturer: 'Seagate',
        serialNumber: 'MOCKSN0003',
        capacityBytes: 2000000000000,
      ),
    ];
    if (_usbConnected) {
      devices.add(
        const StorageDevice(
          id: 'mock-usb-hdd-1',
          type: StorageDeviceType.hdd,
          interfaceType: StorageInterfaceType.usb,
          sensorAvailability: SensorAvailability.unsupported,
          model: 'Generic USB 3.0 Enclosure',
          manufacturer: null,
          serialNumber: 'MOCKSN0004',
          capacityBytes: 4000000000000,
          isRemovable: true,
        ),
      );
    }
    return devices;
  }

  @override
  Future<TemperatureReading?> readTemperature(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    if (deviceId == 'mock-usb-hdd-1') {
      return null;
    }
    final state = [_nvme, _sataSsd, _hdd].firstWhere(
      (s) => s.id == deviceId,
      orElse: () => throw DeviceNotFoundException(deviceId),
    );
    final celsius = state.sample(DateTime.now().difference(_start), _random);
    return TemperatureReading(
      celsius: celsius,
      timestamp: DateTime.now(),
      source: const TemperatureSource(
        backendName: 'Mock',
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
      StorageSensor(
        id: 'sensor-2',
        name: 'Sensor 2',
        reading: reading.copyWith(celsius: reading.celsius - 3),
        type: TemperatureSensorType.namespace,
      ),
    ];
  }

  @override
  Future<DeviceHealth?> getHealth(String deviceId) async {
    if (deviceId == 'mock-usb-hdd-1') return DeviceHealth.unavailable;
    return const DeviceHealth(
      status: DeviceHealthStatus.healthy,
      percentageUsed: 4,
      availableSparePercent: 100,
      criticalWarning: '0x00',
      mediaErrors: 0,
      powerCycles: 128,
      powerOnHours: 940,
      unsafeShutdowns: 2,
      smartPassed: true,
    );
  }
}

class _MockDeviceState {
  _MockDeviceState({
    required this.id,
    required this.baseline,
    required this.amplitude,
    required this.periodSeconds,
  });

  final String id;
  final double baseline;
  final double amplitude;
  final int periodSeconds;
  double? override;

  double sample(Duration elapsed, Random random) {
    if (override != null) {
      final v = override!;
      override = null;
      return v;
    }
    final phase = (elapsed.inSeconds % periodSeconds) / periodSeconds;
    final wave = sin(phase * 2 * pi) * amplitude;
    final noise = (random.nextDouble() - 0.5) * 0.6;
    return baseline + wave + noise;
  }
}
