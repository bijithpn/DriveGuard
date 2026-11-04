import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tray_manager/tray_manager.dart';

import '../../application/settings/app_settings.dart' show TraySettings;
import '../../core/logging/app_logger.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import 'tray_icon_painter.dart';

class TrayDeviceSummary {
  const TrayDeviceSummary({
    required this.id,
    required this.name,
    required this.valueText,
    required this.severity,
    this.celsius,
    this.fraction = 0,
    this.detail,
  });

  final String id;
  final String name;

  /// Formatted in the user's unit, e.g. "42°C".
  final String valueText;
  final TemperatureSeverity severity;
  final double? celsius;

  /// 0..1 — how close to the critical limit (drives the ring style).
  final double fraction;

  /// One-line extra info for the detailed menu ("Normal · 63% used").
  final String? detail;
}

/// System-tray / menu-bar presence.
///
/// The icon is drawn at runtime from the user's chosen style, so it looks the
/// same on every platform — nothing depends on the OS supporting a text label
/// next to the icon (Windows doesn't, and macOS/Linux do it inconsistently).
class AppTrayService {
  static const _tag = 'AppTrayService';

  final void Function() onOpenDashboard;
  final void Function() onPauseResume;
  final void Function() onOpenSettings;
  final void Function() onRescan;
  final void Function() onQuit;
  final void Function()? onOpenStorageSense;

  /// Called when the user changes an option from the tray menu itself.
  final void Function(TraySettings)? onTraySettingsChanged;

  AppTrayService({
    required this.onOpenDashboard,
    required this.onPauseResume,
    required this.onOpenSettings,
    required this.onRescan,
    required this.onQuit,
    this.onOpenStorageSense,
    this.onTraySettingsChanged,
    TraySettings settings = const TraySettings(),
  }) : _settings = settings;

  TraySettings _settings;
  TemperatureSeverity _lastSeverity = TemperatureSeverity.normal;
  bool _paused = false;
  List<TrayDeviceSummary> _devices = const [];
  String? _averageText;
  double _averageFraction = 0;
  final Map<String, String> _iconPathCache = {};
  Directory? _iconDir;

  String? _selectedDeviceId;
  bool _selectionIsExplicit = false;
  _Listener? _listener;
  Future<void> _queue = Future.value();

  Future<void> initialize() async {
    await _prepareIconDir();
    await _applyIcon();
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

  /// Icon files live in one private folder that is wiped on start, so they
  /// never pile up in the system temp directory.
  Future<void> _prepareIconDir() async {
    try {
      final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}driveguard_tray',
      );
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      _iconDir = dir;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Icon dir unavailable: $e');
    }
  }

  // --- Public updates (serialised so rapid updates can't interleave) -------

  Future<void> _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      AppLogger.instance.debug(_tag, 'Tray update failed: $e');
    });
    return _queue;
  }

  Future<void> updateSeverity(TemperatureSeverity severity) {
    if (severity == _lastSeverity) return Future.value();
    _lastSeverity = severity;
    return _enqueue(_applyIcon);
  }

  Future<void> setPaused(bool paused) {
    if (paused == _paused) return Future.value();
    _paused = paused;
    return _enqueue(_rebuildMenu);
  }

  Future<void> updateDevices(
    List<TrayDeviceSummary> devices, {
    String? averageText,
    double averageFraction = 0,
  }) {
    _devices = devices;
    _averageText = averageText;
    _averageFraction = averageFraction;
    if (_selectionIsExplicit &&
        !devices.any((d) => d.id == _selectedDeviceId)) {
      _selectionIsExplicit = false;
    }
    return _enqueue(() async {
      await _applyIcon();
      await _rebuildMenu();
    });
  }

  Future<void> applySettings(TraySettings settings) {
    if (settings == _settings) return Future.value();
    _settings = settings;
    return _enqueue(() async {
      await _applyIcon();
      await _rebuildMenu();
    });
  }

  /// The OS light/dark appearance changed: neutral icon colours must flip.
  Future<void> onBrightnessChanged() {
    _iconPathCache.clear();
    return _enqueue(_applyIcon);
  }

  // --- What is displayed ----------------------------------------------------

  int _rank(TemperatureSeverity s) => switch (s) {
    TemperatureSeverity.critical => 4,
    TemperatureSeverity.warning => 3,
    TemperatureSeverity.warm => 2,
    TemperatureSeverity.normal => 1,
    TemperatureSeverity.unavailable => 0,
  };

  TrayDeviceSummary? get _hottest {
    if (_devices.isEmpty) return null;
    return _devices.reduce((a, b) {
      final r = _rank(a.severity).compareTo(_rank(b.severity));
      if (r != 0) return r > 0 ? a : b;
      return (a.celsius ?? -1000) >= (b.celsius ?? -1000) ? a : b;
    });
  }

  TrayDeviceSummary? get _displayedDevice {
    if (_devices.isEmpty) return null;
    if (_selectionIsExplicit) {
      for (final d in _devices) {
        if (d.id == _selectedDeviceId) return d;
      }
    }
    return _hottest;
  }

  /// (text like "42°C", fraction, severity) shown by the icon.
  ({String? text, double fraction, TemperatureSeverity severity}) get _shown {
    if (_devices.isEmpty) {
      return (
        text: null,
        fraction: 0,
        severity: TemperatureSeverity.unavailable,
      );
    }
    final worst = _lastSeverity;
    if (!_selectionIsExplicit &&
        _settings.metric == TrayMetric.average &&
        _averageText != null) {
      return (text: _averageText, fraction: _averageFraction, severity: worst);
    }
    final d = _displayedDevice;
    return (text: d?.valueText, fraction: d?.fraction ?? 0, severity: worst);
  }

  // --- Icon -----------------------------------------------------------------

  bool get _darkBackground =>
      ui.PlatformDispatcher.instance.platformBrightness == ui.Brightness.dark;

  Future<void> _applyIcon() async {
    try {
      final shown = _shown;
      var spec = TrayIconSpec(
        style: _settings.style,
        severity: shown.severity,
        numberText: trayNumberText(shown.text),
        unit: trayUnitText(shown.text),
        fraction: shown.fraction,
        darkBackground: _darkBackground,
      );
      // macOS can tint monochrome images to match the menu bar automatically.
      if (Platform.isMacOS && !spec.needsColor) {
        spec = TrayIconSpec(
          style: spec.style,
          severity: spec.severity,
          numberText: spec.numberText,
          unit: spec.unit,
          fraction: spec.fraction,
          darkBackground: spec.darkBackground,
          template: true,
        );
      }
      final path = await _iconPathFor(spec);
      await trayManager.setIcon(path, isTemplate: spec.template);

      if (!Platform.isLinux) {
        try {
          await trayManager.setToolTip('DriveGuard — ${_tooltipSummary()}');
        } catch (_) {}
      }

      // Text beside the icon is a macOS/Linux-only extra, and only when the
      // icon itself doesn't already show the number.
      if (Platform.isMacOS || Platform.isLinux) {
        final iconShowsNumber =
            _settings.style == TrayIconStyle.temperature ||
            _settings.style == TrayIconStyle.ring;
        try {
          await trayManager.setTitle(
            _settings.showText && !iconShowsNumber ? (shown.text ?? '') : '',
          );
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to apply tray icon: $e');
    }
  }

  String _tooltipSummary() {
    if (_devices.isEmpty) return 'Scanning for drives…';
    if (_devices.length == 1) {
      final d = _devices.single;
      return '${d.name}: ${d.valueText} · ${_severityLabel(d.severity)}';
    }
    final h = _hottest!;
    return '${_devices.length} drives · Hottest ${h.valueText} · '
        '${_severityLabel(_lastSeverity)}';
  }

  String _severityLabel(TemperatureSeverity s) => switch (s) {
    TemperatureSeverity.normal || TemperatureSeverity.warm => 'Normal',
    TemperatureSeverity.warning => 'Warning',
    TemperatureSeverity.critical => 'Critical',
    TemperatureSeverity.unavailable => 'N/A',
  };

  Future<String> _iconPathFor(TrayIconSpec spec) async {
    final isWindows = Platform.isWindows;
    final key = '${spec.cacheKey}_${isWindows ? 'ico' : 'png'}';
    final cached = _iconPathCache[key];
    if (cached != null && File(cached).existsSync()) return cached;

    final png = Uint8List.fromList(await renderTrayIconPng(spec));
    final bytes = isWindows ? wrapPngInIco(png, 64, 64) : png;
    final dir = _iconDir?.path ?? Directory.systemTemp.path;
    final file = File(
      '$dir${Platform.pathSeparator}dg_${key.replaceAll(RegExp(r'[^\w]'), '_')}.${isWindows ? 'ico' : 'png'}',
    );
    await file.writeAsBytes(bytes, flush: true);
    _iconPathCache[key] = file.path;
    return file.path;
  }

  /// Wraps a PNG in a single-image ICO container (Windows tray requires .ico).
  static Uint8List wrapPngInIco(Uint8List pngBytes, int width, int height) {
    final byteData = ByteData(22 + pngBytes.length);

    byteData.setUint16(0, 0, Endian.little);
    byteData.setUint16(2, 1, Endian.little);
    byteData.setUint16(4, 1, Endian.little);

    byteData.setUint8(6, width >= 256 ? 0 : width);
    byteData.setUint8(7, height >= 256 ? 0 : height);
    byteData.setUint8(8, 0);
    byteData.setUint8(9, 0);
    byteData.setUint16(10, 1, Endian.little);
    byteData.setUint16(12, 32, Endian.little);
    byteData.setUint32(14, pngBytes.length, Endian.little);
    byteData.setUint32(18, 22, Endian.little);

    final result = byteData.buffer.asUint8List();
    result.setRange(22, 22 + pngBytes.length, pngBytes);
    return result;
  }

  // --- Menu -----------------------------------------------------------------

  String get _overallLabel {
    if (_paused) return 'Monitoring paused';
    if (_devices.isEmpty) return 'Scanning for drives…';
    final n = _devices.length;
    final attention = _devices
        .where((d) => _rank(d.severity) >= _rank(TemperatureSeverity.warning))
        .length;
    if (attention > 0) {
      return '$attention of $n drive${n == 1 ? '' : 's'} need attention';
    }
    return n == 1 ? '1 drive · all normal' : '$n drives · all normal';
  }

  Future<void> _rebuildMenu() async {
    final displayed = _displayedDevice;
    final detailed = _settings.menuDetail == TrayMenuDetail.detailed;
    final showTextSupported = Platform.isMacOS || Platform.isLinux;
    final menu = Menu(
      items: [
        MenuItem(disabled: true, label: _overallLabel),
        MenuItem.separator(),
        for (final d in _devices)
          MenuItem.checkbox(
            key: 'device:${d.id}',
            label: detailed && d.detail != null
                ? '${d.name}  —  ${d.valueText} · ${d.detail}'
                : '${d.name}   ${d.valueText}',
            checked: displayed?.id == d.id,
          ),
        if (_devices.isNotEmpty) MenuItem.separator(),
        MenuItem(key: 'open', label: 'Open Dashboard'),
        if (onOpenStorageSense != null)
          MenuItem(key: 'sense', label: 'Storage Sense'),
        MenuItem(
          key: 'pause_resume',
          label: _paused ? 'Resume Monitoring' : 'Pause Monitoring',
        ),
        MenuItem(key: 'rescan', label: 'Rescan Drives'),
        MenuItem.separator(),
        MenuItem.submenu(
          label: 'Tray Icon',
          submenu: Menu(
            items: [
              for (final s in TrayIconStyle.values)
                MenuItem.checkbox(
                  key: 'style:${s.name}',
                  label: s.label,
                  checked: _settings.style == s,
                ),
              MenuItem.separator(),
              for (final m in TrayMetric.values)
                MenuItem.checkbox(
                  key: 'metric:${m.name}',
                  label: m.label,
                  checked: !_selectionIsExplicit && _settings.metric == m,
                ),
              MenuItem.separator(),
              if (showTextSupported)
                MenuItem.checkbox(
                  key: 'showtext',
                  label: 'Show text beside icon',
                  checked: _settings.showText,
                ),
              MenuItem.checkbox(
                key: 'detail',
                label: 'Detailed drive list',
                checked: detailed,
              ),
            ],
          ),
        ),
        MenuItem(key: 'settings', label: 'Settings…'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit DriveGuard'),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Failed to rebuild tray menu: $e');
    }
  }

  void _change(TraySettings next) {
    onTraySettingsChanged?.call(next);
    unawaited(applySettings(next));
  }

  void handleMenuClick(String key) {
    if (key.startsWith('device:')) {
      _selectedDeviceId = key.substring('device:'.length);
      _selectionIsExplicit = true;
      unawaited(
        _enqueue(() async {
          await _applyIcon();
          await _rebuildMenu();
        }),
      );
      return;
    }
    if (key.startsWith('style:')) {
      final s = TrayIconStyle.values.where((e) => e.name == key.substring(6));
      if (s.isNotEmpty) _change(_settings.copyWith(style: s.first));
      return;
    }
    if (key.startsWith('metric:')) {
      final m = TrayMetric.values.where((e) => e.name == key.substring(7));
      if (m.isNotEmpty) {
        _selectionIsExplicit = false; // choosing a metric un-pins a drive
        final next = _settings.copyWith(metric: m.first);
        if (next == _settings) {
          unawaited(
            _enqueue(() async {
              await _applyIcon();
              await _rebuildMenu();
            }),
          );
        } else {
          _change(next);
        }
      }
      return;
    }
    switch (key) {
      case 'showtext':
        _change(_settings.copyWith(showText: !_settings.showText));
      case 'detail':
        _change(
          _settings.copyWith(
            menuDetail: _settings.menuDetail == TrayMenuDetail.detailed
                ? TrayMenuDetail.compact
                : TrayMenuDetail.detailed,
          ),
        );
      case 'open':
        onOpenDashboard();
      case 'sense':
        onOpenStorageSense?.call();
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
