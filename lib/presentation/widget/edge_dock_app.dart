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

/// Window entry point for the edge-docked hover panel. A slim always-on-top
/// strip, docked flush to a screen edge, that expands into a compact panel
/// when the cursor is near it. See
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
  static const _pollInterval = Duration(milliseconds: 120);

  MiniWidgetSnapshot _snapshot = MiniWidgetSnapshot.empty;
  final _hoverTracker = EdgeDockHoverTracker();
  Timer? _pollTimer;
  Offset _displayPosition = Offset.zero;
  Size _displaySize = const Size(1920, 1080);
  late ScreenEdge _edge;

  @override
  void initState() {
    super.initState();
    _edge = ScreenEdge.values.firstWhere(
      (e) => e.name == widget.initialArgs['edge'],
      orElse: () => ScreenEdge.right,
    );
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
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        final payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        final newSnapshot = MiniWidgetSnapshot.fromJson(payload);
        if (_snapshot == newSnapshot) return null;
        if (mounted) setState(() => _snapshot = newSnapshot);
      case 'close':
        _pollTimer?.cancel();
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
      if (!Platform.isLinux) {
        await windowManager.setHasShadow(false);
      }

      final display = await screenRetriever.getPrimaryDisplay();
      _displayPosition = display.visiblePosition ?? Offset.zero;
      _displaySize = display.visibleSize ?? display.size;

      await windowManager.setBounds(
        EdgeDockGeometry.stripRect(_displayPosition, _displaySize, _edge),
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Error initializing edge dock window', e);
    } finally {
      try {
        await windowManager.show();
      } catch (_) {}
      try {
        await widget.controller.show();
      } catch (_) {}
      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollCursor());
    }
  }

  Future<void> _pollCursor() async {
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final stripRect = EdgeDockGeometry.stripRect(
        _displayPosition,
        _displaySize,
        _edge,
      );
      final panelRect = EdgeDockGeometry.panelRect(
        _displayPosition,
        _displaySize,
        _edge,
      );
      final changed = _hoverTracker.update(
        cursor: cursor,
        stripRect: stripRect,
        panelRect: panelRect,
        now: DateTime.now(),
      );
      if (!changed) return;
      await windowManager.setBounds(
        _hoverTracker.expanded ? panelRect : stripRect,
        animate: true,
      );
      if (mounted) setState(() {});
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Cursor poll failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _hoverTracker.expanded
            ? EdgeDockPanel(snapshot: _snapshot)
            : EdgeDockStrip(snapshot: _snapshot),
      ),
    );
  }
}
