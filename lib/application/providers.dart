import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/storage_device.dart';
import '../domain/repositories/storage_monitor.dart';
import '../infrastructure/persistence/settings_repository.dart';
import 'monitoring/monitoring_service.dart';
import 'monitoring/temperature_history_store.dart';
import 'notifications/notification_service.dart';
import 'settings/app_settings.dart';

/// These three are overridden with concrete instances in main.dart after
/// the async bootstrap (backend selection, settings load) completes -
/// keeping every downstream provider synchronous and testable.
final storageMonitorProvider = Provider<StorageMonitor>(
    (ref) => throw UnimplementedError('storageMonitorProvider must be overridden'));

final notificationServiceProvider = Provider<NotificationService>(
    (ref) => throw UnimplementedError('notificationServiceProvider must be overridden'));

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

final historyStoreProvider = Provider<TemperatureHistoryStore>((ref) => TemperatureHistoryStore());

final monitoringServiceProvider = Provider<MonitoringService>((ref) {
  final service = MonitoringService(
    backend: ref.watch(storageMonitorProvider),
    notifications: ref.watch(notificationServiceProvider),
    historyStore: ref.watch(historyStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class SettingsNotifier extends Notifier<AppSettings> {
  /// [initial] carries the settings already loaded from disk in main.dart's
  /// async bootstrap, before `runApp`. It must be supplied this way - via
  /// `settingsProvider.overrideWith(() => SettingsNotifier(loaded))` at
  /// `ProviderScope` construction - and never by reading
  /// `settingsProvider.notifier` and mutating `state` from a descendant
  /// widget's `initState`. Doing the latter mutates provider state while
  /// `ProviderScope`'s own element is still mid-`rebuild()` for the first
  /// frame, which trips Flutter's `!_dirty` reentrancy assertion (a real
  /// crash this app hit before this fix). `build()` returning the already-
  /// correct value up front avoids the mutation entirely.
  SettingsNotifier([this.initial]);

  final AppSettings? initial;

  @override
  AppSettings build() => initial ?? const AppSettings();

  Future<void> updateWith(AppSettings Function(AppSettings current) updater) async {
    final next = updater(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
    ref.read(monitoringServiceProvider).updateSettings(next);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

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

final devicesProvider = NotifierProvider<DevicesNotifier, List<StorageDevice>>(DevicesNotifier.new);
