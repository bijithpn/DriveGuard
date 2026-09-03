import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../infrastructure/tray/desktop_window_controller.dart'
    show kWidgetChannel, kWidgetMinimumSize;
import 'mini_monitor_view.dart';

/// Root widget for the mini-widget's own OS window - a completely separate
/// Flutter engine/isolate from the main dashboard window (created via
/// `desktop_multi_window`, see `DesktopWindowController.enterWidgetMode`).
///
/// Unlike the old approach (reshaping the single main window down to widget
/// size), this window owns its own frame/size/always-on-top state via its
/// own `window_manager` plugin instance (registered per-window natively -
/// see MainFlutterWindow.swift / flutter_window.cpp / my_application.cc),
/// and has no access to the main window's Riverpod provider container -
/// device/settings data arrives as a [MiniWidgetSnapshot] pushed over
/// [kWidgetChannel].
class MiniWidgetApp extends StatefulWidget {
  const MiniWidgetApp({super.key, required this.controller, required this.initialArgs});

  final WindowController controller;
  final Map<String, dynamic> initialArgs;

  @override
  State<MiniWidgetApp> createState() => _MiniWidgetAppState();
}

class _MiniWidgetAppState extends State<MiniWidgetApp> {
  MiniWidgetSnapshot _snapshot = MiniWidgetSnapshot.empty;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    kWidgetChannel.setMethodCallHandler(_handleMethodCall);
    // The main window pushes a snapshot as soon as this window is created,
    // but that's a race against this isolate finishing startup and
    // registering the line above - lost pushes aren't retried, so without
    // this the widget can sit empty until the next unrelated device/
    // settings change happens to fire one. Ask explicitly once ready.
    unawaited(kWidgetChannel.invokeMethod('ready').catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialWindowState());
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        final payload = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        if (mounted) setState(() => _snapshot = MiniWidgetSnapshot.fromJson(payload));
      case 'close':
        // The main window is asking this widget to go away (e.g. the user
        // picked "Open Dashboard" from the tray while the widget was up).
        await windowManager.close();
    }
    return null;
  }

  Future<void> _applyInitialWindowState() async {
    final args = widget.initialArgs;
    final x = (args['x'] as num?)?.toDouble() ?? 100;
    final y = (args['y'] as num?)?.toDouble() ?? 100;
    final width = (args['width'] as num?)?.toDouble() ?? 260;
    final height = (args['height'] as num?)?.toDouble() ?? 180;
    final opacity = (args['opacity'] as num?)?.toDouble() ?? 0.95;
    final alwaysOnTop = args['alwaysOnTop'] as bool? ?? true;
    final compact = args['compact'] as bool? ?? false;
    final requested = compact ? Size(width * 0.7, height * 0.7) : Size(width, height);
    final size = Size(
      requested.width < kWidgetMinimumSize.width ? kWidgetMinimumSize.width : requested.width,
      requested.height < kWidgetMinimumSize.height ? kWidgetMinimumSize.height : requested.height,
    );

    await windowManager.ensureInitialized();
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(alwaysOnTop);
    await windowManager.setHasShadow(false);
    await windowManager.setOpacity(opacity);
    await windowManager.setMinimumSize(kWidgetMinimumSize);
    await windowManager.setSize(size);
    await windowManager.setPosition(Offset(x, y));
    await windowManager.setResizable(true);
    await windowManager.show();
  }

  Future<void> _onExpand() async {
    if (_closing) return;
    _closing = true;
    // Report where the user left the widget so the next time it's opened
    // it reappears in the same place.
    final position = await windowManager.getPosition();
    final size = await windowManager.getSize();
    try {
      await kWidgetChannel.invokeMethod(
        'expand_requested',
        jsonEncode({'x': position.dx, 'y': position.dy, 'width': size.width, 'height': size.height}),
      );
    } finally {
      await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: MiniMonitorView(snapshot: _snapshot, onExpand: _onExpand),
      ),
    );
  }
}
