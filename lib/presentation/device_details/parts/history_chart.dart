part of '../device_details_screen.dart';

class _HistoryChart extends StatefulWidget {
  const _HistoryChart({
    required this.samples,
    required this.thresholds,
    required this.unit,
    required this.isDark,
    required this.window,
    required this.windowLabel,
    required this.stats,
    this.currentCelsius,
  });

  final List<HistoryPoint> samples;
  final TemperatureThresholds thresholds;
  final TemperatureUnit unit;
  final bool isDark;
  final Duration window;
  final String windowLabel;
  final HistoryStats stats;
  final double? currentCelsius;

  @override
  State<_HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<_HistoryChart> {
  bool _showGrid = true;

  @override
  Widget build(BuildContext context) {
    final sortedSamples = downsampleHistory(
      List<HistoryPoint>.from(widget.samples)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
    ).toList();

    final now = DateTime.now();
    if (widget.currentCelsius != null) {
      if (sortedSamples.isEmpty ||
          now.difference(sortedSamples.last.timestamp).inSeconds >= 2) {
        sortedSamples.add(HistoryPoint(now, widget.currentCelsius!));
      }
    }

    if (sortedSamples.isEmpty) {
      return const SizedBox(height: 220);
    }

    final startTime = sortedSamples.first.timestamp;
    final endTime = sortedSamples.last.timestamp;
    final totalSpanSeconds = endTime.difference(startTime).inSeconds.toDouble();
    final effectiveMaxX = totalSpanSeconds < 30 ? 30.0 : totalSpanSeconds;

    final rightPadding = (effectiveMaxX * 0.05).clamp(8.0, 60.0);
    final plotMaxX = effectiveMaxX + rightPadding;

    final spots = <FlSpot>[];
    for (var i = 0; i < sortedSamples.length; i++) {
      final point = sortedSamples[i];
      final x = point.timestamp.difference(startTime).inSeconds.toDouble();
      final y = TemperatureUtils.convert(point.celsius, widget.unit);
      spots.add(FlSpot(x, y));
    }

    final validSpots = spots
        .where((s) => s != FlSpot.nullSpot && !s.y.isNaN)
        .toList();
    if (validSpots.isEmpty) {
      return const SizedBox(height: 220);
    }

    final allTemps = validSpots.map((s) => s.y).toList();
    final dataMin = allTemps.reduce(min);
    final dataMax = allTemps.reduce(max);
    final span = dataMax - dataMin;

    final double yInterval;
    if (span <= 6) {
      yInterval = 2.0;
    } else if (span <= 15) {
      yInterval = 5.0;
    } else if (span <= 35) {
      yInterval = 5.0;
    } else if (span <= 70) {
      yInterval = 10.0;
    } else {
      yInterval = 20.0;
    }

    final paddedMin = dataMin - (yInterval * 0.4);
    final paddedMax = dataMax + (yInterval * 0.4);
    final minY = (paddedMin / yInterval).floor() * yInterval;
    final maxY = (paddedMax / yInterval).ceil() * yInterval;

    final warn = TemperatureUtils.convert(
      widget.thresholds.warningCelsius,
      widget.unit,
    );
    final crit = TemperatureUtils.convert(
      widget.thresholds.criticalCelsius,
      widget.unit,
    );

    final double latestConverted = validSpots.last.y;
    final Color lineColor;
    if (latestConverted >= crit) {
      lineColor = AppColors.critical;
    } else if (latestConverted >= warn) {
      lineColor = AppColors.warning;
    } else if (latestConverted >=
        warn - (widget.unit == TemperatureUnit.celsius ? 10 : 18)) {
      lineColor = const Color(0xFFF5A623);
    } else {
      lineColor = AppColors.accent;
    }

    final xInterval = (effectiveMaxX / 4).clamp(15.0, double.infinity);

    final firstVal = validSpots.first.y;
    final lastVal = validSpots.last.y;
    final tempDelta = lastVal - firstVal;
    final String trendText;
    final IconData trendIcon;
    final Color trendColor;

    if (tempDelta.abs() < 0.6) {
      trendText = 'Steady (±0${TemperatureUtils.unitSuffix(widget.unit)})';
      trendIcon = Icons.trending_flat_rounded;
      trendColor = widget.isDark
          ? AppColors.textMuted
          : AppColors.lightTextSecondary;
    } else if (tempDelta > 0) {
      trendText =
          '+${tempDelta.toStringAsFixed(1)}${TemperatureUtils.unitSuffix(widget.unit)} (Warming)';
      trendIcon = Icons.trending_up_rounded;
      trendColor = tempDelta >= 3.0 ? AppColors.warning : AppColors.accent;
    } else {
      trendText =
          '${tempDelta.toStringAsFixed(1)}${TemperatureUtils.unitSuffix(widget.unit)} (Cooling)';
      trendIcon = Icons.trending_down_rounded;
      trendColor = AppColors.normal;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _MetricPill(
              icon: Icons.thermostat_rounded,
              label: 'Current',
              value: TemperatureUtils.format(
                validSpots.last.y,
                widget.unit,
                decimals: 0,
              ),
              color: lineColor,
              isDark: widget.isDark,
            ),
            _MetricPill(
              icon: Icons.arrow_downward_rounded,
              label: 'Min',
              value:
                  '${dataMin.round()}${TemperatureUtils.unitSuffix(widget.unit)}',
              color: AppColors.normal,
              isDark: widget.isDark,
            ),
            _MetricPill(
              icon: Icons.tune_rounded,
              label: 'Avg',
              value:
                  '${((dataMin + dataMax) / 2).round()}${TemperatureUtils.unitSuffix(widget.unit)}',
              color: widget.isDark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
              isDark: widget.isDark,
            ),
            _MetricPill(
              icon: Icons.arrow_upward_rounded,
              label: 'Peak',
              value:
                  '${dataMax.round()}${TemperatureUtils.unitSuffix(widget.unit)}',
              color: dataMax >= warn ? AppColors.warning : AppColors.accent,
              isDark: widget.isDark,
            ),
            _MetricPill(
              icon: trendIcon,
              label: 'Trend',
              value: trendText,
              color: trendColor,
              isDark: widget.isDark,
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),

        SizedBox(
          height: 230,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: plotMaxX,
              minY: minY,
              maxY: maxY,
              clipData: const FlClipData.vertical(),
              gridData: FlGridData(
                show: _showGrid,
                drawVerticalLine: true,
                drawHorizontalLine: true,
                horizontalInterval: yInterval,
                verticalInterval: xInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFCBD5E1),
                  strokeWidth: 1.0,
                  dashArray: [5, 4],
                ),
                getDrawingVerticalLine: (_) => FlLine(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE2E8F0),
                  strokeWidth: 1.0,
                  dashArray: [4, 4],
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
                    reservedSize: 28,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < -0.05 || value > effectiveMaxX + 0.05) {
                        return const SizedBox.shrink();
                      }

                      final pointTime = startTime.add(
                        Duration(seconds: value.round()),
                      );
                      final ago = endTime.difference(pointTime);

                      String label;
                      if (value >= effectiveMaxX - (xInterval * 0.35) ||
                          ago.inSeconds < 30) {
                        label = 'Now';
                      } else {
                        if (widget.window <= const Duration(minutes: 10)) {
                          final s = ago.inSeconds;
                          label = s < 60
                              ? '${s}s ago'
                              : '${ago.inMinutes}m ago';
                        } else if (widget.window <= const Duration(hours: 1)) {
                          label = '${ago.inMinutes}m ago';
                        } else if (widget.window <= const Duration(hours: 24)) {
                          final h = ago.inHours;
                          final m = ago.inMinutes % 60;
                          label = m == 0 || h >= 6
                              ? '${h}h ago'
                              : '${h}h ${m}m ago';
                        } else {
                          final d = ago.inDays;
                          label = d == 0 ? '${ago.inHours}h ago' : '${d}d ago';
                        }
                      }

                      return SideTitleWidget(
                        meta: meta,
                        space: 8,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(
                          meta,
                          distanceFromEdge: 4,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: widget.isDark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < minY - 0.05 || value > maxY + 0.05) {
                        return const SizedBox.shrink();
                      }

                      final stepNum = ((value - minY) / yInterval).round();
                      final expectedValue = minY + (stepNum * yInterval);
                      if ((value - expectedValue).abs() > 0.05) {
                        return const SizedBox.shrink();
                      }

                      return SideTitleWidget(
                        meta: meta,
                        space: 8,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(
                          meta,
                          distanceFromEdge: 2,
                        ),
                        child: Text(
                          '${expectedValue.round()}${TemperatureUtils.unitSuffix(widget.unit)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFF94A3B8),
                    width: 1.2,
                  ),
                  bottom: BorderSide(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFF94A3B8),
                    width: 1.2,
                  ),
                  top: BorderSide.none,
                  right: BorderSide.none,
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (warn >= minY && warn <= maxY)
                    HorizontalLine(
                      y: warn,
                      color: AppColors.warning.withValues(alpha: 0.75),
                      strokeWidth: 1.2,
                      dashArray: [5, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 6, bottom: 2),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                        labelResolver: (_) =>
                            'Warn (${warn.round()}${TemperatureUtils.unitSuffix(widget.unit)})',
                      ),
                    ),
                  if (crit >= minY && crit <= maxY)
                    HorizontalLine(
                      y: crit,
                      color: AppColors.critical.withValues(alpha: 0.75),
                      strokeWidth: 1.2,
                      dashArray: [5, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 6, bottom: 2),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.critical,
                          fontWeight: FontWeight.w700,
                        ),
                        labelResolver: (_) =>
                            'Crit (${crit.round()}${TemperatureUtils.unitSuffix(widget.unit)})',
                      ),
                    ),
                ],
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  preventCurveOverShooting: true,
                  color: lineColor,
                  barWidth: 2.8,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, barData) {
                      return spot == validSpots.last;
                    },
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4.5,
                        color: lineColor,
                        strokeWidth: 2.5,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(
                          alpha: widget.isDark ? 0.28 : 0.20,
                        ),
                        lineColor.withValues(
                          alpha: widget.isDark ? 0.08 : 0.04,
                        ),
                        lineColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: lineColor.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                        dashArray: [4, 4],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 5.5,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: lineColor,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      widget.isDark ? const Color(0xFF1E1E26) : Colors.white,
                  tooltipBorderRadius: BorderRadius.circular(AppRadius.md),
                  tooltipBorder: BorderSide(
                    color: widget.isDark
                        ? AppColors.border
                        : AppColors.lightBorder,
                    width: 1.2,
                  ),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                    if (s == FlSpot.nullSpot || s.y.isNaN) return null;
                    final spotTime = startTime.add(
                      Duration(seconds: s.x.round()),
                    );
                    final ago = endTime.difference(spotTime);

                    final hour = spotTime.hour % 12 == 0
                        ? 12
                        : spotTime.hour % 12;
                    final minute = spotTime.minute.toString().padLeft(2, '0');
                    final second = spotTime.second.toString().padLeft(2, '0');
                    final ampm = spotTime.hour >= 12 ? 'PM' : 'AM';
                    final exactTime = '$hour:$minute:$second $ampm';

                    final agoStr = ago.inSeconds < 15
                        ? 'Just now'
                        : (ago.inMinutes < 60
                              ? '${ago.inMinutes}m ago'
                              : '${ago.inHours}h ${ago.inMinutes % 60}m ago');

                    final tempColor = s.y >= crit
                        ? AppColors.critical
                        : (s.y >= warn ? AppColors.warning : AppColors.accent);

                    return LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}${TemperatureUtils.unitSuffix(widget.unit)}\n',
                      TextStyle(
                        color: tempColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                      children: [
                        TextSpan(
                          text: '$exactTime · $agoStr',
                          style: TextStyle(
                            color: widget.isDark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            duration: AppDurations.medium,
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final content = <Widget>[
              _ThresholdLegend(
                label:
                    'Warning: ${warn.round()}${TemperatureUtils.unitSuffix(widget.unit)}',
                color: AppColors.warning,
                isDark: widget.isDark,
              ),
              const SizedBox(width: AppSpacing.md),
              _ThresholdLegend(
                label:
                    'Critical: ${crit.round()}${TemperatureUtils.unitSuffix(widget.unit)}',
                color: AppColors.critical,
                isDark: widget.isDark,
              ),
              const SizedBox(width: AppSpacing.md),
              _GridToggleChip(
                showGrid: _showGrid,
                isDark: widget.isDark,
                onToggle: () => setState(() => _showGrid = !_showGrid),
              ),
              if (!isNarrow) const Spacer(),
              Text(
                '${sortedSamples.length} samples · ${widget.windowLabel}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark
                      ? AppColors.textMuted
                      : AppColors.lightTextSecondary,
                ),
              ),
            ];

            if (isNarrow) {
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: content
                    .where((w) => w is! SizedBox && w is! Spacer)
                    .toList(),
              );
            }

            return Row(children: content);
          },
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdLegend extends StatelessWidget {
  const _ThresholdLegend({
    required this.label,
    required this.color,
    required this.isDark,
  });

  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _GridToggleChip extends StatelessWidget {
  const _GridToggleChip({
    required this.showGrid,
    required this.isDark,
    required this.onToggle,
  });

  final bool showGrid;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF334155);
    final inactiveColor = isDark
        ? AppColors.textMuted
        : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: showGrid
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF1F5F9))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: showGrid
                  ? (isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFFCBD5E1))
                  : (isDark
                        ? AppColors.border.withValues(alpha: 0.5)
                        : AppColors.lightBorder),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                size: 13,
                color: showGrid ? activeColor : inactiveColor,
              ),
              const SizedBox(width: 4.5),
              Text(
                showGrid ? 'Grid on' : 'Grid off',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: showGrid ? FontWeight.w600 : FontWeight.w500,
                  color: showGrid ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
