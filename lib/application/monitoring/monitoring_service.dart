import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_device_event.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/repositories/storage_monitor.dart';
import '../alerts/alert_engine.dart';
import '../notifications/notification_service.dart';
import '../settings/app_settings.dart';
import 'temperature_history_store.dart';

class MonitoringService {
  MonitoringService({
    required StorageMonitor backend,
    required NotificationService notifications,
    required TemperatureHistoryStore historyStore,
  }) : _backend = backend,
       _notifications = notifications,
       _historyStore = historyStore;

  static const _tag = 'MonitoringService';

  final StorageMonitor _backend;
  final NotificationService _notifications;
  final TemperatureHistoryStore _historyStore;

  final Map<String, StorageDevice> _devices = {};
  final Map<String, DeviceAlertState> _alertStates = {};
  final Set<String> _disconnectedOnce = {};

  final _devicesController = StreamController<List<StorageDevice>>.broadcast();
  Stream<List<StorageDevice>> get devicesStream => _devicesController.stream;
  List<StorageDevice> get currentDevices =>
      _devices.values.toList(growable: false);

  Timer? _pollTimer;
  Timer? _discoveryTimer;
  StreamSubscription<StorageDeviceEvent>? _deviceEventsSub;
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
    _started = true;
    AppLogger.instance.info(_tag, 'Monitoring started');
  }

  /// Native hot-plug push notifications (see STORAGE_MONITORING.md Phase 7)
  /// are a *hint* to rediscover immediately, not a replacement for polled
  /// discovery - not every platform/driver combination reliably fires
  /// them, and [watchDeviceEvents] is an empty stream wherever a backend
  /// doesn't support it, so this simply does nothing extra there.
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
        settings.deviceDiscoveryInterval != _settings.deviceDiscoveryInterval;
    _settings = settings;
    if (_started && intervalsChanged) _rescheduleTimers();
  }

  void _rescheduleTimers() {
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    _pollTimer = Timer.periodic(_settings.pollingInterval, (_) => _pollAll());
    _discoveryTimer = Timer.periodic(
      _settings.deviceDiscoveryInterval,
      (_) => _discoverDevices(),
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
        _historyStore.clearDevice(id);
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

  /// Refreshes capacity/usage and volume enumeration for every tracked
  /// device. Deliberately run on the (slower) discovery cadence rather than
  /// the temperature-polling cadence - see STORAGE_MONITORING.md section 6
  /// ("medium" metrics, 5-10s) - since a full volume/statfs walk is more
  /// expensive than a single temperature read.
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
          _devices[id] = current.copyWith(
            capacity: results[0] as StorageCapacity,
            volumes: results[1] as List<StorageVolume>,
          );
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

  Future<void> _pollOne(String id) async {
    final device = _devices[id];
    if (device == null) return;

    try {
      final reading = await _backend.readTemperature(id);

      if (reading == null) {
        _devices[id] = device.copyWith(
          sensorAvailability: SensorAvailability.unsupported,
          monitoringStatus: MonitoringStatus.sensorUnavailable,
          clearTemperature: true,
          lastUpdated: DateTime.now(),
          clearLastError: true,
        );
      } else {
        final previous = device.primaryTemperature;
        var plausible = TemperatureUtils.isPlausibleValue(reading.celsius);
        if (plausible && previous != null && previous.isValid) {
          plausible = TemperatureUtils.isPlausibleTransition(
            previous.celsius,
            reading.celsius,
          );
        }

        if (!plausible) {
          AppLogger.instance.warning(
            _tag,
            'Rejected implausible reading for $id: ${reading.celsius}C',
          );
          _devices[id] = device.copyWith(
            monitoringStatus: MonitoringStatus.error,
            lastError:
                'Sensor returned an implausible value; reading discarded',
          );
        } else {
          _historyStore.record(id, reading);
          _devices[id] = device.copyWith(
            primaryTemperature: reading,
            sensorAvailability: SensorAvailability.available,
            monitoringStatus: MonitoringStatus.active,
            lastUpdated: DateTime.now(),
            clearLastError: true,
          );
          await _evaluateAlert(id, reading.celsius, device);
        }
      }
    } on PermissionDeniedException catch (e) {
      _devices[id] = device.copyWith(
        sensorAvailability: SensorAvailability.permissionDenied,
        monitoringStatus: MonitoringStatus.permissionDenied,
        lastError: e.message,
      );
    } on StorageMonitorException catch (e) {
      AppLogger.instance.warning(_tag, 'Read failed for $id: ${e.message}');
      _devices[id] = device.copyWith(
        monitoringStatus: MonitoringStatus.error,
        lastError: e.message,
      );
    } catch (e) {
      AppLogger.instance.error(_tag, 'Unexpected error polling $id', e);
      _devices[id] = device.copyWith(
        monitoringStatus: MonitoringStatus.error,
        lastError: 'Unexpected error: $e',
      );
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
    if (!result.shouldNotify || !_settings.notificationsEnabled) return;

    final tempText = TemperatureUtils.format(
      celsius,
      _settings.temperatureUnit,
    );
    if (result.isRecoveryNotification) {
      await _notifications.showRecovered(
        deviceName: device.displayName,
        temperatureText: tempText,
      );
    } else if (result.severity == TemperatureSeverity.critical) {
      await _notifications.showCritical(
        deviceName: device.displayName,
        temperatureText: tempText,
      );
    } else if (result.severity == TemperatureSeverity.warning) {
      await _notifications.showWarning(
        deviceName: device.displayName,
        temperatureText: tempText,
      );
    }
  }

  TemperatureSeverity severityFor(String deviceId) =>
      _alertStates[deviceId]?.lastSeverity ?? TemperatureSeverity.normal;

  void _emit() {
    if (!_devicesController.isClosed) {
      _devicesController.add(currentDevices);
    }
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _discoveryTimer?.cancel();
    await _deviceEventsSub?.cancel();
    await _devicesController.close();
  }
}
