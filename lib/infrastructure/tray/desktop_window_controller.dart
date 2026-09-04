import 'dart:convert';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart';
import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';

const kWidgetChannel = WindowMethodChannel('driveguard.widget');

const kWidgetMinimumSize = Size(260, 220);

class DesktopWindowController with WindowListener {
  static const _tag = 'DesktopWindowController';
  static const Size _defaultDashboardSize = Size(1100, 760);
  static const Size _dashboardMinimumSize = Size(720, 480);

  WindowController? _miniWindow;
  Future<void> Function()? onCloseHandler;
  Future<void> Function()? onMinimizeHandler;

  bool get isMiniWindowOpen => _miniWindow != null;

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
    final options = WindowOptions(
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
  }) async {
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

  Future<void> minimizeToTray() => windowManager.hide();

  Future<void> restoreFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> isVisible() => windowManager.isVisible();
}
