import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';

class WidgetSettings {
  const WidgetSettings({
    this.enabled = false,
    this.x = 100,
    this.y = 100,
    this.width = 260,
    this.height = 180,
    this.opacity = 0.95,
    this.alwaysOnTop = true,
    this.compact = false,
    this.borderless = false,
  });

  final bool enabled;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
  final bool alwaysOnTop;
  final bool compact;
  final bool borderless;

  WidgetSettings copyWith({
    bool? enabled,
    double? x,
    double? y,
    double? width,
    double? height,
    double? opacity,
    bool? alwaysOnTop,
    bool? compact,
    bool? borderless,
  }) {
    return WidgetSettings(
      enabled: enabled ?? this.enabled,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      opacity: opacity ?? this.opacity,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      compact: compact ?? this.compact,
      borderless: borderless ?? this.borderless,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'opacity': opacity,
        'alwaysOnTop': alwaysOnTop,
        'compact': compact,
        'borderless': borderless,
      };

  factory WidgetSettings.fromJson(Map<String, dynamic> json) => WidgetSettings(
        enabled: json['enabled'] as bool? ?? false,
        x: (json['x'] as num?)?.toDouble() ?? 100,
        y: (json['y'] as num?)?.toDouble() ?? 100,
        width: (json['width'] as num?)?.toDouble() ?? 260,
        height: (json['height'] as num?)?.toDouble() ?? 180,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.95,
        alwaysOnTop: json['alwaysOnTop'] as bool? ?? true,
        compact: json['compact'] as bool? ?? false,
        borderless: json['borderless'] as bool? ?? false,
      );
}

/// The full persisted configuration surface (section 19 & 33).
class AppSettings {
  const AppSettings({
    this.pollingInterval = AppConstants.defaultPollingInterval,
    this.deviceDiscoveryInterval = AppConstants.deviceDiscoveryInterval,
    this.temperatureUnit = TemperatureUnit.celsius,
    this.monitoringEnabled = true,
    this.notificationsEnabled = true,
    this.notificationCooldown = AppConstants.defaultNotificationCooldown,
    this.recoveryNotificationsEnabled = true,
    this.globalThresholds = TemperatureThresholds.defaults,
    this.perDeviceThresholds = const {},
    this.themeMode = ThemeMode.system,
    this.uiDensity = 1.0,
    this.startWithOS = false,
    this.startMinimized = false,
    this.minimizeToTray = true,
    this.closeToTray = true,
    this.diagnosticLoggingEnabled = false,
    this.widget = const WidgetSettings(),
    this.mockBackendForced = false,
    this.dashboardCompactView = false,
  });

  final Duration pollingInterval;
  final Duration deviceDiscoveryInterval;
  final TemperatureUnit temperatureUnit;
  final bool monitoringEnabled;

  final bool notificationsEnabled;
  final Duration notificationCooldown;
  final bool recoveryNotificationsEnabled;

  final TemperatureThresholds globalThresholds;
  final Map<String, TemperatureThresholds> perDeviceThresholds;

  final ThemeMode themeMode;
  final double uiDensity;

  final bool startWithOS;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;

  final bool diagnosticLoggingEnabled;
  final WidgetSettings widget;

  /// Advanced -> "use simulated devices". Not a Windows/macOS/Linux
  /// distinction - just a developer/demo escape hatch.
  final bool mockBackendForced;

  /// Home page drive listing: false = card grid, true = compact one-row-
  /// per-drive list. Persisted so the choice survives a restart.
  final bool dashboardCompactView;

  TemperatureThresholds thresholdsFor(String deviceId) =>
      perDeviceThresholds[deviceId] ?? globalThresholds;

  AppSettings copyWith({
    Duration? pollingInterval,
    Duration? deviceDiscoveryInterval,
    TemperatureUnit? temperatureUnit,
    bool? monitoringEnabled,
    bool? notificationsEnabled,
    Duration? notificationCooldown,
    bool? recoveryNotificationsEnabled,
    TemperatureThresholds? globalThresholds,
    Map<String, TemperatureThresholds>? perDeviceThresholds,
    ThemeMode? themeMode,
    double? uiDensity,
    bool? startWithOS,
    bool? startMinimized,
    bool? minimizeToTray,
    bool? closeToTray,
    bool? diagnosticLoggingEnabled,
    WidgetSettings? widget,
    bool? mockBackendForced,
    bool? dashboardCompactView,
  }) {
    return AppSettings(
      pollingInterval: pollingInterval ?? this.pollingInterval,
      deviceDiscoveryInterval: deviceDiscoveryInterval ?? this.deviceDiscoveryInterval,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationCooldown: notificationCooldown ?? this.notificationCooldown,
      recoveryNotificationsEnabled:
          recoveryNotificationsEnabled ?? this.recoveryNotificationsEnabled,
      globalThresholds: globalThresholds ?? this.globalThresholds,
      perDeviceThresholds: perDeviceThresholds ?? this.perDeviceThresholds,
      themeMode: themeMode ?? this.themeMode,
      uiDensity: uiDensity ?? this.uiDensity,
      startWithOS: startWithOS ?? this.startWithOS,
      startMinimized: startMinimized ?? this.startMinimized,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      closeToTray: closeToTray ?? this.closeToTray,
      diagnosticLoggingEnabled: diagnosticLoggingEnabled ?? this.diagnosticLoggingEnabled,
      widget: widget ?? this.widget,
      mockBackendForced: mockBackendForced ?? this.mockBackendForced,
      dashboardCompactView: dashboardCompactView ?? this.dashboardCompactView,
    );
  }

  Map<String, dynamic> toJson() => {
        'pollingIntervalMs': pollingInterval.inMilliseconds,
        'deviceDiscoveryIntervalMs': deviceDiscoveryInterval.inMilliseconds,
        'temperatureUnit': temperatureUnit.name,
        'monitoringEnabled': monitoringEnabled,
        'notificationsEnabled': notificationsEnabled,
        'notificationCooldownMs': notificationCooldown.inMilliseconds,
        'recoveryNotificationsEnabled': recoveryNotificationsEnabled,
        'globalThresholds': globalThresholds.toJson(),
        'perDeviceThresholds':
            perDeviceThresholds.map((k, v) => MapEntry(k, v.toJson())),
        'themeMode': themeMode.name,
        'uiDensity': uiDensity,
        'startWithOS': startWithOS,
        'startMinimized': startMinimized,
        'minimizeToTray': minimizeToTray,
        'closeToTray': closeToTray,
        'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
        'widget': widget.toJson(),
        'mockBackendForced': mockBackendForced,
        'dashboardCompactView': dashboardCompactView,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final perDevice = <String, TemperatureThresholds>{};
    final rawPerDevice = json['perDeviceThresholds'] as Map<String, dynamic>?;
    if (rawPerDevice != null) {
      for (final entry in rawPerDevice.entries) {
        perDevice[entry.key] =
            TemperatureThresholds.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return AppSettings(
      pollingInterval: Duration(
          milliseconds: json['pollingIntervalMs'] as int? ??
              AppConstants.defaultPollingInterval.inMilliseconds),
      deviceDiscoveryInterval: Duration(
          milliseconds: json['deviceDiscoveryIntervalMs'] as int? ??
              AppConstants.deviceDiscoveryInterval.inMilliseconds),
      temperatureUnit: TemperatureUnit.values.firstWhere(
          (u) => u.name == json['temperatureUnit'],
          orElse: () => TemperatureUnit.celsius),
      monitoringEnabled: json['monitoringEnabled'] as bool? ?? true,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      notificationCooldown: Duration(
          milliseconds: json['notificationCooldownMs'] as int? ??
              AppConstants.defaultNotificationCooldown.inMilliseconds),
      recoveryNotificationsEnabled: json['recoveryNotificationsEnabled'] as bool? ?? true,
      globalThresholds: json['globalThresholds'] != null
          ? TemperatureThresholds.fromJson(json['globalThresholds'] as Map<String, dynamic>)
          : TemperatureThresholds.defaults,
      perDeviceThresholds: perDevice,
      themeMode: ThemeMode.values.firstWhere((m) => m.name == json['themeMode'],
          orElse: () => ThemeMode.system),
      uiDensity: (json['uiDensity'] as num?)?.toDouble() ?? 1.0,
      startWithOS: json['startWithOS'] as bool? ?? false,
      startMinimized: json['startMinimized'] as bool? ?? false,
      minimizeToTray: json['minimizeToTray'] as bool? ?? true,
      closeToTray: json['closeToTray'] as bool? ?? true,
      diagnosticLoggingEnabled: json['diagnosticLoggingEnabled'] as bool? ?? false,
      widget: json['widget'] != null
          ? WidgetSettings.fromJson(json['widget'] as Map<String, dynamic>)
          : const WidgetSettings(),
      mockBackendForced: json['mockBackendForced'] as bool? ?? false,
      dashboardCompactView: json['dashboardCompactView'] as bool? ?? false,
    );
  }
}
