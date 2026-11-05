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
import '../../infrastructure/persistence/local_state_repository.dart';
import '../alerts/alert_engine.dart';
import '../alerts/predictive_engine.dart';
import '../alerts/ssd_life_advisor.dart';
import '../notifications/notification_service.dart';
import '../protection/resource_guard_service.dart';
import '../protection/thermal_protection_service.dart';
import '../prediction/trend_analyzer.dart';
import '../settings/app_settings.dart';
import 'metric_history_store.dart';
import 'temperature_history_store.dart';

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
    ThermalProtectionService? thermalProtection,
    ResourceGuardService? resourceGuard,
    LocalStateRepository? localState,
    String? sessionId,
  }) : _backend = backend,
       _notifications = notifications,
       _historyStore = historyStore,
       _incidentRepository = incidentRepository,
       _thermalProtection = thermalProtection,
       _resourceGuard = resourceGuard,
       _localState = localState,
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
  final ThermalProtectionService? _thermalProtection;
  final ResourceGuardService? _resourceGuard;
  final LocalStateRepository? _localState;
  final Set<String> _capacityRestored = {};
  final Map<String, DateTime> _capacitySavedAt = {};
  final SsdLifeAdvisor _advisor = const SsdLifeAdvisor();
  final Set<String> _advisoriesSent = {};
  final Map<String, int> _rejectedStreak = {};

  // A single failed sensor read (a smartctl hiccup, a busy bus) used to wipe
  // the temperature at once, so every UI sampling at that instant - the dock
  // and mini widget re-read every 2s - showed "N/A" while the dashboard,
  // which re-reads a moment later, looked fine. Keep the last reading (marked
  // stale) until the sensor has stayed silent for several polls in a row.
  final Map<String, int> _nullReadStreak = {};
  static const int _transientNullReadsAllowed = 3;
  final Map<String, int> _healthUnavailableStreak = {};
  static const int _transientHealthFailuresAllowed = 5;
  bool _hotCadence = false;
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
  bool _disposed = false;
  bool _uiActive = true;
  bool _polling = false;
  bool _discovering = false;
  bool _healthPolling = false;

  /// Minimum poll interval while no window/widget is visible. Alerts keep
  /// working, but we stop spawning backend processes at the 2s rate.
  static const _backgroundMinPollInterval = Duration(seconds: 15);
  static const _backgroundMinHealthInterval = Duration(minutes: 10);

  bool get isPaused => _paused;

  Future<void> start(AppSettings settings) async {
    _settings = settings;
    final clock = Stopwatch()..start();
    void lap(String step) => AppLogger.instance.info(
      _tag,
      'start(): $step done at ${clock.elapsedMilliseconds} ms',
    );
    final saved = await _localState?.loadSentAdvisories();
    if (saved != null) _advisoriesSent.addAll(saved);
    lap('load advisories');
    await _notifications.initialize();
    lap('notifier setup');
    await _discoverDevices();
    lap('device discovery');
    _rescheduleTimers();
    _listenForHotplugEvents();
    _listenForActivity();
    unawaited(_pollHealthAll());
    _resourceGuard
      ?..attach(
        devices: () => currentDevices,
        onMemory: (m) => _thermalProtection?.latestMemory = m,
      )
      ..start();
    _started = true;
    AppLogger.instance.info(_tag, 'Monitoring started');
  }

  void _listenForActivity() {
    _activitySub = _backend.watchActivity().listen(
      (activity) {
        _latestActivity[activity.deviceId] = activity;
        _resourceGuard?.recordActivity(activity);
        if (!_activityController.isClosed) {
          _activityController.add(activity);
        }
      },
      onError: (Object e) {
        AppLogger.instance.debug(_tag, 'Activity stream error: $e');
      },
    );
  }

  Timer? _hotplugDebounce;

  void _listenForHotplugEvents() {
    _deviceEventsSub = _backend.watchDeviceEvents().listen(
      (event) {
        final known = _devices.containsKey(event.deviceId);
        if (event.kind.name == 'added' && known) return; // startup replay
        AppLogger.instance.info(
          _tag,
          'Hot-plug event: ${event.kind.name} ${event.deviceId}',
        );
        _hotplugDebounce?.cancel();
        _hotplugDebounce = Timer(
          const Duration(milliseconds: 500),
          () => unawaited(_discoverDevices()),
        );
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

  /// Tells the service whether anything on screen (main window, mini widget,
  /// edge dock) is currently showing live data. When nothing is, polling is
  /// throttled to save CPU and battery.
  void setUiActive(bool active) {
    _resourceGuard?.setUiActive(active);
    if (_uiActive == active) return;
    _uiActive = active;
    if (_started) {
      _rescheduleTimers();
      if (active) unawaited(_pollAll());
    }
  }

  /// Idle drives are polled slowly (and very slowly when nothing is
  /// visible) to keep CPU and SMART reads minimal. As soon as any drive is
  /// hot, polling speeds up — even with the window hidden — so a thermal
  /// emergency is caught within seconds instead of minutes.
  Duration get _effectivePollInterval {
    final base = _settings.pollingInterval;
    final guard = _thermalProtection;
    if (guard != null && _settings.thermalProtection.enabled) {
      if (guard.anyEmergency) return _min(base, const Duration(seconds: 2));
      if (guard.anyElevated) return _min(base, const Duration(seconds: 5));
    }
    return _uiActive ? base : _max(base, _backgroundMinPollInterval);
  }

  static Duration _min(Duration a, Duration b) => a <= b ? a : b;

  Duration get _effectiveHealthInterval => _uiActive
      ? _settings.healthPollingInterval
      : _max(_settings.healthPollingInterval, _backgroundMinHealthInterval);

  static Duration _max(Duration a, Duration b) => a >= b ? a : b;

  void _rescheduleTimers() {
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    _healthTimer?.cancel();
    _pollTimer = Timer.periodic(_effectivePollInterval, (_) => _pollAll());
    _discoveryTimer = Timer.periodic(
      _settings.deviceDiscoveryInterval,
      (_) => _discoverDevices(),
    );
    _healthTimer = Timer.periodic(
      _effectiveHealthInterval,
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

  Future<void> refreshNow({String? deviceId}) async {
    final ids = deviceId != null
        ? [
            if (_devices.containsKey(deviceId) &&
                _devices[deviceId]!.monitoringStatus !=
                    MonitoringStatus.disconnected)
              deviceId,
          ]
        : _devices.keys
              .where(
                (id) =>
                    _devices[id]!.monitoringStatus !=
                    MonitoringStatus.disconnected,
              )
              .toList();
    if (ids.isEmpty) return;
    AppLogger.instance.info(_tag, 'Manual refresh requested for $ids');
    await Future.wait(ids.map(_pollOne));
    _emit();
  }

  Future<void> reinitializeAfterResume() async {
    AppLogger.instance.info(_tag, 'Reinitializing after system resume');
    _thermalProtection?.onSystemResume();
    await _discoverDevices();
    await _pollAll();
  }

  Future<void> _discoverDevices() async {
    if (_discovering || _disposed) return;
    _discovering = true;
    try {
      await _discoverDevicesImpl();
    } finally {
      _discovering = false;
    }
  }

  Future<void> _discoverDevicesImpl() async {
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
        _thermalProtection?.forget(id);
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
          if (_capacityRestored.add(id) && _localState != null) {
            _capacityHistoryStore.restore(
              id,
              await _localState.loadCapacity(id),
            );
          }
          if (usagePercent != null) {
            _capacityHistoryStore.record(id, usagePercent);
            _persistCapacity(id);
          }
          await _evaluatePredictiveCapacity(id, capacity, updated);
          await _evaluateCapacityAlert(id, capacity, updated);
          await _evaluateAdvisories(updated, null);
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

  /// Usage history is saved at most hourly — a handful of bytes, but there
  /// is no reason to touch the SSD more often than that.
  void _persistCapacity(String id) {
    final repo = _localState;
    if (repo == null) return;
    final last = _capacitySavedAt[id];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 1)) return;
    _capacitySavedAt[id] = now;
    unawaited(repo.saveCapacity(id, _capacityHistoryStore.pointsFor(id)));
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
    if (_healthPolling || _disposed) return;
    _healthPolling = true;
    try {
      await Future.wait(ids.map(_pollHealthOne));
    } finally {
      _healthPolling = false;
    }
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
      // Same idea as temperature: a one-off failed SMART read must not
      // replace good health data with "UNAVAILABLE".
      final lostData =
          health.status == DeviceHealthStatus.unavailable &&
          current.health.status != DeviceHealthStatus.unavailable &&
          current.health.status != DeviceHealthStatus.unknown;
      if (lostData) {
        final streak = (_healthUnavailableStreak[id] ?? 0) + 1;
        _healthUnavailableStreak[id] = streak;
        if (streak <= _transientHealthFailuresAllowed) return;
      } else {
        _healthUnavailableStreak.remove(id);
      }
      final updated = current.copyWith(health: health);
      _devices[id] = updated;
      final wear = health.percentageUsed;
      if (wear != null) {
        _healthHistoryStore.record(id, wear.toDouble());
      }
      final previousHealth = _lastKnownHealth[id];
      await _evaluatePredictiveHealthWear(id, health, updated);
      await _evaluateHealthAlert(id, health, updated);
      await _evaluateAdvisories(updated, previousHealth);
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
    } else {
      final ataAlert = _ataAttributeAlert(previous, health);
      if (ataAlert != null) {
        message = ataAlert.message;
        critical = ataAlert.critical;
      }
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

  /// Flags a new or growing ATA SMART sector/error count — the classic
  /// early-warning signs of imminent drive failure that aren't captured by
  /// the status/wear/media-error checks above. Reallocated/pending sectors
  /// are treated as critical (data is or was at risk); reallocated events
  /// and offline-uncorrectable growth are treated as a warning.
  ({String message, bool critical})? _ataAttributeAlert(
    DeviceHealth previous,
    DeviceHealth health,
  ) {
    int grown(int? before, int? after) {
      if (after == null) return 0;
      return after - (before ?? 0);
    }

    final newReallocated = grown(
      previous.reallocatedSectorCount,
      health.reallocatedSectorCount,
    );
    if (newReallocated > 0) {
      return (
        message:
            '$newReallocated new reallocated sector${newReallocated == 1 ? '' : 's'} '
            'detected since the last check.',
        critical: true,
      );
    }

    final newPending = grown(
      previous.currentPendingSectorCount,
      health.currentPendingSectorCount,
    );
    if (newPending > 0) {
      return (
        message:
            '$newPending new pending sector${newPending == 1 ? '' : 's'} '
            'detected since the last check.',
        critical: true,
      );
    }

    final newUncorrectable = grown(
      previous.offlineUncorrectableCount,
      health.offlineUncorrectableCount,
    );
    if (newUncorrectable > 0) {
      return (
        message:
            '$newUncorrectable new offline uncorrectable error'
            '${newUncorrectable == 1 ? '' : 's'} detected since the last check.',
        critical: false,
      );
    }

    final newReallocatedEvents = grown(
      previous.reallocatedEventCount,
      health.reallocatedEventCount,
    );
    if (newReallocatedEvents > 0) {
      return (
        message:
            '$newReallocatedEvents new reallocation event'
            '${newReallocatedEvents == 1 ? '' : 's'} detected since the last check.',
        critical: false,
      );
    }

    return null;
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

  /// SSD-longevity advice (wear, spare blocks, unsafe shutdowns, free space).
  /// Each advisory is announced once per session, again only if it worsens.
  Future<void> _evaluateAdvisories(
    StorageDevice device,
    DeviceHealth? previousHealth,
  ) async {
    if (!_settings.notificationsEnabled || !_settings.healthAlertsEnabled) {
      return;
    }
    for (final a in _advisor.evaluate(device, previous: previousHealth)) {
      final key = '${device.id}:${a.id}';
      if (!_advisoriesSent.add(key)) continue;
      unawaited(
        _localState?.saveSentAdvisories(_advisoriesSent) ?? Future.value(),
      );
      AppLogger.instance.info(_tag, 'Advisory for ${device.id}: ${a.id}');
      await _notifications.showAdvisory(
        id: key,
        deviceId: device.id,
        title: a.title,
        body: a.body,
        urgent: a.severity == AdvisorySeverity.critical,
      );
    }
  }

  Future<void> _pollAll() async {
    if (_paused || !_settings.monitoringEnabled) return;
    if (_polling || _disposed) return;
    final ids = _devices.keys
        .where(
          (id) =>
              _devices[id]!.monitoringStatus != MonitoringStatus.disconnected,
        )
        .toList();
    _polling = true;
    try {
      await Future.wait(ids.map(_pollOne));
    } finally {
      _polling = false;
    }
    _emit();
    final hot =
        (_thermalProtection?.anyElevated ?? false) && !_disposed && _started;
    if (hot != _hotCadence) {
      _hotCadence = hot;
      _rescheduleTimers();
    }
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

      if (reading == null &&
          previousReading != null &&
          (_nullReadStreak[id] = (_nullReadStreak[id] ?? 0) + 1) <=
              _transientNullReadsAllowed) {
        _devices[id] = current.copyWith(
          monitoringStatus: MonitoringStatus.staleData,
        );
      } else if (reading == null) {
        _thermalProtection?.onSensorLost(id);
        _devices[id] = current.copyWith(
          sensorAvailability: SensorAvailability.unsupported,
          monitoringStatus: MonitoringStatus.sensorUnavailable,
          clearTemperature: true,
          lastUpdated: DateTime.now(),
          clearLastError: true,
        );
      } else {
        _nullReadStreak.remove(id);
        var plausible = TemperatureUtils.isPlausibleValue(reading.celsius);
        if (plausible && previousReading != null && previousReading.isValid) {
          plausible = TemperatureUtils.isPlausibleTransition(
            previousReading.celsius,
            reading.celsius,
          );
          if (!plausible) {
            // A sensor can legitimately jump (waking from sleep, a stalled
            // poll). Only discard a few consecutive outliers; if the new
            // level persists it IS the truth, otherwise we would stay stuck
            // on the old value forever.
            final streak = (_rejectedStreak[id] ?? 0) + 1;
            _rejectedStreak[id] = streak;
            if (streak >= 3) plausible = true;
          }
        }
        if (plausible) _rejectedStreak.remove(id);

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
          await _thermalProtection?.onReading(
            device: updated,
            celsius: reading.celsius,
            recent: _historyStore
                .pointsFor(id, const Duration(minutes: 2))
                .map((p) => TrendPoint(p.timestamp, p.celsius))
                .toList(),
            activity: _latestActivity[id],
            settings: _settings,
          );
          await _evaluatePredictiveTemperature(id, reading.celsius, updated);
          await _evaluateAlert(id, reading.celsius, updated);
          await _evaluateRapidRise(id, reading.celsius, updated);
        }
      }
    } on PermissionDeniedException catch (e) {
      _thermalProtection?.onSensorLost(id);
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
      _thermalProtection?.onSensorLost(id);
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
    final cause = _thermalProtection?.causeHeadlineFor(device.id);
    if (cause != null) parts.add('Cause: $cause');
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
    _disposed = true;
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    _healthTimer?.cancel();
    await _deviceEventsSub?.cancel();
    await _activitySub?.cancel();
    await _devicesController.close();
    await _activityController.close();
  }
}
