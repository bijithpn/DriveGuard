import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import 'system_diagnostics.dart';

class LinuxSystemDiagnostics implements SystemDiagnostics {
  static const _tag = 'LinuxSystemDiagnostics';

  // ── Keyword lists ─────────────────────────────────────────────────────────

  static const _panicKeywords = [
    'kernel panic',
    'oops:',
    'hard lockup',
    'call trace',
    'rip ',
    'bug:',
    'general protection fault',
    'kernel bug',
    'machine check exception',
    'mce:',
  ];

  static const _oomKeywords = [
    'out of memory',
    'oom-killer',
    'oom_kill',
    'killed process',
  ];

  static const _storageKeywords = [
    'i/o error',
    'ata error',
    'nvme',
    'controller reset',
    'medium error',
    'ext4-fs error',
    'xfs',
    'btrfs error',
    'scsi error',
    'buffer i/o error',
    'failed command',
    'blk_update_request',
    'ata link reset',
  ];

  static const _thermalKeywords = [
    'critical temperature reached',
    'acpi: thermal',
    'cpu0: core temperature above',
  ];

  static const _mceKeywords = [
    'machine check exception',
    'mce:',
    'edac',
    'uncorrected error',
  ];

  static const _appCrashKeywords = [
    'segfault at',
    'core dumped',
    'segmentation fault',
  ];

  static const _cleanShutdownKeywords = [
    'reached target poweroff',
    'reached target shutdown',
    'system is powering down',
  ];

  static const _cleanRebootKeywords = ['reached target reboot'];

  // ── Interface ─────────────────────────────────────────────────────────────

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

    final events = <SystemDiagnosticEvent>[];

    // 1. journalctl -b -1 scan
    List<String> journalLines = const [];
    var sawCleanShutdownTarget = false;
    var sawRebootTarget = false;
    var sawPanic = false;
    var sawMCE = false;

    try {
      final result = await SafeProcessRunner.instance.run(
        'journalctl',
        ['-b', '-1', '--no-pager', '-o', 'short-iso'],
        requireZeroExit: false,
        timeout: const Duration(seconds: 10),
      );
      if (result.exitCode == 0 && result.stdout.trim().isNotEmpty) {
        journalLines = result.stdout.split('\n');
        final journalEvents = _parseJournalLines(journalLines);
        for (final e in journalEvents) {
          switch (e.category) {
            case 'kernel-panic':
              sawPanic = true;
            case 'mce':
              sawMCE = true;
            case 'reboot-clean':
              sawRebootTarget = true;
            case 'shutdown-clean':
              sawCleanShutdownTarget = true;
          }
        }
        events.addAll(journalEvents);
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'journalctl -b -1 failed: $e');
    }

    // 2. /var/crash scan
    try {
      events.addAll(await _scanVarCrash());
    } catch (e) {
      AppLogger.instance.debug(_tag, '/var/crash scan failed: $e');
    }

    // 3. coredumpctl scan
    try {
      if (await SafeProcessRunner.instance.exists('coredumpctl')) {
        events.addAll(await _scanCoredumpctl());
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'coredumpctl scan failed: $e');
    }

    // Sort by timestamp descending
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Classification
    final ShutdownClassification classification;
    if (sawPanic || sawMCE) {
      classification = ShutdownClassification.kernelPanic;
    } else if (sawRebootTarget) {
      classification = ShutdownClassification.osRebootClean;
    } else if (sawCleanShutdownTarget) {
      classification = ShutdownClassification.osShutdownClean;
    } else if (journalLines.where((l) => l.trim().isNotEmpty).isEmpty) {
      classification = ShutdownClassification.unknown;
    } else {
      classification = ShutdownClassification.possiblePowerLoss;
    }

    return PreviousBootDiagnosis(
      classification: classification,
      events: events,
      shutdownAt: events.isNotEmpty ? events.first.timestamp : null,
    );
  }

  // ── journalctl parsing ────────────────────────────────────────────────────

  List<SystemDiagnosticEvent> _parseJournalLines(List<String> lines) {
    final events = <SystemDiagnosticEvent>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      final timestamp = _parseTimestamp(line);

      if (_panicKeywords.any(lower.contains)) {
        // Collect up to 15 subsequent lines for context
        final contextLines = <String>[line];
        for (var j = i + 1; j <= i + 15 && j < lines.length; j++) {
          contextLines.add(lines[j]);
        }
        final rawBlock = contextLines.join('\n');
        final errorCode = _extractPanicErrorCode(line, lower);

        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'kernel-panic',
            summary: _truncate(line),
            raw: rawBlock,
            errorCode: errorCode,
          ),
        );
      } else if (_mceKeywords.any(lower.contains)) {
        final contextLines = <String>[line];
        for (var j = i + 1; j <= i + 15 && j < lines.length; j++) {
          contextLines.add(lines[j]);
        }
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'mce',
            summary: _truncate(line),
            raw: contextLines.join('\n'),
            errorCode: 'MACHINE_CHECK_EXCEPTION',
          ),
        );
      } else if (_oomKeywords.any(lower.contains)) {
        final errorCode = _extractOomErrorCode(line);
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'oom',
            summary: _truncate(line),
            raw: line,
            errorCode: errorCode,
          ),
        );
      } else if (_storageKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'storage-error',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (_thermalKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'thermal',
            summary: _truncate(line),
            raw: line,
            errorCode: 'THERMAL_SHUTDOWN',
          ),
        );
      } else if (_appCrashKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'app-crash',
            summary: _truncate(line),
            raw: line,
            errorCode: 'SEGFAULT',
          ),
        );
      } else if (_cleanRebootKeywords.any(lower.contains)) {
        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'journalctl',
            category: 'reboot-clean',
            summary: _truncate(line),
            raw: line,
          ),
        );
      } else if (_cleanShutdownKeywords.any(lower.contains)) {
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

    return events;
  }

  // ── /var/crash scan ───────────────────────────────────────────────────────

  Future<List<SystemDiagnosticEvent>> _scanVarCrash() async {
    final crashDir = Directory('/var/crash');
    if (!crashDir.existsSync()) return const [];

    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final events = <SystemDiagnosticEvent>[];

    try {
      for (final entity in crashDir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last.toLowerCase();
        if (!name.endsWith('.crash')) continue;

        final stat = entity.statSync();
        if (stat.modified.isBefore(cutoff)) continue;

        try {
          // Read first 800 chars
          final raf = entity.openSync();
          final bytes = raf.readSync(800);
          raf.closeSync();
          final content = String.fromCharCodes(bytes);

          final package = _extractField(content, 'Package');
          final signal = _extractField(content, 'Signal');
          final exePath = _extractField(content, 'ExecutablePath');

          final displayName =
              package ?? exePath?.split('/').last ?? entity.path;
          final errorCode =
              (signal != null && signal.isNotEmpty) ? signal : (package ?? 'UNKNOWN');
          final summary = 'Crash: $displayName'
              '${(signal != null && signal.isNotEmpty) ? ' signal $signal' : ''}';

          events.add(
            SystemDiagnosticEvent(
              timestamp: stat.modified,
              source: 'crash-report (/var/crash)',
              category: 'app-crash',
              summary: summary,
              raw: '${entity.path}\n$content',
              errorCode: errorCode,
            ),
          );
        } catch (e) {
          AppLogger.instance.debug(
            _tag,
            'Failed to read crash file ${entity.path}: $e',
          );
        }
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Failed to list /var/crash: $e');
    }

    return events;
  }

  // ── coredumpctl scan ──────────────────────────────────────────────────────

  Future<List<SystemDiagnosticEvent>> _scanCoredumpctl() async {
    try {
      final result = await SafeProcessRunner.instance.run(
        'coredumpctl',
        ['list', '--no-pager', '-q'],
        requireZeroExit: false,
        timeout: const Duration(seconds: 8),
      );
      if (result.stdout.trim().isEmpty) return const [];

      final cutoff = DateTime.now().subtract(const Duration(days: 3));
      final events = <SystemDiagnosticEvent>[];

      for (final line in result.stdout.split('\n')) {
        if (line.trim().isEmpty) continue;
        final parsed = _parseCoredumpctlLine(line);
        if (parsed == null) continue;
        final (timestamp, sig, exe) = parsed;
        if (timestamp.isBefore(cutoff)) continue;

        events.add(
          SystemDiagnosticEvent(
            timestamp: timestamp,
            source: 'coredumpctl',
            category: 'app-crash',
            summary: 'Crash: $exe (signal $sig)',
            raw: line,
            errorCode: 'SIG$sig',
          ),
        );
      }

      return events;
    } catch (e) {
      AppLogger.instance.debug(_tag, 'coredumpctl list failed: $e');
      return const [];
    }
  }

  /// Parses a coredumpctl list line.
  /// Returns (timestamp, sig, exe) or null if unparseable.
  ///
  /// coredumpctl list -q format (columns):
  ///   TIME  PID  UID  GID  SIG  COREFILE  EXE
  ///   e.g.: Mon 2026-09-07 10:23:45 UTC  1234  1000  1000  11  present  /usr/bin/myapp
  (DateTime, String, String)? _parseCoredumpctlLine(String line) {
    final dateMatch = RegExp(
      r'(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})',
    ).firstMatch(line);
    if (dateMatch == null) return null;

    final timestamp =
        DateTime.tryParse('${dateMatch.group(1)} ${dateMatch.group(2)}');
    if (timestamp == null) return null;

    // After the timestamp portion, strip optional timezone label then split
    final afterTs = line.substring(dateMatch.end).trim();
    final withoutTz = afterTs.replaceFirst(RegExp(r'^[A-Z+\d:]+\s*'), '');
    final cols =
        withoutTz.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();

    // cols: PID  UID  GID  SIG  COREFILE  [EXE...]
    if (cols.length < 5) return null;

    final sig = cols[3];
    final exe = cols.length > 5 ? cols.sublist(5).join(' ') : cols[4];

    return (timestamp, sig, exe);
  }

  // ── Error code extractors ─────────────────────────────────────────────────

  String? _extractPanicErrorCode(String line, String lower) {
    if (lower.contains('kernel panic')) {
      final match = RegExp(
        r'[Kk]ernel panic - not synced:\s*(.{1,60})',
      ).firstMatch(line);
      if (match != null) return match.group(1)!.trim();
      return 'KERNEL_PANIC';
    }
    if (lower.contains('oops:')) return 'KERNEL_OOPS';
    if (lower.contains('hard lockup')) return 'HARD_LOCKUP';
    if (lower.contains('general protection fault')) return 'GPF';
    if (lower.contains('machine check exception') || lower.contains('mce:')) {
      return 'MACHINE_CHECK_EXCEPTION';
    }
    return null;
  }

  String _extractOomErrorCode(String line) {
    // Look for "Kill process <pid> (<name>)" or "Killed process <pid> (<name>)"
    final match = RegExp(
      r'[Kk]ill(?:ed)? process \d+ \((\w+)\)',
    ).firstMatch(line);
    if (match != null) return 'OOM: ${match.group(1)}';
    return 'OOM';
  }

  String? _extractField(String content, String fieldName) {
    final match = RegExp(
      '^$fieldName:\\s*(.+)',
      multiLine: true,
    ).firstMatch(content);
    return match?.group(1)?.trim();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  DateTime _parseTimestamp(String line) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})',
    ).firstMatch(line);
    if (match == null) return DateTime.now();
    return DateTime.tryParse(match.group(1)!) ?? DateTime.now();
  }

  String _truncate(String s) =>
      s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
