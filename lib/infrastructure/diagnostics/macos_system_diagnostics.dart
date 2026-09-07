import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import 'system_diagnostics.dart';















class MacOSSystemDiagnostics implements SystemDiagnostics {
  static const _tag = 'MacOSSystemDiagnostics';

  @override
  String get backendName => 'macOS unified log + panic reports';

  @override
  Future<bool> isAvailable() => SafeProcessRunner.instance.exists('log');

  @override
  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  }) async {
    final events = <SystemDiagnosticEvent>[];

    final panicEvents = await _scanPanicReports();
    events.addAll(panicEvents);

    if (await isAvailable()) {
      events.addAll(await _scanUnifiedLog());
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    ShutdownClassification classification;
    if (panicEvents.isNotEmpty) {
      classification = ShutdownClassification.kernelPanic;
    } else {
      final cleanShutdown = events.any((e) => e.category == 'shutdown-clean');
      final cleanReboot = events.any((e) => e.category == 'reboot-clean');
      if (cleanReboot) {
        classification = ShutdownClassification.osRebootClean;
      } else if (cleanShutdown) {
        classification = ShutdownClassification.osShutdownClean;
      } else if (events.isEmpty) {
        classification = ShutdownClassification.unknown;
      } else {
        classification = ShutdownClassification.osShutdownUnexpected;
      }
    }

    return PreviousBootDiagnosis(
      classification: classification,
      events: events,
      shutdownAt: events.isNotEmpty ? events.first.timestamp : null,
    );
  }

  Future<List<SystemDiagnosticEvent>> _scanPanicReports() async {
    final dirs = <String>[
      '/Library/Logs/DiagnosticReports',
      if (Platform.environment['HOME'] != null)
        '${Platform.environment['HOME']}/Library/Logs/DiagnosticReports',
    ];
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final found = <SystemDiagnosticEvent>[];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last.toLowerCase();
          final looksLikePanic =
              name.contains('panic') || name.endsWith('.panic');
          if (!looksLikePanic) continue;
          final stat = entity.statSync();
          if (stat.modified.isBefore(cutoff)) continue;
          found.add(
            SystemDiagnosticEvent(
              timestamp: stat.modified,
              source: 'macOS panic report',
              category: 'kernel-panic',
              summary: 'Kernel panic report found: ${entity.path}',
              raw: entity.path,
            ),
          );
        }
      } catch (e) {
        AppLogger.instance.debug(_tag, 'panic scan of $dirPath failed: $e');
      }
    }
    return found;
  }

  Future<List<SystemDiagnosticEvent>> _scanUnifiedLog() async {
    try {
      final result = await SafeProcessRunner.instance.run('log', [
        'show',
        '--last',
        '10m',
        '--predicate',
        'eventMessage contains "SIGTERM" OR eventMessage contains '
            '"shutdown cause" OR eventMessage contains "restart cause"',
        '--style',
        'compact',
      ], requireZeroExit: false, timeout: const Duration(seconds: 10));
      if (result.stdout.trim().isEmpty) return const [];

      final events = <SystemDiagnosticEvent>[];
      for (final line in result.stdout.split('\n')) {
        if (line.trim().isEmpty) continue;
        final lower = line.toLowerCase();
        String category;
        if (lower.contains('restart cause')) {
          category = 'reboot-clean';
        } else if (lower.contains('shutdown cause')) {
          category = 'shutdown-clean';
        } else {
          continue;
        }
        final tsMatch = RegExp(
          r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})',
        ).firstMatch(line);
        final timestamp = tsMatch != null
            ? DateTime.tryParse(tsMatch.group(1)!) ?? DateTime.now()
            : DateTime.now();
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'macOS unified log',
            category: category,
            summary: line.length > 160 ? '${line.substring(0, 160)}…' : line,
            raw: line,
          ),
        );
      }
      return events;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'log show failed: $e');
      return const [];
    }
  }
}
