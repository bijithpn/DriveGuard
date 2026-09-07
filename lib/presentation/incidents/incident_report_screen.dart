import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/shutdown_incident.dart';
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

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _HeaderCard(incident: incident, primary: primary, isDark: isDark),
        const SizedBox(height: AppSpacing.md),
        if (incident.timeline.isNotEmpty) ...[
          _SectionLabel('Temperature Timeline', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _TimelineChart(incident: incident, isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _TimelineList(incident: incident, isDark: isDark),
          const SizedBox(height: AppSpacing.md),
        ],
        if (incident.deviceStats.isNotEmpty) ...[
          _SectionLabel('Storage Diagnostics', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          ...incident.deviceStats.map(
            (s) => _DeviceStatRow(stat: s, isDark: isDark),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _SectionLabel('System Diagnostics', isDark: isDark),
        const SizedBox(height: AppSpacing.sm),
        if (incident.diagnosticEvents.isEmpty)
          _InfoNote(
            text: 'No platform diagnostic events were found for this '
                'session (the diagnostic utility may be unavailable, or '
                'the window had no relevant entries).',
            isDark: isDark,
          )
        else
          ...incident.diagnosticEvents.map(
            (e) => _DiagnosticEventRow(event: e, isDark: isDark),
          ),
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

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.bg1 : AppColors.lightCard;
    final borderColor = isDark ? AppColors.border : AppColors.lightBorder;
    final textColor = isDark ? AppColors.textPrimary : AppColors.lightText;
    final secondary = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

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
          Text(
            incident.summary,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _StatBlock(
                label: 'Correlation',
                value: incident.correlationLevel.name.toUpperCase(),
                color: _correlationColor(),
              ),
              if (primary?.lastCelsius != null)
                _StatBlock(
                  label: 'Last temperature',
                  value: '${primary!.lastCelsius!.round()}°C',
                  color: textColor,
                ),
              if (primary?.maxCelsius != null)
                _StatBlock(
                  label: 'Maximum temperature',
                  value: '${primary!.maxCelsius!.round()}°C',
                  color: textColor,
                ),
              if (primary != null && primary!.criticalDuration > Duration.zero)
                _StatBlock(
                  label: 'Critical duration',
                  value: '${primary!.criticalDuration.inSeconds}s',
                  color: textColor,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Shutdown: ${_fmt(incident.estimatedShutdownAt)}   '
            'Startup: ${_fmt(incident.startupAt)}',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return 'unknown';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
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

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.incident, required this.isDark});
  final ShutdownIncident incident;
  final bool isDark;

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
    // Keep the last point/marker off the plot's right edge so it doesn't
    // clip against the card border - same treatment as the device details
    // temperature chart.
    final maxX = dataMaxX == 0
        ? 1.0
        : dataMaxX + (dataMaxX * 0.05).clamp(8.0, 60.0);
    final values = samples.map((s) => s.celsius).toList();
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final minY = (dataMin - 8).clamp(0, double.infinity).toDouble();
    final maxY = dataMax + 8;

    final shutdownIndex = samples.indexWhere((s) => s.label == 'Shutdown');

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      height: 240,
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFFE2E8F0),
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
                  final t = start.add(Duration(seconds: value.round()));
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
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: AppColors.warning,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.warning.withValues(alpha: 0.08),
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(
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
        ),
      ),
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.incident, required this.isDark});
  final ShutdownIncident incident;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: incident.timeline
          .where((s) => s.label != 'Normal')
          .map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${s.timestamp.hour.toString().padLeft(2, '0')}:'
                      '${s.timestamp.minute.toString().padLeft(2, '0')}:'
                      '${s.timestamp.second.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    s.label ?? '',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${s.celsius.round()}°C',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
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

class _DiagnosticEventRow extends StatelessWidget {
  const _DiagnosticEventRow({required this.event, required this.isDark});
  final dynamic event;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.summary as String,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.lightText,
                  ),
                ),
                Text(
                  '${event.source} · ${event.category}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}
