import 'dart:async';
import 'dart:math' show min;

import '../../core/constants/app_constants.dart';
import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_health.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_device_event.dart';
import '../../domain/entities/storage_thresholds.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';
import '../../domain/entities/monitoring_session.dart';
import '../../infrastructure/persistence/incident_repository.dart';
import '../alerts/alert_engine.dart';
import '../alerts/predictive_engine.dart';
import '../notifications/notification_service.dart';
import '../prediction/trend_analyzer.dart';
import '../settings/app_settings.dart';
import 'metric_history_store.dart';
import 'temperature_history_store.dart';

/// How far back to persist samples once a device crosses warning/critical,
/// so a sudden shutdown can't erase the run-up to it. Matches the spec's
/// "keep ~10 minutes of pre-incident buffer" requirement.
const Duration _preIncidentWindow = Duration(minutes: 10);

class MonitoringService {
  MonitoringService({
    required StorageMonitor backend,
    required NotificationService notifications,
    required TemperatureHistoryStore historyStore,
    MetricHistoryStore? capacityHistoryStore,
    MetricHistoryStore? healthHistoryStore,
    PredictiveEngine predictiveEngine = const PredictiveEngine(),
    IncidentRepository? incidentRepository,
    String? sessionId,
  }) : _backend = backend,
       _notifications = notifications,
       _historyStore = historyStore,
       _incidentRepository = incidentRepository,
       _sessionId = sessionId,
       _capacityHistoryStore =
           capacityHistoryStore ??
           MetricHistoryStore(
             retention: AppConstants.predictiveCapacityRetention,
             minSampleInterval: AppConstants.predictiveCapacitySampleInterval,
           ),
       _healthHistoryStore =
           healthHistoryStore ??
           MetricHistoryStore(
             retention: AppConstants.predictiveHealthRetention,
             minSampleInterval: AppConstants.predictiveHealthSampleInterval,
           ),
       _predictiveEngine = predictiveEngine;

  static const _tag = 'MonitoringService';

  final StorageMonitor _backend;
  final NotificationService _notifications;
  final TemperatureHistoryStore _historyStore;
  final MetricHistoryStore _capacityHistoryStore;
  final MetricHistoryStore _healthHistoryStore;
  final PredictiveEngine _predictiveEngine;
  final IncidentRepository? _incidentRepository;
  final String? _sessionId;

  
  
  
  
  
  
  
  static const _spinDownRiskMinPollInterval = Duration(seconds: 30);
  static const _spinDownRiskMinHealthPollInterval = Duration(minutes: 5);

  final Map<String, StorageDevice> _devices = {};
  final Map<String, DateTime> _lastPolledAt = {};
  final Map<String, DateTime> _lastHealthPolledAt = {};
  final Map<String, DeviceAlertState> _alertStates = {};
  final Map<String, StorageAlertState> _capacityAlertStates = {};
  final Map<String, bool> _rapidRiseArmed = {};
  final Map<String, DateTime> _lastRapidRiseNotifiedAt = {};
  final Map<String, DeviceHealth> _lastKnownHealth = {};
  final Set<String> _disconnectedOnce = {};

  
  
  
  final Map<String, DateTime> _lastPredictiveTempAt = {};
  final Map<String, TemperatureSeverity> _lastPredictiveTempSeverity = {};
  final Map<String, DateTime> _lastPredictiveCapacityAt = {};
  final Map<String, CapacitySeverity> _lastPredictiveCapacitySeverity = {};
  final Map<String, DateTime> _lastPredictiveHealthAt = {};

  final _devicesController = StreamController<List<StorageDevice>>.broadcast();
  Stream<List<StorageDevice>> get devicesStream => _devicesController.stream;
  List<StorageDevice> get currentDevices =>
      _devices.values.toList(growable: false);

  final Map<String, StorageActivity> _latestActivity = {};
  final _activityController = StreamController<StorageActivity>.broadcast();

  Stream<StorageActivity> get activityStream => _activityController.stream;
  StorageActivity? latestActivityFor(String deviceId) =>
      _latestActivity[deviceId];

  Timer? _pollTimer;
  Timer? _discoveryTimer;
  Timer? _healthTimer;
  StreamSubscription<StorageDeviceEvent>? _deviceEventsSub;
  StreamSubscription<StorageActivity>? _activitySub;
  AppSettings _settings = const AppSettings();
  bool _paused = false;
  bool _started = false;

  bool get isPaused => _paused;

  Future<void> start(AppSettings settings) async {
    _settings = settings;
    await _notifications.initialize();
    await _discoverDevices();
    _rescheduleTimers();
    _listenForHotplugEvents();
    _listenForActivity();
    unawaited(_pollHealthAll());
    _started = true;
    AppLogger.instance.info(_tag, 'Monitoring started');
  }

  void _listenForActivity() {
    _activitySub = _backend.watchActivity().listen(
      (activity) {
        _latestActivity[activity.deviceId] = activity;
        if (!_activityController.isClosed) {
          _activityController.add(activity);
        }
      },
      onError: (Object e) {
        AppLogger.instance.debug(_tag, 'Activity stream error: $e');
      },
    );
  }

  void _listenForHotplugEvents() {
    _deviceEventsSub = _backend.watchDeviceEvents().listen(
      (event) {
        AppLogger.instance.info(
          _tag,
          'Hot-plug event: ${event.kind.name} ${event.deviceId}',
        );
        unawaited(_discoverDevices());
      },
      onError: (Object e) {
        AppLogger.instance.debug(_tag, 'Device event stream error: $e');
      },
    );
  }

  void updateSettings(AppSettings settings) {
    final intervalsChanged =
        settings.pollingInterval != _settings.pollingInterval ||
        settings.deviceDiscoveryInterval != _settings.deviceDiscoveryInterval ||
        settings.healthPollingInterval != _settings.healthPollingInterval;
    _settings = settings;
    if (_started && intervalsChanged) _rescheduleTimers();
  }

  void _rescheduleTimers() {
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    _healthTimer?.cancel();
    _pollTimer = Timer.periodic(_settings.pollingInterval, (_) => _pollAll());
    _discoveryTimer = Timer.periodic(
      _settings.deviceDiscoveryInterval,
      (_) => _discoverDevices(),
    );
    _healthTimer = Timer.periodic(
      _settings.healthPollingInterval,
      (_) => _pollHealthAll(),
    );
  }

  void pause() {
    _paused = true;
    AppLogger.instance.info(_tag, 'Monitoring paused');
  }

  void resume() {
    _paused = false;
    AppLogger.instance.info(_tag, 'Monitoring resumed');
  }

  Future<void> rescan() => _discoverDevices();

  Future<void> reinitializeAfterResume() async {
    AppLogger.instance.info(_tag, 'Reinitializing after system resume');
    await _discoverDevices();
    await _pollAll();
  }

  Future<void> _discoverDevices() async {
    List<StorageDevice> discovered;
    try {
      discovered = await _backend.getDevices();
    } catch (e) {
      AppLogger.instance.error(_tag, 'Device discovery failed', e);
      return;
    }

    final discoveredIds = discovered.map((d) => d.id).toSet();

    for (final device in discovered) {
      final existing = _devices[device.id];
      if (existing == null) {
        _devices[device.id] = device;
        _disconnectedOnce.remove(device.id);
        AppLogger.instance.info(
          _tag,
          'Discovered new device: ${device.type.name} ${device.interfaceType.name}',
        );
        unawaited(_pollOne(device.id));
      } else if (existing.monitoringStatus == MonitoringStatus.disconnected) {
        _devices[device.id] = device.copyWith(
          primaryTemperature: existing.primaryTemperature,
          monitoringStatus: MonitoringStatus.initializing,
        );
        _disconnectedOnce.remove(device.id);
        AppLogger.instance.info(_tag, 'Device reconnected: ${device.id}');
        unawaited(_pollOne(device.id));
      }
    }

    for (final id in _devices.keys.toList()) {
      if (discoveredIds.contains(id)) continue;
      if (_disconnectedOnce.contains(id)) {
        _devices.remove(id);
        _alertStates.remove(id);
        _capacityAlertStates.remove(id);
        _rapidRiseArmed.remove(id);
        _lastRapidRiseNotifiedAt.remove(id);
        _lastKnownHealth.remove(id);
        _historyStore.clearDevice(id);
        _capacityHistoryStore.clearDevice(id);
        _healthHistoryStore.clearDevice(id);
        _lastPredictiveTempAt.remove(id);
        _lastPredictiveTempSeverity.remove(id);
        _lastPredictiveCapacityAt.remove(id);
        _lastPredictiveCapacitySeverity.remove(id);
        _lastPredictiveHealthAt.remove(id);
        _latestActivity.remove(id);
        _lastPolledAt.remove(id);
        _lastHealthPolledAt.remove(id);
        _disconnectedOnce.remove(id);
        AppLogger.instance.info(_tag, 'Device removed after disconnect: $id');
      } else {
        _devices[id] = _devices[id]!.copyWith(
          monitoringStatus: MonitoringStatus.disconnected,
        );
        _disconnectedOnce.add(id);
        AppLogger.instance.warning(_tag, 'Device disconnected: $id');
      }
    }

    _emit();
    unawaited(_refreshCapacity());
  }

  Future<void> _refreshCapacity() async {
    final ids = _devices.keys
        .where(
          (id) =>
              _devices[id]!.monitoringStatus != MonitoringStatus.disconnected,
        )
        .toList();
    await Future.wait(
      ids.map((id) async {
        final device = _devices[id];
        if (device == null) return;
        try {
          final results = await Future.wait([
            _backend.getCapacity(id),
            _backend.getVolumes(id),
          ]);
          final current = _devices[id];
          if (current == null) return;
          final capacity = results[0] as StorageCapacity;
          final volumes = results[1] as List<StorageVolume>;
          final updated = current.copyWith(
            capacity: capacity,
            volumes: volumes,
          );
          _devices[id] = updated;

          AppLogger.instance.debug(
            _tag,
            'Capacity for $id: ${capacity.availability.name}'
            '${capacity.isValid ? ' (${capacity.usagePercent?.toStringAsFixed(0) ?? '?'}% used)' : ''}, '
            'volumes: ${volumes.length}',
          );
          final usagePercent = capacity.usagePercent;
          if (usagePercent != null) {
            _capacityHistoryStore.record(id, usagePercent);
          }
          await _evaluatePredictiveCapacity(id, capacity, updated);
          await _evaluateCapacityAlert(id, capacity, updated);
        } catch (e) {
          AppLogger.instance.debug(
            _tag,
            'Capacity/volume refresh failed for $id: $e',
          );
        }
      }),
    );
    _emit();
  }

  
  
  Future<void> _evaluatePredictiveCapacity(
    String id,
    StorageCapacity capacity,
    StorageDevice device,
  ) async {
    if (!_settings.predictiveAlertsEnabled || !_settings.storageAlertsEnabled) {
      return;
    }
    final usagePercent = capacity.usagePercent;
    if (usagePercent == null) return;
    
    final currentSeverity = capacitySeverityFor(id);
    if (currentSeverity == CapacitySeverity.warning ||
        currentSeverity == CapacitySeverity.critical) {
      return;
    }

    final points = _capacityHistoryStore
        .pointsFor(id)
        .map((p) => TrendPoint(p.timestamp, p.value))
        .toList();
    final hit = _predictiveEngine.evaluateCapacity(
      points: points,
      currentUsagePercent: usagePercent,
      thresholds: _settings.storageThresholdsFor(id),
      leadTime: AppConstants.predictiveCapacityLeadTime,
    );
    if (hit == null) return;

    final severity = hit.critical
        ? CapacitySeverity.critical
        : CapacitySeverity.warning;
    final lastAt = _lastPredictiveCapacityAt[id];
    final alreadyWarned =
        _lastPredictiveCapacitySeverity[id] == severity &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < _settings.notificationCooldown;
    if (alreadyWarned) return;

    _lastPredictiveCapacityAt[id] = DateTime.now();
    _lastPredictiveCapacitySeverity[id] = severity;

    AppLogger.instance.info(
      _tag,
      'Predictive capacity alert for $id: ${hit.etaText} to ${severity.name}',
    );
    if (!_settings.notificationsEnabled) return;
    await _notifications.showPredictiveCapacity(
      deviceId: id,
      deviceName: device.displayName,
      critical: hit.critical,
      etaText: hit.etaText,
    );
  }

  Future<void> _evaluateCapacityAlert(
    String id,
    StorageCapacity capacity,
    StorageDevice device,
  ) async {
    if (!_settings.storageAlertsEnabled) return;
    final alertState = _capacityAlertStates.putIfAbsent(
      id,
      StorageAlertState.new,
    );
    final result = alertState.evaluate(
      usagePercent: capacity.usagePercent,
      thresholds: _settings.storageThresholdsFor(id),
      cooldown: _settings.notificationCooldown,
      recoveryNotificationsEnabled: _settings.recoveryNotificationsEnabled,
    );
    if (!result.shouldNotify || !_settings.notificationsEnabled) return;

    if (!result.isRecoveryNotification &&
        _lastPredictiveCapacitySeverity[id] == result.severity &&
        _recentlyPredicted(_lastPredictiveCapacityAt[id])) {
      
      return;
    }

    final usageText = capacity.usagePercent != null
        ? '${capacity.usagePercent!.toStringAsFixed(0)}% used'
        : 'Usage unavailable';
    if (result.isRecoveryNotification) {
      await _notifications.showStorageRecovered(
        deviceId: id,
        deviceName: device.displayName,
        usageText: usageText,
      );
    } else if (result.severity == CapacitySeverity.critical) {
      await _notifications.showStorageCritical(
        deviceId: id,
        deviceName: device.displayName,
        usageText: usageText,
      );
    } else if (result.severity == CapacitySeverity.warning) {
      await _notifications.showStorageWarning(
        deviceId: id,
        deviceName: device.displayName,
        usageText: usageText,
      );
    }
  }

  Future<void> _pollHealthAll() async {
    final ids = _devices.keys
        .where(
          (id) =>
              _devices[id]!.monitoringStatus != MonitoringStatus.disconnected,
        )
        .toList();
    await Future.wait(ids.map(_pollHealthOne));
    _emit();
  }

  Future<void> _pollHealthOne(String id) async {
    final device = _devices[id];
    if (device == null) return;
    if (_throttledBySpinDownGuard(
      device,
      _lastHealthPolledAt,
      _spinDownRiskMinHealthPollInterval,
    )) {
      return;
    }
    try {
      final health = await _backend.getHealth(id);
      if (health == null) return;

      final current = _devices[id];
      if (current == null) return;
      final updated = current.copyWith(health: health);
      _devices[id] = updated;
      final wear = health.percentageUsed;
      if (wear != null) {
        _healthHistoryStore.record(id, wear.toDouble());
      }
      await _evaluatePredictiveHealthWear(id, health, updated);
      await _evaluateHealthAlert(id, health, updated);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Health read failed for $id: $e');
    }
  }

  
  
  
  
  
  
  
  
  Future<void> _evaluatePredictiveHealthWear(
    String id,
    DeviceHealth health,
    StorageDevice device,
  ) async {
    if (!_settings.predictiveAlertsEnabled || !_settings.healthAlertsEnabled) {
      return;
    }
    final wear = health.percentageUsed;
    if (wear == null) return;

    final points = _healthHistoryStore
        .pointsFor(id)
        .map((p) => TrendPoint(p.timestamp, p.value))
        .toList();
    final hit = _predictiveEngine.evaluateHealthWear(
      points: points,
      currentPercentageUsed: wear.toDouble(),
      leadTime: AppConstants.predictiveHealthLeadTime,
    );
    if (hit == null) return;

    final lastAt = _lastPredictiveHealthAt[id];
    if (_recentlyPredicted(lastAt)) return;
    _lastPredictiveHealthAt[id] = DateTime.now();

    AppLogger.instance.info(
      _tag,
      'Predictive health-wear alert for $id: ${hit.etaText} to end of rated life',
    );
    if (!_settings.notificationsEnabled) return;
    await _notifications.showPredictiveHealth(
      deviceId: id,
      deviceName: device.displayName,
      etaText: hit.etaText,
    );
  }

  Future<void> _evaluateHealthAlert(
    String id,
    DeviceHealth health,
    StorageDevice device,
  ) async {
    final previous = _lastKnownHealth[id];
    _lastKnownHealth[id] = health;
    if (previous == null) return;
    if (!_settings.healthAlertsEnabled || !_settings.notificationsEnabled) {
      return;
    }

    String? message;
    var critical = false;

    final statusWorsened =
        _healthRank(health.status) > _healthRank(previous.status);
    if (statusWorsened &&
        health.status != DeviceHealthStatus.unavailable &&
        health.status != DeviceHealthStatus.unknown) {
      critical = health.status == DeviceHealthStatus.critical;
      message =
          'Health status changed from ${previous.status.name} to '
          '${health.status.name}.';
    } else if (health.percentageUsed != null &&
        previous.percentageUsed != null &&
        health.percentageUsed! - previous.percentageUsed! >=
            AppConstants.defaultWearJumpAlertPercent) {
      message =
          'Wear increased from ${previous.percentageUsed}% to '
          '${health.percentageUsed}% since the last check.';
    } else if (health.mediaErrors != null &&
        previous.mediaErrors != null &&
        health.mediaErrors! > previous.mediaErrors!) {
      final newErrors = health.mediaErrors! - previous.mediaErrors!;
      message =
          '$newErrors new media/data error${newErrors == 1 ? '' : 's'} '
          'detected since the last check.';
    }

    if (message == null) return;
    AppLogger.instance.warning(_tag, 'Health alert for $id: $message');
    await _notifications.showHealthAlert(
      deviceId: id,
      deviceName: device.displayName,
      critical: critical,
      message: message,
      detailsText: _detailsFor(device),
    );
  }

  int _healthRank(DeviceHealthStatus status) {
    switch (status) {
      case DeviceHealthStatus.critical:
        return 3;
      case DeviceHealthStatus.warning:
        return 2;
      case DeviceHealthStatus.healthy:
        return 1;
      case DeviceHealthStatus.unknown:
      case DeviceHealthStatus.unavailable:
        return 0;
    }
  }

  Future<void> _pollAll() async {
    if (_paused || !_settings.monitoringEnabled) return;
    final ids = _devices.keys
        .where(
          (id) =>
              _devices[id]!.monitoringStatus != MonitoringStatus.disconnected,
        )
        .toList();
    await Future.wait(ids.map(_pollOne));
    _emit();
  }

  bool _recentlyPredicted(DateTime? at) =>
      at != null &&
      DateTime.now().difference(at) < _settings.notificationCooldown;

  bool _isSpinDownRisk(StorageDevice device) =>
      device.type == StorageDeviceType.hdd || device.isRemovable;

  bool _throttledBySpinDownGuard(
    StorageDevice device,
    Map<String, DateTime> lastPolledAt,
    Duration minInterval,
  ) {
    if (!_isSpinDownRisk(device)) return false;
    final last = lastPolledAt[device.id];
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return true;
    }
    lastPolledAt[device.id] = DateTime.now();
    return false;
  }

  Future<void> _pollOne(String id) async {
    final device = _devices[id];
    if (device == null) return;
    if (_throttledBySpinDownGuard(
      device,
      _lastPolledAt,
      _spinDownRiskMinPollInterval,
    )) {
      return;
    }

    final previousReading = device.primaryTemperature;

    try {
      final reading = await _backend.readTemperature(id);

      final current = _devices[id];
      if (current == null) return;

      if (reading == null) {
        _devices[id] = current.copyWith(
          sensorAvailability: SensorAvailability.unsupported,
          monitoringStatus: MonitoringStatus.sensorUnavailable,
          clearTemperature: true,
          lastUpdated: DateTime.now(),
          clearLastError: true,
        );
      } else {
        var plausible = TemperatureUtils.isPlausibleValue(reading.celsius);
        if (plausible && previousReading != null && previousReading.isValid) {
          plausible = TemperatureUtils.isPlausibleTransition(
            previousReading.celsius,
            reading.celsius,
          );
        }

        if (!plausible) {
          AppLogger.instance.warning(
            _tag,
            'Rejected implausible reading for $id: ${reading.celsius}C',
          );
          _devices[id] = current.copyWith(
            monitoringStatus: MonitoringStatus.error,
            lastError:
                'Sensor returned an implausible value; reading discarded',
          );
        } else {
          _historyStore.record(id, reading);
          final updated = current.copyWith(
            primaryTemperature: reading,
            sensorAvailability: SensorAvailability.available,
            monitoringStatus: MonitoringStatus.active,
            lastUpdated: DateTime.now(),
            clearLastError: true,
          );
          _devices[id] = updated;
          await _evaluatePredictiveTemperature(id, reading.celsius, updated);
          await _evaluateAlert(id, reading.celsius, updated);
          await _evaluateRapidRise(id, reading.celsius, updated);
        }
      }
    } on PermissionDeniedException catch (e) {
      final current = _devices[id];
      if (current != null) {
        _devices[id] = current.copyWith(
          sensorAvailability: SensorAvailability.permissionDenied,
          monitoringStatus: MonitoringStatus.permissionDenied,
          lastError: e.message,
        );
      }
    } on StorageMonitorException catch (e) {
      AppLogger.instance.warning(_tag, 'Read failed for $id: ${e.message}');
      final current = _devices[id];
      if (current != null) {
        _devices[id] = current.copyWith(
          monitoringStatus: MonitoringStatus.error,
          lastError: e.message,
        );
      }
    } catch (e) {
      AppLogger.instance.error(_tag, 'Unexpected error polling $id', e);
      final current = _devices[id];
      if (current != null) {
        _devices[id] = current.copyWith(
          monitoringStatus: MonitoringStatus.error,
          lastError: 'Unexpected error: $e',
        );
      }
    }

    _checkStale(id);
  }

  void _checkStale(String id) {
    final device = _devices[id];
    if (device?.lastUpdated == null) return;
    final staleAfter =
        _settings.pollingInterval * AppConstants.staleThresholdMultiplier;
    if (device!.monitoringStatus == MonitoringStatus.active &&
        TemperatureUtils.isStale(device.lastUpdated!, staleAfter)) {
      _devices[id] = device.copyWith(
        monitoringStatus: MonitoringStatus.staleData,
      );
    }
  }

  
  
  
  Future<void> _evaluatePredictiveTemperature(
    String id,
    double celsius,
    StorageDevice device,
  ) async {
    if (!_settings.predictiveAlertsEnabled) return;
    
    final currentSeverity = severityFor(id);
    if (currentSeverity == TemperatureSeverity.warning ||
        currentSeverity == TemperatureSeverity.critical) {
      return;
    }

    final points = _historyStore
        .pointsFor(id, AppConstants.predictiveTemperatureLookback)
        .map((p) => TrendPoint(p.timestamp, p.celsius))
        .toList();
    final hit = _predictiveEngine.evaluateTemperature(
      points: points,
      currentCelsius: celsius,
      thresholds: _settings.thresholdsFor(id),
      leadTime: AppConstants.predictiveTemperatureLeadTime,
    );
    if (hit == null) return;

    final severity = hit.critical
        ? TemperatureSeverity.critical
        : TemperatureSeverity.warning;
    final lastAt = _lastPredictiveTempAt[id];
    final alreadyWarned =
        _lastPredictiveTempSeverity[id] == severity &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < _settings.notificationCooldown;
    if (alreadyWarned) return;

    _lastPredictiveTempAt[id] = DateTime.now();
    _lastPredictiveTempSeverity[id] = severity;

    AppLogger.instance.info(
      _tag,
      'Predictive temperature alert for $id: ${hit.etaText} to ${severity.name}',
    );
    if (!_settings.notificationsEnabled) return;
    await _notifications.showPredictiveTemperature(
      deviceId: id,
      deviceName: device.displayName,
      critical: hit.critical,
      etaText: hit.etaText,
      detailsText: _detailsFor(device),
    );
  }

  Future<void> _evaluateAlert(
    String id,
    double celsius,
    StorageDevice device,
  ) async {
    final alertState = _alertStates.putIfAbsent(id, DeviceAlertState.new);
    final thresholds = _settings.thresholdsFor(id);
    final result = alertState.evaluate(
      celsius: celsius,
      thresholds: thresholds,
      cooldown: _settings.notificationCooldown,
      recoveryNotificationsEnabled: _settings.recoveryNotificationsEnabled,
    );
    if (result.severity == TemperatureSeverity.warning ||
        result.severity == TemperatureSeverity.critical) {
      unawaited(_persistPreIncidentBuffer(id, device.displayName));
    }

    if (!result.shouldNotify || !_settings.notificationsEnabled) return;

    if (!result.isRecoveryNotification &&
        _lastPredictiveTempSeverity[id] == result.severity &&
        _recentlyPredicted(_lastPredictiveTempAt[id])) {

      return;
    }

    final tempText = TemperatureUtils.format(
      celsius,
      _settings.temperatureUnit,
    );
    final details = _detailsFor(device);
    if (result.isRecoveryNotification) {
      await _notifications.showRecovered(
        deviceId: id,
        deviceName: device.displayName,
        temperatureText: tempText,
        detailsText: details,
      );
    } else if (result.severity == TemperatureSeverity.critical) {
      await _notifications.showCritical(
        deviceId: id,
        deviceName: device.displayName,
        temperatureText: tempText,
        detailsText: details,
      );
    } else if (result.severity == TemperatureSeverity.warning) {
      await _notifications.showWarning(
        deviceId: id,
        deviceName: device.displayName,
        temperatureText: tempText,
        detailsText: details,
      );
    }
  }

  Future<void> _evaluateRapidRise(
    String id,
    double celsius,
    StorageDevice device,
  ) async {
    if (!_settings.rapidRiseAlertsEnabled) return;

    final points = _historyStore.pointsFor(id, _settings.rapidRiseWindow);

    if (points.length < 2) return;
    final windowStart = DateTime.now().subtract(_settings.rapidRiseWindow);
    if (points.first.timestamp.isAfter(
      windowStart.add(_settings.rapidRiseWindow ~/ 2),
    )) {
      return;
    }

    final baseline = points.map((p) => p.celsius).reduce(min);
    final delta = celsius - baseline;
    final threshold = _settings.rapidRiseDeltaFor(id);
    final armed = _rapidRiseArmed[id] ?? false;

    if (delta >= threshold) {
      final lastAt = _lastRapidRiseNotifiedAt[id];
      final cooldownElapsed =
          lastAt == null ||
          DateTime.now().difference(lastAt) >= _settings.notificationCooldown;
      if (!armed || cooldownElapsed) {
        _rapidRiseArmed[id] = true;
        _lastRapidRiseNotifiedAt[id] = DateTime.now();
        AppLogger.instance.warning(
          _tag,
          'Rapid temperature rise for $id: +${delta.toStringAsFixed(1)}C '
          'in ${_settings.rapidRiseWindow.inMinutes}min',
        );
        if (_settings.notificationsEnabled) {
          final tempText = TemperatureUtils.format(
            celsius,
            _settings.temperatureUnit,
          );
          final displayDelta = TemperatureUtils.convertDelta(
            delta,
            _settings.temperatureUnit,
          );
          final unitSuffix = TemperatureUtils.unitSuffix(
            _settings.temperatureUnit,
          );
          await _notifications.showRapidRise(
            deviceId: id,
            deviceName: device.displayName,
            temperatureText: tempText,
            riseText:
                '+${displayDelta.toStringAsFixed(0)}$unitSuffix in '
                '${_settings.rapidRiseWindow.inMinutes} min',
            detailsText: _detailsFor(device),
          );
        }
      }
    } else if (delta < threshold / 2) {
      _rapidRiseArmed[id] = false;
    }
  }

  final Map<String, DateTime> _lastPreIncidentPersistAt = {};

  Future<void> _persistPreIncidentBuffer(
    String deviceId,
    String deviceName, {
    bool force = false,
  }) async {
    final repo = _incidentRepository;
    final sessionId = _sessionId;
    if (repo == null || sessionId == null) return;

    if (!force) {
      final lastAt = _lastPreIncidentPersistAt[deviceId];
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < const Duration(seconds: 20)) {
        return;
      }
    }
    _lastPreIncidentPersistAt[deviceId] = DateTime.now();

    final points = _historyStore.pointsFor(deviceId, _preIncidentWindow);
    if (points.isEmpty) return;
    await repo.recordPreIncidentSamples(
      points
          .map(
            (p) => PreIncidentSample(
              sessionId: sessionId,
              deviceId: deviceId,
              deviceName: deviceName,
              timestamp: p.timestamp,
              celsius: p.celsius,
            ),
          )
          .toList(),
    );
  }

  /// Best-effort, synchronous-as-possible flush for an abnormal shutdown
  /// path (a termination signal, a forced close): persists the full
  /// temperature history plus a fresh pre-incident snapshot for every
  /// device that is currently at warning/critical, and stamps one final
  /// heartbeat — so if this really is the last chance to write anything,
  /// the next launch has the freshest possible picture instead of relying
  /// on the last periodic write (up to ~20s old for pre-incident data, or
  /// up to 10 polls old for history).
  Future<void> flushForShutdown() async {
    AppLogger.instance.warning(_tag, 'Flushing telemetry before shutdown');
    try {
      await _historyStore.persistAll();
    } catch (e) {
      AppLogger.instance.error(_tag, 'History flush failed', e);
    }

    for (final device in _devices.values) {
      if (severityFor(device.id) == TemperatureSeverity.warning ||
          severityFor(device.id) == TemperatureSeverity.critical) {
        try {
          await _persistPreIncidentBuffer(
            device.id,
            device.displayName,
            force: true,
          );
        } catch (e) {
          AppLogger.instance.error(
            _tag,
            'Pre-incident flush failed for ${device.id}',
            e,
          );
        }
      }
    }

    final repo = _incidentRepository;
    final sessionId = _sessionId;
    if (repo != null && sessionId != null) {
      try {
        await repo.heartbeat(sessionId, DateTime.now());
      } catch (e) {
        AppLogger.instance.debug(_tag, 'Final heartbeat write failed: $e');
      }
    }
  }

  String? _detailsFor(StorageDevice device) {
    final parts = <String>[];
    switch (device.health.status) {
      case DeviceHealthStatus.healthy:
        parts.add('Health: Healthy');
      case DeviceHealthStatus.warning:
        parts.add('Health: Warning');
      case DeviceHealthStatus.critical:
        parts.add('Health: Critical');
      case DeviceHealthStatus.unknown:
      case DeviceHealthStatus.unavailable:
        break;
    }
    if (device.capacity.isValid && device.capacity.freeBytes != null) {
      final usagePercent = device.capacity.usagePercent;
      parts.add(
        '${_formatBytes(device.capacity.freeBytes!)} free'
        '${usagePercent != null ? ' (${usagePercent.toStringAsFixed(0)}% used)' : ''}',
      );
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  TemperatureSeverity severityFor(String deviceId) =>
      _alertStates[deviceId]?.lastSeverity ?? TemperatureSeverity.normal;

  CapacitySeverity capacitySeverityFor(String deviceId) =>
      _capacityAlertStates[deviceId]?.lastSeverity ?? CapacitySeverity.normal;

  bool rapidRiseActiveFor(String deviceId) =>
      _rapidRiseArmed[deviceId] ?? false;

  void _emit() {
    if (!_devicesController.isClosed) {
      _devicesController.add(currentDevices);
    }
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    _healthTimer?.cancel();
    await _deviceEventsSub?.cancel();
    await _activitySub?.cancel();
    await _devicesController.close();
    await _activityController.close();
  }
}
