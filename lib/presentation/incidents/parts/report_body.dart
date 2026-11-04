part of '../incident_report_screen.dart';

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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.page,
      ),
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
