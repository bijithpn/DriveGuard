import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../application/providers.dart';
import '../application/widget/mini_widget_snapshot.dart';
import '../core/logging/app_logger.dart';
import '../domain/entities/storage_device.dart';
import '../domain/enums/storage_enums.dart';
import '../infrastructure/tray/app_tray_service.dart';
import '../infrastructure/tray/desktop_window_controller.dart' show kWidgetChannel;
import 'components/device_presentation.dart';
import 'dashboard/dashboard_screen.dart';
import 'settings/settings_screen.dart';
import 'theme/app_theme.dart';

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
    // The mini-widget window is a separate Flutter engine/isolate (see
    // main()'s branch on WindowController.arguments) - this is how it
    // talks back to the main window, e.g. "the user clicked Expand, here's
    // where I was left". Registering here is also what completes the
    // channel's pairing (see kWidgetChannel's doc comment).
    kWidgetChannel.setMethodCallHandler(_handleWidgetChannelCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray());
  }

  Future<dynamic> _handleWidgetChannelCall(MethodCall call) async {
    switch (call.method) {
      case 'expand_requested':
        final raw = call.arguments;
        final geometry =
            raw is String && raw.isNotEmpty ? jsonDecode(raw) as Map<String, dynamic> : null;
        await _syncWidgetMode(false, geometry: geometry);
      case 'ready':
        // The widget just finished starting up and is asking for its
        // first snapshot - see MiniWidgetApp.initState's doc comment on
        // why this can't just wait for the next unrelated device/settings
        // change to happen to push one.
        await _pushSnapshotToMiniWindowIfActive();
    }
    return null;
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
        // Same reasoning as onOpenDashboard above: Settings is a full-size
        // screen and must never be pushed while the dashboard window is
        // still hidden behind the mini widget - exit widget mode first,
        // unconditionally.
        await _syncWidgetMode(false);
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
    // `ref.listen` (registered in build()) only fires on a *change* to
    // widget.enabled after this point - it never retroactively fires for
    // the value settings already had when loaded from disk. Without this,
    // a persisted "widget enabled" from a previous session sits inert:
    // the dashboard shows normally, and the user has to flip the Settings
    // switch off then on again before the mini widget actually appears.
    // Sync once, explicitly, against whatever was just loaded.
    await _syncWidgetMode(ref.read(settingsProvider).widget.enabled);
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
        id: d.id,
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

  /// Builds the same per-device data the tray uses, but shaped for - and
  /// sent to - the mini-widget window instead. A no-op if the widget isn't
  /// currently open (`DesktopWindowController.updateMiniWindowSnapshot`
  /// already guards this too; checked here first to skip the work).
  Future<void> _pushSnapshotToMiniWindowIfActive() async {
    if (!ref.read(widgetModeActiveProvider)) return;
    final settings = ref.read(settingsProvider);
    final deviceList = ref.read(devicesProvider);
    final snapshotDevices = <MiniWidgetDeviceSnapshot>[];
    for (final d in deviceList) {
      final presentation =
          DevicePresentation.of(d, settings.thresholdsFor(d.id), settings.temperatureUnit);
      snapshotDevices.add(MiniWidgetDeviceSnapshot(
        id: d.id,
        name: d.displayName,
        valueText: presentation.valueText,
        fraction: presentation.fraction,
        severity: presentation.severity,
      ));
    }
    await widget.windowController.updateMiniWindowSnapshot(
      MiniWidgetSnapshot(devices: snapshotDevices, compact: settings.widget.compact),
    );
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
  /// widget" toggle. The widget is a genuinely separate OS window (see
  /// DesktopWindowController/MiniWidgetApp) - this only opens/closes it and
  /// swaps which window is on screen, one at a time from the user's
  /// perspective, but the widget's own size can never again squeeze
  /// whatever the main window happens to be showing (e.g. Settings).
  Future<void> _syncWidgetMode(bool shouldBeActive, {Map<String, dynamic>? geometry}) async {
    if (_widgetModeSyncInFlight) return;
    final alreadyActive = ref.read(widgetModeActiveProvider);
    if (shouldBeActive == alreadyActive) return;
    _widgetModeSyncInFlight = true;
    try {
      final settings = ref.read(settingsProvider);
      if (shouldBeActive) {
        await widget.windowController.enterWidgetMode(settings.widget);
        ref.read(widgetModeActiveProvider.notifier).state = true;
        // The widget starts with an empty snapshot otherwise, until the
        // next device/settings change happens to fire.
        await _pushSnapshotToMiniWindowIfActive();
        await windowManager.hide();
      } else {
        final restored =
            await widget.windowController.exitWidgetMode(settings.widget, geometry: geometry);
        // Also clear the Settings toggle itself: "Expand" is the user
        // explicitly leaving widget mode, so the next launch should come up
        // as the normal dashboard, not silently re-enter widget mode
        // because the persisted setting was never updated.
        ref
            .read(settingsProvider.notifier)
            .updateWith((s) => s.copyWith(widget: restored.copyWith(enabled: false)));
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
