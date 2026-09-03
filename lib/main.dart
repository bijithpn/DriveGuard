import 'dart:async';
import 'dart:io';
import 'dart:ui';

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

void main() {
  // Framework-caught widget-build errors (thrown during build/layout/paint)
  // still render Flutter's normal red error screen via presentError - we
  // only add structured logging alongside it so a crash also lands in
  // AppLogger (and therefore in Settings -> Advanced -> Export Diagnostic
  // Report), instead of only ever existing as terminal scrollback.
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.error('FlutterError', details.exceptionAsString(), details.exception);
    FlutterError.presentError(details);
  };

  // Errors thrown outside the widget build pipeline (a bad async call in a
  // service, a stream listener throwing, etc.) do NOT go through
  // FlutterError.onError and would otherwise crash the isolate silently on
  // desktop with nothing but a stack trace in the terminal. Returning true
  // marks it handled so the app keeps running instead of dying.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.error('PlatformDispatcher', 'Uncaught error', error);
    return true;
  };

  runZonedGuarded(_bootstrap, (error, stack) {
    AppLogger.instance.error('main', 'Uncaught zone error during bootstrap', error);
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final settingsRepository = SettingsRepository();
    final settings = await settingsRepository.load();

    AppLogger.instance.verboseDiagnostics = settings.diagnosticLoggingEnabled;
    AppLogger.instance.info('main', 'DriveGuard starting');

    final backend = await StorageMonitorFactory.create(forceMock: settings.mockBackendForced);
    final notificationService = LocalNotifierService();

    final windowController = DesktopWindowController();
    await windowController.initialize(startMinimized: settings.startMinimized);

    try {
      launchAtStartup.setup(appName: 'DriveGuard', appPath: Platform.resolvedExecutable);
      if (settings.startWithOS) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (e) {
      // Not every platform's launch_at_startup implementation supports
      // every method (e.g. a missing platform channel implementation) -
      // this is a non-fatal capability gap, not a startup failure.
      AppLogger.instance.warning('main', 'launch-at-startup setup skipped: $e');
    }

    runApp(
      ProviderScope(
        overrides: [
          storageMonitorProvider.overrideWithValue(backend),
          notificationServiceProvider.overrideWithValue(notificationService),
          // The settings loaded from disk are supplied here, at provider
          // construction, rather than by mutating settingsProvider.notifier
          // from a descendant's initState (that pattern caused a real
          // '!_dirty' reentrant-rebuild crash - see SettingsNotifier's doc
          // comment).
          settingsProvider.overrideWith(() => SettingsNotifier(settings)),
        ],
        child: _Bootstrapper(windowController: windowController),
      ),
    );
  } catch (error, stack) {
    // If startup itself fails (before there is any UI to show a normal
    // error in), show something rather than leaving a blank/frozen
    // window - this uses Flutter's own error-screen widget so it looks
    // and behaves like any other Flutter error, not a bespoke screen.
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

/// Starts the monitoring service exactly once (after settings have
/// already been supplied via provider override) before handing off to
/// [AppRoot].
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
                  child: const Icon(Icons.storage_rounded, color: Colors.white, size: 32),
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
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7E5FF0)),
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
