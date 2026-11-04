part of '../incident_report_screen.dart';

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
    if (code == null) {
      return 'A critical system error caused the computer to stop.';
    }
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

  String _fmtFull(DateTime dt) => formatDateTime(dt, seconds: true);
}
