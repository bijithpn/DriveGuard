import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/entities/system_diagnostic_event.dart';
import '../../domain/enums/incident_enums.dart';
import '../theme/app_theme.dart';

class IncidentReportScreen extends ConsumerWidget {
  const IncidentReportScreen({super.key, required this.incidentId});
  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(incidentDetailProvider(incidentId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('Incident Report'),
        backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load incident: $e')),
        data: (incident) {
          if (incident == null) {
            return const Center(child: Text('Incident not found'));
          }
          return _ReportBody(incident: incident, isDark: isDark);
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.incident, required this.isDark});
  final ShutdownIncident incident;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final primary = incident.deviceStats.isEmpty
        ? null
        : incident.deviceStats.firstWhere(
            (s) => s.deviceId == incident.primaryDeviceId,
            orElse: () => incident.deviceStats.first,
          );

    // Partition diagnostic events by category
    final kernelPanics = incident.diagnosticEvents
        .where((e) => e.category == 'kernel-panic')
        .toList();
    final hardwareErrors = incident.diagnosticEvents
        .where((e) => e.category == 'hardware-error')
        .toList();
    final storageErrors = incident.diagnosticEvents
        .where((e) => e.category == 'storage-error')
        .toList();
    final appCrashes = incident.diagnosticEvents
        .where((e) => e.category == 'app-crash')
        .toList();
    final shutdownEvents = incident.diagnosticEvents
        .where((e) => e.category == 'shutdown')
        .toList();
    final otherEvents = incident.diagnosticEvents
        .where(
          (e) =>
              e.category != 'kernel-panic' &&
              e.category != 'hardware-error' &&
              e.category != 'storage-error' &&
              e.category != 'app-crash' &&
              e.category != 'shutdown',
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ── Summary header ──────────────────────────────────────────────
        _HeaderCard(incident: incident, primary: primary, isDark: isDark),
        const SizedBox(height: AppSpacing.md),

        // ── BSoD / Stop-code banner ─────────────────────────────────────
        if (kernelPanics.isNotEmpty) ...[
          _BsodBanner(events: kernelPanics, isDark: isDark),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Hardware errors (WHEA) ──────────────────────────────────────
        if (hardwareErrors.isNotEmpty) ...[
          _SectionLabel('Hardware Errors (WHEA)', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...hardwareErrors.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Temperature timeline ────────────────────────────────────────
        if (incident.timeline.isNotEmpty) ...[
          _SectionLabel('Temperature Timeline', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _TimelineChart(incident: incident, isDark: isDark),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Storage diagnostics ─────────────────────────────────────────
        if (incident.deviceStats.isNotEmpty) ...[
          _SectionLabel('Storage Diagnostics', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...incident.deviceStats.map(
            (s) => _DeviceStatRow(stat: s, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Disk / storage errors ───────────────────────────────────────
        if (storageErrors.isNotEmpty) ...[
          _SectionLabel('Disk & Storage Errors', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...storageErrors.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── App crashes ─────────────────────────────────────────────────
        if (appCrashes.isNotEmpty) ...[
          _SectionLabel('Application Crashes', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...appCrashes.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Shutdown events ─────────────────────────────────────────────
        if (shutdownEvents.isNotEmpty) ...[
          _SectionLabel('Shutdown Events', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...shutdownEvents.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Other events ────────────────────────────────────────────────
        if (otherEvents.isNotEmpty) ...[
          _SectionLabel('Other System Events', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...otherEvents.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Empty state ─────────────────────────────────────────────────
        if (incident.diagnosticEvents.isEmpty)
          _InfoNote(
            text:
                'No platform diagnostic events or application errors '
                'were found for this session (the diagnostic utility may '
                'be unavailable, or the window had no relevant entries).',
            isDark: isDark,
          ),

        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.incident,
    required this.primary,
    required this.isDark,
  });
  final ShutdownIncident incident;
  final DeviceIncidentStat? primary;
  final bool isDark;

  Color _correlationColor() {
    switch (incident.correlationLevel) {
      case CorrelationLevel.high:
        return AppColors.critical;
      case CorrelationLevel.moderate:
        return AppColors.warning;
      case CorrelationLevel.low:
        return AppColors.warm;
      case CorrelationLevel.none:
        return AppColors.normal;
    }
  }

  // Human-readable shutdown classification label
  static String _classLabel(ShutdownClassification c) {
    switch (c) {
      case ShutdownClassification.bsod:
        return 'Blue Screen (BSoD)';
      case ShutdownClassification.kernelPanic:
        return 'Kernel Panic';
      case ShutdownClassification.osShutdownUnexpected:
        return 'Unexpected Shutdown';
      case ShutdownClassification.possiblePowerLoss:
        return 'Possible Power Loss';
      case ShutdownClassification.osShutdownClean:
        return 'Clean Shutdown';
      case ShutdownClassification.osRebootClean:
        return 'Clean Reboot';
      case ShutdownClassification.appSessionEndedUnexpectedly:
        return 'App Crash';
      case ShutdownClassification.cleanAppExit:
        return 'Normal Exit';
      case ShutdownClassification.unknown:
        return 'Unknown';
    }
  }

  static Color _classColor(ShutdownClassification c) {
    switch (c) {
      case ShutdownClassification.bsod:
      case ShutdownClassification.kernelPanic:
        return AppColors.critical;
      case ShutdownClassification.osShutdownUnexpected:
      case ShutdownClassification.possiblePowerLoss:
        return AppColors.warning;
      case ShutdownClassification.appSessionEndedUnexpectedly:
        return AppColors.warm;
      case ShutdownClassification.osShutdownClean:
      case ShutdownClassification.osRebootClean:
      case ShutdownClassification.cleanAppExit:
        return AppColors.normal;
      case ShutdownClassification.unknown:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.bg1 : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    final textColor = isDark ? AppColors.textPrimary : AppColors.lightText;
    final secondary = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

    final classColor = _classColor(incident.classification);
    final classLabel = _classLabel(incident.classification);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Classification badge row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: classColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: classColor.withValues(alpha: 0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      incident.classification == ShutdownClassification.bsod ||
                              incident.classification ==
                                  ShutdownClassification.kernelPanic
                          ? Icons.report_rounded
                          : incident.classification ==
                                  ShutdownClassification.possiblePowerLoss
                          ? Icons.power_off_rounded
                          : Icons.warning_amber_rounded,
                      size: 13,
                      color: classColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      classLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: classColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            incident.summary,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _StatBlock(
                label: 'Thermal Correlation',
                value: incident.correlationLevel.name.toUpperCase(),
                color: _correlationColor(),
              ),
              if (primary?.lastCelsius != null)
                _StatBlock(
                  label: 'Last Temp',
                  value: '${primary!.lastCelsius!.round()}°C',
                  color: textColor,
                ),
              if (primary?.maxCelsius != null)
                _StatBlock(
                  label: 'Peak Temp',
                  value: '${primary!.maxCelsius!.round()}°C',
                  color: primary!.criticalExceeded
                      ? AppColors.critical
                      : primary!.warningExceeded
                      ? AppColors.warning
                      : textColor,
                ),
              if (primary != null && primary!.criticalDuration > Duration.zero)
                _StatBlock(
                  label: 'Time Critical',
                  value: _fmtDuration(primary!.criticalDuration),
                  color: AppColors.critical,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_fmtFull(incident.estimatedShutdownAt)} → shutdown   '
            '${_fmtFull(incident.startupAt)} → startup',
            style: TextStyle(fontSize: 11.5, color: secondary),
          ),
        ],
      ),
    );
  }

  String _fmtFull(DateTime? dt) {
    if (dt == null) return 'unknown';
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String _fmtDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── BSoD / Stop-code banner ─────────────────────────────────────────────────
class _BsodBanner extends StatefulWidget {
  const _BsodBanner({required this.events, required this.isDark});
  final List<SystemDiagnosticEvent> events;
  final bool isDark;

  @override
  State<_BsodBanner> createState() => _BsodBannerState();
}

class _BsodBannerState extends State<_BsodBanner> {
  int _selected = 0;
  bool _expanded = false;

  SystemDiagnosticEvent get _current => widget.events[_selected];

  // Map well-known stop codes to a plain-English description
  static const _descriptions = <String, String>{
    'CRITICAL_PROCESS_DIED':
        'A critical Windows system process stopped unexpectedly. '
        'This usually indicates corrupted system files, a bad driver, '
        'or failing hardware.',
    'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED':
        'A kernel-mode thread raised an exception that could not be handled. '
        'Often caused by a faulty device driver.',
    'PAGE_FAULT_IN_NONPAGED_AREA':
        'Windows tried to access memory that should always be present but '
        'wasn\'t — often caused by faulty RAM, disk errors, or a bad driver.',
    'IRQL_NOT_LESS_OR_EQUAL':
        'A driver tried to access memory at an invalid interrupt request level. '
        'Typically caused by a buggy or outdated driver.',
    'DRIVER_IRQL_NOT_LESS_OR_EQUAL':
        'Similar to IRQL_NOT_LESS_OR_EQUAL, caused specifically by a driver '
        'accessing memory incorrectly.',
    'DRIVER_POWER_STATE_FAILURE':
        'A driver failed during system sleep/wake transitions. '
        'Usually a driver compatibility issue.',
    'KERNEL_SECURITY_CHECK_FAILURE':
        'Windows detected data corruption in kernel structures, '
        'possibly due to faulty RAM or a rootkit.',
    'KERNEL_DATA_INPAGE_ERROR':
        'Windows could not read required data from the pagefile or virtual memory. '
        'Often linked to failing storage or bad RAM.',
    'MEMORY_MANAGEMENT':
        'A serious memory management error occurred. '
        'Could be faulty RAM, a driver issue, or disk errors.',
    'BAD_POOL_HEADER':
        'The Windows kernel pool allocator detected data corruption. '
        'Usually caused by a driver writing beyond its allocated memory.',
    'BAD_POOL_CALLER':
        'A driver or process made an invalid pool allocation request, '
        'often indicating a driver bug.',
    'SYSTEM_SERVICE_EXCEPTION':
        'A system service threw an exception while in kernel mode. '
        'Commonly caused by a faulty driver or corrupted system files.',
    'KMODE_EXCEPTION_NOT_HANDLED':
        'A kernel-mode program generated an exception that could not be handled. '
        'Often a driver bug.',
    'DPC_WATCHDOG_VIOLATION':
        'Windows detected that a deferred procedure call ran too long, '
        'usually caused by a driver or SSD firmware issue.',
    'WHEA_UNCORRECTABLE_ERROR':
        'A hardware error was detected that Windows could not correct. '
        'This points directly to faulty hardware — CPU, RAM, or PCIe device.',
    'CLOCK_WATCHDOG_TIMEOUT':
        'A processor clock interrupt was not received in time. '
        'Usually indicates an overclocking issue or hardware fault.',
    'VIDEO_TDR_FAILURE':
        'The GPU driver stopped responding and could not recover. '
        'Check GPU drivers, temperature, or hardware stability.',
    'ATTEMPTED_WRITE_TO_READONLY_MEMORY':
        'A driver tried to write to read-only or protected memory. '
        'Usually a driver bug.',

    // ── Linux kernel error codes ──────────────────────────────────────────
    'KERNEL_OOPS':
        'The Linux kernel encountered a non-fatal internal error (Oops). '
        'Often caused by a buggy kernel module or driver. '
        'If this recurs it can lead to data corruption.',
    'HARD_LOCKUP':
        'A CPU core stopped responding to interrupts (hard lockup). '
        'Typically caused by faulty hardware, overheating, or a runaway driver.',
    'GPF':
        'A General Protection Fault occurred in kernel mode. '
        'Usually caused by a driver accessing memory it should not.',
    'MACHINE_CHECK_EXCEPTION':
        'The CPU reported an uncorrectable hardware error (Machine Check Exception). '
        'This indicates failing hardware — CPU, RAM, or motherboard.',
    'CALL_TRACE':
        'The kernel printed a call trace, indicating a serious error or assertion failure. '
        'Review the raw log for the triggering cause.',
    'THERMAL_SHUTDOWN':
        'The system shut down due to a critical thermal event. '
        'A component exceeded its maximum safe temperature.',
    'SEGFAULT':
        'An application caused a segmentation fault (illegal memory access) '
        'which may have contributed to the system instability.',

    // ── macOS kernel / crash codes ────────────────────────────────────────
    'KERNEL_PANIC':
        'The macOS kernel encountered an unrecoverable error and halted. '
        'Often caused by a faulty kernel extension (kext), hardware issue, '
        'or incompatible driver.',
    'EXC_CRASH':
        'An application crashed due to an unhandled exception or signal. '
        'This may have been an app crash that destabilised the session.',
    'THERMAL_EVENT':
        'A thermal event was logged by macOS. '
        'A component may have exceeded its safe operating temperature.',
    'SMART_FAIL':
        'The disk reported a non-OK SMART status. '
        'This indicates the drive may be failing — back up your data immediately.',
  };

  static String _descriptionFor(String? code) {
    if (code == null) return 'A critical system error caused the computer to stop.';
    // For OOM events like 'OOM: firefox', give a generic OOM description
    if (code.startsWith('OOM:')) {
      final process = code.substring(4).trim();
      return 'The system ran out of memory and was forced to kill the "$process" '
          'process. Insufficient RAM, a memory leak, or runaway process can '
          'cause this — and may trigger system instability.';
    }
    return _descriptions[code] ??
        'A system-level error ($code) caused the computer to halt. '
            'Check device drivers, hardware health, and system logs.';
  }

  @override
  Widget build(BuildContext context) {
    final event = _current;
    final stopCode = event.errorCode;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628), // deep blue, BSoD-inspired
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.critical.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AppColors.critical.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.report_rounded,
                  color: AppColors.critical,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'STOP ERROR  ·  BLUE SCREEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.critical,
                  ),
                ),
                const Spacer(),
                // Event navigator if multiple BSoD events
                if (widget.events.length > 1) ...[
                  Text(
                    '${_selected + 1} / ${widget.events.length}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _NavButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: _selected > 0,
                    onTap: () => setState(() => _selected--),
                  ),
                  _NavButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: _selected < widget.events.length - 1,
                    onTap: () => setState(() => _selected++),
                  ),
                ],
              ],
            ),
          ),

          // ── Stop code ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: SelectableText(
              stopCode ?? 'UNKNOWN_STOP_CODE',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // ── Description ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              _descriptionFor(stopCode),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
          ),

          // ── Timestamp ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              _fmtFull(event.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ),
          ),

          // ── Raw event toggle ─────────────────────────────────────────
          if (event.raw != null) ...[
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? 'Hide raw event' : 'Show raw event log',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      color: Colors.white38,
                      tooltip: 'Copy raw',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: event.raw!)),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: SelectableText(
                  event.raw!,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              )
            else
              const SizedBox(height: AppSpacing.sm),
          ] else
            const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  String _fmtFull(DateTime dt) {
    final d =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    return '$d  $t';
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(
        icon,
        size: 18,
        color: enabled ? AppColors.textSecondary : AppColors.textMuted,
      ),
    );
  }
}


class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.incident, required this.isDark});
  final ShutdownIncident incident;
  final bool isDark;

  static const double _warnThreshold = 70;
  static const double _critThreshold = 85;

  Color _spotColor(String? label) {
    switch (label) {
      case 'Critical':
        return AppColors.critical;
      case 'Warning':
        return AppColors.warning;
      case 'Shutdown':
        return AppColors.critical;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final samples = incident.timeline;
    if (samples.isEmpty) return const SizedBox.shrink();

    final start = samples.first.timestamp;

    final spots = samples
        .map(
          (s) => FlSpot(
            s.timestamp.difference(start).inSeconds.toDouble(),
            s.celsius,
          ),
        )
        .toList();

    final dataMaxX = spots.last.x;
    final maxX = dataMaxX == 0
        ? 1.0
        : dataMaxX + (dataMaxX * 0.05).clamp(8.0, 60.0);

    final values = samples.map((s) => s.celsius).toList();
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    // Make sure threshold lines are visible in the chart bounds
    final effectiveMax = dataMax < _critThreshold ? _critThreshold + 4 : dataMax;
    final minY = (dataMin - 8).clamp(0, double.infinity).toDouble();
    final maxY = effectiveMax + 8;

    // Significant event samples (non-Normal, non-null label)
    final eventSamples = samples
        .where((s) => s.label != null && s.label != 'Normal')
        .toList();

    final shutdownIndex = samples.indexWhere((s) => s.label == 'Shutdown');

    final cardColor = isDark ? AppColors.bg1 : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    final gridLine = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Chart ──────────────────────────────────────────────────────
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: gridLine,
                    strokeWidth: 1,
                    dashArray: [5, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final t =
                            start.add(Duration(seconds: value.round()));
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            '${t.hour.toString().padLeft(2, '0')}:'
                            '${t.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.round()}°',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                // Threshold + shutdown lines
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    // Warning threshold
                    if (minY < _warnThreshold && maxY > _warnThreshold)
                      HorizontalLine(
                        y: _warnThreshold,
                        color: AppColors.warning.withValues(alpha: 0.55),
                        strokeWidth: 1.2,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                          labelResolver: (_) => 'WARN ${_warnThreshold.round()}°',
                        ),
                      ),
                    // Critical threshold
                    if (minY < _critThreshold && maxY > _critThreshold)
                      HorizontalLine(
                        y: _critThreshold,
                        color: AppColors.critical.withValues(alpha: 0.55),
                        strokeWidth: 1.2,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 4, bottom: 2),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.critical,
                          ),
                          labelResolver: (_) => 'CRIT ${_critThreshold.round()}°',
                        ),
                      ),
                  ],
                  verticalLines: [
                    if (shutdownIndex >= 0)
                      VerticalLine(
                        x: spots[shutdownIndex].x,
                        color: AppColors.critical,
                        strokeWidth: 1.5,
                        dashArray: [4, 3],
                        label: VerticalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.critical,
                          ),
                          labelResolver: (_) => 'Shutdown',
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: AppColors.warning,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) {
                        // Only show dots for significant event positions
                        return eventSamples.any((s) {
                          final x = s.timestamp
                              .difference(start)
                              .inSeconds
                              .toDouble();
                          return (spot.x - x).abs() < 0.5;
                        });
                      },
                      getDotPainter: (spot, pct, bar, idx) {
                        final match = eventSamples.cast<TimelineSample?>().firstWhere(
                          (s) {
                            final x = s!.timestamp
                                .difference(start)
                                .inSeconds
                                .toDouble();
                            return (spot.x - x).abs() < 0.5;
                          },
                          orElse: () => null,
                        );
                        final color = _spotColor(match?.label);
                        return FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 1.5,
                          strokeColor:
                              isDark ? AppColors.bg1 : AppColors.lightCard,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.warning.withValues(alpha: 0.08),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map(
                          (s) => LineTooltipItem(
                            '${s.y.round()}°C',
                            TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textPrimary
                                  : AppColors.lightText,
                            ),
                          ),
                        )
                        .toList(),
                    getTooltipColor: (_) =>
                        isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
                  ),
                ),
              ),
            ),
          ),

          // ── Legend ─────────────────────────────────────────────────────
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _LegendItem(
                color: AppColors.warning,
                label: 'Temperature',
                dashed: false,
              ),
              _LegendItem(
                color: AppColors.warning.withValues(alpha: 0.8),
                label: 'Warning ${_warnThreshold.round()}°C',
                dashed: true,
              ),
              _LegendItem(
                color: AppColors.critical.withValues(alpha: 0.8),
                label: 'Critical ${_critThreshold.round()}°C',
                dashed: true,
              ),
              if (shutdownIndex >= 0)
                _LegendItem(
                  color: AppColors.critical,
                  label: 'Shutdown',
                  dashed: true,
                  vertical: true,
                ),
            ],
          ),

          // ── Event chips ────────────────────────────────────────────────
          if (eventSamples.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: eventSamples.map((s) {
                final color = _spotColor(s.label);
                final hh = s.timestamp.hour.toString().padLeft(2, '0');
                final mm = s.timestamp.minute.toString().padLeft(2, '0');
                final ss = s.timestamp.second.toString().padLeft(2, '0');
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: color.withValues(alpha: 0.28),
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$hh:$mm:$ss  ',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        TextSpan(
                          text: s.label ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        TextSpan(
                          text: '  ${s.celsius.round()}°C',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.dashed,
    this.vertical = false,
  });
  final Color color;
  final String label;
  final bool dashed;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: vertical ? 10 : 18,
          height: vertical ? 10 : 10,
          child: CustomPaint(
            painter: _LinePainter(
              color: color,
              dashed: dashed,
              vertical: vertical,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.color,
    required this.dashed,
    this.vertical = false,
  });
  final Color color;
  final bool dashed;
  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    if (vertical) {
      // Draw a short vertical dashed line
      double y = 0;
      bool on = true;
      while (y < size.height) {
        final end = (y + 3).clamp(0.0, size.height);
        if (on) {
          canvas.drawLine(
            Offset(size.width / 2, y),
            Offset(size.width / 2, end),
            paint,
          );
        }
        y += 3;
        on = !on;
      }
    } else {
      double x = 0;
      bool on = true;
      while (x < size.width) {
        final end = (x + 4).clamp(0.0, size.width);
        if (on) {
          canvas.drawLine(
            Offset(x, size.height / 2),
            Offset(end, size.height / 2),
            paint,
          );
        }
        x += 6;
        on = !on;
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.dashed != dashed || old.vertical != vertical;
}


class _DeviceStatRow extends StatelessWidget {
  const _DeviceStatRow({required this.stat, required this.isDark});
  final DeviceIncidentStat stat;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.deviceName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimary : AppColors.lightText,
              ),
            ),
          ),
          if (stat.maxCelsius != null)
            Text(
              'Max ${stat.maxCelsius!.round()}°C',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          const SizedBox(width: AppSpacing.sm),
          if (stat.criticalExceeded)
            const _Badge(text: 'Critical', color: AppColors.critical)
          else if (stat.warningExceeded)
            const _Badge(text: 'Warning', color: AppColors.warning)
          else
            const _Badge(text: 'Normal', color: AppColors.normal),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DiagnosticEventRow extends StatefulWidget {
  const _DiagnosticEventRow({required this.event, required this.isDark});
  final SystemDiagnosticEvent event;
  final bool isDark;

  @override
  State<_DiagnosticEventRow> createState() => _DiagnosticEventRowState();
}

class _DiagnosticEventRowState extends State<_DiagnosticEventRow> {
  bool _expanded = false;

  bool get _isCrash => widget.event.category == 'app-crash';

  Color get _categoryColor {
    switch (widget.event.category) {
      case 'app-crash':
      case 'kernel-panic':
        return AppColors.critical;
      case 'storage-error':
      case 'thermal':
        return AppColors.warning;
      default:
        return widget.isDark
            ? AppColors.textMuted
            : AppColors.lightTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isDark = widget.isDark;

    final hasDetail = event.raw != null && event.raw != event.summary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: _isCrash
            ? AppColors.critical.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _isCrash ? Icons.bug_report_outlined : Icons.circle,
                    size: _isCrash ? 14 : 6,
                    color: _categoryColor,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.summary,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? AppColors.textPrimary
                                : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              '${event.source} · ${event.category}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (event.errorCode != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _categoryColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  event.errorCode!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: _categoryColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (hasDetail)
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: isDark
                          ? AppColors.textMuted
                          : AppColors.lightTextSecondary,
                    ),
                ],
              ),
              if (_expanded && hasDetail) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bg0 : AppColors.lightSurfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: isDark ? AppColors.border : AppColors.lightBorder,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          event.raw!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        color: AppColors.textMuted,
                        tooltip: 'Copy',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: event.raw!)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? AppColors.textSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}
