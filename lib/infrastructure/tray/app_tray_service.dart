import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tray_manager/tray_manager.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/enums/storage_enums.dart';

class TrayDeviceSummary {
  const TrayDeviceSummary({
    required this.id,
    required this.name,
    required this.valueText,
    required this.severity,
  });

  final String id;
  final String name;
  final String valueText;
  final TemperatureSeverity severity;
}

class AppTrayService {
  static const _tag = 'AppTrayService';

  final void Function() onOpenDashboard;
  final void Function() onPauseResume;
  final void Function() onOpenSettings;
  final void Function() onRescan;
  final void Function() onQuit;

  AppTrayService({
    required this.onOpenDashboard,
    required this.onPauseResume,
    required this.onOpenSettings,
    required this.onRescan,
    required this.onQuit,
  });

  TemperatureSeverity _lastSeverity = TemperatureSeverity.normal;
  bool _paused = false;
  List<TrayDeviceSummary> _devices = const [];
  final Map<String, String> _iconPathCache = {};

  String? _selectedDeviceId;
  bool _selectionIsExplicit = false;

  Future<void> initialize() async {
    await _applyIcon(TemperatureSeverity.normal);
    await _rebuildMenu();
    trayManager.addListener(
      _Listener(
        onDoubleClick: onOpenDashboard,
        onMenuItemClick: handleMenuClick,
      ),
    );
  }

  Future<void> updateSeverity(TemperatureSeverity severity) async {
    if (severity == _lastSeverity) return;
    _lastSeverity = severity;
    await _applyIcon(severity);
  }

  Future<void> setPaused(bool paused) async {
    if (paused == _paused) return;
    _paused = paused;
    await _rebuildMenu();
  }

  Future<void> updateDevices(List<TrayDeviceSummary> devices) async {
    _devices = devices;

    if (_selectionIsExplicit &&
        !devices.any((d) => d.id == _selectedDeviceId)) {
      _selectionIsExplicit = false;
    }
    await _applyIcon(_lastSeverity);
    await _rebuildMenu();
  }

  void _selectDevice(String id) {
    _selectedDeviceId = id;
    _selectionIsExplicit = true;
    unawaited(_applyIcon(_lastSeverity));
    unawaited(_rebuildMenu());
  }

  TrayDeviceSummary? get _displayedDevice {
    if (_devices.isEmpty) return null;
    if (_selectionIsExplicit) {
      for (final d in _devices) {
        if (d.id == _selectedDeviceId) return d;
      }
    }
    return _devices.reduce(
      (a, b) => _rank(a.severity) >= _rank(b.severity) ? a : b,
    );
  }

  Future<void> _applyIcon(TemperatureSeverity severity) async {
    try {
      final displayed = _displayedDevice;
      final label = displayed?.valueText;
      final path = await _iconPathFor(severity, label);
      await trayManager.setIcon(path);
      await trayManager.setToolTip('DriveGuard - ${_tooltipSummary(severity)}');

      if (Platform.isMacOS) {
        await trayManager.setTitle(
          displayed == null ? '' : displayed.valueText,
        );
      }
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to apply tray icon: $e');
    }
  }

  String _tooltipSummary(TemperatureSeverity severity) {
    if (_devices.isEmpty) return _severityLabel(severity);
    if (_devices.length == 1) {
      final d = _devices.single;
      return '${d.name}: ${d.valueText} · ${_severityLabel(d.severity)}';
    }
    final warmest = _devices.reduce(
      (a, b) => _rank(a.severity) >= _rank(b.severity) ? a : b,
    );
    return '${_devices.length} drives · Warmest ${warmest.valueText} · ${_severityLabel(severity)}';
  }

  int _rank(TemperatureSeverity s) => switch (s) {
    TemperatureSeverity.critical => 4,
    TemperatureSeverity.warning => 3,
    TemperatureSeverity.warm => 2,
    TemperatureSeverity.normal => 1,
    TemperatureSeverity.unavailable => 0,
  };

  Future<String> _iconPathFor(TemperatureSeverity severity, String? label) async {
    // Include label in cache key so icon re-renders when temperature changes.
    final cacheKey = '${severity.name}_${label ?? ''}';
    final cached = _iconPathCache[cacheKey];
    if (cached != null && File(cached).existsSync()) return cached;

    final bytes = await _renderTrayIcon(_severityColor(severity), label);
    final safe = (label ?? '').replaceAll(RegExp(r'[^\w]'), '_');
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}driveguard_tray_${severity.name}_$safe.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    _iconPathCache[cacheKey] = file.path;
    return file.path;
  }

  ui.Color _severityColor(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return const ui.Color(0xFF3DD68C);
      case TemperatureSeverity.warning:
        return const ui.Color(0xFFFFBC42);
      case TemperatureSeverity.critical:
        return const ui.Color(0xFFFF4D4D);
      case TemperatureSeverity.unavailable:
        return const ui.Color(0xFF5E587A);
    }
  }

  /// Renders a 64×64 tray icon.
  ///
  /// When [label] is provided (e.g. "38°C", "N/A") it is drawn as white text
  /// centred on a coloured rounded-rectangle — giving a visible temperature
  /// reading directly in the Windows system tray.
  /// When [label] is null the original dot + lines design is used as a
  /// fallback (e.g. before any device is discovered).
  Future<Uint8List> _renderTrayIcon(ui.Color color, String? label) async {
    const double size = 64;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Background rounded rectangle.
    final bgPaint = ui.Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(2, 2, size - 4, size - 4),
        const ui.Radius.circular(14),
      ),
      bgPaint,
    );

    if (label != null && label.isNotEmpty) {
      // Draw the label text centred in the icon.
      // ui.Paragraph lets us render text onto a canvas in dart:ui.
      final style = ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: label.length <= 4 ? 22.0 : 17.0,
        fontWeight: ui.FontWeight.w700,
      );
      final paraStyle = ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        maxLines: 1,
      );
      final builder = ui.ParagraphBuilder(paraStyle)
        ..pushStyle(style)
        ..addText(label);
      final para = builder.build();
      para.layout(const ui.ParagraphConstraints(width: size));
      // Centre vertically.
      final yOffset = (size - para.height) / 2;
      canvas.drawParagraph(para, ui.Offset(0, yOffset));
    } else {
      // Fallback: three horizontal lines (hamburger / scanning indicator).
      final linePaint = ui.Paint()
        ..blendMode = ui.BlendMode.clear
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = ui.StrokeCap.round
        ..isAntiAlias = true;
      for (final y in [23.0, 32.0, 41.0]) {
        canvas.drawLine(
          ui.Offset(17, y),
          ui.Offset(size - 17, y),
          linePaint,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  String _severityLabel(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return 'Normal';
      case TemperatureSeverity.warning:
        return 'Warning';
      case TemperatureSeverity.critical:
        return 'Critical';
      case TemperatureSeverity.unavailable:
        return 'N/A';
    }
  }

  Future<void> _rebuildMenu() async {
    final displayed = _displayedDevice;
    final menu = Menu(
      items: [
        if (_devices.isEmpty)
          MenuItem(disabled: true, label: 'Scanning for drives…')
        else ...[
          for (final d in _devices)
            MenuItem.checkbox(
              key: 'device:${d.id}',
              label: '${d.name}   ${d.valueText}',
              checked: displayed?.id == d.id,
            ),
        ],
        MenuItem.separator(),
        MenuItem(key: 'open', label: 'Open Dashboard'),
        MenuItem(
          key: 'pause_resume',
          label: _paused ? 'Resume Monitoring' : 'Pause Monitoring',
        ),
        MenuItem(key: 'settings', label: 'Settings'),
        MenuItem(key: 'rescan', label: 'Rescan Drives'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  void handleMenuClick(String key) {
    if (key.startsWith('device:')) {
      _selectDevice(key.substring('device:'.length));
      return;
    }
    switch (key) {
      case 'open':
        onOpenDashboard();
      case 'pause_resume':
        onPauseResume();
      case 'settings':
        onOpenSettings();
      case 'rescan':
        onRescan();
      case 'quit':
        onQuit();
    }
  }
}

class _Listener with TrayListener {
  _Listener({required this.onDoubleClick, required this.onMenuItemClick});

  final void Function() onDoubleClick;
  final void Function(String key) onMenuItemClick;

  @override
  void onTrayIconMouseDown() => onDoubleClick();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null) onMenuItemClick(key);
  }
}
