import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../domain/entities/shutdown_incident.dart';
import '../domain/entities/storage_activity.dart';
import '../domain/entities/storage_device.dart';
import '../domain/repositories/storage_monitor.dart';
import '../infrastructure/persistence/incident_repository.dart';
import '../infrastructure/persistence/settings_repository.dart';
import 'incidents/heartbeat_service.dart';
import 'monitoring/metric_history_store.dart';
import 'monitoring/monitoring_service.dart';
import 'monitoring/temperature_history_store.dart';
import 'notifications/notification_service.dart';
import 'settings/app_settings.dart';

final incidentRepositoryProvider = Provider<IncidentRepository?>((ref) => null);

final sessionIdProvider = Provider<String?>((ref) => null);

final heartbeatServiceProvider = Provider<HeartbeatService>(
  (ref) =>
      throw UnimplementedError('heartbeatServiceProvider must be overridden'),
);

final startupIncidentProvider = Provider<ShutdownIncident?>((ref) => null);

final storageMonitorProvider = Provider<StorageMonitor>(
  (ref) =>
      throw UnimplementedError('storageMonitorProvider must be overridden'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider must be overridden',
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(),
);

final historyStoreProvider = Provider<TemperatureHistoryStore>(
  (ref) => TemperatureHistoryStore(),
);

final capacityHistoryStoreProvider = Provider<MetricHistoryStore>(
  (ref) => MetricHistoryStore(
    retention: AppConstants.predictiveCapacityRetention,
    minSampleInterval: AppConstants.predictiveCapacitySampleInterval,
  ),
);

final healthHistoryStoreProvider = Provider<MetricHistoryStore>(
  (ref) => MetricHistoryStore(
    retention: AppConstants.predictiveHealthRetention,
    minSampleInterval: AppConstants.predictiveHealthSampleInterval,
  ),
);

final monitoringServiceProvider = Provider<MonitoringService>((ref) {
  final service = MonitoringService(
    backend: ref.watch(storageMonitorProvider),
    notifications: ref.watch(notificationServiceProvider),
    historyStore: ref.watch(historyStoreProvider),
    capacityHistoryStore: ref.watch(capacityHistoryStoreProvider),
    healthHistoryStore: ref.watch(healthHistoryStoreProvider),
    incidentRepository: ref.watch(incidentRepositoryProvider),
    sessionId: ref.watch(sessionIdProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class SettingsNotifier extends Notifier<AppSettings> {
  SettingsNotifier([this.initial]);

  final AppSettings? initial;

  @override
  AppSettings build() => initial ?? const AppSettings();

  Future<void> updateWith(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final next = updater(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
    ref.read(monitoringServiceProvider).updateSettings(next);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class DevicesNotifier extends Notifier<List<StorageDevice>> {
  StreamSubscription<List<StorageDevice>>? _subscription;

  @override
  List<StorageDevice> build() {
    final service = ref.watch(monitoringServiceProvider);
    _subscription = service.devicesStream.listen((devices) => state = devices);
    ref.onDispose(() => _subscription?.cancel());
    return service.currentDevices;
  }
}

final devicesProvider = NotifierProvider<DevicesNotifier, List<StorageDevice>>(
  DevicesNotifier.new,
);

class ActivityNotifier extends Notifier<Map<String, StorageActivity>> {
  StreamSubscription<StorageActivity>? _subscription;

  @override
  Map<String, StorageActivity> build() {
    final service = ref.watch(monitoringServiceProvider);
    _subscription = service.activityStream.listen((activity) {
      state = {...state, activity.deviceId: activity};
    });
    ref.onDispose(() => _subscription?.cancel());
    return const {};
  }
}

final activityProvider =
    NotifierProvider<ActivityNotifier, Map<String, StorageActivity>>(
      ActivityNotifier.new,
    );

final incidentListProvider = FutureProvider.autoDispose((ref) {
  final repo = ref.watch(incidentRepositoryProvider);
  return repo?.listIncidents() ?? Future.value(const []);
});

final incidentDetailProvider = FutureProvider.autoDispose
    .family<ShutdownIncident?, String>((ref, incidentId) {
      final repo = ref.watch(incidentRepositoryProvider);
      return repo?.incidentDetail(incidentId) ?? Future.value(null);
    });
