import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart';
import '../../core/logging/app_logger.dart';

/// Wraps `window_manager` to provide the two window "shapes" the app needs
/// (section 21): the normal dashboard window, and a compact, optionally
/// borderless/always-on-top "mini monitor" - implemented as a mode of the
/// single app window rather than a second OS-level window, since no
/// single widget API exists uniformly across Windows/macOS/Linux.
class DesktopWindowController {
  static const _tag = 'DesktopWindowController';
  static const Size _defaultDashboardSize = Size(1100, 760);
  static const Size _dashboardMinimumSize = Size(720, 480);
  static const Size _widgetMinimumSize = Size(150, 110);

  Offset? _savedDashboardPosition;
  Size _savedDashboardSize = _defaultDashboardSize;

  Future<void> initialize({required bool startMinimized}) async {
    await windowManager.ensureInitialized();
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

    // Without this, the native window-close button destroys the window
    // (and, since there was previously no tray icon to bring it back,
    // effectively quits the whole app) before `WindowListener.onWindowClose`
    // ever runs - the "close to tray" Dart logic in AppRoot is unreachable
    // dead code otherwise. `AppRoot.onWindowClose` is responsible for
    // calling `windowManager.destroy()` itself when the user actually wants
    // to quit (closeToTray disabled, or the tray's Quit action), so
    // preventing the native close unconditionally here is safe.
    await windowManager.setPreventClose(true);
  }

  Future<void> enterWidgetMode(WidgetSettings widgetSettings) async {
    try {
      _savedDashboardPosition = await windowManager.getPosition();
      _savedDashboardSize = await windowManager.getSize();
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(widgetSettings.alwaysOnTop);
      await windowManager.setOpacity(widgetSettings.opacity);
      // Widget mode allows a much smaller window than the dashboard, but
      // still needs a floor so its own layout never gets squeezed into a
      // RenderFlex overflow.
      await windowManager.setMinimumSize(_widgetMinimumSize);
      final requestedSize = widgetSettings.compact
          ? Size(widgetSettings.width * 0.7, widgetSettings.height * 0.7)
          : Size(widgetSettings.width, widgetSettings.height);
      final size = Size(
        requestedSize.width < _widgetMinimumSize.width
            ? _widgetMinimumSize.width
            : requestedSize.width,
        requestedSize.height < _widgetMinimumSize.height
            ? _widgetMinimumSize.height
            : requestedSize.height,
      );
      await windowManager.setSize(size);
      await windowManager.setPosition(Offset(widgetSettings.x, widgetSettings.y));
      await windowManager.setResizable(true);
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed entering widget mode', e);
    }
  }

  Future<WidgetSettings> exitWidgetMode(WidgetSettings widgetSettings) async {
    try {
      final position = await windowManager.getPosition();
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setOpacity(1.0);
      await windowManager.setMinimumSize(_dashboardMinimumSize);
      await windowManager.setSize(_savedDashboardSize);
      if (_savedDashboardPosition != null) {
        await windowManager.setPosition(_savedDashboardPosition!);
      }
      // titleBarStyle cannot be toggled back to normal on every platform
      // once frameless; a full frame restore may require a window
      // recreate on some platforms (documented limitation).
      return widgetSettings.copyWith(x: position.dx, y: position.dy);
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed exiting widget mode', e);
      return widgetSettings;
    }
  }

  Future<WidgetSettings> captureWidgetGeometry(WidgetSettings widgetSettings) async {
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      return widgetSettings.copyWith(x: position.dx, y: position.dy, width: size.width, height: size.height);
    } catch (_) {
      return widgetSettings;
    }
  }

  Future<void> minimizeToTray() => windowManager.hide();

  Future<void> restoreFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> isVisible() => windowManager.isVisible();
}
