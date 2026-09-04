import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/storage_thresholds.dart';
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
    this.storageThresholds = StorageThresholds.defaults,
    this.storageAlertsEnabled = true,
    this.perDeviceStorageThresholds = const {},
    this.rapidRiseAlertsEnabled = true,
    this.rapidRiseDeltaCelsius = AppConstants.defaultRapidRiseDeltaCelsius,
    this.rapidRiseWindow = AppConstants.defaultRapidRiseWindow,
    this.perDeviceRapidRiseDelta = const {},
    this.healthPollingInterval = AppConstants.defaultHealthPollingInterval,
    this.healthAlertsEnabled = true,
    this.themeMode = ThemeMode.system,
    this.uiDensity = 1.0,
    this.startWithOS = false,
    this.startMinimized = false,
    this.showTrayIcon = true,
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

  final StorageThresholds storageThresholds;
  final bool storageAlertsEnabled;
  final Map<String, StorageThresholds> perDeviceStorageThresholds;

  final bool rapidRiseAlertsEnabled;
  final double rapidRiseDeltaCelsius;
  final Duration rapidRiseWindow;
  final Map<String, double> perDeviceRapidRiseDelta;

  final Duration healthPollingInterval;
  final bool healthAlertsEnabled;

  final ThemeMode themeMode;
  final double uiDensity;

  final bool startWithOS;
  final bool startMinimized;
  final bool showTrayIcon;
  final bool minimizeToTray;
  final bool closeToTray;

  final bool diagnosticLoggingEnabled;
  final WidgetSettings widget;

  final bool mockBackendForced;

  final bool dashboardCompactView;

  TemperatureThresholds thresholdsFor(String deviceId) =>
      perDeviceThresholds[deviceId] ?? globalThresholds;

  StorageThresholds storageThresholdsFor(String deviceId) =>
      perDeviceStorageThresholds[deviceId] ?? storageThresholds;

  double rapidRiseDeltaFor(String deviceId) =>
      perDeviceRapidRiseDelta[deviceId] ?? rapidRiseDeltaCelsius;

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
    StorageThresholds? storageThresholds,
    bool? storageAlertsEnabled,
    Map<String, StorageThresholds>? perDeviceStorageThresholds,
    bool? rapidRiseAlertsEnabled,
    double? rapidRiseDeltaCelsius,
    Duration? rapidRiseWindow,
    Map<String, double>? perDeviceRapidRiseDelta,
    Duration? healthPollingInterval,
    bool? healthAlertsEnabled,
    ThemeMode? themeMode,
    double? uiDensity,
    bool? startWithOS,
    bool? startMinimized,
    bool? showTrayIcon,
    bool? minimizeToTray,
    bool? closeToTray,
    bool? diagnosticLoggingEnabled,
    WidgetSettings? widget,
    bool? mockBackendForced,
    bool? dashboardCompactView,
  }) {
    return AppSettings(
      pollingInterval: pollingInterval ?? this.pollingInterval,
      deviceDiscoveryInterval:
          deviceDiscoveryInterval ?? this.deviceDiscoveryInterval,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationCooldown: notificationCooldown ?? this.notificationCooldown,
      recoveryNotificationsEnabled:
          recoveryNotificationsEnabled ?? this.recoveryNotificationsEnabled,
      globalThresholds: globalThresholds ?? this.globalThresholds,
      perDeviceThresholds: perDeviceThresholds ?? this.perDeviceThresholds,
      storageThresholds: storageThresholds ?? this.storageThresholds,
      storageAlertsEnabled: storageAlertsEnabled ?? this.storageAlertsEnabled,
      perDeviceStorageThresholds:
          perDeviceStorageThresholds ?? this.perDeviceStorageThresholds,
      rapidRiseAlertsEnabled:
          rapidRiseAlertsEnabled ?? this.rapidRiseAlertsEnabled,
      rapidRiseDeltaCelsius:
          rapidRiseDeltaCelsius ?? this.rapidRiseDeltaCelsius,
      rapidRiseWindow: rapidRiseWindow ?? this.rapidRiseWindow,
      perDeviceRapidRiseDelta:
          perDeviceRapidRiseDelta ?? this.perDeviceRapidRiseDelta,
      healthPollingInterval:
          healthPollingInterval ?? this.healthPollingInterval,
      healthAlertsEnabled: healthAlertsEnabled ?? this.healthAlertsEnabled,
      themeMode: themeMode ?? this.themeMode,
      uiDensity: uiDensity ?? this.uiDensity,
      startWithOS: startWithOS ?? this.startWithOS,
      startMinimized: startMinimized ?? this.startMinimized,
      showTrayIcon: showTrayIcon ?? this.showTrayIcon,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      closeToTray: closeToTray ?? this.closeToTray,
      diagnosticLoggingEnabled:
          diagnosticLoggingEnabled ?? this.diagnosticLoggingEnabled,
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
    'perDeviceThresholds': perDeviceThresholds.map(
      (k, v) => MapEntry(k, v.toJson()),
    ),
    'storageThresholds': storageThresholds.toJson(),
    'storageAlertsEnabled': storageAlertsEnabled,
    'perDeviceStorageThresholds': perDeviceStorageThresholds.map(
      (k, v) => MapEntry(k, v.toJson()),
    ),
    'rapidRiseAlertsEnabled': rapidRiseAlertsEnabled,
    'rapidRiseDeltaCelsius': rapidRiseDeltaCelsius,
    'rapidRiseWindowMs': rapidRiseWindow.inMilliseconds,
    'perDeviceRapidRiseDelta': perDeviceRapidRiseDelta,
    'healthPollingIntervalMs': healthPollingInterval.inMilliseconds,
    'healthAlertsEnabled': healthAlertsEnabled,
    'themeMode': themeMode.name,
    'uiDensity': uiDensity,
    'startWithOS': startWithOS,
    'startMinimized': startMinimized,
    'showTrayIcon': showTrayIcon,
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
        perDevice[entry.key] = TemperatureThresholds.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    final perDeviceStorage = <String, StorageThresholds>{};
    final rawPerDeviceStorage =
        json['perDeviceStorageThresholds'] as Map<String, dynamic>?;
    if (rawPerDeviceStorage != null) {
      for (final entry in rawPerDeviceStorage.entries) {
        perDeviceStorage[entry.key] = StorageThresholds.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    final perDeviceRapidRise = <String, double>{};
    final rawPerDeviceRapidRise =
        json['perDeviceRapidRiseDelta'] as Map<String, dynamic>?;
    if (rawPerDeviceRapidRise != null) {
      for (final entry in rawPerDeviceRapidRise.entries) {
        final v = (entry.value as num?)?.toDouble();
        if (v != null) perDeviceRapidRise[entry.key] = v;
      }
    }
    return AppSettings(
      pollingInterval: Duration(
        milliseconds:
            json['pollingIntervalMs'] as int? ??
            AppConstants.defaultPollingInterval.inMilliseconds,
      ),
      deviceDiscoveryInterval: Duration(
        milliseconds:
            json['deviceDiscoveryIntervalMs'] as int? ??
            AppConstants.deviceDiscoveryInterval.inMilliseconds,
      ),
      temperatureUnit: TemperatureUnit.values.firstWhere(
        (u) => u.name == json['temperatureUnit'],
        orElse: () => TemperatureUnit.celsius,
      ),
      monitoringEnabled: json['monitoringEnabled'] as bool? ?? true,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      notificationCooldown: Duration(
        milliseconds:
            json['notificationCooldownMs'] as int? ??
            AppConstants.defaultNotificationCooldown.inMilliseconds,
      ),
      recoveryNotificationsEnabled:
          json['recoveryNotificationsEnabled'] as bool? ?? true,
      globalThresholds: json['globalThresholds'] != null
          ? TemperatureThresholds.fromJson(
              json['globalThresholds'] as Map<String, dynamic>,
            )
          : TemperatureThresholds.defaults,
      perDeviceThresholds: perDevice,
      storageThresholds: json['storageThresholds'] != null
          ? StorageThresholds.fromJson(
              json['storageThresholds'] as Map<String, dynamic>,
            )
          : StorageThresholds.defaults,
      storageAlertsEnabled: json['storageAlertsEnabled'] as bool? ?? true,
      perDeviceStorageThresholds: perDeviceStorage,
      rapidRiseAlertsEnabled: json['rapidRiseAlertsEnabled'] as bool? ?? true,
      rapidRiseDeltaCelsius:
          (json['rapidRiseDeltaCelsius'] as num?)?.toDouble() ??
          AppConstants.defaultRapidRiseDeltaCelsius,
      rapidRiseWindow: Duration(
        milliseconds:
            json['rapidRiseWindowMs'] as int? ??
            AppConstants.defaultRapidRiseWindow.inMilliseconds,
      ),
      perDeviceRapidRiseDelta: perDeviceRapidRise,
      healthPollingInterval: Duration(
        milliseconds:
            json['healthPollingIntervalMs'] as int? ??
            AppConstants.defaultHealthPollingInterval.inMilliseconds,
      ),
      healthAlertsEnabled: json['healthAlertsEnabled'] as bool? ?? true,
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      uiDensity: (json['uiDensity'] as num?)?.toDouble() ?? 1.0,
      startWithOS: json['startWithOS'] as bool? ?? false,
      startMinimized: json['startMinimized'] as bool? ?? false,
      showTrayIcon: json['showTrayIcon'] as bool? ?? true,
      minimizeToTray: json['minimizeToTray'] as bool? ?? true,
      closeToTray: json['closeToTray'] as bool? ?? true,
      diagnosticLoggingEnabled:
          json['diagnosticLoggingEnabled'] as bool? ?? false,
      widget: json['widget'] != null
          ? WidgetSettings.fromJson(json['widget'] as Map<String, dynamic>)
          : const WidgetSettings(),
      mockBackendForced: json['mockBackendForced'] as bool? ?? false,
      dashboardCompactView: json['dashboardCompactView'] as bool? ?? false,
    );
  }
}
