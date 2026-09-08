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

    // ── Kernel panic reports ─────────────────────────────────────────────
    final panicEvents = await _scanPanicReports();
    events.addAll(panicEvents);

    // ── App crash reports (DiagnosticReports .crash files) ───────────────
    events.addAll(await _scanAppCrashReports());

    // ── Unified log ──────────────────────────────────────────────────────
    if (await isAvailable()) {
      events.addAll(await _scanUnifiedLog());
    }

    // ── Disk errors from system_profiler / diskutil ───────────────────────
    events.addAll(await _scanDiskErrors());

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

  // ── Kernel panic (.panic) scan ──────────────────────────────────────────
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
          if (!name.contains('panic') && !name.endsWith('.panic')) continue;
          final stat = entity.statSync();
          if (stat.modified.isBefore(cutoff)) continue;

          // Read first 1200 chars to extract stop reason
          String? raw;
          String? errorCode;
          String summary = 'Kernel panic report: ${entity.path}';
          try {
            final content = await entity.readAsString();
            raw = content.length > 1200
                ? '${content.substring(0, 1200)}…'
                : content;

            // Extract panic reason
            final reasonMatch = RegExp(
              r'panic\(cpu \d+ caller[^:]+\):\s*([^\n]{1,120})',
              caseSensitive: false,
            ).firstMatch(content);
            if (reasonMatch != null) {
              errorCode = reasonMatch.group(1)?.trim();
              summary = 'Kernel Panic: ${errorCode ?? entity.path}';
            }

            // Fall back: look for "Kernel version:" line for OS version
            final versionMatch =
                RegExp(r'Kernel version:\s*([^\n]+)').firstMatch(content);
            if (errorCode == null && versionMatch != null) {
              errorCode = 'KERNEL_PANIC';
              summary = 'Kernel Panic (${versionMatch.group(1)?.trim()})';
            }
            errorCode ??= 'KERNEL_PANIC';
          } catch (_) {
            // couldn't read file content — use path only
          }

          found.add(
            SystemDiagnosticEvent(
              timestamp: stat.modified,
              source: 'macOS panic report',
              category: 'kernel-panic',
              summary: summary,
              raw: raw ?? entity.path,
              errorCode: errorCode ?? 'KERNEL_PANIC',
            ),
          );
        }
      } catch (e) {
        AppLogger.instance.debug(_tag, 'panic scan of $dirPath failed: $e');
      }
    }
    return found;
  }

  // ── App crash (.crash) scan ─────────────────────────────────────────────
  Future<List<SystemDiagnosticEvent>> _scanAppCrashReports() async {
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
          // .crash files are app crashes; exclude .panic which we handle above
          if (!name.endsWith('.crash') && !name.endsWith('.ips')) continue;
          final stat = entity.statSync();
          if (stat.modified.isBefore(cutoff)) continue;

          String? processName;
          String? exceptionType;
          String? errorCode;
          String summary;
          String? raw;

          try {
            final content = await entity.readAsString();
            raw = content.length > 1200
                ? '${content.substring(0, 1200)}…'
                : content;

            processName =
                RegExp(r'^Process:\s+(\S+)', multiLine: true)
                    .firstMatch(content)
                    ?.group(1);
            exceptionType =
                RegExp(r'^Exception Type:\s+(.+)', multiLine: true)
                    .firstMatch(content)
                    ?.group(1)
                    ?.trim();
            errorCode = exceptionType ?? 'EXC_CRASH';
            summary =
                'App Crash: ${processName ?? entity.uri.pathSegments.last}'
                '${exceptionType != null ? ' ($exceptionType)' : ''}';
          } catch (_) {
            summary = 'App Crash: ${entity.uri.pathSegments.last}';
            errorCode = 'EXC_CRASH';
          }

          found.add(
            SystemDiagnosticEvent(
              timestamp: stat.modified,
              source: 'macOS crash report',
              category: 'app-crash',
              summary: summary,
              raw: raw ?? entity.path,
              errorCode: errorCode,
            ),
          );
        }
      } catch (e) {
        AppLogger.instance.debug(_tag, 'crash scan of $dirPath failed: $e');
      }
    }
    return found;
  }

  // ── Unified log (shutdown/restart cause + disk/thermal errors) ───────────
  Future<List<SystemDiagnosticEvent>> _scanUnifiedLog() async {
    final events = <SystemDiagnosticEvent>[];

    // Shutdown/restart cause events
    try {
      final result = await SafeProcessRunner.instance.run(
        'log',
        [
          'show',
          '--last',
          '30m',
          '--predicate',
          'eventMessage contains "SIGTERM" OR '
              'eventMessage contains "shutdown cause" OR '
              'eventMessage contains "restart cause" OR '
              'eventMessage contains "panic" OR '
              'eventMessage contains "thermal" OR '
              'eventMessage contains "I/O error" OR '
              'eventMessage contains "disk error"',
          '--style',
          'compact',
        ],
        requireZeroExit: false,
        timeout: const Duration(seconds: 12),
      );

      if (result.stdout.trim().isNotEmpty) {
        for (final line in result.stdout.split('\n')) {
          if (line.trim().isEmpty) continue;
          final lower = line.toLowerCase();

          String? category;
          String? errorCode;
          if (lower.contains('restart cause')) {
            category = 'reboot-clean';
          } else if (lower.contains('shutdown cause')) {
            category = 'shutdown-clean';
          } else if (lower.contains('thermal')) {
            category = 'thermal';
            errorCode = 'THERMAL_EVENT';
          } else if (lower.contains('i/o error') ||
              lower.contains('disk error')) {
            category = 'storage-error';
          } else if (lower.contains('panic')) {
            category = 'kernel-panic';
            errorCode = 'KERNEL_PANIC';
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
              errorCode: errorCode,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'log show failed: $e');
    }

    return events;
  }

  // ── Disk errors from diskutil ────────────────────────────────────────────
  Future<List<SystemDiagnosticEvent>> _scanDiskErrors() async {
    final events = <SystemDiagnosticEvent>[];
    try {
      // diskutil list gives us drives; we want to detect any S.M.A.R.T issues
      // via 'diskutil info' for each disk. This is best-effort.
      final listResult = await SafeProcessRunner.instance.run(
        'diskutil',
        ['list', '-plist'],
        requireZeroExit: false,
        timeout: const Duration(seconds: 8),
      );
      if (listResult.exitCode != 0 || listResult.stdout.trim().isEmpty) {
        return const [];
      }

      // Extract disk identifiers e.g. /dev/disk0, /dev/disk1
      final diskMatches =
          RegExp(r'/dev/(disk\d+)(?!s)').allMatches(listResult.stdout);
      final disks = diskMatches.map((m) => m.group(1)!).toSet().take(4);

      for (final disk in disks) {
        try {
          final infoResult = await SafeProcessRunner.instance.run(
            'diskutil',
            ['info', disk],
            requireZeroExit: false,
            timeout: const Duration(seconds: 5),
          );
          if (infoResult.exitCode != 0) continue;
          final info = infoResult.stdout;

          // Look for SMART Status
          final smartMatch = RegExp(
            r'SMART Status:\s*(.+)',
          ).firstMatch(info);
          final smartStatus = smartMatch?.group(1)?.trim();
          if (smartStatus != null &&
              !smartStatus.toLowerCase().contains('verified') &&
              !smartStatus.toLowerCase().contains('not supported')) {
            events.add(
              SystemDiagnosticEvent(
                timestamp: DateTime.now(),
                source: 'diskutil ($disk)',
                category: 'storage-error',
                summary: '$disk SMART status: $smartStatus',
                raw: info.length > 600 ? '${info.substring(0, 600)}…' : info,
                errorCode: 'SMART_FAIL',
              ),
            );
          }
        } catch (e) {
          AppLogger.instance.debug(_tag, 'diskutil info $disk failed: $e');
        }
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'diskutil list failed: $e');
    }
    return events;
  }
}
