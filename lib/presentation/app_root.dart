import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../application/providers.dart';
import '../core/logging/app_logger.dart';
import '../domain/entities/storage_device.dart';
import '../domain/enums/storage_enums.dart';
import '../infrastructure/tray/app_tray_service.dart';
import 'components/device_presentation.dart';
import 'dashboard/dashboard_screen.dart';
import 'settings/settings_screen.dart';
import 'theme/app_theme.dart';
import 'widget/mini_monitor_view.dart';

final widgetModeActiveProvider = StateProvider<bool>((ref) => false);

/// Root-level navigator key so the system tray/menu-bar menu (which fires
/// from outside the widget tree, with no `BuildContext` of its own) can
/// still push the Settings screen the same way an in-app tap does.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key, required this.windowController});
  final dynamic windowController; // DesktopWindowController, kept loosely typed to avoid a cycle

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> with WidgetsBindingObserver, WindowListener {
  static const _tag = 'AppRoot';

  AppTrayService? _tray;
  bool _widgetModeSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray());
  }

  Future<void> _initTray() async {
    final tray = AppTrayService(
      onOpenDashboard: () async {
        // Always resolves to the full dashboard being visible and focused -
        // if the app happened to be in compact widget mode, that mode is
        // exited first rather than leaving the click looking like it did
        // nothing because the (correct, on-screen) widget window was
        // mistaken for "already open".
        await _syncWidgetMode(false);
        await windowManager.show();
        await windowManager.focus();
      },
      onPauseResume: () {
        final settings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .updateWith((s) => s.copyWith(monitoringEnabled: !settings.monitoringEnabled));
      },
      onOpenSettings: () async {
        await windowManager.show();
        await windowManager.focus();
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      },
      onRescan: () => ref.read(monitoringServiceProvider).rescan(),
      onQuit: () async {
        // Bypasses setPreventClose (see DesktopWindowController.initialize) -
        // this is the one deliberate "actually exit" path, distinct from
        // the close button's hide-to-tray behavior.
        await windowManager.destroy();
      },
    );
    try {
      await tray.initialize();
      _tray = tray;
      // ref.listen only fires on the *next* change, not the value already
      // current when the listener is registered - push what's already
      // known immediately so the tray doesn't sit on "Scanning for
      // drives…" until the next poll happens to change something.
      await _pushDeviceSummaryToTray(tray);
      await tray.setPaused(!ref.read(settingsProvider).monitoringEnabled);
    } catch (e) {
      // No system tray on this desktop environment (some minimal Linux
      // window managers lack one) - the app keeps working, just without a
      // tray icon; the widget mode toggle below is unaffected.
      AppLogger.instance.warning(_tag, 'Tray unavailable: $e');
    }
  }

  Future<void> _pushDeviceSummaryToTray(AppTrayService tray) async {
    final settings = ref.read(settingsProvider);
    final deviceList = ref.read(devicesProvider);
    var worst = TemperatureSeverity.normal;
    final summaries = <TrayDeviceSummary>[];
    for (final d in deviceList) {
      final presentation =
          DevicePresentation.of(d, settings.thresholdsFor(d.id), settings.temperatureUnit);
      summaries.add(TrayDeviceSummary(
        name: d.displayName,
        valueText: presentation.valueText,
        severity: presentation.severity,
      ));
      if (presentation.severity == TemperatureSeverity.critical) {
        worst = TemperatureSeverity.critical;
      } else if (presentation.severity == TemperatureSeverity.warning &&
          worst != TemperatureSeverity.critical) {
        worst = TemperatureSeverity.warning;
      }
    }
    await tray.updateDevices(summaries);
    await tray.updateSeverity(worst);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
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

  /// Enters/exits the compact always-on-top widget mode (spec section 21/28)
  /// in response to the Settings -> Desktop Widget -> "Enable mini monitor
  /// widget" toggle. This is the piece that was missing entirely before:
  /// the toggle only persisted a setting, nothing ever acted on it, so
  /// turning it on had no visible effect.
  Future<void> _syncWidgetMode(bool shouldBeActive) async {
    if (_widgetModeSyncInFlight) return;
    final alreadyActive = ref.read(widgetModeActiveProvider);
    if (shouldBeActive == alreadyActive) return;
    _widgetModeSyncInFlight = true;
    try {
      final settings = ref.read(settingsProvider);
      if (shouldBeActive) {
        await windowManager.show();
        await windowManager.focus();
        await widget.windowController.enterWidgetMode(settings.widget);
        ref.read(widgetModeActiveProvider.notifier).state = true;
      } else {
        final restored = await widget.windowController.exitWidgetMode(settings.widget);
        // Also clear the Settings toggle itself: "Expand" is the user
        // explicitly leaving widget mode, so the next launch should come up
        // as the normal dashboard, not silently re-enter widget mode
        // because the persisted setting was never updated.
        ref
            .read(settingsProvider.notifier)
            .updateWith((s) => s.copyWith(widget: restored.copyWith(enabled: false)));
        ref.read(widgetModeActiveProvider.notifier).state = false;
      }
    } finally {
      _widgetModeSyncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final widgetModeActive = ref.watch(widgetModeActiveProvider);

    // Side-effect listeners - deliberately in build() via ref.listen (the
    // documented Riverpod pattern for "react to a state change with an
    // imperative call"), not in a StreamSubscription set up once in
    // initState, so they always see the latest ref/settings.
    ref.listen<bool>(
      settingsProvider.select((s) => s.widget.enabled),
      (previous, enabled) => _syncWidgetMode(enabled),
    );
    ref.listen(settingsProvider, (previous, next) {
      _tray?.setPaused(!next.monitoringEnabled);
    });
    ref.listen<List<StorageDevice>>(devicesProvider, (previous, deviceList) {
      final tray = _tray;
      if (tray == null) return;
      _pushDeviceSummaryToTray(tray);
    });

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'DriveGuard',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: widgetModeActive
          ? MiniMonitorView(
              onExpand: () => _syncWidgetMode(false),
            )
          : const DashboardScreen(),
    );
  }
}
