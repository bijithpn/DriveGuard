part of '../incident_report_screen.dart';

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
    final classColor = _classColor(incident.classification);
    final classLabel = _classLabel(incident.classification);
    final text = primaryTextOf(context);

    Widget cell(String label, String value, Color color) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption(context)),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppText.metric(context, size: 22).copyWith(color: color),
            ),
          ],
        ),
      ),
    );

    final cells = <Widget>[
      cell(
        'Thermal correlation',
        incident.correlationLevel.name[0].toUpperCase() +
            incident.correlationLevel.name.substring(1),
        _correlationColor(),
      ),
      if (primary?.lastCelsius != null)
        cell('Last temperature', '${primary!.lastCelsius!.round()}°C', text),
      if (primary?.maxCelsius != null)
        cell(
          'Peak temperature',
          '${primary!.maxCelsius!.round()}°C',
          primary!.criticalExceeded
              ? AppColors.critical
              : (primary!.warningExceeded ? AppColors.warning : text),
        ),
      if (primary != null && primary!.criticalDuration > Duration.zero)
        cell(
          'Time critical',
          _fmtDuration(primary!.criticalDuration),
          AppColors.critical,
        ),
    ];

    return Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusDot(classColor, size: 9),
                    const SizedBox(width: 10),
                    Text(
                      classLabel,
                      style: AppText.heading(context).copyWith(fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(incident.summary, style: AppText.secondary(context)),
              ],
            ),
          ),
          Divider(height: 1, color: hairlineOf(context)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.card),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(width: 1, color: hairlineOf(context)),
                    cells[i],
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: hairlineOf(context)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.card,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                KeyValueRow('Shutdown', _fmtFull(incident.estimatedShutdownAt)),
                KeyValueRow('Startup', _fmtFull(incident.startupAt)),
              ],
            ),
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
