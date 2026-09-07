import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'application/incidents/heartbeat_service.dart';
import 'application/incidents/startup_recovery_service.dart';
import 'application/monitoring/temperature_history_store.dart';
import 'application/providers.dart';
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'domain/entities/system_diagnostic_event.dart';
import 'infrastructure/notifications/local_notifier_service.dart';
import 'infrastructure/persistence/app_database.dart';
import 'infrastructure/persistence/incident_repository.dart';
import 'infrastructure/persistence/settings_repository.dart';
import 'infrastructure/storage/storage_monitor_factory.dart';
import 'infrastructure/tray/desktop_window_controller.dart';
import 'presentation/app_root.dart';
import 'presentation/widget/mini_widget_app.dart';

/// Set once `_bootstrap` has opened the database and started a session, so
/// a crash handler below has somewhere to persist to. `null` until then -
/// a crash before the database exists can't be recorded to it, which is an
/// unavoidable limitation, not a bug.
IncidentRepository? _crashRepository;
String? _crashSessionId;

/// Persists an application-level error (Flutter framework error, uncaught
/// platform error, or an error escaping the root zone) as a diagnostic
/// event tied to the current session, full stack trace included, so it
/// survives to be shown in that session's incident report even if the app
/// terminates right after. Best-effort and silent on failure - a crash
/// handler must never itself throw.
void _recordCrash(String source, Object error, StackTrace? stack) {
  final repo = _crashRepository;
  final sessionId = _crashSessionId;
  if (repo == null || sessionId == null) return;
  try {
    unawaited(
      repo.recordDiagnosticEvents(sessionId, [
        SystemDiagnosticEvent(
          timestamp: DateTime.now(),
          source: 'DriveGuard ($source)',
          category: 'app-crash',
          summary: error.toString().split('\n').first,
          raw: stack != null ? '$error\n\n$stack' : error.toString(),
          errorCode: error.runtimeType.toString(),
        ),
      ]),
    );
  } catch (_) {
    // Never let crash reporting itself throw.
  }
}

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.error(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
    );
    _recordCrash('Flutter error', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.error('PlatformDispatcher', 'Uncaught error', error);
    _recordCrash('platform error', error, stack);
    return true;
  };

  runZonedGuarded(_run, (error, stack) {
    AppLogger.instance.error(
      'main',
      'Uncaught zone error during bootstrap',
      error,
    );
    _recordCrash('zone error', error, stack);
  });
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowController = await WindowController.fromCurrentEngine();
  if (windowController.arguments.isNotEmpty) {
    final initialArgs =
        jsonDecode(windowController.arguments) as Map<String, dynamic>;
    runApp(
      MiniWidgetApp(controller: windowController, initialArgs: initialArgs),
    );
    return;
  }

  await _bootstrap();
}

Future<void> _bootstrap() async {
  try {
    final settingsRepository = SettingsRepository();
    final settings = await settingsRepository.load();

    AppLogger.instance.verboseDiagnostics = settings.diagnosticLoggingEnabled;
    AppLogger.instance.info('main', 'DriveGuard starting');

    final backend = await StorageMonitorFactory.create(
      forceMock: settings.mockBackendForced,
    );
    final notificationService = LocalNotifierService();

    final windowController = DesktopWindowController();
    await windowController.initialize(startMinimized: settings.startMinimized);

    final historyStore = TemperatureHistoryStore();
    await historyStore.initialize();

    final appDb = await AppDatabase.open();
    unawaited(
      appDb
          .pruneOldSamples(DateTime.now().subtract(const Duration(days: 30)))
          .catchError(
            (Object e) =>
                AppLogger.instance.debug('main', 'pruneOldSamples failed: $e'),
          ),
    );
    final incidentRepository = IncidentRepository(appDb);
    final recoveryService = StartupRecoveryService(
      repository: incidentRepository,
    );
    final session = await recoveryService.startNewSession(
      appVersion: AppConstants.appVersion,
      pollingInterval: settings.pollingInterval,
    );
    _crashRepository = incidentRepository;
    _crashSessionId = session.id;
    final startupIncident = await recoveryService.recoverPreviousSession(
      currentSessionId: session.id,
      warningCelsiusFor: (id) => settings.thresholdsFor(id).warningCelsius,
      criticalCelsiusFor: (id) => settings.thresholdsFor(id).criticalCelsius,
    );
    final heartbeat = HeartbeatService(
      repository: incidentRepository,
      sessionId: session.id,
    )..start();

    try {
      launchAtStartup.setup(
        appName: 'DriveGuard',
        appPath: Platform.resolvedExecutable,
      );
      if (settings.startWithOS) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (e) {
      AppLogger.instance.warning('main', 'launch-at-startup setup skipped: $e');
    }

    final container = ProviderContainer(
      overrides: [
        storageMonitorProvider.overrideWithValue(backend),
        notificationServiceProvider.overrideWithValue(notificationService),
        historyStoreProvider.overrideWithValue(historyStore),
        settingsProvider.overrideWith(() => SettingsNotifier(settings)),
        incidentRepositoryProvider.overrideWithValue(incidentRepository),
        sessionIdProvider.overrideWithValue(session.id),
        heartbeatServiceProvider.overrideWithValue(heartbeat),
        startupIncidentProvider.overrideWithValue(startupIncident),
      ],
    );
    _armTerminationSignalHandlers(container);

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: _Bootstrapper(windowController: windowController),
      ),
    );
  } catch (error, stack) {
    AppLogger.instance.error('main', 'Bootstrap failed', error);
    runApp(_BootstrapFailureApp(error: error, stack: stack));
  }
}

/// Catches termination signals sent to the process itself — `kill`/`kill
/// -TERM`, a systemd/session-manager stop, Ctrl+C in a terminal, a logout
/// that asks running apps to quit — which bypass the Flutter window
/// entirely and would otherwise never run `AppRoot`'s clean-quit path.
/// `SIGKILL` (`kill -9`) can never be caught by any process on any OS; that
/// case is unavoidably left to the next-launch heartbeat-gap detection.
///
/// `ProcessSignal.sigterm` is not supported on Windows (the Dart docs say
/// so explicitly) so `watch()` is wrapped per-signal rather than failing
/// the whole app if one isn't available on this platform.
void _armTerminationSignalHandlers(ProviderContainer container) {
  var handled = false;
  Future<void> onSignal(ProcessSignal signal) async {
    if (handled) return;
    handled = true;
    AppLogger.instance.warning(
      'main',
      'Received ${signal.name} — flushing telemetry before exit',
    );
    try {
      await container
          .read(monitoringServiceProvider)
          .flushForShutdown()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      AppLogger.instance.error('main', 'Shutdown flush failed', e);
    }
    exit(0);
  }

  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    try {
      signal.watch().listen(onSignal);
    } catch (e) {
      AppLogger.instance.debug(
        'main',
        '${signal.name} not supported on this platform: $e',
      );
    }
  }
}

class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: ErrorWidget.withDetails(
          message: 'DriveGuard failed to start.\n\n$error',
        ),
      ),
    );
  }
}

class _Bootstrapper extends ConsumerStatefulWidget {
  const _Bootstrapper({required this.windowController});
  final DesktopWindowController windowController;

  @override
  ConsumerState<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends ConsumerState<_Bootstrapper> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final settings = ref.read(settingsProvider);
    await ref.read(monitoringServiceProvider).start(settings);
    if (mounted) setState(() => _started = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0D0B1A),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7E5FF0), Color(0xFF3D2D9E)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x665B3FCE),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'DriveGuard',
                  style: TextStyle(
                    color: Color(0xFFE8E3FF),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Detecting storage devices…',
                  style: TextStyle(color: Color(0xFF9990CC), fontSize: 13),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    backgroundColor: const Color(0xFF201E4D),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF7E5FF0),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AppRoot(windowController: widget.windowController);
  }
}

/*

2026-09-04T10:07:28.245571 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:07:28.245989 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:07:43.247180 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:07:43.247326 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:07:58.244674 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:07:58.244791 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme0n1: PermissionDeniedException(linux-nvme0n1): 
2026-09-04T10:07:58.245196 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:07:58.245253 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme1n1: PermissionDeniedException(linux-nvme1n1): 
2026-09-04T10:07:58.287685 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:07:58.287897 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:08:13.247514 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:08:13.247674 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:08:28.247518 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:08:28.247876 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:08:43.250708 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:08:43.250836 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:08:49.955972 [INFO   ] MonitoringService: Hot-plug event: added linux-hint
2026-09-04T10:08:49.963074 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:08:49.963340 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:08:58.242891 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:08:58.243025 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme0n1: PermissionDeniedException(linux-nvme0n1): 
2026-09-04T10:08:58.243464 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:08:58.243522 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme1n1: PermissionDeniedException(linux-nvme1n1): 
2026-09-04T10:08:58.278121 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:08:58.278326 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:09:13.246514 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:09:13.246875 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:09:28.249084 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:09:28.249276 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:09:43.247669 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:09:43.247874 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:09:58.242978 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:09:58.243121 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme0n1: PermissionDeniedException(linux-nvme0n1): 
2026-09-04T10:09:58.243663 [WARNING] StorageNativeChannel: getHealth failed: PERMISSION_DENIED 
2026-09-04T10:09:58.243726 [DEBUG  ] FallbackStorageMonitor: Native health read failed for linux-nvme1n1: PermissionDeniedException(linux-nvme1n1): 
2026-09-04T10:09:58.295985 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:09:58.296277 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:10:13.247675 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:10:13.247852 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
2026-09-04T10:10:28.254013 [DEBUG  ] MonitoringService: Capacity for linux-nvme0n1: available (?% used), volumes: 3
2026-09-04T10:10:28.254159 [DEBUG  ] MonitoringService: Capacity for linux-nvme1n1: available (5% used), volumes: 5
*/
