import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../application/providers.dart';
import '../application/widget/mini_widget_snapshot.dart';
import '../core/logging/app_logger.dart';
import '../domain/entities/storage_device.dart';
import '../domain/entities/storage_thresholds.dart';
import '../domain/enums/storage_enums.dart';
import '../infrastructure/tray/app_tray_service.dart';
import '../infrastructure/tray/desktop_window_controller.dart'
    show kWidgetChannel;
import 'components/device_presentation.dart';
import 'dashboard/dashboard_screen.dart';
import 'device_details/device_details_screen.dart';
import 'settings/settings_screen.dart';
import 'theme/app_theme.dart';

final widgetModeActiveProvider = StateProvider<bool>((ref) => false);

final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key, required this.windowController});
  final dynamic windowController;

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot>
    with WidgetsBindingObserver, WindowListener {
  static const _tag = 'AppRoot';

  AppTrayService? _tray;
  bool _widgetModeSyncInFlight = false;
  StreamSubscription<String>? _notificationClickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);

    kWidgetChannel.setMethodCallHandler(_handleWidgetChannelCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray());

    _notificationClickSub = ref
        .read(notificationServiceProvider)
        .deviceClicks
        .listen(_onNotificationClicked);
  }

  Future<void> _onNotificationClicked(String deviceId) async {
    await _syncWidgetMode(false);
    await windowManager.show();
    await windowManager.focus();
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceDetailsScreen(deviceId: deviceId),
      ),
    );
  }

  Future<dynamic> _handleWidgetChannelCall(MethodCall call) async {
    switch (call.method) {
      case 'expand_requested':
        final raw = call.arguments;
        final geometry = raw is String && raw.isNotEmpty
            ? jsonDecode(raw) as Map<String, dynamic>
            : null;
        await _syncWidgetMode(false, geometry: geometry);
      case 'ready':
        await _pushSnapshotToMiniWindowIfActive();
    }
    return null;
  }

  Future<void> _initTray() async {
    final tray = AppTrayService(
      onOpenDashboard: () async {
        await _syncWidgetMode(false);
        await windowManager.show();
        await windowManager.focus();
      },
      onPauseResume: () {
        final settings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .updateWith(
              (s) => s.copyWith(monitoringEnabled: !settings.monitoringEnabled),
            );
      },
      onOpenSettings: () async {
        await _syncWidgetMode(false);
        await windowManager.show();
        await windowManager.focus();
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      },
      onRescan: () => ref.read(monitoringServiceProvider).rescan(),
      onQuit: () async {
        await windowManager.destroy();
      },
    );
    try {
      await tray.initialize();
      _tray = tray;

      await _pushDeviceSummaryToTray(tray);
      await tray.setPaused(!ref.read(settingsProvider).monitoringEnabled);
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Tray unavailable: $e');
    }

    await _syncWidgetMode(ref.read(settingsProvider).widget.enabled);
  }

  TemperatureSeverity _combinedSeverity(
    String deviceId,
    TemperatureSeverity tempSeverity,
  ) {
    final service = ref.read(monitoringServiceProvider);
    final capacitySeverity = service.capacitySeverityFor(deviceId);
    var result = tempSeverity;
    if (capacitySeverity == CapacitySeverity.critical) {
      result = TemperatureSeverity.critical;
    } else if (capacitySeverity == CapacitySeverity.warning &&
        result != TemperatureSeverity.critical) {
      result = TemperatureSeverity.warning;
    }
    if (service.rapidRiseActiveFor(deviceId) &&
        result != TemperatureSeverity.critical) {
      result = TemperatureSeverity.warning;
    }
    return result;
  }

  Future<void> _pushDeviceSummaryToTray(AppTrayService tray) async {
    final settings = ref.read(settingsProvider);
    final deviceList = ref.read(devicesProvider);
    var worst = TemperatureSeverity.normal;
    final summaries = <TrayDeviceSummary>[];
    for (final d in deviceList) {
      final presentation = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      final severity = _combinedSeverity(d.id, presentation.severity);
      summaries.add(
        TrayDeviceSummary(
          id: d.id,
          name: d.displayName,
          valueText: presentation.valueText,
          severity: severity,
        ),
      );
      if (severity == TemperatureSeverity.critical) {
        worst = TemperatureSeverity.critical;
      } else if (severity == TemperatureSeverity.warning &&
          worst != TemperatureSeverity.critical) {
        worst = TemperatureSeverity.warning;
      }
    }
    await tray.updateDevices(summaries);
    await tray.updateSeverity(worst);
  }

  Future<void> _pushSnapshotToMiniWindowIfActive() async {
    if (!ref.read(widgetModeActiveProvider)) return;
    final settings = ref.read(settingsProvider);
    final deviceList = ref.read(devicesProvider);
    final snapshotDevices = <MiniWidgetDeviceSnapshot>[];
    for (final d in deviceList) {
      final presentation = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      snapshotDevices.add(
        MiniWidgetDeviceSnapshot(
          id: d.id,
          name: d.displayName,
          valueText: presentation.valueText,
          fraction: presentation.fraction,
          severity: _combinedSeverity(d.id, presentation.severity),
        ),
      );
    }
    await widget.windowController.updateMiniWindowSnapshot(
      MiniWidgetSnapshot(
        devices: snapshotDevices,
        compact: settings.widget.compact,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    unawaited(_notificationClickSub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(monitoringServiceProvider).reinitializeAfterResume();
    }
  }

  @override
  void onWindowClose() async {
    final settings = ref.read(settingsProvider);
    if (settings.closeToTray) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void onWindowMinimize() async {
    final settings = ref.read(settingsProvider);
    if (settings.minimizeToTray) {
      await windowManager.hide();
    }
  }

  Future<void> _syncWidgetMode(
    bool shouldBeActive, {
    Map<String, dynamic>? geometry,
  }) async {
    if (_widgetModeSyncInFlight) return;
    final alreadyActive = ref.read(widgetModeActiveProvider);
    if (shouldBeActive == alreadyActive) return;
    _widgetModeSyncInFlight = true;
    try {
      final settings = ref.read(settingsProvider);
      if (shouldBeActive) {
        await widget.windowController.enterWidgetMode(settings.widget);
        ref.read(widgetModeActiveProvider.notifier).state = true;

        await _pushSnapshotToMiniWindowIfActive();
      } else {
        final restored = await widget.windowController.exitWidgetMode(
          settings.widget,
          geometry: geometry,
        );

        ref
            .read(settingsProvider.notifier)
            .updateWith(
              (s) => s.copyWith(widget: restored.copyWith(enabled: false)),
            );
        ref.read(widgetModeActiveProvider.notifier).state = false;
        await windowManager.show();
        await windowManager.focus();
      }
    } finally {
      _widgetModeSyncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    ref.listen<bool>(
      settingsProvider.select((s) => s.widget.enabled),
      (previous, enabled) => _syncWidgetMode(enabled),
    );
    ref.listen(settingsProvider, (previous, next) {
      _tray?.setPaused(!next.monitoringEnabled);
      _pushSnapshotToMiniWindowIfActive();
    });
    ref.listen<List<StorageDevice>>(devicesProvider, (previous, deviceList) {
      final tray = _tray;
      if (tray != null) _pushDeviceSummaryToTray(tray);
      _pushSnapshotToMiniWindowIfActive();
    });

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'DriveGuard',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const DashboardScreen(),
    );
  }
}
