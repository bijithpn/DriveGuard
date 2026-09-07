import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import 'system_diagnostics.dart';

class LinuxSystemDiagnostics implements SystemDiagnostics {
  static const _tag = 'LinuxSystemDiagnostics';

  @override
  String get backendName => 'systemd journal (journalctl)';

  @override
  Future<bool> isAvailable() => SafeProcessRunner.instance.exists('journalctl');

  @override
  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  }) async {
    if (!await isAvailable()) {
      return const PreviousBootDiagnosis(
        classification: ShutdownClassification.unknown,
        events: [],
      );
    }

    List<String> lines;
    try {
      final result = await SafeProcessRunner.instance.run(
        'journalctl',
        ['-b', '-1', '--no-pager', '-o', 'short-iso'],
        requireZeroExit: false,
        timeout: const Duration(seconds: 10),
      );
      if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
        return const PreviousBootDiagnosis(
          classification: ShutdownClassification.unknown,
          events: [],
        );
      }
      lines = result.stdout.split('\n');
    } catch (e) {
      AppLogger.instance.debug(_tag, 'journalctl -b -1 failed: $e');
      return const PreviousBootDiagnosis(
        classification: ShutdownClassification.unknown,
        events: [],
      );
    }

    final events = <SystemDiagnosticEvent>[];
    const storageKeywords = [
      'i/o error',
      'ata error',
      'nvme',
      'controller reset',
      'medium error',
      'ext4-fs error',
      'xfs',
      'btrfs error',
    ];
    const panicKeywords = ['kernel panic', 'oops:', 'hard lockup'];
    const oomKeywords = ['out of memory', 'oom-killer', 'oom_kill'];

    var sawCleanShutdownTarget = false;
    var sawRebootTarget = false;
    var sawPanic = false;

    for (final line in lines) {
      final lower = line.toLowerCase();
      final timestamp = _parseTimestamp(line);

      if (panicKeywords.any(lower.contains)) {
        sawPanic = true;
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'kernel-panic',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (oomKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'oom',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (storageKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'storage-error',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (lower.contains('reached target reboot')) {
        sawRebootTarget = true;
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'reboot-clean',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (lower.contains('reached target poweroff') ||
          lower.contains('reached target shutdown') ||
          lower.contains('system is powering down')) {
        sawCleanShutdownTarget = true;
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'shutdown-clean',
            summary: _truncate(line),
            raw: line,
          ),
        );
      }
    }

    ShutdownClassification classification;
    if (sawPanic) {
      classification = ShutdownClassification.kernelPanic;
    } else if (sawRebootTarget) {
      classification = ShutdownClassification.osRebootClean;
    } else if (sawCleanShutdownTarget) {
      classification = ShutdownClassification.osShutdownClean;
    } else if (lines.where((l) => l.trim().isNotEmpty).isEmpty) {
      classification = ShutdownClassification.unknown;
    } else {
      classification = ShutdownClassification.possiblePowerLoss;
    }

    return PreviousBootDiagnosis(
      classification: classification,
      events: events,
      shutdownAt: events.isNotEmpty
          ? events
                .map((e) => e.timestamp)
                .reduce((a, b) => a.isAfter(b) ? a : b)
          : null,
    );
  }

  DateTime _parseTimestamp(String line) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})',
    ).firstMatch(line);
    if (match == null) return DateTime.now();
    return DateTime.tryParse(match.group(1)!) ?? DateTime.now();
  }

  String _truncate(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
