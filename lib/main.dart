import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'application/providers.dart';
import 'core/logging/app_logger.dart';
import 'infrastructure/notifications/local_notifier_service.dart';
import 'infrastructure/persistence/settings_repository.dart';
import 'infrastructure/storage/storage_monitor_factory.dart';
import 'infrastructure/tray/desktop_window_controller.dart';
import 'presentation/app_root.dart';
import 'presentation/widget/mini_widget_app.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.error(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.error('PlatformDispatcher', 'Uncaught error', error);
    return true;
  };

  runZonedGuarded(_run, (error, stack) {
    AppLogger.instance.error(
      'main',
      'Uncaught zone error during bootstrap',
      error,
    );
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

    runApp(
      ProviderScope(
        overrides: [
          storageMonitorProvider.overrideWithValue(backend),
          notificationServiceProvider.overrideWithValue(notificationService),

          settingsProvider.overrideWith(() => SettingsNotifier(settings)),
        ],
        child: _Bootstrapper(windowController: windowController),
      ),
    );
  } catch (error, stack) {
    AppLogger.instance.error('main', 'Bootstrap failed', error);
    runApp(_BootstrapFailureApp(error: error, stack: stack));
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
