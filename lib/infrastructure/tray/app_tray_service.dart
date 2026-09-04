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
  _Listener? _listener;

  Future<void> initialize() async {
    await _applyIcon(TemperatureSeverity.normal);
    await _rebuildMenu();
    final listener = _Listener(
      onDoubleClick: onOpenDashboard,
      onMenuItemClick: handleMenuClick,
    );
    _listener = listener;
    trayManager.addListener(listener);
  }

  Future<void> destroy() async {
    final listener = _listener;
    if (listener != null) {
      trayManager.removeListener(listener);
      _listener = null;
    }
    try {
      await trayManager.destroy();
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Failed to destroy tray: $e');
    }
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

      // tray_manager does not implement setToolTip on Linux.
      if (!Platform.isLinux) {
        try {
          await trayManager.setToolTip('DriveGuard - ${_tooltipSummary(severity)}');
        } catch (_) {}
      }

      // On macOS and Linux (Ayatana/AppIndicator), setTitle displays the temperature
      // directly in the top menu bar / system panel beside the icon.
      if (Platform.isMacOS || Platform.isLinux) {
        try {
          await trayManager.setTitle(
            displayed == null ? '' : displayed.valueText,
          );
        } catch (_) {}
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

  /// Wraps raw PNG bytes in a standard 22-byte Windows .ico container
  /// (ICONDIR + single ICONDIRENTRY).
  ///
  /// Windows Vista+ Shell_NotifyIcon and LoadImage natively decode PNG-compressed
  /// icons within .ico files. Passing a raw .png directly causes Win32 LoadImage
  /// to fail with NULL, which prevents the system tray icon from appearing.
  static Uint8List wrapPngInIco(Uint8List pngBytes, int width, int height) {
    final byteData = ByteData(22 + pngBytes.length);
    // ICONDIR structure (6 bytes)
    byteData.setUint16(0, 0, Endian.little); // Reserved: must be 0
    byteData.setUint16(2, 1, Endian.little); // Image type: 1 = ICO (2 = CUR)
    byteData.setUint16(4, 1, Endian.little); // Number of images: 1

    // ICONDIRENTRY structure (16 bytes)
    byteData.setUint8(6, width >= 256 ? 0 : width); // Width in pixels (0 means 256)
    byteData.setUint8(7, height >= 256 ? 0 : height); // Height in pixels (0 means 256)
    byteData.setUint8(8, 0); // Number of colors in palette (0 = no palette / >=8bpp)
    byteData.setUint8(9, 0); // Reserved: must be 0
    byteData.setUint16(10, 1, Endian.little); // Color planes (0 or 1)
    byteData.setUint16(12, 32, Endian.little); // Bits per pixel (32-bit RGBA)
    byteData.setUint32(14, pngBytes.length, Endian.little); // Size of image data in bytes
    byteData.setUint32(18, 22, Endian.little); // File offset of image data (6 + 16 = 22)

    final result = byteData.buffer.asUint8List();
    result.setRange(22, 22 + pngBytes.length, pngBytes);
    return result;
  }

  Future<String> _iconPathFor(TemperatureSeverity severity, String? label) async {
    // Include label and platform in cache key so icon re-renders when temperature changes.
    final isWindows = Platform.isWindows;
    final cacheKey = '${severity.name}_${label ?? ''}_${isWindows ? "ico" : "png"}';
    final cached = _iconPathCache[cacheKey];
    if (cached != null && File(cached).existsSync()) return cached;

    final pngBytes = await _renderTrayIcon(_severityColor(severity), label);
    final bytes = isWindows ? wrapPngInIco(pngBytes, 64, 64) : pngBytes;
    final ext = isWindows ? 'ico' : 'png';
    final safe = (label ?? '').replaceAll(RegExp(r'[^\w]'), '_');
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}driveguard_tray_${severity.name}_$safe.$ext',
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

    // If label is too long (e.g. "Permission required", "Disconnected"),
    // show a clean short fallback or N/A so it doesn't overflow the icon.
    final displayLabel = (label == null || label.length > 5)
        ? (label == null ? null : 'N/A')
        : label;

    if (displayLabel != null && displayLabel.isNotEmpty) {
      // Draw the label text centred in the icon.
      // ui.Paragraph lets us render text onto a canvas in dart:ui.
      final fontSize = switch (displayLabel.length) {
        <= 2 => 32.0,
        3 => 27.0,
        4 => 23.0,
        _ => 18.0,
      };
      final style = ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: ui.FontWeight.w800,
      );
      final paraStyle = ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        maxLines: 1,
      );
      final builder = ui.ParagraphBuilder(paraStyle)
        ..pushStyle(style)
        ..addText(displayLabel);
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
    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to rebuild tray menu: $e');
    }
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
    if (!Platform.isLinux) {
      try {
        trayManager.popUpContextMenu();
      } catch (_) {}
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null) onMenuItemClick(key);
  }
}
