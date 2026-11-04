import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/utils/date_format.dart';
import '../../domain/entities/shutdown_incident.dart';
import '../../domain/enums/incident_enums.dart';
import '../components/app_shell.dart';
import '../components/ui_kit.dart';
import '../theme/app_theme.dart';
import 'incident_report_screen.dart';

/// Every time DriveGuard noticed the computer shut down unexpectedly, with
/// how strongly drive temperature correlates with it.
class IncidentHistoryScreen extends ConsumerStatefulWidget {
  const IncidentHistoryScreen({super.key});

  @override
  ConsumerState<IncidentHistoryScreen> createState() =>
      _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends ConsumerState<IncidentHistoryScreen> {
  /// null = all. Default hides info-level noise (app restarts).
  IncidentSeverity? _min = IncidentSeverity.warning;

  bool _passes(ShutdownIncident i) =>
      _min == null || i.severity.index >= _min!.index;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ShutdownIncident>> incidentsAsync = ref.watch(
      incidentListProvider,
    );

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
        data: (all) {
          final incidents = all.where(_passes).toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: 'Incidents',
                    subtitle: all.isEmpty
                        ? 'Unexpected shutdowns and crashes appear here'
                        : '${incidents.length} shown of ${all.length}  ·  newest first',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      0,
                      AppSpacing.page,
                      AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedSwitch<IncidentSeverity?>(
                        value: _min,
                        onChanged: (v) => setState(() => _min = v),
                        options: const [
                          (
                            IncidentSeverity.error,
                            'Errors',
                            Icons.error_outline_rounded,
                          ),
                          (
                            IncidentSeverity.warning,
                            'Warnings & errors',
                            Icons.warning_amber_rounded,
                          ),
                          (null, 'All', Icons.list_rounded),
                        ],
                      ),
                    ),
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
          );
        },
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
          'Nothing to show for this filter.',
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

  Color _color() => switch (incident.severity) {
    IncidentSeverity.error => AppColors.critical,
    IncidentSeverity.warning => AppColors.warning,
    IncidentSeverity.info => AppColors.normal,
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

  static String _date(DateTime dt) => formatDateTime(dt);

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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _classification(),
                            style: AppText.heading(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SeverityBadge(incident.severity, color),
                      ],
                    ),
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

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge(this.severity, this.color);
  final IncidentSeverity severity;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      switch (severity) {
        IncidentSeverity.error => 'ERROR',
        IncidentSeverity.warning => 'WARNING',
        IncidentSeverity.info => 'INFO',
      },
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: color,
      ),
    ),
  );
}
