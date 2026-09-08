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

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _HeaderCard(incident: incident, primary: primary, isDark: isDark),
        const SizedBox(height: AppSpacing.md),
        if (incident.timeline.isNotEmpty) ...[
          _SectionLabel('Temperature Timeline', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _TimelineChart(incident: incident, isDark: isDark),
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
        _SectionLabel('System & Application Diagnostics', isDark: isDark),
        const SizedBox(height: AppSpacing.sm),
        if (incident.diagnosticEvents.isEmpty)
          _InfoNote(
            text:
                'No platform diagnostic events or application errors '
                'were found for this session (the diagnostic utility may '
                'be unavailable, or the window had no relevant entries).',
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
