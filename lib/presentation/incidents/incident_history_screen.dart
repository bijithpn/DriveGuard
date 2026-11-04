import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/enums/incident_enums.dart';
import '../components/app_shell.dart';
import '../components/ui_kit.dart';
import '../theme/app_theme.dart';
import 'incident_report_screen.dart';

/// Every time DriveGuard noticed the computer shut down unexpectedly, with
/// how strongly drive temperature correlates with it.
class IncidentHistoryScreen extends ConsumerWidget {
  const IncidentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidentsAsync = ref.watch(incidentListProvider);

    return AppShell(
      section: AppSection.incidents,
      child: incidentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Failed to load incidents: $e',
            style: AppText.secondary(context),
          ),
        ),
        data: (incidents) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Incidents',
                  subtitle: incidents.isEmpty
                      ? 'Unexpected shutdowns and crashes appear here'
                      : '${incidents.length} recorded  ·  newest first',
                ),
                Expanded(
                  child: incidents.isEmpty
                      ? const _EmptyState()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.page,
                            AppSpacing.xs,
                            AppSpacing.page,
                            AppSpacing.page,
                          ),
                          children: [
                            Surface(
                              padding: EdgeInsets.zero,
                              clip: true,
                              child: Column(
                                children: [
                                  for (var i = 0; i < incidents.length; i++)
                                    _IncidentRow(
                                      incident: incidents[i],
                                      first: i == 0,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_outlined, size: 32, color: AppColors.normal),
        const SizedBox(height: AppSpacing.md),
        Text('No incidents recorded', style: AppText.heading(context)),
        const SizedBox(height: 4),
        Text(
          'Every DriveGuard session so far has ended cleanly.',
          style: AppText.secondary(context),
        ),
      ],
    ),
  );
}

class _IncidentRow extends StatefulWidget {
  const _IncidentRow({required this.incident, required this.first});
  final ShutdownIncident incident;
  final bool first;

  @override
  State<_IncidentRow> createState() => _IncidentRowState();
}

class _IncidentRowState extends State<_IncidentRow> {
  bool _hover = false;
  ShutdownIncident get incident => widget.incident;

  Color _color() => switch (incident.correlationLevel) {
    CorrelationLevel.high => AppColors.critical,
    CorrelationLevel.moderate => AppColors.warning,
    CorrelationLevel.low => AppColors.warm,
    CorrelationLevel.none => AppColors.normal,
  };

  String _classification() => switch (incident.classification) {
    ShutdownClassification.cleanAppExit => 'Clean exit',
    ShutdownClassification.appSessionEndedUnexpectedly =>
      'App session ended unexpectedly',
    ShutdownClassification.osShutdownClean => 'Clean shutdown',
    ShutdownClassification.osRebootClean => 'Clean reboot',
    ShutdownClassification.osShutdownUnexpected => 'Unexpected shutdown',
    ShutdownClassification.kernelPanic => 'Kernel panic',
    ShutdownClassification.bsod => 'System error (BSOD)',
    ShutdownClassification.possiblePowerLoss => 'Possible power loss',
    ShutdownClassification.unknown => 'Unknown shutdown',
  };

  String _correlation() => switch (incident.correlationLevel) {
    CorrelationLevel.high => 'Strong thermal correlation',
    CorrelationLevel.moderate => 'Possible thermal correlation',
    CorrelationLevel.low => 'Slight temperature rise',
    CorrelationLevel.none => 'No thermal correlation',
  };

  static String _date(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  $h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final stat = incident.deviceStats.isEmpty
        ? null
        : incident.deviceStats.firstWhere(
            (s) => s.deviceId == incident.primaryDeviceId,
            orElse: () => incident.deviceStats.first,
          );
    final color = _color();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => IncidentReportScreen(incidentId: incident.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.card,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: _hover
                ? (dark ? Colors.white : Colors.black).withValues(alpha: 0.03)
                : Colors.transparent,
            border: widget.first
                ? null
                : Border(top: BorderSide(color: hairlineOf(context))),
          ),
          child: Row(
            children: [
              StatusDot(color, size: 9),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_classification(), style: AppText.heading(context)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _date(
                          incident.estimatedShutdownAt ?? incident.detectedAt,
                        ),
                        stat?.deviceName ?? 'No device data',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondary(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (stat?.lastCelsius != null)
                    Text(
                      '${stat!.lastCelsius!.round()}°C',
                      style: AppText.heading(context).copyWith(
                        fontSize: 16,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(_correlation(), style: AppText.caption(context)),
                ],
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: faintOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
