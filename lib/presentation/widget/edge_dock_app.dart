import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/settings/app_settings.dart' show kAllEdgeDockMetrics;
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

class _EdgeDockAppState extends State<EdgeDockApp>
    with SingleTickerProviderStateMixin {
  static const _tag = 'EdgeDockApp';

  MiniWidgetSnapshot _snapshot = MiniWidgetSnapshot.empty;
  final _collapseDebouncer = EdgeDockCollapseDebouncer();
  Offset _displayPosition = Offset.zero;
  Size _displaySize = const Size(1920, 1080);
  late ScreenEdge _edge;
  late Color? _accentOverride;
  late double _opacity;
  late String? _displayId;
  late EdgeDockTheme _theme;
  late Set<EdgeDockMetric> _visibleMetrics;
  late double _alongOffset;
  int? _hoveredIndex;
  bool _isHoveredDock = false;

  late final AnimationController _expansionController;
  late final Animation<double> _expansionAnimation;

  // Set by clicking a ring (or pressing Enter/Space while it's keyboard-
  // focused) - keeps the detail panel open without the pointer needing to
  // stay over the dock, which is both the "click to pin" convenience and
  // the non-hover accessibility fallback (see settings-screen tooltip).
  // `pinnedIndex ?? hoveredIndex` is what's actually shown.
  int? _pinnedIndex;

  double _dragStartOffset = 0;

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
    _displayId = widget.initialArgs['displayId'] as String?;
    _alongOffset =
        (widget.initialArgs['positionOffset'] as num?)?.toDouble() ?? 0;
    _theme = EdgeDockTheme.resolve(
      backgroundColor: (widget.initialArgs['backgroundColor'] as num?)?.toInt(),
      textColor: (widget.initialArgs['textColor'] as num?)?.toInt(),
      warningColor: (widget.initialArgs['warningColor'] as num?)?.toInt(),
      criticalColor: (widget.initialArgs['criticalColor'] as num?)?.toInt(),
    );
    final metricNames = widget.initialArgs['visibleMetrics'];
    _visibleMetrics = metricNames is List && metricNames.isNotEmpty
        ? metricNames
              .whereType<String>()
              .map((n) => EdgeDockMetric.values.where((m) => m.name == n))
              .expand((matches) => matches)
              .toSet()
        : kAllEdgeDockMetrics;
    final snapJson = widget.initialArgs['snapshot'];
    if (snapJson is Map<String, dynamic>) {
      try {
        _snapshot = MiniWidgetSnapshot.fromJson(snapJson);
      } catch (_) {}
    }

    _expansionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _expansionAnimation = CurvedAnimation(
      parent: _expansionController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    kEdgeDockChannel.setMethodCallHandler(_handleMethodCall);
    unawaited(kEdgeDockChannel.invokeMethod('ready').catchError((_) {}));
    unawaited(_initWindow());
  }

  @override
  void dispose() {
    _expansionController.dispose();
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
      if (Platform.isMacOS) await _applyFullScreenAuxiliary();

      final primary = await screenRetriever.getPrimaryDisplay();
      var display = primary;
      if (_displayId != null) {
        try {
          final all = await screenRetriever.getAllDisplays();
          display = EdgeDockGeometry.pickDisplay(all, primary, _displayId);
        } catch (e) {
          AppLogger.instance.debug(_tag, 'getAllDisplays failed: $e');
        }
      }
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
      // Some macOS versions drop the fullscreen-auxiliary collection
      // behavior applied earlier once `makeKeyAndOrderFront` runs (both
      // `windowManager.show()` and `controller.show()` above call it) -
      // reapplying once more after the window is actually on screen is
      // what makes it stick, matching reports from other window_manager
      // users hitting the same "dock disappears over fullscreen apps"
      // symptom.
      if (Platform.isMacOS) await _applyFullScreenAuxiliary();
    }
  }

  // Otherwise the dock disappears the moment any app (including
  // DriveGuard's own main window) goes native fullscreen, since fullscreen
  // apps get their own Space by default. window_manager already wraps the
  // NSWindow collectionBehavior flags needed for this - no native Swift
  // code required.
  Future<void> _applyFullScreenAuxiliary() async {
    try {
      await windowManager.setVisibleOnAllWorkspaces(
        true,
        visibleOnFullScreen: true,
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'setVisibleOnAllWorkspaces failed: $e');
    }
  }

  Rect get _railRect => EdgeDockGeometry.railRect(
    _displayPosition,
    _displaySize,
    _edge,
    _snapshot.devices.length,
    alongOffset: _alongOffset,
  );

  Rect get _collapsedRailRect => EdgeDockGeometry.collapsedRailRect(
    _displayPosition,
    _displaySize,
    _edge,
    _snapshot.devices.length,
    alongOffset: _alongOffset,
  );

  bool get _isExpanded =>
      _isHoveredDock || _pinnedIndex != null || _expansionController.value > 0;

  /// Which device's ring is shown expanded: pinned (click/keyboard) wins
  /// over merely hovered.
  int? get _displayedIndex => _pinnedIndex ?? _hoveredIndex;

  Rect? get _panelRect {
    final index = _displayedIndex;
    if (index == null) return null;
    final devices = _snapshot.devices;
    if (index >= devices.length) return null;
    final center = EdgeDockGeometry.ringCenter(_railRect, _edge, index);
    final rowCount = edgeDockDetailRows(devices[index], _visibleMetrics).length;
    return EdgeDockGeometry.panelRectFor(
      _railRect,
      _edge,
      center,
      _displayPosition,
      _displaySize,
      panelHeight: EdgeDockGeometry.panelHeightFor(rowCount),
    );
  }

  Future<void> _applyWindowBounds() async {
    final rail = _railRect;
    final collapsedRail = _collapsedRailRect;
    final panel = _panelRect;
    final windowRect = EdgeDockGeometry.windowRectFor(
      rail,
      panel,
      collapsedRail: collapsedRail,
      isExpanded: _isExpanded,
    );
    // Update the origin - and rebuild - before awaiting the native resize,
    // not after. With an animated native resize, the OS window kept
    // growing for ~200-300ms while Flutter had already redrawn assuming
    // the *new* origin from a stale `await`, so the panel briefly rendered
    // outside the window's actual (still mid-animation) bounds - visible
    // as the hover panel flickering/disappearing. Resizing instantly
    // (`animate: false`) and updating local state synchronously first
    // keeps Flutter's assumed window geometry and the OS window's actual
    // geometry from ever disagreeing across frames.
    _windowOrigin = windowRect.topLeft;
    if (mounted) setState(() {});
    try {
      await windowManager.setBounds(windowRect, animate: false);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'setBounds failed: $e');
    }
  }

  void _onMouseEnterDock() {
    _collapseDebouncer.cancel();
    _isHoveredDock = true;
    final wasDismissed = _expansionController.value == 0.0;
    if (wasDismissed) {
      unawaited(_applyWindowBounds());
    }
    _expansionController.forward();
  }

  void _onMouseExitDock() {
    _isHoveredDock = false;
    if (_pinnedIndex != null) return;
    _collapseDebouncer.schedule(() {
      if (!mounted || _isHoveredDock || _pinnedIndex != null) return;
      setState(() {
        _hoveredIndex = null;
      });
      unawaited(_applyWindowBounds());
      _expansionController.reverse().then((_) {
        if (mounted && !_isHoveredDock && _pinnedIndex == null) {
          unawaited(_applyWindowBounds());
        }
      });
    });
  }

  void _onHover(int? index) {
    if (index != null) {
      _collapseDebouncer.cancel();
      _isHoveredDock = true;
      if (_expansionController.value < 1.0) {
        _expansionController.forward();
      }
      if (_hoveredIndex == index) return;
      setState(() => _hoveredIndex = index);
      unawaited(_applyWindowBounds());
      return;
    }
    // A pinned panel stays open when the pointer leaves - that's the whole
    // point of pinning (click-to-pin doubles as the non-hover accessibility
    // fallback: the panel doesn't require the pointer to keep hovering).
    if (_pinnedIndex != null) {
      if (_hoveredIndex == null) return;
      setState(() => _hoveredIndex = null);
      return;
    }
    _onMouseExitDock();
  }

  /// Toggles the pin on [index]: clicking (or pressing Enter/Space) an
  /// already-pinned ring unpins it; clicking a different one re-pins there.
  /// `null` always unpins (used by Escape).
  void _onTapRing(int? index) {
    final next = (index == null || _pinnedIndex == index) ? null : index;
    if (next == _pinnedIndex) return;
    setState(() {
      _pinnedIndex = next;
      if (next != null) {
        _expansionController.value = 1.0;
      }
    });
    unawaited(_applyWindowBounds());
    if (next == null && !_isHoveredDock) {
      _onMouseExitDock();
    }
  }

  /// Arrow-key rail navigation, reusing the same hover mechanism the mouse
  /// uses. Only reachable once the dock's own content has keyboard focus
  /// (a deliberate click on it - never grabbed automatically, so this
  /// doesn't count as focus-stealing from the main app window).
  void _onArrowKey({required bool forward}) {
    final count = _snapshot.devices.length;
    if (count == 0) return;
    if (_expansionController.value < 1.0) {
      _expansionController.forward();
    }
    final current = _displayedIndex ?? -1;
    final next = forward
        ? (current + 1) % count
        : (current - 1 + count) % count;
    _onHover(next);
  }

  void _onDragStart() {
    _dragStartOffset = _alongOffset;
  }

  void _onDragUpdate(double delta) {
    setState(() => _alongOffset += delta);
    unawaited(_applyWindowBounds());
  }

  void _onDragEnd() {
    if (_alongOffset == _dragStartOffset) return;
    unawaited(
      kEdgeDockChannel
          .invokeMethod(
            'position_changed',
            jsonEncode({'offset': _alongOffset}),
          )
          .catchError((_) {}),
    );
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
          pinnedIndex: _pinnedIndex,
          onHover: _onHover,
          onTapRing: _onTapRing,
          onArrowKey: _onArrowKey,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          railLocalRect: rail.shift(-_windowOrigin),
          panelLocalRect: panel?.shift(-_windowOrigin),
          theme: _theme,
          visibleMetrics: _visibleMetrics,
          isExpanded: _isExpanded,
          expansionProgress: _expansionAnimation.value,
          onMouseEnterDock: _onMouseEnterDock,
          onMouseExitDock: _onMouseExitDock,
        ),
      ),
    );
  }
}
