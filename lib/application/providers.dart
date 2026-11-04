import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../domain/entities/shutdown_incident.dart';
import '../domain/entities/storage_activity.dart';
import '../domain/entities/storage_device.dart';
import '../domain/repositories/storage_monitor.dart';
import '../infrastructure/persistence/incident_repository.dart';
import '../infrastructure/persistence/local_state_repository.dart';
import '../infrastructure/persistence/settings_repository.dart';
import 'incidents/heartbeat_service.dart';
import 'monitoring/metric_history_store.dart';
import 'monitoring/monitoring_service.dart';
import 'monitoring/temperature_history_store.dart';
import '../infrastructure/system/os_privileged_runner.dart';
import '../infrastructure/system/system_actions.dart';
import 'notifications/notification_service.dart';
import 'protection/privileged_runner.dart';
import 'protection/system_actions.dart';
import 'protection/resource_guard_service.dart';
import 'protection/thermal_models.dart';
import 'protection/thermal_protection_service.dart';
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

final privilegedRunnerProvider = Provider<PrivilegedRunner>(
  (ref) => OsPrivilegedRunner(),
);

final systemActionsProvider = Provider<SystemActions>(
  (ref) => OsSystemActions(privileged: ref.watch(privilegedRunnerProvider)),
);

final Provider<ThermalProtectionService> thermalProtectionServiceProvider =
    Provider<ThermalProtectionService>((ref) {
      final service = ThermalProtectionService(
        actions: ref.watch(systemActionsProvider),
        notifications: ref.watch(notificationServiceProvider),
        beforeShutdown: () =>
            ref.read(monitoringServiceProvider).flushForShutdown(),
      );
      ref.onDispose(service.dispose);
      return service;
    });

/// Live thermal-protection state (cause, countdown) for banners/dialogs.
final thermalProtectionStateProvider = StreamProvider<ThermalProtectionState>((
  ref,
) async* {
  final service = ref.watch(thermalProtectionServiceProvider);
  yield service.state;
  yield* service.stream;
});

/// Null in tests (no disk access); the app overrides it with the real thing.
final localStateRepositoryProvider = Provider<LocalStateRepository?>(
  (ref) => null,
);

final Provider<ResourceGuardService> resourceGuardProvider =
    Provider<ResourceGuardService>((ref) {
      final service = ResourceGuardService(
        actions: ref.watch(systemActionsProvider),
        notifications: ref.watch(notificationServiceProvider),
        devices: () => ref.read(monitoringServiceProvider).currentDevices,
        settings: () => ref.read(settingsProvider),
        onMemory: (m) =>
            ref.read(thermalProtectionServiceProvider).latestMemory = m,
      );
      ref.onDispose(service.dispose);
      return service;
    });

/// Active memory/write-pressure alerts for the dashboard banner.
final resourceAlertsProvider = StreamProvider<List<ResourceAlert>>((
  ref,
) async* {
  final service = ref.watch(resourceGuardProvider);
  yield service.current;
  yield* service.stream;
});

final Provider<MonitoringService> monitoringServiceProvider =
    Provider<MonitoringService>((ref) {
      final service = MonitoringService(
        backend: ref.watch(storageMonitorProvider),
        notifications: ref.watch(notificationServiceProvider),
        historyStore: ref.watch(historyStoreProvider),
        capacityHistoryStore: ref.watch(capacityHistoryStoreProvider),
        healthHistoryStore: ref.watch(healthHistoryStoreProvider),
        incidentRepository: ref.watch(incidentRepositoryProvider),
        thermalProtection: ref.watch(thermalProtectionServiceProvider),
        resourceGuard: ref.watch(resourceGuardProvider),
        localState: ref.watch(localStateRepositoryProvider),
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

/// Ordered device ids. Only notifies when the set/order of devices changes,
/// not on every temperature poll — lists can key off this and let each row
/// watch [deviceProvider] for its own updates.
class DeviceIdsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    ref.listen<List<StorageDevice>>(devicesProvider, (_, devices) {
      final ids = [for (final d in devices) d.id];
      if (!listEquals(ids, state)) state = ids;
    });
    return [for (final d in ref.read(devicesProvider)) d.id];
  }
}

final deviceIdsProvider = NotifierProvider<DeviceIdsNotifier, List<String>>(
  DeviceIdsNotifier.new,
);

/// A single device by id; rebuilds only when that device's data changes.
final deviceProvider = Provider.family<StorageDevice?, String>((ref, id) {
  return ref.watch(
    devicesProvider.select((list) {
      for (final d in list) {
        if (d.id == id) return d;
      }
      return null;
    }),
  );
});

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
