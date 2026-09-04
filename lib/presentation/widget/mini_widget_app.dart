import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';
import '../../infrastructure/tray/desktop_window_controller.dart'
    show kWidgetChannel, kWidgetMinimumSize;
import 'mini_monitor_view.dart';

class MiniWidgetApp extends StatefulWidget {
  const MiniWidgetApp({
    super.key,
    required this.controller,
    required this.initialArgs,
  });

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
    final snapJson = widget.initialArgs['snapshot'];
    if (snapJson is Map<String, dynamic>) {
      try {
        _snapshot = MiniWidgetSnapshot.fromJson(snapJson);
      } catch (_) {}
    }
    kWidgetChannel.setMethodCallHandler(_handleMethodCall);

    unawaited(kWidgetChannel.invokeMethod('ready').catchError((_) {}));
    unawaited(_applyInitialWindowState());
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        final payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        final newSnapshot = MiniWidgetSnapshot.fromJson(payload);
        if (_snapshot == newSnapshot) return null;
        if (mounted) {
          setState(() => _snapshot = newSnapshot);
        }
      case 'close':
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

  Future<void> _applyInitialWindowState() async {
    final args = widget.initialArgs;
    final x = (args['x'] as num?)?.toDouble() ?? 100;
    final y = (args['y'] as num?)?.toDouble() ?? 100;
    final width = (args['width'] as num?)?.toDouble() ?? 290;
    final height = (args['height'] as num?)?.toDouble() ?? 250;
    final opacity = (args['opacity'] as num?)?.toDouble() ?? 0.95;
    final alwaysOnTop = args['alwaysOnTop'] as bool? ?? true;
    final compact = args['compact'] as bool? ?? false;
    final requested = compact
        ? Size(width * 0.7, height * 0.7)
        : Size(width, height);
    final size = Size(
      requested.width < kWidgetMinimumSize.width
          ? kWidgetMinimumSize.width
          : requested.width,
      requested.height < kWidgetMinimumSize.height
          ? kWidgetMinimumSize.height
          : requested.height,
    );

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
        await windowManager.setBackgroundColor(const Color(0xFF1C1C1E));
      }
      await windowManager.setAlwaysOnTop(alwaysOnTop);
      if (!Platform.isLinux) {
        await windowManager.setHasShadow(false);
      }
      await windowManager.setOpacity(opacity);
      await windowManager.setMinimumSize(kWidgetMinimumSize);
      await windowManager.setSize(size);
      await windowManager.setPosition(Offset(x, y));
      await windowManager.setResizable(true);
    } catch (e) {
      AppLogger.instance.error(
        'MiniWidgetApp',
        'Error applying window state',
        e,
      );
    } finally {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        AppLogger.instance.error(
          'MiniWidgetApp',
          'windowManager.show failed',
          e,
        );
      }
      try {
        await widget.controller.show();
      } catch (_) {}
    }
  }

  Future<void> _onExpand() async {
    if (_closing) return;
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      await kWidgetChannel.invokeMethod(
        'expand_requested',
        jsonEncode({
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        }),
      );
    } catch (_) {
      try {
        await kWidgetChannel.invokeMethod('expand_requested', '');
      } catch (_) {}
    }
  }

  Future<void> _onClose() async {
    if (_closing) return;
    _closing = true;
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      await kWidgetChannel.invokeMethod(
        'widget_closed',
        jsonEncode({
          'x': position.dx,
          'y': position.dy,
          'width': size.width,
          'height': size.height,
        }),
      );
    } catch (_) {
      try {
        await kWidgetChannel.invokeMethod('widget_closed');
      } catch (_) {}
    }
    try {
      await windowManager.close();
    } catch (_) {
      try {
        await widget.controller.hide();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF1C1C1E),
        body: MiniMonitorView(
          snapshot: _snapshot,
          onExpand: _onExpand,
          onClose: _onClose,
        ),
      ),
    );
  }
}
