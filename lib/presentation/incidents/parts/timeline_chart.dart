part of '../incident_report_screen.dart';

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(
        icon,
        size: 18,
        color: enabled ? AppColors.textSecondary : AppColors.textMuted,
      ),
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
    final effectiveMax = dataMax < _critThreshold
        ? _critThreshold + 4
        : dataMax;
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
                          labelResolver: (_) =>
                              'WARN ${_warnThreshold.round()}°',
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
                          labelResolver: (_) =>
                              'CRIT ${_critThreshold.round()}°',
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
                        final match = eventSamples
                            .cast<TimelineSample?>()
                            .firstWhere((s) {
                              final x = s!.timestamp
                                  .difference(start)
                                  .inSeconds
                                  .toDouble();
                              return (spot.x - x).abs() < 0.5;
                            }, orElse: () => null);
                        final color = _spotColor(match?.label);
                        return FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 1.5,
                          strokeColor: isDark
                              ? AppColors.bg1
                              : AppColors.lightCard,
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
              const _LegendItem(
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
                const _LegendItem(
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
                    border: Border.all(color: color.withValues(alpha: 0.28)),
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
