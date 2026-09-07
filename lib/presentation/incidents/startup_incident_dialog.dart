import 'package:flutter/material.dart';

import '../../domain/entities/shutdown_incident.dart';
import '../../domain/enums/incident_enums.dart';
import '../theme/app_theme.dart';





Future<void> showStartupIncidentDialog(
  BuildContext context,
  ShutdownIncident incident, {
  required VoidCallback onViewReport,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primary = incident.deviceStats.isEmpty
      ? null
      : incident.deviceStats.firstWhere(
          (s) => s.deviceId == incident.primaryDeviceId,
          orElse: () => incident.deviceStats.first,
        );

  final title = incident.classification == ShutdownClassification.appSessionEndedUnexpectedly
      ? 'Previous Session Ended Unexpectedly'
      : 'Unexpected Shutdown Detected';

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 28,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (primary != null) ...[
                Text(
                  primary.deviceName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (primary.lastCelsius != null)
                  Text(
                    'Last recorded temperature: ${primary.lastCelsius!.round()}°C',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                incident.summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark
                      ? AppColors.textSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onViewReport();
                    },
                    child: const Text('View Incident Report'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
