import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/enums/ui_enums.dart';
import '../../infrastructure/tray/desktop_window_controller.dart'
    show kEdgeDockChannel;
import '../../infrastructure/tray/edge_dock_geometry.dart';
import '../theme/app_theme.dart';
import 'edge_dock_view.dart';

/// Window entry point for the edge-docked hover widget: a rail of
/// per-device ring indicators docked to a screen edge, each expanding a
/// detail card on hover. See
/// docs/superpowers/specs/2026-09-09-edge-dock-widget-design.md.
class EdgeDockApp extends StatefulWidget {
  const EdgeDockApp({
    super.key,
    required this.controller,
    required this.initialArgs,
  });

  final WindowController controller;
  final Map<String, dynamic> initialArgs;

  @override
  State<EdgeDockApp> createState() => _EdgeDockAppState();
}

class _EdgeDockAppState extends State<EdgeDockApp> {
  static const _tag = 'EdgeDockApp';

  MiniWidgetSnapshot _snapshot = MiniWidgetSnapshot.empty;
  final _collapseDebouncer = EdgeDockCollapseDebouncer();
  Offset _displayPosition = Offset.zero;
  Size _displaySize = const Size(1920, 1080);
  late ScreenEdge _edge;
  late Color? _accentOverride;
  late double _opacity;
  int? _hoveredIndex;

  // The current window rect's top-left, in screen coordinates - needed to
  // translate screen-space geometry into window-local Positioned rects.
  Offset _windowOrigin = Offset.zero;

  @override
  void initState() {
    super.initState();
    _edge = ScreenEdge.values.firstWhere(
      (e) => e.name == widget.initialArgs['edge'],
      orElse: () => ScreenEdge.right,
    );
    final accent = EdgeDockAccent.values.firstWhere(
      (a) => a.name == widget.initialArgs['accent'],
      orElse: () => EdgeDockAccent.auto,
    );
    _accentOverride = resolveAccent(accent);
    _opacity = (widget.initialArgs['opacity'] as num?)?.toDouble() ?? 1.0;
    final snapJson = widget.initialArgs['snapshot'];
    if (snapJson is Map<String, dynamic>) {
      try {
        _snapshot = MiniWidgetSnapshot.fromJson(snapJson);
      } catch (_) {}
    }
    kEdgeDockChannel.setMethodCallHandler(_handleMethodCall);
    unawaited(kEdgeDockChannel.invokeMethod('ready').catchError((_) {}));
    unawaited(_initWindow());
  }

  @override
  void dispose() {
    _collapseDebouncer.dispose();
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        final payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        final newSnapshot = MiniWidgetSnapshot.fromJson(payload);
        if (_snapshot == newSnapshot) return null;
        if (mounted) {
          setState(() {
            _snapshot = newSnapshot;
            if (_hoveredIndex != null &&
                _hoveredIndex! >= newSnapshot.devices.length) {
              _hoveredIndex = null;
            }
          });
          unawaited(_applyWindowBounds());
        }
      case 'close':
        _collapseDebouncer.cancel();
        try {
          await windowManager.close();
        } catch (_) {
          try {
            await widget.controller.hide();
          } catch (_) {}
        }
    }
    return null;
  }

  Future<void> _initWindow() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setAsFrameless();
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      if (!Platform.isLinux) {
        await windowManager.setBackgroundColor(Colors.transparent);
      } else {
        await windowManager.setBackgroundColor(AppColors.bg1);
      }
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      try {
        await windowManager.setOpacity(_opacity);
      } catch (e) {
        AppLogger.instance.debug(_tag, 'setOpacity failed: $e');
      }
      if (!Platform.isLinux) {
        await windowManager.setHasShadow(false);
      }
      if (Platform.isMacOS) {
        // Otherwise the dock disappears the moment any app (including
        // DriveGuard's own main window) goes native fullscreen, since
        // fullscreen apps get their own Space by default. window_manager
        // already wraps the NSWindow collectionBehavior flags needed for
        // this - no native Swift code required.
        try {
          await windowManager.setVisibleOnAllWorkspaces(
            true,
            visibleOnFullScreen: true,
          );
        } catch (e) {
          AppLogger.instance.debug(
            _tag,
            'setVisibleOnAllWorkspaces failed: $e',
          );
        }
      }

      final display = await screenRetriever.getPrimaryDisplay();
      _displayPosition = display.visiblePosition ?? Offset.zero;
      _displaySize = display.visibleSize ?? display.size;

      await _applyWindowBounds();
    } catch (e) {
      AppLogger.instance.error(_tag, 'Error initializing edge dock window', e);
    } finally {
      try {
        await windowManager.show();
      } catch (_) {}
      try {
        await widget.controller.show();
      } catch (_) {}
    }
  }

  Rect get _railRect => EdgeDockGeometry.railRect(
    _displayPosition,
    _displaySize,
    _edge,
    _snapshot.devices.length,
  );

  Rect? get _panelRect {
    final index = _hoveredIndex;
    if (index == null) return null;
    final center = EdgeDockGeometry.ringCenter(_railRect, _edge, index);
    return EdgeDockGeometry.panelRectFor(
      _railRect,
      _edge,
      center,
      _displayPosition,
      _displaySize,
    );
  }

  Future<void> _applyWindowBounds() async {
    final rail = _railRect;
    final panel = _panelRect;
    final windowRect = EdgeDockGeometry.windowRectFor(rail, panel);
    _windowOrigin = windowRect.topLeft;
    try {
      await windowManager.setBounds(windowRect, animate: true);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'setBounds failed: $e');
    }
    if (mounted) setState(() {});
  }

  void _onHover(int? index) {
    if (index != null) {
      _collapseDebouncer.cancel();
      if (_hoveredIndex == index) return;
      setState(() => _hoveredIndex = index);
      unawaited(_applyWindowBounds());
      return;
    }
    // Debounced: a fast cursor movement across the rail/panel boundary can
    // report a same-frame exit+re-enter, and collapsing instantly would
    // flicker. Cancelled above if hover resumes before the grace elapses.
    _collapseDebouncer.schedule(() {
      if (!mounted) return;
      setState(() => _hoveredIndex = null);
      unawaited(_applyWindowBounds());
    });
  }

  @override
  Widget build(BuildContext context) {
    final rail = _railRect;
    final panel = _panelRect;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: EdgeDockContent(
          snapshot: _snapshot,
          edge: _edge,
          accentOverride: _accentOverride,
          hoveredIndex: _hoveredIndex,
          onHover: _onHover,
          railLocalRect: rail.shift(-_windowOrigin),
          panelLocalRect: panel?.shift(-_windowOrigin),
        ),
      ),
    );
  }
}
