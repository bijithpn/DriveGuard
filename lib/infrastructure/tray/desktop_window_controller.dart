import 'dart:convert';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart';
import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';

/// One bidirectional channel shared by the main window and the mini-widget
/// window - up to two engines can pair on a `WindowMethodChannel`, which is
/// exactly this pair. Both sides register a handler (becoming "paired")
/// and can then `invokeMethod` on each other: main -> widget pushes
/// `'snapshot'` updates and a `'close'` request; widget -> main sends
/// `'expand_requested'` with the widget's last position/size. Defined here
/// (infrastructure), not in the presentation-layer widget, so both that
/// widget and this controller can depend on it without infrastructure
/// having to import presentation.
const kWidgetChannel = WindowMethodChannel('driveguard.widget');

/// Floor so the widget can never be shrunk into overflowing itself - the
/// legacy "compact" mode multiplies the configured size by 0.7, which
/// produced a window too small for even its own header + one device row.
const kWidgetMinimumSize = Size(220, 170);

/// Wraps `window_manager` for the main dashboard window, and
/// `desktop_multi_window` for the compact, optionally borderless/
/// always-on-top "mini monitor" widget (section 21/28) - a genuinely
/// separate OS-level window/Flutter engine on Windows, macOS and Linux,
/// not the main window resized down.
///
/// Note on package version: `desktop_multi_window: ^0.2.1` was tried first
/// and reverted - creating a second window/engine through it corrupted the
/// main window's engine on this Flutter version ("Running with merged UI
/// and platform thread. Experimental" - that plugin predates Flutter's
/// merged UI/platform-thread mode). `^0.3.1` is a from-scratch rewrite
/// (published well after that engine change existed) and is what's in use
/// now. If this starts crashing again, that incompatibility is the first
/// thing to suspect.
class DesktopWindowController {
  static const _tag = 'DesktopWindowController';
  static const Size _defaultDashboardSize = Size(1100, 760);
  static const Size _dashboardMinimumSize = Size(720, 480);

  WindowController? _miniWindow;

  bool get isMiniWindowOpen => _miniWindow != null;

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

  /// Opens the mini-widget as its own window (spawns a second Flutter
  /// engine - see `main()`'s branch on `WindowController.arguments` and
  /// `MiniWidgetApp`). A no-op if it's already open. The new window is
  /// created hidden and applies its own frame/always-on-top/opacity from
  /// [widgetSettings] itself, once its isolate starts
  /// (`MiniWidgetApp._applyInitialWindowState`, which calls
  /// `windowManager.show()` last) - so it never flashes a default-styled,
  /// default-sized window on screen first.
  Future<void> enterWidgetMode(WidgetSettings widgetSettings) async {
    if (_miniWindow != null) return;
    try {
      _miniWindow = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode(widgetSettings.toJson()),
          hiddenAtLaunch: true,
        ),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed opening mini widget window', e);
      _miniWindow = null;
    }
  }

  /// Closes the mini-widget window, if open. [geometry], when supplied
  /// (the widget reports its own last position/size on its way down - see
  /// `MiniWidgetApp._onExpand`), is merged into the returned settings so
  /// the widget reopens in the same place next time.
  Future<WidgetSettings> exitWidgetMode(
    WidgetSettings widgetSettings, {
    Map<String, dynamic>? geometry,
  }) async {
    if (_miniWindow != null) {
      try {
        // The widget usually closes itself (see MiniWidgetApp._onExpand)
        // before this runs - this covers the other path, where the main
        // window is telling an already-open widget to go away (e.g. "Open
        // Dashboard" from the tray). A widget that's already gone by the
        // time this arrives just means nothing is listening; harmless.
        await kWidgetChannel.invokeMethod('close');
      } catch (e) {
        AppLogger.instance.warning(_tag, 'Failed asking mini widget to close: $e');
      }
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

  /// Pushes a fresh device/settings snapshot to the mini-widget window, if
  /// it's open - the only way it learns about new readings, since it has
  /// no access to the main window's provider container.
  Future<void> updateMiniWindowSnapshot(MiniWidgetSnapshot snapshot) async {
    if (_miniWindow == null) return;
    try {
      await kWidgetChannel.invokeMethod('snapshot', jsonEncode(snapshot.toJson()));
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Failed pushing snapshot to mini widget: $e');
    }
  }

  Future<void> minimizeToTray() => windowManager.hide();

  Future<void> restoreFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> isVisible() => windowManager.isVisible();
}
