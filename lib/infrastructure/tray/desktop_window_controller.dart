import 'dart:convert';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart';
import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';

const kWidgetChannel = WindowMethodChannel('driveguard.widget');
const kEdgeDockChannel = WindowMethodChannel('driveguard.edgedock');

const kWidgetMinimumSize = Size(260, 220);

class DesktopWindowController with WindowListener {
  static const _tag = 'DesktopWindowController';
  static const Size _defaultDashboardSize = Size(1100, 760);
  static const Size _dashboardMinimumSize = Size(720, 480);

  WindowController? _miniWindow;
  WindowController? _edgeDockWindow;
  // In-flight creation guards: two rapid settings changes used to each pass
  // the "no window yet" check while the first create was still awaiting,
  // spawning duplicate dock/widget windows (the stray black bars).
  Future<void>? _miniOpening;
  Future<void>? _edgeDockOpening;
  Future<void> Function()? onCloseHandler;
  Future<void> Function()? onMinimizeHandler;

  bool get isMiniWindowOpen => _miniWindow != null;
  bool get isEdgeDockOpen => _edgeDockWindow != null;

  void clearMiniWindow() {
    _miniWindow = null;
  }

  Future<void> showMiniWindow() async {
    try {
      await _miniWindow?.show();
    } catch (_) {}
  }

  Future<void> initialize({required bool startMinimized}) async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    const options = WindowOptions(
      size: _defaultDashboardSize,
      minimumSize: _dashboardMinimumSize,
      center: true,
      titleBarStyle: TitleBarStyle.normal,
      title: 'DriveGuard',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (!startMinimized) {
        await windowManager.show();
        await windowManager.focus();
      } else {
        await windowManager.minimize();
      }
    });

    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() async {
    if (onCloseHandler != null) {
      await onCloseHandler!();
    } else {
      await windowManager.hide();
    }
  }

  @override
  void onWindowMinimize() async {
    if (onMinimizeHandler != null) {
      await onMinimizeHandler!();
    }
  }

  Future<void> enterWidgetMode(
    WidgetSettings widgetSettings, {
    MiniWidgetSnapshot? initialSnapshot,
  }) {
    return _miniOpening ??= _enterWidgetMode(
      widgetSettings,
      initialSnapshot,
    ).whenComplete(() => _miniOpening = null);
  }

  Future<void> _enterWidgetMode(
    WidgetSettings widgetSettings,
    MiniWidgetSnapshot? initialSnapshot,
  ) async {
    if (_miniWindow != null) {
      try {
        final windows = await WindowController.getAll();
        if (!windows.any((w) => w.windowId == _miniWindow!.windowId)) {
          _miniWindow = null;
        }
      } catch (_) {
        _miniWindow = null;
      }
    }
    if (_miniWindow != null) {
      try {
        await _miniWindow!.show();
      } catch (_) {}
      return;
    }
    try {
      final args = widgetSettings.toJson();
      if (initialSnapshot != null) {
        args['snapshot'] = initialSnapshot.toJson();
      }
      _miniWindow = await WindowController.create(
        WindowConfiguration(arguments: jsonEncode(args), hiddenAtLaunch: false),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed opening mini widget window', e);
      _miniWindow = null;
    }
  }

  Future<WidgetSettings> exitWidgetMode(
    WidgetSettings widgetSettings, {
    Map<String, dynamic>? geometry,
  }) async {
    if (_miniWindow != null) {
      try {
        await kWidgetChannel.invokeMethod('close');
      } catch (e) {
        AppLogger.instance.warning(
          _tag,
          'Failed asking mini widget to close: $e',
        );
      }
      try {
        await _miniWindow?.hide();
      } catch (_) {}
    }
    _miniWindow = null;
    if (geometry == null) return widgetSettings;
    return widgetSettings.copyWith(
      x: (geometry['x'] as num?)?.toDouble(),
      y: (geometry['y'] as num?)?.toDouble(),
      width: (geometry['width'] as num?)?.toDouble(),
      height: (geometry['height'] as num?)?.toDouble(),
    );
  }

  Future<void> updateMiniWindowSnapshot(MiniWidgetSnapshot snapshot) async {
    if (_miniWindow == null) return;
    try {
      await kWidgetChannel.invokeMethod(
        'snapshot',
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      AppLogger.instance.warning(
        _tag,
        'Failed pushing snapshot to mini widget: $e',
      );
    }
  }

  Future<void> enterEdgeDockMode(
    String edgeName, {
    String accentName = 'auto',
    double opacity = 1.0,
    String? displayId,
    int? backgroundColor,
    int? textColor,
    int? warningColor,
    int? criticalColor,
    List<String> visibleMetrics = const [],
    double positionOffset = 0,
    MiniWidgetSnapshot? initialSnapshot,
  }) {
    return _edgeDockOpening ??= _enterEdgeDockMode(
      edgeName,
      accentName,
      opacity,
      displayId,
      backgroundColor,
      textColor,
      warningColor,
      criticalColor,
      visibleMetrics,
      positionOffset,
      initialSnapshot,
    ).whenComplete(() => _edgeDockOpening = null);
  }

  Future<void> _enterEdgeDockMode(
    String edgeName,
    String accentName,
    double opacity,
    String? displayId,
    int? backgroundColor,
    int? textColor,
    int? warningColor,
    int? criticalColor,
    List<String> visibleMetrics,
    double positionOffset,
    MiniWidgetSnapshot? initialSnapshot,
  ) async {
    if (_edgeDockWindow != null) {
      try {
        final windows = await WindowController.getAll();
        if (!windows.any((w) => w.windowId == _edgeDockWindow!.windowId)) {
          _edgeDockWindow = null;
        }
      } catch (_) {
        _edgeDockWindow = null;
      }
    }
    if (_edgeDockWindow != null) {
      try {
        await _edgeDockWindow!.show();
      } catch (_) {}
      return;
    }
    try {
      final args = <String, dynamic>{
        'mode': 'edgeDock',
        'edge': edgeName,
        'accent': accentName,
        'opacity': opacity,
        'displayId': displayId,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'warningColor': warningColor,
        'criticalColor': criticalColor,
        'visibleMetrics': visibleMetrics,
        'positionOffset': positionOffset,
      };
      if (initialSnapshot != null) {
        args['snapshot'] = initialSnapshot.toJson();
      }
      _edgeDockWindow = await WindowController.create(
        WindowConfiguration(arguments: jsonEncode(args), hiddenAtLaunch: false),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed opening edge dock window', e);
      _edgeDockWindow = null;
    }
  }

  Future<void> exitEdgeDockMode() async {
    if (_edgeDockWindow != null) {
      try {
        await kEdgeDockChannel.invokeMethod('close');
      } catch (e) {
        AppLogger.instance.warning(
          _tag,
          'Failed asking edge dock to close: $e',
        );
      }
      try {
        await _edgeDockWindow?.hide();
      } catch (_) {}
    }
    _edgeDockWindow = null;
  }

  void clearEdgeDockWindow() {
    _edgeDockWindow = null;
  }

  Future<void> updateEdgeDockSnapshot(MiniWidgetSnapshot snapshot) async {
    if (_edgeDockWindow == null) return;
    try {
      await kEdgeDockChannel.invokeMethod(
        'snapshot',
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      AppLogger.instance.warning(
        _tag,
        'Failed pushing snapshot to edge dock: $e',
      );
    }
  }

  Future<void> minimizeToTray() => windowManager.hide();

  Future<void> restoreFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> isVisible() => windowManager.isVisible();
}
