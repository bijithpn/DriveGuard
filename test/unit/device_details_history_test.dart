import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driveguard/application/monitoring/temperature_history_store.dart';
import 'package:driveguard/application/providers.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/entities/temperature_reading.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/infrastructure/storage/mock_storage_monitor.dart';
import 'package:driveguard/presentation/device_details/device_details_screen.dart';

import '../mocks/fake_notification_service.dart';

class FakeDevicesNotifier extends DevicesNotifier {
  FakeDevicesNotifier(this.devices);
  final List<StorageDevice> devices;

  @override
  List<StorageDevice> build() => devices;
}

void main() {
  testWidgets(
    'DeviceDetailsScreen renders temperature history section with empty state',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testDevice = StorageDevice(
        id: 'test-disk',
        type: StorageDeviceType.nvme,
        interfaceType: StorageInterfaceType.nvme,
        sensorAvailability: SensorAvailability.available,
        model: 'Test NVMe Drive',
        primaryTemperature: TemperatureReading(
          celsius: 42.0,
          timestamp: DateTime.now(),
          source: const TemperatureSource(
            backendName: 'native',
            sensorId: 'composite',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageMonitorProvider.overrideWithValue(MockStorageMonitor()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            devicesProvider.overrideWith(
              () => FakeDevicesNotifier([testDevice]),
            ),
          ],
          child: const MaterialApp(
            home: DeviceDetailsScreen(deviceId: 'test-disk'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Temperature History'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);
      expect(find.text('24 hours'), findsOneWidget);
      expect(find.textContaining('readings'), findsOneWidget);
    },
  );

  testWidgets(
    'DeviceDetailsScreen renders history chart and metrics pills when samples exist',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final historyStore = TemperatureHistoryStore();
      // Record multiple samples across the past 30 minutes
      for (int i = 30; i >= 0; i--) {
        final t = now.subtract(Duration(minutes: i));
        final celsius = 40.0 + (i % 5);
        historyStore.record(
          'test-disk',
          TemperatureReading(
            celsius: celsius,
            timestamp: t,
            source: const TemperatureSource(
              backendName: 'native',
              sensorId: 'composite',
            ),
          ),
        );
      }

      final testDevice = StorageDevice(
        id: 'test-disk',
        type: StorageDeviceType.nvme,
        interfaceType: StorageInterfaceType.nvme,
        sensorAvailability: SensorAvailability.available,
        model: 'Test NVMe Drive',
        primaryTemperature: TemperatureReading(
          celsius: 42.0,
          timestamp: now,
          source: const TemperatureSource(
            backendName: 'native',
            sensorId: 'composite',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageMonitorProvider.overrideWithValue(MockStorageMonitor()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            historyStoreProvider.overrideWithValue(historyStore),
            devicesProvider.overrideWith(
              () => FakeDevicesNotifier([testDevice]),
            ),
          ],
          child: const MaterialApp(
            home: DeviceDetailsScreen(deviceId: 'test-disk'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify showcase metric pills exist
      expect(find.textContaining('Current: '), findsWidgets);
      expect(find.textContaining('Min: '), findsWidgets);
      expect(find.textContaining('Avg: '), findsWidgets);
      expect(find.textContaining('Peak: '), findsWidgets);
      expect(find.textContaining('Trend: '), findsWidgets);

      // Verify legend exists
      expect(find.textContaining('Warning: '), findsWidgets);
      expect(find.textContaining('Critical: '), findsWidgets);

      // Verify grid showcase toggle exists and functions
      expect(find.text('Grid on'), findsOneWidget);
      await tester.tap(find.text('Grid on'));
      await tester.pumpAndSettle();
      expect(find.text('Grid off'), findsOneWidget);
      await tester.tap(find.text('Grid off'));
      await tester.pumpAndSettle();
      expect(find.text('Grid on'), findsOneWidget);
    },
  );
}
