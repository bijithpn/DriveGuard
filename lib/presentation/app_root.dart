import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../infrastructure/native/native_widget_bridge.dart';
import '../infrastructure/tray/app_tray_service.dart';
import '../infrastructure/tray/desktop_window_controller.dart'
    show kWidgetChannel;
import 'components/device_presentation.dart';
import 'dashboard/dashboard_screen.dart';
import 'device_details/device_details_screen.dart';
import 'incidents/incident_report_screen.dart';
import 'incidents/startup_incident_dialog.dart';
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
  MiniWidgetSnapshot? _lastPushedSnapshot;
  MiniWidgetSnapshot? _lastNativeWidgetSnapshot;
  DateTime? _lastNativeWidgetPushAt;

  static const _nativeWidgetPushInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    widget.windowController.onCloseHandler = () async => onWindowClose();
    widget.windowController.onMinimizeHandler = () async => onWindowMinimize();

    kWidgetChannel.setMethodCallHandler(_handleWidgetChannelCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray());

    _notificationClickSub = ref
        .read(notificationServiceProvider)
        .deviceClicks
        .listen(_onNotificationClicked);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowStartupIncident(),
    );
  }

  Future<void> _maybeShowStartupIncident() async {
    final incident = ref.read(startupIncidentProvider);
    if (incident == null || !mounted) return;
    unawaited(
      ref
          .read(incidentRepositoryProvider)
          ?.markIncidentNotificationShown(incident.id),
    );
    await showStartupIncidentDialog(
      rootNavigatorKey.currentContext ?? context,
      incident,
      onViewReport: () {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => IncidentReportScreen(incidentId: incident.id),
          ),
        );
      },
    );
  }

  Future<void> _quitApp() async {
    try {
      await ref.read(monitoringServiceProvider).flushForShutdown();
    } catch (_) {}
    try {
      await ref.read(heartbeatServiceProvider).stop();
    } catch (_) {}
    try {
      await _tray?.destroy();
    } catch (_) {}
    exit(0);
  }

  Future<void> _onNotificationClicked(String deviceId) async {
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
        if (geometry != null) {
          final settings = ref.read(settingsProvider);
          final updated = settings.widget.copyWith(
            x: (geometry['x'] as num?)?.toDouble() ?? settings.widget.x,
            y: (geometry['y'] as num?)?.toDouble() ?? settings.widget.y,
            width:
                (geometry['width'] as num?)?.toDouble() ??
                settings.widget.width,
            height:
                (geometry['height'] as num?)?.toDouble() ??
                settings.widget.height,
          );
          ref
              .read(settingsProvider.notifier)
              .updateWith((s) => s.copyWith(widget: updated));
        }
        await windowManager.show();
        await windowManager.focus();
      case 'widget_closed':
        _lastPushedSnapshot = null;
        widget.windowController.clearMiniWindow();
        final raw = call.arguments;
        final geometry = raw is String && raw.isNotEmpty
            ? jsonDecode(raw) as Map<String, dynamic>
            : null;
        ref.read(widgetModeActiveProvider.notifier).state = false;
        ref.read(settingsProvider.notifier).updateWith((s) {
          var w = s.widget.copyWith(enabled: false);
          if (geometry != null) {
            w = w.copyWith(
              x: (geometry['x'] as num?)?.toDouble() ?? w.x,
              y: (geometry['y'] as num?)?.toDouble() ?? w.y,
              width: (geometry['width'] as num?)?.toDouble() ?? w.width,
              height: (geometry['height'] as num?)?.toDouble() ?? w.height,
            );
          }
          return s.copyWith(widget: w);
        });

        final isMainVisible = await windowManager.isVisible();
        final settings = ref.read(settingsProvider);
        if (!isMainVisible && (!settings.showTrayIcon || _tray == null)) {
          await windowManager.show();
          await windowManager.focus();
        }
      case 'ready':
        await widget.windowController.showMiniWindow();
        await _pushSnapshotToMiniWindowIfActive(force: true);
    }
    return null;
  }

  Future<void> _initTray() async {
    final settings = ref.read(settingsProvider);
    if (!settings.showTrayIcon) {
      await _syncWidgetMode(settings.widget.enabled);
      return;
    }

    final tray = AppTrayService(
      onOpenDashboard: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      onPauseResume: () {
        final currentSettings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .updateWith(
              (s) => s.copyWith(
                monitoringEnabled: !currentSettings.monitoringEnabled,
              ),
            );
      },
      onOpenSettings: () async {
        await windowManager.show();
        await windowManager.focus();
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      },
      onRescan: () => ref.read(monitoringServiceProvider).rescan(),
      onQuit: _quitApp,
    );
    try {
      await tray.initialize();
      _tray = tray;

      await _pushDeviceSummaryToTray(tray);
      await tray.setPaused(!settings.monitoringEnabled);
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Tray unavailable: $e');
    }

    await _syncWidgetMode(settings.widget.enabled);
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

  MiniWidgetSnapshot _buildSnapshot() {
    final settings = ref.read(settingsProvider);
    final deviceList = ref.read(devicesProvider);
    final snapshotDevices = <MiniWidgetDeviceSnapshot>[];
    final activityMap = ref.read(activityProvider);
    for (final d in deviceList) {
      final presentation = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      final activity = activityMap[d.id];
      final readSpeed = activity?.readBytesPerSecond != null
          ? '${(activity!.readBytesPerSecond! / (1024 * 1024)).toStringAsFixed(1)} MB/s'
          : null;
      final writeSpeed = activity?.writeBytesPerSecond != null
          ? '${(activity!.writeBytesPerSecond! / (1024 * 1024)).toStringAsFixed(1)} MB/s'
          : null;
      final freeCapacity = d.capacity.freeBytes != null
          ? '${(d.capacity.freeBytes! / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB free'
          : null;
      final lifePercent = d.health.percentageUsed != null
          ? (100 - d.health.percentageUsed!).clamp(0, 100)
          : null;
      final tbwBytes = d.health.totalBytesWritten;
      final tbwText = tbwBytes != null
          ? '${(tbwBytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TBW'
          : null;
      final powerOnHours = d.health.powerOnHours;
      final powerOnHoursText = powerOnHours != null
          ? '${powerOnHours}h on'
          : null;

      snapshotDevices.add(
        MiniWidgetDeviceSnapshot(
          id: d.id,
          name: d.displayName,
          valueText: presentation.valueText,
          fraction: presentation.fraction,
          severity: _combinedSeverity(d.id, presentation.severity),
          type: d.type,
          healthStatus: d.health.status.name.toUpperCase(),
          lifePercent: lifePercent,
          freeCapacityText: freeCapacity,
          readSpeedText: readSpeed,
          writeSpeedText: writeSpeed,
          tbwText: tbwText,
          powerOnHoursText: powerOnHoursText,
        ),
      );
    }
    return MiniWidgetSnapshot(
      devices: snapshotDevices,
      compact: settings.widget.compact,
    );
  }

  void _maybePushNativeWidgetSnapshot(
    MiniWidgetSnapshot snapshot, {
    bool force = false,
  }) {
    if (!force && snapshot == _lastNativeWidgetSnapshot) return;
    final now = DateTime.now();
    final last = _lastNativeWidgetPushAt;
    if (!force &&
        last != null &&
        now.difference(last) < _nativeWidgetPushInterval) {
      return;
    }
    _lastNativeWidgetSnapshot = snapshot;
    _lastNativeWidgetPushAt = now;
    unawaited(NativeWidgetBridge.pushSnapshot(snapshot));
  }

  Future<void> _pushSnapshotToMiniWindowIfActive({bool force = false}) async {
    final snapshot = _buildSnapshot();

    _maybePushNativeWidgetSnapshot(snapshot, force: force);

    if (!ref.read(widgetModeActiveProvider)) return;
    if (!force && _lastPushedSnapshot == snapshot) return;
    _lastPushedSnapshot = snapshot;

    await widget.windowController.updateMiniWindowSnapshot(snapshot);
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
    final isWidgetActive = ref.read(widgetModeActiveProvider);

    if (isWidgetActive || (settings.closeToTray && settings.showTrayIcon)) {
      await windowManager.hide();
    } else {
      await _quitApp();
    }
  }

  @override
  void onWindowMinimize() async {
    final settings = ref.read(settingsProvider);
    if (settings.minimizeToTray && settings.showTrayIcon) {
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
        final initialSnapshot = _buildSnapshot();
        await widget.windowController.enterWidgetMode(
          settings.widget,
          initialSnapshot: initialSnapshot,
        );
        ref.read(widgetModeActiveProvider.notifier).state = true;
        _lastPushedSnapshot = initialSnapshot;
      } else {
        _lastPushedSnapshot = null;
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
      if (previous?.showTrayIcon != next.showTrayIcon) {
        if (!next.showTrayIcon) {
          _tray?.destroy();
          _tray = null;
        } else if (_tray == null) {
          _initTray();
        }
      }
      _tray?.setPaused(!next.monitoringEnabled);
      _pushSnapshotToMiniWindowIfActive();
    });
    ref.listen<List<StorageDevice>>(devicesProvider, (previous, deviceList) {
      final tray = _tray;
      if (tray != null) _pushDeviceSummaryToTray(tray);
      _pushSnapshotToMiniWindowIfActive();
    });

    ref.listen(activityProvider, (previous, next) {
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
