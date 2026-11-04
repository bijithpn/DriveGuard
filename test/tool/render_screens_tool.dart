// Developer tool (not part of the suite): renders key screens to PNG files so
// layout/spacing can be reviewed visually.
//   flutter test test/tool/render_screens_tool.dart --dart-define=OUT=/path
import 'dart:io';
import 'dart:ui' as ui;

import 'package:driveguard/application/protection/thermal_models.dart';
import 'package:driveguard/application/providers.dart';
import 'package:driveguard/application/storage_sense/cleanup_scanner.dart'
    show ScanProgress;
import 'package:driveguard/application/storage_sense/storage_sense_controller.dart';
import 'package:driveguard/domain/entities/cleanup_item.dart';
import 'package:driveguard/domain/entities/device_health.dart';
import 'package:driveguard/domain/entities/temperature_reading.dart';
import 'package:driveguard/domain/entities/storage_activity.dart';
import 'package:driveguard/domain/entities/storage_capacity.dart';
import 'package:driveguard/domain/entities/shutdown_incident.dart';
import 'package:driveguard/domain/enums/incident_enums.dart';
import 'package:driveguard/presentation/incidents/incident_history_screen.dart';
import 'package:driveguard/presentation/incidents/incident_report_screen.dart';
import 'package:driveguard/domain/entities/storage_device.dart';
import 'package:driveguard/domain/entities/storage_volume.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/infrastructure/storage/mock_storage_monitor.dart';
import 'package:driveguard/presentation/dashboard/dashboard_screen.dart';
import 'package:driveguard/presentation/device_details/device_details_screen.dart';
import 'package:driveguard/presentation/settings/settings_screen.dart';
import 'package:driveguard/presentation/storage_sense/storage_sense_screen.dart';
import 'package:driveguard/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_notification_service.dart';

const _out = String.fromEnvironment('OUT', defaultValue: '/tmp/shots');
const _gb = 1024 * 1024 * 1024;

class _Seed extends DevicesNotifier {
  _Seed(this.devices);
  final List<StorageDevice> devices;
  @override
  List<StorageDevice> build() => devices;
}

class _SeedActivity extends ActivityNotifier {
  _SeedActivity(this.a);
  final StorageActivity a;
  @override
  Map<String, StorageActivity> build() => {a.deviceId: a};
}

class _SeedScanning extends _SeedSense {
  @override
  StorageSenseState build() => super.build().copyWith(
    status: SenseStatus.scanning,
    progress: 0.42,
    scanProgress: const ScanProgress(
      done: 21,
      total: 50,
      current: 'App cache: com.google.Chrome',
      foundBytes: 14 * 1024 * 1024 * 1024,
    ),
  );
}

class _SeedSense extends StorageSenseController {
  @override
  StorageSenseState build() => StorageSenseState(
    status: SenseStatus.ready,
    hasScanned: true,
    reclaimedBytes: 6 * _gb,
    items: [
      CleanupItem(
        id: 'a',
        name: 'Xcode DerivedData',
        description: 'Build products and indexes. Xcode regenerates them.',
        path: '/x/a',
        safety: CleanupSafety.safe,
        category: CleanupCategory.developer,
        sizeBytes: 14 * _gb,
        lastModified: DateTime.now().subtract(const Duration(days: 90)),
      ),
      const CleanupItem(
        id: 'b',
        name: 'iOS Simulators',
        description: 'Simulator devices and their data. Deleting resets them.',
        path: '/x/b',
        safety: CleanupSafety.review,
        category: CleanupCategory.developer,
        sizeBytes: 9 * _gb,
      ),
      const CleanupItem(
        id: 'c',
        name: 'Gradle caches',
        description: 'Build caches. Rebuilt on the next Gradle build.',
        path: '/x/c',
        safety: CleanupSafety.safe,
        category: CleanupCategory.developer,
        sizeBytes: 4 * _gb,
      ),
      const CleanupItem(
        id: 'd',
        name: 'App cache: Google',
        description: 'Temporary files apps rebuild when needed.',
        path: '/x/d',
        safety: CleanupSafety.safe,
        category: CleanupCategory.systemCaches,
        sizeBytes: 2 * _gb,
      ),
      const CleanupItem(
        id: 'e',
        name: 'System caches',
        description: 'Shared caches for all users. Rebuilt automatically.',
        path: '/x/e',
        safety: CleanupSafety.safe,
        category: CleanupCategory.systemCaches,
        sizeBytes: 800 * 1024 * 1024,
        requiresAdmin: true,
      ),
      const CleanupItem(
        id: 'f',
        name: 'movie.mkv',
        description:
            'Personal file in Downloads. Only you know if you need it.',
        path: '/x/f',
        safety: CleanupSafety.manual,
        category: CleanupCategory.downloads,
        sizeBytes: 3 * _gb,
      ),
      const CleanupItem(
        id: 'g',
        name: 'node_modules',
        description: 'Installed npm packages.',
        path: '/x/g',
        safety: CleanupSafety.safe,
        category: CleanupCategory.projects,
        sizeBytes: 1 * _gb,
        project: 'web-app',
      ),
    ],
  );
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 900));
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await t.runAsync(() async {
    final ui.Image img = await boundary.toImage(pixelRatio: 1.25);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<StorageDevice>> devices() async {
    final m = MockStorageMonitor();
    final out = <StorageDevice>[];
    for (final d in await m.getDevices()) {
      out.add(
        d.copyWith(
          primaryTemperature: await m.readTemperature(d.id),
          health: await m.getHealth(d.id),
          capacity: await m.getCapacity(d.id),
          volumes: await m.getVolumes(d.id),
          monitoringStatus: MonitoringStatusX.active,
        ),
      );
    }
    return out;
  }

  Future<void> boot(
    WidgetTester t,
    Widget home, {
    Size size = const Size(1180, 780),
    List<Override> extra = const [],
  }) async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
    await t.runAsync(font.load);
    final icons = FontLoader('MaterialIcons');
    final root =
        Platform.environment['FLUTTER_ROOT'] ??
        '/Users/intersamrt/Documents/flutter';
    final f = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) {
      icons.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await t.runAsync(icons.load);
    }
    final devs = await t.runAsync(devices);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          storageMonitorProvider.overrideWithValue(MockStorageMonitor()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          devicesProvider.overrideWith(() => _Seed(devs!)),
          ...extra,
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: RepaintBoundary(child: home),
          ),
        ),
      ),
    );
  }

  testWidgets('dashboard', (t) async {
    await boot(t, const DashboardScreen());
    await _shot(t, 'dashboard');
  });
  testWidgets('alerts', (t) async {
    await boot(
      t,
      const DashboardScreen(),
      size: const Size(1180, 980),
      extra: [
        thermalProtectionStateProvider.overrideWith(
          (ref) => Stream.value(
            const ThermalProtectionState(
              stage: ThermalStage.emergency,
              deviceId: 'mock-nvme-1',
              deviceName: 'Samsung 990 PRO 1TB',
              celsius: 78,
              message: 'Stayed at or above 75°C',
              countdown: Duration(seconds: 42),
              shutdownScheduled: true,
              cause: ThermalCause(
                kind: ThermalCauseKind.heavyWrites,
                headline: 'Heavy disk writes (412 MB/s) from ffmpeg',
                detail:
                    'The drive is being written to continuously, which keeps the controller and NAND under constant load.',
                secondary: ['Drive is 91% full'],
                culprit: ProcessSample(
                  pid: 4411,
                  name: 'ffmpeg',
                  cpuPercent: 84,
                  user: 'me',
                  rssBytes: 2 * _gb,
                ),
                culpritMeasured: true,
                advice: [
                  'Pause the large copy, download, backup or render that is running.',
                  'Resume it later in smaller batches so the drive can cool between them.',
                ],
              ),
            ),
          ),
        ),
        resourceAlertsProvider.overrideWith(
          (ref) => Stream.value(const [
            ResourceAlert(
              id: 'memory',
              kind: ResourceAlertKind.memoryPressure,
              severity: ResourceSeverity.warning,
              title: 'Memory is running low',
              detail:
                  '7% of memory is available. 5.2 GB is swapped to the SSD. When RAM runs out the system keeps writing memory pages to your SSD, which slows everything down and wears the drive. Biggest memory user: Chrome (3.1 GB).',
              culprit: ProcessSample(
                pid: 99,
                name: 'Chrome',
                cpuPercent: 12,
                user: 'me',
                rssBytes: 3 * _gb,
              ),
              advice: [
                'Quit the biggest memory user or close unused apps and browser tabs.',
              ],
            ),
          ]),
        ),
      ],
    );
    await t.pump(const Duration(milliseconds: 100));
    debugPrint(
      'FOUND memory=${find.text('Memory is running low').evaluate().length} thermal=${find.textContaining('overheating').evaluate().length}',
    );
    await _shot(t, 'alerts');
  });
  testWidgets('details', (t) async {
    await boot(t, const DeviceDetailsScreen(deviceId: 'mock-nvme-1'));
    await _shot(t, 'details');
  });
  for (final name in ['health', 'storage', 'diagnostics']) {
    testWidgets('tab_$name', (t) async {
      await boot(t, const DeviceDetailsScreen(deviceId: 'mock-nvme-1'));
      await t.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text(name[0].toUpperCase() + name.substring(1)),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
      await _shot(t, 'tab_$name');
    });
  }
  testWidgets('storage_full', (t) async {
    final m = MockStorageMonitor();
    final base = (await t.runAsync(() => m.getDevices()))!.first;
    final dev = base.copyWith(
      primaryTemperature: await t.runAsync<TemperatureReading?>(
        () => m.readTemperature(base.id),
      ),
      health: (await t.runAsync<DeviceHealth?>(() => m.getHealth(base.id)))!,
      monitoringStatus: MonitoringStatus.active,
      capacity: const StorageCapacity(
        availability: SensorAvailability.available,
        totalBytes: 1000 * 1000 * 1000 * 1000,
        usedBytes: 880 * 1000 * 1000 * 1000,
        freeBytes: 120 * 1000 * 1000 * 1000,
      ),
      volumes: const [
        StorageVolume(
          id: 'v1',
          mountPoint: '/',
          volumeName: 'Macintosh HD',
          filesystem: 'APFS',
          isBootVolume: true,
          isEncrypted: true,
          totalBytes: 994 * 1000 * 1000 * 1000,
          usedBytes: 640 * 1000 * 1000 * 1000,
          freeBytes: 354 * 1000 * 1000 * 1000,
        ),
        StorageVolume(
          id: 'v2',
          mountPoint: '/Volumes/Data',
          volumeName: 'Data',
          filesystem: 'APFS',
          totalBytes: 500 * 1000 * 1000 * 1000,
          usedBytes: 480 * 1000 * 1000 * 1000,
          freeBytes: 20 * 1000 * 1000 * 1000,
        ),
        StorageVolume(
          id: 'v3',
          mountPoint: '/Volumes/Recovery',
          volumeName: 'Recovery',
          filesystem: 'APFS',
          isReadOnly: true,
          totalBytes: 5 * 1000 * 1000 * 1000,
        ),
      ],
    );
    await boot(
      t,
      const DeviceDetailsScreen(deviceId: 'mock-nvme-1'),
      size: const Size(1180, 900),
      extra: [
        devicesProvider.overrideWith(() => _Seed([dev])),
        activityProvider.overrideWith(
          () => _SeedActivity(
            StorageActivity(
              deviceId: base.id,
              timestamp: DateTime.now(),
              availability: SensorAvailability.available,
              readBytesPerSecond: 412 * 1024 * 1024,
              writeBytesPerSecond: 38 * 1024 * 1024,
              readOperationsPerSecond: 5200,
              writeOperationsPerSecond: 640,
              utilizationPercent: 42,
            ),
          ),
        ),
      ],
    );
    await t.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Storage')),
    );
    await t.pump(const Duration(milliseconds: 600));
    await _shot(t, 'tab_storage_full');
  });
  testWidgets('settings', (t) async {
    await boot(t, const SettingsScreen());
    await _shot(t, 'settings');
  });
  testWidgets('tray_settings', (t) async {
    await boot(t, const SettingsScreen());
    await t.tap(find.text(Platform.isMacOS ? 'Menu bar' : 'Tray').first);
    await t.pump(const Duration(milliseconds: 400));
    await _shot(t, 'tray_settings');
  });
  final incidents = [
    for (final (i, c, k) in [
      (0, CorrelationLevel.high, ShutdownClassification.osShutdownUnexpected),
      (3, CorrelationLevel.moderate, ShutdownClassification.possiblePowerLoss),
      (9, CorrelationLevel.none, ShutdownClassification.cleanAppExit),
      (21, CorrelationLevel.low, ShutdownClassification.kernelPanic),
    ])
      ShutdownIncident(
        id: 'i$i',
        sessionId: 's$i',
        detectedAt: DateTime(2026, 11, 4 - i.clamp(0, 3), 14, 20),
        classification: k,
        correlationLevel: c,
        summary: 'Shutdown detected after a rise in temperature.',
        primaryDeviceId: 'd',
        deviceStats: [
          DeviceIncidentStat(
            deviceId: 'd',
            deviceName: 'Samsung 990 PRO 1TB',
            lastCelsius: 62.0 + i,
            maxCelsius: 71,
            warningExceeded: true,
          ),
        ],
      ),
  ];
  testWidgets('incidents', (t) async {
    await boot(
      t,
      const IncidentHistoryScreen(),
      extra: [incidentListProvider.overrideWith((ref) async => incidents)],
    );
    await _shot(t, 'incidents');
  });
  testWidgets('incident_report', (t) async {
    await boot(
      t,
      const IncidentReportScreen(incidentId: 'i0'),
      extra: [
        incidentDetailProvider.overrideWith((ref, id) async => incidents.first),
      ],
    );
    await _shot(t, 'incident_report');
  });
  testWidgets('sense_scanning', (t) async {
    await boot(
      t,
      const StorageSenseScreen(),
      extra: [storageSenseProvider.overrideWith(_SeedScanning.new)],
    );
    await _shot(t, 'sense_scanning');
  });
  testWidgets('sense', (t) async {
    await boot(
      t,
      const StorageSenseScreen(),
      extra: [storageSenseProvider.overrideWith(_SeedSense.new)],
    );
    await _shot(t, 'sense');
  });
}

// Alias so the tool reads clearly.
// ignore: avoid_classes_with_only_static_members
class MonitoringStatusX {
  static const active = MonitoringStatus.active;
}
