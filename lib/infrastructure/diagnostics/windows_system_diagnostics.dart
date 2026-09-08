import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import 'system_diagnostics.dart';

class WindowsSystemDiagnostics implements SystemDiagnostics {
  static const _tag = 'WindowsSystemDiagnostics';

  @override
  String get backendName => 'Windows Event Log (wevtutil)';

  @override
  Future<bool> isAvailable() => SafeProcessRunner.instance.exists('wevtutil');

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
    try {
      // ── Shutdown / power events ───────────────────────────────────────
      // Kernel-Power 41: unexpected power-loss / hard reset
      events.addAll(await _query('System', 41, 'Kernel-Power', 'shutdown'));
      // EventLog 6008: unexpected shutdown (dirty boot)
      events.addAll(await _query('System', 6008, 'EventLog', 'shutdown'));
      // User32 1074: clean / planned shutdown or restart
      events.addAll(await _query('System', 1074, 'User32', 'shutdown'));

      // ── BSoD / kernel bugcheck ────────────────────────────────────────
      // WER 1001 (BugCheck): written after every BSoD; contains stop code
      events.addAll(
        await _query(
          'System',
          1001,
          'Microsoft-Windows-WER-SystemErrorReporting',
          'kernel-panic',
        ),
      );
      // WHEA (Windows Hardware Error Architecture) uncorrectable error
      // EventID 18 = hardware error, EventID 19 = hardware error (critical)
      events.addAll(await _query('System', 18, 'WHEA-Logger', 'hardware-error'));
      events.addAll(await _query('System', 19, 'WHEA-Logger', 'hardware-error'));

      // ── Storage / disk errors ─────────────────────────────────────────
      // Disk 7: "The device \Device\... has a bad block" / IO error
      events.addAll(await _query('System', 7, 'disk', 'storage-error'));
      // Disk 11: "The driver detected a controller error"
      events.addAll(await _query('System', 11, 'disk', 'storage-error'));
      // StorPort 129: device did not respond in time
      events.addAll(
        await _query('System', 129, 'storahci', 'storage-error'),
      );
      // StorPort 153: Windows attempted to reset device
      events.addAll(
        await _query('System', 153, 'storahci', 'storage-error'),
      );
      // NTFS 55: file system is corrupt / dirty
      events.addAll(
        await _query('System', 55, 'Ntfs', 'storage-error'),
      );

      // ── Memory diagnostics ────────────────────────────────────────────
      // MemoryDiagnostics-Results 1201/1202: hardware memory problem detected
      events.addAll(
        await _queryLog(
          'System',
          1201,
          'Microsoft-Windows-MemoryDiagnostics-Results',
          'hardware-error',
          count: 3,
        ),
      );
      events.addAll(
        await _queryLog(
          'System',
          1202,
          'Microsoft-Windows-MemoryDiagnostics-Results',
          'hardware-error',
          count: 3,
        ),
      );

      // ── Application crashes ───────────────────────────────────────────
      // Application Error 1000: application crash (WER)
      events.addAll(
        await _queryLog(
          'Application',
          1000,
          'Application Error',
          'app-crash',
          count: 5,
        ),
      );
      // Windows Error Reporting 1001 in Application log: crash summary
      events.addAll(
        await _queryLog(
          'Application',
          1001,
          'Windows Error Reporting',
          'app-crash',
          count: 5,
        ),
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'wevtutil query failed: $e');
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final hasBugcheck = events.any((e) => e.category == 'kernel-panic');
    final hasHardwareError = events.any((e) => e.category == 'hardware-error');
    final hasCleanShutdown = events.any(
      (e) => e.category == 'shutdown' && e.source.contains('User32'),
    );
    final hasKernelPower41 = events.any(
      (e) => e.category == 'shutdown' && e.source.contains('Kernel-Power'),
    );

    ShutdownClassification classification;
    if (hasBugcheck) {
      classification = ShutdownClassification.bsod;
    } else if (hasHardwareError && hasKernelPower41 && !hasCleanShutdown) {
      // WHEA + unexpected power = probable hardware failure
      classification = ShutdownClassification.osShutdownUnexpected;
    } else if (hasKernelPower41 && !hasCleanShutdown) {
      classification = ShutdownClassification.osShutdownUnexpected;
    } else if (hasCleanShutdown) {
      final reasonIsReboot = events.any(
        (e) =>
            e.source.contains('User32') &&
            e.raw != null &&
            e.raw!.toLowerCase().contains('restart'),
      );
      classification = reasonIsReboot
          ? ShutdownClassification.osRebootClean
          : ShutdownClassification.osShutdownClean;
    } else if (events.isEmpty) {
      classification = ShutdownClassification.unknown;
    } else {
      classification = ShutdownClassification.osShutdownUnexpected;
    }

    return PreviousBootDiagnosis(
      classification: classification,
      events: events,
      shutdownAt: events.isNotEmpty ? events.first.timestamp : null,
    );
  }

  // Query from the System log (default).
  Future<List<SystemDiagnosticEvent>> _query(
    String log,
    int eventId,
    String providerHint,
    String category, {
    int count = 5,
  }) => _queryLog(log, eventId, providerHint, category, count: count);

  // Query from any log.
  Future<List<SystemDiagnosticEvent>> _queryLog(
    String log,
    int eventId,
    String providerHint,
    String category, {
    int count = 5,
  }) async {
    final query = '*[System[(EventID=$eventId)]]';
    final result = await SafeProcessRunner.instance.run('wevtutil', [
      'qe',
      log,
      '/q:$query',
      '/rd:true',
      '/c:$count',
      '/f:text',
    ], requireZeroExit: false);
    if (result.exitCode != 0 || result.stdout.trim().isEmpty) return const [];
    return _parseTextEvents(result.stdout, providerHint, category);
  }

  List<SystemDiagnosticEvent> _parseTextEvents(
    String text,
    String providerHint,
    String category,
  ) {
    final events = <SystemDiagnosticEvent>[];
    final blocks = text.split(RegExp(r'\n(?=Log Name:)'));
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;

      final dateMatch = RegExp(r'Date:\s*(.+)').firstMatch(block);
      DateTime? timestamp;
      if (dateMatch != null) {
        timestamp = DateTime.tryParse(dateMatch.group(1)!.trim());
      }
      timestamp ??= DateTime.now();

      // --- Extract stop code / error code ---
      String? errorCode;
      String? stopCodeName;

      if (category == 'kernel-panic' || category == 'hardware-error') {
        // Try to extract well-known stop code name first
        // Pattern: BugcheckCode or stop code string like CRITICAL_PROCESS_DIED
        final stopNameMatch = RegExp(
          r'(CRITICAL_PROCESS_DIED|SYSTEM_THREAD_EXCEPTION_NOT_HANDLED|'
          r'PAGE_FAULT_IN_NONPAGED_AREA|IRQL_NOT_LESS_OR_EQUAL|'
          r'DRIVER_IRQL_NOT_LESS_OR_EQUAL|DRIVER_POWER_STATE_FAILURE|'
          r'KERNEL_SECURITY_CHECK_FAILURE|KERNEL_DATA_INPAGE_ERROR|'
          r'MEMORY_MANAGEMENT|BAD_POOL_HEADER|BAD_POOL_CALLER|'
          r'SYSTEM_SERVICE_EXCEPTION|KMODE_EXCEPTION_NOT_HANDLED|'
          r'DPC_WATCHDOG_VIOLATION|WHEA_UNCORRECTABLE_ERROR|'
          r'CLOCK_WATCHDOG_TIMEOUT|VIDEO_TDR_FAILURE|'
          r'ATTEMPTED_WRITE_TO_READONLY_MEMORY)',
          caseSensitive: false,
        ).firstMatch(block);
        if (stopNameMatch != null) {
          stopCodeName = stopNameMatch.group(0)!.toUpperCase();
        }

        // Also capture hex stop code (0x0000xxxx)
        final hexMatch = RegExp(
          r'0x[0-9A-Fa-f]{4,16}',
        ).firstMatch(block);
        errorCode = hexMatch?.group(0);

        // Prefer the human-readable name as the error code shown in UI
        if (stopCodeName != null) {
          errorCode = stopCodeName;
        }
      } else if (category == 'storage-error') {
        // Disk errors: capture device path or error status
        final deviceMatch = RegExp(
          r'\\Device\\[A-Za-z0-9\\]+',
        ).firstMatch(block);
        errorCode = deviceMatch?.group(0);
      }

      // --- Build summary line ---
      // For BSoD events, try to extract a meaningful description
      String summary;
      if (category == 'kernel-panic' && stopCodeName != null) {
        final bugcheckParam =
            RegExp(r'BugcheckParameter1\s*:\s*(0x[0-9A-Fa-f]+)')
                .firstMatch(block)
                ?.group(1);
        summary = stopCodeName +
            (bugcheckParam != null ? ' ($bugcheckParam)' : '');
      } else {
        // Default: first few non-empty lines of the block
        final lines = block
            .trim()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(4)
            .join('  ');
        summary = lines.length > 180 ? '${lines.substring(0, 180)}…' : lines;
      }

      events.add(
        SystemDiagnosticEvent(
          timestamp: timestamp,
          source: 'Windows Event Log ($providerHint)',
          category: category,
          summary: summary,
          raw: block.trim(),
          errorCode: errorCode,
        ),
      );
    }
    return events;
  }
}
