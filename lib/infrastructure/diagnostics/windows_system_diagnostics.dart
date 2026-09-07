import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import 'system_diagnostics.dart';

/// Reads the Windows Event Log for evidence about the previous shutdown via
/// `wevtutil` (a built-in, documented Windows diagnostic utility — chosen
/// over a raw `EvtQuery`/`EvtNext` Win32 FFI binding to keep this class
/// dependency-free; it is isolated entirely behind [SystemDiagnostics] so the
/// rest of the app never depends on it directly, matching the "CLI fallback
/// isolated behind a backend" rule).
///
/// Looks for:
///  - Kernel-Power Event ID 41 ("The system has rebooted without cleanly
///    shutting down first") — unexpected shutdown/power loss indicator.
///  - EventLog Event ID 6008 — "previous system shutdown was unexpected".
///  - User32 Event ID 1074 — a clean, user/process-initiated shutdown or
///    restart, with the requested reason.
///  - BugCheck Event ID 1001 (source "Microsoft-Windows-WER-SystemErrorReporting")
///    — a bugcheck (BSOD) report with code/parameters.
class WindowsSystemDiagnostics implements SystemDiagnostics {
  static const _tag = 'WindowsSystemDiagnostics';

  @override
  String get backendName => 'Windows Event Log (wevtutil)';

  @override
  Future<bool> isAvailable() =>
      SafeProcessRunner.instance.exists('wevtutil');

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
      events.addAll(await _query('System', 41, 'Kernel-Power', 'shutdown'));
      events.addAll(await _query('System', 6008, 'EventLog', 'shutdown'));
      events.addAll(await _query('System', 1074, 'User32', 'shutdown'));
      events.addAll(
        await _query(
          'System',
          1001,
          'Microsoft-Windows-WER-SystemErrorReporting',
          'kernel-panic',
        ),
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'wevtutil query failed: $e');
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final hasBugcheck = events.any((e) => e.category == 'kernel-panic');
    final hasCleanShutdown = events.any(
      (e) => e.category == 'shutdown' && e.source.contains('User32'),
    );
    final hasKernelPower41 = events.any(
      (e) => e.category == 'shutdown' && e.source.contains('Kernel-Power'),
    );

    ShutdownClassification classification;
    if (hasBugcheck) {
      classification = ShutdownClassification.bsod;
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

  Future<List<SystemDiagnosticEvent>> _query(
    String log,
    int eventId,
    String providerHint,
    String category,
  ) async {
    final query =
        '*[System[(EventID=$eventId)]]';
    final result = await SafeProcessRunner.instance.run('wevtutil', [
      'qe',
      log,
      '/q:$query',
      '/rd:true',
      '/c:5',
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
      final firstLine = block.trim().split('\n').take(3).join(' ').trim();
      // For a bugcheck/WER event, wevtutil's text output includes the
      // bugcheck code as a hex value (e.g. "0x0000009f") somewhere in the
      // event data - surfaced as-is, never reformatted or guessed at.
      final errorCode = category == 'kernel-panic'
          ? RegExp(
              r'0x[0-9A-Fa-f]{4,16}',
            ).firstMatch(block)?.group(0)
          : null;
      events.add(
        SystemDiagnosticEvent(
          timestamp: timestamp,
          source: 'Windows Event Log ($providerHint)',
          category: category,
          summary: firstLine.length > 160
              ? '${firstLine.substring(0, 160)}…'
              : firstLine,
          raw: block.trim(),
          errorCode: errorCode,
        ),
      );
    }
    return events;
  }
}
