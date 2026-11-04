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
