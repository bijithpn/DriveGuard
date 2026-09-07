import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/enums/incident_enums.dart';
import '../theme/app_theme.dart';
import 'incident_report_screen.dart';

class IncidentHistoryScreen extends ConsumerWidget {
  const IncidentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incidentsAsync = ref.watch(incidentListProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('Incident History'),
        backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
        elevation: 0,
      ),
      body: incidentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load incidents: $e')),
        data: (incidents) {
          if (incidents.isEmpty) {
            return _EmptyState(isDark: isDark);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: incidents.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _IncidentTile(incident: incidents[index], isDark: isDark),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 48,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No incidents recorded',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimary : AppColors.lightText,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Every DriveGuard session so far has ended cleanly.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({required this.incident, required this.isDark});
  final ShutdownIncident incident;
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

  String _classificationLabel() {
    switch (incident.classification) {
      case ShutdownClassification.cleanAppExit:
        return 'Clean Exit';
      case ShutdownClassification.appSessionEndedUnexpectedly:
        return 'App Session Ended Unexpectedly';
      case ShutdownClassification.osShutdownClean:
        return 'Clean Shutdown';
      case ShutdownClassification.osRebootClean:
        return 'Clean Reboot';
      case ShutdownClassification.osShutdownUnexpected:
        return 'Unexpected Shutdown';
      case ShutdownClassification.kernelPanic:
        return 'Kernel Panic';
      case ShutdownClassification.bsod:
        return 'System Error (BSOD)';
      case ShutdownClassification.possiblePowerLoss:
        return 'Possible Power Loss';
      case ShutdownClassification.unknown:
        return 'Unknown Shutdown';
    }
  }

  String _correlationLabel() {
    switch (incident.correlationLevel) {
      case CorrelationLevel.high:
        return 'Strong thermal correlation';
      case CorrelationLevel.moderate:
        return 'Possible thermal correlation';
      case CorrelationLevel.low:
        return 'Slight temperature elevation';
      case CorrelationLevel.none:
        return 'No thermal correlation';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.bg1 : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    final primaryStat = incident.deviceStats.isEmpty
        ? null
        : incident.deviceStats.firstWhere(
            (s) => s.deviceId == incident.primaryDeviceId,
            orElse: () => incident.deviceStats.first,
          );

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IncidentReportScreen(incidentId: incident.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: _correlationColor(),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(
                      incident.estimatedShutdownAt ?? incident.detectedAt,
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _classificationLabel(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    primaryStat?.deviceName ?? 'No device data',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (primaryStat?.lastCelsius != null)
                  Text(
                    '${primaryStat!.lastCelsius!.round()}°C',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _correlationColor(),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _correlationLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _correlationColor(),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
  }
}
