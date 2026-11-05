import 'dart:async';
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

/// How often the main app re-sends state to the floating windows, and how
/// long a window waits without hearing it before concluding it is orphaned.
const kWidgetHeartbeat = Duration(seconds: 2);
const kWidgetOrphanTimeout = Duration(seconds: 30);

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
  bool _pendingMinimize = false;
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
        // A minimised/hidden window gets no frames from macOS, and
        // everything that opens the floating widgets and starts monitoring
        // waits for a frame - so a minimised start used to stall (for
        // minutes) until the user happened to bring the window up. Keep it
        // technically on screen but fully transparent and click-through
        // until startup is done, then minimise (completeStartMinimized).
        _pendingMinimize = true;
        await windowManager.setOpacity(0);
        await windowManager.setIgnoreMouseEvents(true);
        await windowManager.show(inactive: true);
        Timer(const Duration(seconds: 30), completeStartMinimized);
      }
    });

    await windowManager.setPreventClose(true);
  }

  /// Ends the transparent "startup" state set up for a minimised start:
  /// minimise the window for real and make it opaque / clickable again.
  Future<void> completeStartMinimized() async {
    if (!_pendingMinimize) return;
    _pendingMinimize = false;
    try {
      await windowManager.minimize();
      await windowManager.setIgnoreMouseEvents(false);
      await windowManager.setOpacity(1);
    } catch (e) {
      AppLogger.instance.warning(_tag, 'completeStartMinimized failed: $e');
    }
  }

  @override
  void onWindowFocus() {
    // The user (tray, dock icon, single-instance activation) brought the
    // window up before startup finished: make it real straight away.
    if (_pendingMinimize) {
      _pendingMinimize = false;
      unawaited(windowManager.setIgnoreMouseEvents(false));
      unawaited(windowManager.setOpacity(1));
    }
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
    final liveMini = await _closeStrayWindows(dock: false);
    if (liveMini.isNotEmpty) {
      _miniWindow = liveMini.first;
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
        WindowConfiguration(arguments: jsonEncode(args), hiddenAtLaunch: true),
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

  /// Returns whether the window actually received the snapshot, so callers
  /// can retry instead of assuming it arrived.
  Future<bool> updateMiniWindowSnapshot(MiniWidgetSnapshot snapshot) async {
    if (_miniWindow == null) return false;
    try {
      await kWidgetChannel.invokeMethod(
        'snapshot',
        jsonEncode(snapshot.toJson()),
      );
      return true;
    } catch (e) {
      _logPushFailure('mini widget', e);
    }
    return false;
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

  /// Closes dock/widget windows this controller has no handle on.
  ///
  /// A hot restart (or crash-restart of the main isolate) resets this class
  /// but leaves the native secondary windows - and their engines, still
  /// showing their last snapshot - alive; the next open then stacked a second
  /// window on top of the stale one ("multiple widgets"). Anything of the
  /// right kind that exists before we create ours is, by definition, stray.
  ///
  /// Returns the strays that are STILL alive after giving them time to shut
  /// down. The caller must reuse one of those instead of creating another
  /// window: a channel allows only two engines, so a new window created while
  /// an old one is still registered fails with CHANNEL_LIMIT_REACHED and ends
  /// up as an orphan.
  Future<List<WindowController>> _closeStrayWindows({
    required bool dock,
  }) async {
    try {
      final self = await WindowController.fromCurrentEngine();
      bool isStray(WindowController w) {
        if (w.windowId == self.windowId) return false;
        final isDock = w.arguments.contains('"mode":"edgeDock"');
        final isMini = !isDock && w.arguments.contains('"alwaysOnTop"');
        return dock ? isDock : isMini;
      }

      final channel = dock ? kEdgeDockChannel : kWidgetChannel;
      var strays = (await WindowController.getAll()).where(isStray).toList();
      for (var i = 0; i < strays.length; i++) {
        // Their own isolate closes its window; no new window of this kind
        // exists yet, so the call can only reach a stray.
        try {
          await channel.invokeMethod('close');
        } catch (_) {}
      }
      if (strays.isEmpty) return const [];
      // Wait (up to ~3s) for the stray engines to actually unregister.
      for (var i = 0; i < 15 && strays.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        strays = (await WindowController.getAll()).where(isStray).toList();
      }
      AppLogger.instance.info(
        _tag,
        strays.isEmpty
            ? 'Closed stray ${dock ? 'edge dock' : 'widget'} window(s) left '
                  'over from a previous run'
            : 'Stray ${dock ? 'edge dock' : 'widget'} window did not close; '
                  'reusing it',
      );
      return strays;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Stray window cleanup failed: $e');
      return const [];
    }
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
    final liveDock = await _closeStrayWindows(dock: true);
    if (liveDock.isNotEmpty) {
      _edgeDockWindow = liveDock.first;
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
        WindowConfiguration(arguments: jsonEncode(args), hiddenAtLaunch: true),
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

  /// Returns whether the window actually received the snapshot, so callers
  /// can retry instead of assuming it arrived.
  Future<bool> updateEdgeDockSnapshot(MiniWidgetSnapshot snapshot) async {
    if (_edgeDockWindow == null) return false;
    try {
      await kEdgeDockChannel.invokeMethod(
        'snapshot',
        jsonEncode(snapshot.toJson()),
      );
      return true;
    } catch (e) {
      _logPushFailure('edge dock', e);
    }
    return false;
  }

  /// A push that races the window's own startup (its channel isn't
  /// registered yet) is expected - the window asks for a fresh snapshot with
  /// 'ready' - so only real failures are warnings.
  void _logPushFailure(String target, Object e) {
    final startingUp =
        e.toString().contains('CHANNEL_UNREGISTERED') ||
        e.toString().contains('NO_HANDLER');
    if (startingUp) {
      AppLogger.instance.debug(
        _tag,
        'Snapshot for $target not delivered yet: $e',
      );
    } else {
      AppLogger.instance.warning(
        _tag,
        'Failed pushing snapshot to $target: $e',
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
