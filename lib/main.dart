import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

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
import 'infrastructure/persistence/local_state_repository.dart';
import 'infrastructure/persistence/settings_repository.dart';
import 'infrastructure/storage/storage_monitor_factory.dart';
import 'infrastructure/tray/desktop_window_controller.dart';
import 'application/settings/app_settings.dart';
import 'domain/repositories/storage_monitor.dart';
import 'presentation/app_root.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/widget/edge_dock_app.dart';
import 'presentation/widget/mini_widget_app.dart';

IncidentRepository? _crashRepository;
String? _crashSessionId;

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
  } catch (_) {}
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
    if (initialArgs['mode'] == 'edgeDock') {
      runApp(
        EdgeDockApp(controller: windowController, initialArgs: initialArgs),
      );
    } else {
      runApp(
        MiniWidgetApp(controller: windowController, initialArgs: initialArgs),
      );
    }
    return;
  }

  await _bootstrap();
}

const _singleInstancePort = 51477;

Future<bool> _acquireSingleInstanceLock() async {
  try {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      _singleInstancePort,
    );
    server.listen((socket) {
      socket.destroy();
      unawaited(windowManager.show());
      unawaited(windowManager.focus());
    });
    return true;
  } on SocketException {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _singleInstancePort,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();
    } catch (_) {}
    return false;
  }
}

Future<void> _bootstrap() async {
  if (!await _acquireSingleInstanceLock()) {
    AppLogger.instance.info(
      'main',
      'DriveGuard is already running - activating that instance instead of starting a second one',
    );
    exit(0);
  }

  try {
    // Only what's needed to show the window runs before the first frame:
    // settings (tiny) and the window itself. Everything else initialises
    // behind a themed splash, so the user sees UI immediately instead of
    // an empty/hidden window while databases and backends spin up.
    final settings = await SettingsRepository().load();
    AppLogger.instance.verboseDiagnostics = settings.diagnosticLoggingEnabled;
    AppLogger.instance.info('main', 'DriveGuard starting');

    final windowController = DesktopWindowController();
    await windowController.initialize(startMinimized: settings.startMinimized);

    runApp(
      _BootRoot(
        init: _initServices(settings),
        windowController: windowController,
      ),
    );
  } catch (error, stack) {
    AppLogger.instance.error('main', 'Bootstrap failed', error);
    runApp(_BootstrapFailureApp(error: error, stack: stack));
  }
}

Future<ProviderContainer> _initServices(AppSettings settings) async {
  // Independent, slow-ish initialisations run concurrently.
  final results = await Future.wait<Object?>([
    StorageMonitorFactory.create(forceMock: settings.mockBackendForced),
    (() async {
      final store = TemperatureHistoryStore();
      await store.initialize();
      return store;
    })(),
    AppDatabase.open(),
  ]);
  final backend = results[0]! as StorageMonitor;
  final historyStore = results[1]! as TemperatureHistoryStore;
  final appDb = results[2]! as AppDatabase;
  final notificationService = LocalNotifierService();

  void pruneSamples() => unawaited(
    appDb
        .pruneOldSamples(DateTime.now().subtract(const Duration(days: 30)))
        .catchError(
          (Object e) =>
              AppLogger.instance.debug('main', 'pruneOldSamples failed: $e'),
        ),
  );
  pruneSamples();
  // The app can run for weeks in the tray; don't rely on startup pruning.
  Timer.periodic(const Duration(hours: 24), (_) => pruneSamples());
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

  // Login-item registration is not needed to render anything.
  unawaited(() async {
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
  }());

  final container = ProviderContainer(
    overrides: [
      storageMonitorProvider.overrideWithValue(backend),
      notificationServiceProvider.overrideWithValue(notificationService),
      historyStoreProvider.overrideWithValue(historyStore),
      settingsProvider.overrideWith(() => SettingsNotifier(settings)),
      incidentRepositoryProvider.overrideWithValue(incidentRepository),
      sessionIdProvider.overrideWithValue(session.id),
      heartbeatServiceProvider.overrideWithValue(heartbeat),
      localStateRepositoryProvider.overrideWithValue(LocalStateRepository()),
      startupIncidentProvider.overrideWithValue(startupIncident),
    ],
  );
  _armTerminationSignalHandlers(container);
  return container;
}

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
    try {
      await container
          .read(heartbeatServiceProvider)
          .stop()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    exit(0);
  }

  final signals = Platform.isWindows
      ? [ProcessSignal.sigint]
      : [ProcessSignal.sigterm, ProcessSignal.sigint];

  for (final signal in signals) {
    try {
      signal.watch().listen(
        onSignal,
        onError: (Object e) {
          AppLogger.instance.debug(
            'main',
            '${signal.name} not supported on this platform: $e',
          );
        },
      );
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

/// Shows the themed splash while [init] runs, then hands over to the app.
class _BootRoot extends StatefulWidget {
  const _BootRoot({required this.init, required this.windowController});
  final Future<ProviderContainer> init;
  final DesktopWindowController windowController;

  @override
  State<_BootRoot> createState() => _BootRootState();
}

class _BootRootState extends State<_BootRoot> {
  ProviderContainer? _container;
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    widget.init.then(
      (c) {
        if (mounted) setState(() => _container = c);
      },
      onError: (Object e, StackTrace st) {
        AppLogger.instance.error('main', 'Bootstrap failed', e);
        if (mounted) {
          setState(() {
            _error = e;
            _stack = st;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _BootstrapFailureApp(error: _error!, stack: _stack!);
    }
    final container = _container;
    if (container == null) return const _SplashApp();
    return UncontrolledProviderScope(
      container: container,
      child: _Bootstrapper(windowController: widget.windowController),
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
    if (!_started) return const _SplashApp();
    return AppRoot(windowController: widget.windowController);
  }
}

/// Startup screen built from the app's own design tokens so the hand-off to
/// the dashboard doesn't change palette, font or surface.
class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: AppColors.bg0,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(AppRadius.xl + 4),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.shield_outlined,
                    color: AppColors.accent,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'DriveGuard',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Reading drive sensors…',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: AppColors.bg3,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accent,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
