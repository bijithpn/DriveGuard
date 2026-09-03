import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../components/animated_entrance.dart';
import '../components/device_presentation.dart';
import '../components/temperature_gauge.dart';
import '../theme/app_theme.dart';

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
}

String _formatBytesPerSecond(double bytesPerSecond) =>
    '${_formatBytes(bytesPerSecond.round())}/s';

const _historyWindows = <String, Duration>{
  '5 min': Duration(minutes: 5),
  '30 min': Duration(minutes: 30),
  '1 hour': Duration(hours: 1),
  '6 hours': Duration(hours: 6),
  '24 hours': Duration(hours: 24),
};

class DeviceDetailsScreen extends ConsumerStatefulWidget {
  const DeviceDetailsScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<DeviceDetailsScreen> createState() =>
      _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends ConsumerState<DeviceDetailsScreen>
    with SingleTickerProviderStateMixin {
  String _windowLabel = '1 hour';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final settings = ref.watch(settingsProvider);
    final device = devices
        .where((d) => d.id == widget.deviceId)
        .cast<StorageDevice?>()
        .firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (device == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
        appBar: AppBar(
          backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Device'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.device_unknown_rounded,
                size: 40,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'This device is no longer available.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final thresholds = settings.thresholdsFor(device.id);
    final presentation = DevicePresentation.of(
      device,
      thresholds,
      settings.temperatureUnit,
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Row(
        children: [
          SizedBox(
            width: 300,
            child: _DeviceInfoPanel(
              device: device,
              presentation: presentation,
              settings: settings,
              isDark: isDark,
            ),
          ),

          Expanded(
            child: Column(
              children: [
                _NativeTabBar(controller: _tabController, isDark: isDark),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _TemperatureTab(
                        device: device,
                        windowLabel: _windowLabel,
                        onWindowChanged: (w) =>
                            setState(() => _windowLabel = w),
                        thresholds: thresholds,
                        unit: settings.temperatureUnit,
                        isDark: isDark,
                      ),
                      _HealthTab(device: device, isDark: isDark),
                      _StorageTab(device: device, isDark: isDark),
                      _DiagnosticsTab(
                        device: device,
                        settings: settings,
                        isDark: isDark,
                      ),
                    ],
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

class _DeviceInfoPanel extends StatelessWidget {
  const _DeviceInfoPanel({
    required this.device,
    required this.presentation,
    required this.settings,
    required this.isDark,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
  final dynamic settings;
  final bool isDark;

  String _typeLabel() {
    switch (device.type) {
      case StorageDeviceType.nvme:
        return 'NVMe SSD';
      case StorageDeviceType.ssd:
        return 'SATA SSD';
      case StorageDeviceType.hdd:
        return 'Hard Drive';
      case StorageDeviceType.unknown:
        return 'Storage Device';
    }
  }

  String _capacityText() {
    final bytes = device.capacityBytes;
    if (bytes == null) return 'Unknown capacity';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  String _healthLabel() {
    switch (device.health.status) {
      case DeviceHealthStatus.healthy:
        return 'Healthy';
      case DeviceHealthStatus.warning:
        return 'Warning';
      case DeviceHealthStatus.critical:
        return 'Critical';
      case DeviceHealthStatus.unknown:
        return 'Unknown';
      case DeviceHealthStatus.unavailable:
        return 'N/A';
    }
  }

  String _lastUpdatedText() {
    final t = device.lastUpdated;
    if (t == null) return 'Never';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(presentation.severity, context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  presentation.valueText,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: style.color,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: style.color.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 11, color: style.color),
                      const SizedBox(width: 5),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: style.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Center(
                  child: TemperatureGauge(
                    valueText: presentation.valueText,
                    fraction: presentation.fraction,
                    severity: presentation.severity,
                    size: 148,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Type', value: _typeLabel(), isDark: isDark),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Capacity',
                  value: _capacityText(),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Health',
                  value: _healthLabel(),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Last Updated',
                  value: _lastUpdatedText(),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimary : AppColors.lightText,
          ),
        ),
      ],
    );
  }
}

class _NativeTabBar extends StatelessWidget {
  const _NativeTabBar({required this.controller, required this.isDark});
  final TabController controller;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? AppColors.bg0 : AppColors.lightBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: isDark ? AppColors.bg2 : AppColors.lightCard,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isDark ? AppColors.border : AppColors.lightBorder,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: isDark ? AppColors.textPrimary : AppColors.lightText,
        unselectedLabelColor: isDark
            ? AppColors.textMuted
            : AppColors.lightTextSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        splashBorderRadius: BorderRadius.circular(AppRadius.sm),
        tabs: const [
          Tab(text: 'Temperature'),
          Tab(text: 'Health'),
          Tab(text: 'Storage'),
          Tab(text: 'Diagnostics'),
        ],
      ),
    );
  }
}

class _TemperatureTab extends ConsumerWidget {
  const _TemperatureTab({
    required this.device,
    required this.windowLabel,
    required this.onWindowChanged,
    required this.thresholds,
    required this.unit,
    required this.isDark,
  });

  final StorageDevice device;
  final String windowLabel;
  final ValueChanged<String> onWindowChanged;
  final dynamic thresholds;
  final TemperatureUnit unit;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = _historyWindows[windowLabel]!;
    final historyStore = ref.watch(historyStoreProvider);
    final samples = historyStore.pointsFor(device.id, window);
    final stats = historyStore.statsFor(device.id, window);
    final presentation = DevicePresentation.of(
      device,
      ref.watch(settingsProvider).thresholdsFor(device.id),
      unit,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _StatCard(
                      label: 'Current',
                      value: device.primaryTemperature != null
                          ? TemperatureUtils.format(
                              device.primaryTemperature!.celsius,
                              unit,
                            )
                          : 'N/A',
                      icon: Icons.thermostat_rounded,
                      isDark: isDark,
                      color:
                          presentation.severity ==
                              TemperatureSeverity.unavailable
                          ? AppColors.textMuted
                          : SeverityStyle.of(
                              presentation.severity,
                              context,
                            ).color,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Min',
                            value: stats.min != null
                                ? TemperatureUtils.format(stats.min!, unit)
                                : '--',
                            icon: Icons.arrow_downward_rounded,
                            isDark: isDark,
                            color: AppColors.normal,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _StatCard(
                            label: 'Max',
                            value: stats.max != null
                                ? TemperatureUtils.format(stats.max!, unit)
                                : '--',
                            icon: Icons.arrow_upward_rounded,
                            isDark: isDark,
                            color: AppColors.warning,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _StatCard(
                      label: 'Average',
                      value: stats.average != null
                          ? TemperatureUtils.format(stats.average!, unit)
                          : '--',
                      icon: Icons.show_chart_rounded,
                      isDark: isDark,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          if (device.primaryTemperature != null)
            _SourceRow(
              source: device.primaryTemperature!.source.toString(),
              timestamp: device.lastUpdated,
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),

          _SectionLabel(title: 'Temperature History', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          Wrap(
            spacing: AppSpacing.xs,
            children: _historyWindows.keys.map((label) {
              final selected = label == windowLabel;
              return GestureDetector(
                onTap: () => onWindowChanged(label),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent
                        : (isDark ? AppColors.bg2 : AppColors.lightCard),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected
                          ? AppColors.accent
                          : (isDark ? AppColors.border : AppColors.lightBorder),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? Colors.white
                          : (isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),

          Container(
            height: 200,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg1 : AppColors.lightCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.border : AppColors.lightBorder,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: samples.length < 2
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.show_chart_rounded,
                          size: 32,
                          color: isDark
                              ? AppColors.textMuted
                              : AppColors.lightTextSecondary,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Not enough history yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : _HistoryChart(
                    samples: samples,
                    thresholds: thresholds,
                    unit: unit,
                    isDark: isDark,
                  ),
          ),

          const SizedBox(height: AppSpacing.lg),

          _SectionLabel(title: 'Sensors', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _SensorsList(deviceId: device.id, unit: unit, isDark: isDark),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: compact
          ? Row(
              children: [
                Icon(icon, size: 13, color: effectiveColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 15, color: effectiveColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.textMuted
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: effectiveColor,
                          letterSpacing: -0.3,
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.timestamp,
    required this.isDark,
  });

  final String source;
  final DateTime? timestamp;
  final bool isDark;

  String _ago() {
    if (timestamp == null) return 'Never';
    final diff = DateTime.now().difference(timestamp!);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
        const SizedBox(width: 5),
        Text(
          'Source: $source',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Icon(
          Icons.schedule_rounded,
          size: 12,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          'Updated ${_ago()}',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textPrimary : AppColors.lightText,
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({
    required this.samples,
    required this.thresholds,
    required this.unit,
    required this.isDark,
  });

  final List<dynamic> samples;
  final dynamic thresholds;
  final TemperatureUnit unit;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final first = samples.first.timestamp as DateTime;
    final spots = samples
        .map<FlSpot>(
          (p) => FlSpot(
            (p.timestamp as DateTime).difference(first).inSeconds.toDouble(),
            TemperatureUtils.convert(p.celsius as double, unit),
          ),
        )
        .toList();

    final allTemps = spots.map((s) => s.y).toList();
    final minTemp = allTemps.reduce(min) - 4;
    final maxTemp = allTemps.reduce(max) + 4;

    final warn = TemperatureUtils.convert(
      thresholds.warningCelsius as double,
      unit,
    );
    final crit = TemperatureUtils.convert(
      thresholds.criticalCelsius as double,
      unit,
    );

    const lineColor = AppColors.accent;

    return LineChart(
      LineChartData(
        minY: minTemp,
        maxY: maxTemp,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}${TemperatureUtils.unitSuffix(unit)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.textMuted
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: warn,
              color: AppColors.warning.withValues(alpha: 0.6),
              strokeWidth: 1,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500,
                ),
                labelResolver: (_) => 'Warn',
              ),
            ),
            HorizontalLine(
              y: crit,
              color: AppColors.critical.withValues(alpha: 0.6),
              strokeWidth: 1,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.critical,
                  fontWeight: FontWeight.w500,
                ),
                labelResolver: (_) => 'Crit',
              ),
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: lineColor,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.15),
                  lineColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                isDark ? AppColors.bg3 : AppColors.lightCard,
            tooltipRoundedRadius: AppRadius.sm,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(1)}${TemperatureUtils.unitSuffix(unit)}',
                    const TextStyle(
                      color: lineColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      duration: AppDurations.medium,
    );
  }
}

class _SensorsList extends ConsumerStatefulWidget {
  const _SensorsList({
    required this.deviceId,
    required this.unit,
    required this.isDark,
  });

  final String deviceId;
  final TemperatureUnit unit;
  final bool isDark;

  @override
  ConsumerState<_SensorsList> createState() => _SensorsListState();
}

class _SensorsListState extends ConsumerState<_SensorsList> {
  Future<List<StorageSensor>>? _future;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant _SensorsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) _load();
  }

  void _load() {
    setState(() {
      _future = ref.read(storageMonitorProvider).getSensors(widget.deviceId);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StorageSensor>>(
      future: _future,
      builder: (context, snapshot) {
        final sensors = snapshot.data ?? const [];
        if (sensors.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: widget.isDark ? AppColors.bg1 : AppColors.lightCard,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: widget.isDark ? AppColors.border : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.thermostat_outlined,
                  size: 18,
                  color: widget.isDark
                      ? AppColors.textMuted
                      : AppColors.lightTextSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'No additional sensor detail available.',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: widget.isDark ? AppColors.bg1 : AppColors.lightCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: widget.isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Column(
            children: sensors.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              final isLast = index == sensors.length - 1;
              final tempText = s.reading != null
                  ? TemperatureUtils.format(s.reading!.celsius, widget.unit)
                  : '--';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          s.isPrimary
                              ? Icons.radio_button_checked_rounded
                              : Icons.thermostat_rounded,
                          size: 15,
                          color: s.isPrimary
                              ? AppColors.accent
                              : (widget.isDark
                                    ? AppColors.textMuted
                                    : AppColors.lightTextSecondary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? AppColors.textPrimary
                                  : AppColors.lightText,
                            ),
                          ),
                        ),
                        if (s.isPrimary)
                          Container(
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppRadius.sm - 2,
                              ),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Text(
                              'Primary',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          tempText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? AppColors.textPrimary
                                : AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: widget.isDark
                          ? AppColors.divider
                          : AppColors.lightBorder,
                    ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _HealthTab extends StatelessWidget {
  const _HealthTab({required this.device, required this.isDark});

  final StorageDevice device;
  final bool isDark;

  String _na(Object? v) => v?.toString() ?? 'Not available';

  Color _statusColor() {
    switch (device.health.status) {
      case DeviceHealthStatus.healthy:
        return AppColors.normal;
      case DeviceHealthStatus.warning:
        return AppColors.warning;
      case DeviceHealthStatus.critical:
        return AppColors.critical;
      case DeviceHealthStatus.unknown:
      case DeviceHealthStatus.unavailable:
        return AppColors.textMuted;
    }
  }

  String _healthDescription(DeviceHealthStatus status) {
    switch (status) {
      case DeviceHealthStatus.healthy:
        return 'Drive is operating normally';
      case DeviceHealthStatus.warning:
        return 'Drive may be showing early warning signs';
      case DeviceHealthStatus.critical:
        return 'Drive health is in a critical state';
      case DeviceHealthStatus.unknown:
        return 'Health status could not be determined';
      case DeviceHealthStatus.unavailable:
        return 'SMART health data is not available for this device';
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = device.health;
    final statusColor = _statusColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: statusColor.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    device.health.status == DeviceHealthStatus.healthy
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.health.status.name[0].toUpperCase() +
                            device.health.status.name.substring(1),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        _healthDescription(device.health.status),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'SMART & NVMe Data', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          _HealthGrid(
            entries: [
              _HealthEntry(
                label: 'SMART Status',
                value: health.smartPassed == null
                    ? 'Not available'
                    : (health.smartPassed! ? 'Passed' : 'Failed'),
                icon: Icons.verified_outlined,
                statusColor: health.smartPassed == true
                    ? AppColors.normal
                    : AppColors.critical,
                available: health.smartPassed != null,
              ),
              _HealthEntry(
                label: 'Percentage Used',
                value: health.percentageUsed != null
                    ? '${health.percentageUsed}%'
                    : '--',
                icon: Icons.pie_chart_outline_rounded,
                available: health.percentageUsed != null,
              ),
              _HealthEntry(
                label: 'Available Spare',
                value: health.availableSparePercent != null
                    ? '${health.availableSparePercent}%'
                    : '--',
                icon: Icons.disc_full_rounded,
                available: health.availableSparePercent != null,
              ),
              _HealthEntry(
                label: 'Spare Threshold',
                value: health.availableSpareThreshold != null
                    ? '${health.availableSpareThreshold}%'
                    : '--',
                icon: Icons.rule_rounded,
                available: health.availableSpareThreshold != null,
              ),
              _HealthEntry(
                label: 'Critical Warnings',
                value: _na(health.criticalWarning),
                icon: Icons.warning_amber_outlined,
                available: health.criticalWarning != null,
              ),
              _HealthEntry(
                label: 'Media / Data Errors',
                value: _na(health.mediaErrors),
                icon: Icons.error_outline_rounded,
                available: health.mediaErrors != null,
              ),
              _HealthEntry(
                label: 'Power Cycles',
                value: _na(health.powerCycles),
                icon: Icons.power_settings_new_rounded,
                available: health.powerCycles != null,
              ),
              _HealthEntry(
                label: 'Power-on Hours',
                value: health.powerOnHours != null
                    ? '${health.powerOnHours} h'
                    : '--',
                icon: Icons.timer_outlined,
                available: health.powerOnHours != null,
              ),
              _HealthEntry(
                label: 'Unsafe Shutdowns',
                value: _na(health.unsafeShutdowns),
                icon: Icons.power_off_rounded,
                available: health.unsafeShutdowns != null,
              ),
              _HealthEntry(
                label: 'Total Read',
                value: health.totalBytesRead != null
                    ? _formatBytes(health.totalBytesRead!)
                    : '--',
                icon: Icons.arrow_downward_rounded,
                available: health.totalBytesRead != null,
              ),
              _HealthEntry(
                label: 'Total Written',
                value: health.totalBytesWritten != null
                    ? _formatBytes(health.totalBytesWritten!)
                    : '--',
                icon: Icons.arrow_upward_rounded,
                available: health.totalBytesWritten != null,
              ),
            ],
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _HealthEntry {
  const _HealthEntry({
    required this.label,
    required this.value,
    required this.icon,
    this.statusColor,
    this.available = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? statusColor;
  final bool available;
}

class _HealthGrid extends StatelessWidget {
  const _HealthGrid({required this.entries, required this.isDark});

  final List<_HealthEntry> entries;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < entries.length; i++)
          EntranceFade(
            index: i,
            child: _HealthTile(entry: entries[i], isDark: isDark),
          ),
      ],
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.entry, required this.isDark});

  final _HealthEntry entry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = entry.available
        ? (entry.statusColor ??
              (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary))
        : AppColors.textMuted;
    return SizedBox(
      width: 188,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bg1 : AppColors.lightCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDark ? AppColors.border : AppColors.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: entry.icon,
                  color: color,
                  size: 24,
                  iconSize: 12,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Capacity/usage, mounted volumes, and real-time read/write activity
/// (STORAGE_MONITORING.md Phases 3/8). Reuses [_HealthGrid]/[_HealthEntry]
/// for the stat tiles rather than introducing a parallel widget - these are
/// generic "labeled stat" tiles, not health-specific.
class _StorageTab extends ConsumerWidget {
  const _StorageTab({required this.device, required this.isDark});

  final StorageDevice device;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = device.capacity;
    final StorageActivity? activity = ref.watch(activityProvider)[device.id];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: 'Capacity', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (capacity.isValid)
            _CapacityBar(capacity: capacity, isDark: isDark)
          else
            _UnavailableNote(
              text:
                  'Capacity information is not available for this device yet.',
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Activity', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (activity != null)
            _HealthGrid(
              entries: [
                _HealthEntry(
                  label: 'Read Speed',
                  value: activity.readBytesPerSecond != null
                      ? _formatBytesPerSecond(activity.readBytesPerSecond!)
                      : '--',
                  icon: Icons.arrow_downward_rounded,
                  available: activity.readBytesPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Write Speed',
                  value: activity.writeBytesPerSecond != null
                      ? _formatBytesPerSecond(activity.writeBytesPerSecond!)
                      : '--',
                  icon: Icons.arrow_upward_rounded,
                  available: activity.writeBytesPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Read IOPS',
                  value: activity.readOperationsPerSecond != null
                      ? activity.readOperationsPerSecond!.toStringAsFixed(0)
                      : '--',
                  icon: Icons.speed_rounded,
                  available: activity.readOperationsPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Write IOPS',
                  value: activity.writeOperationsPerSecond != null
                      ? activity.writeOperationsPerSecond!.toStringAsFixed(0)
                      : '--',
                  icon: Icons.speed_rounded,
                  available: activity.writeOperationsPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Utilization',
                  value: activity.utilizationPercent != null
                      ? '${activity.utilizationPercent!.toStringAsFixed(0)}%'
                      : '--',
                  icon: Icons.donut_large_rounded,
                  available: activity.utilizationPercent != null,
                ),
              ],
              isDark: isDark,
            )
          else
            _UnavailableNote(
              text:
                  'No activity samples yet. Real-time read/write activity '
                  'requires native platform support and appears once the '
                  'device has been active.',
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Volumes', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (device.volumes.isEmpty)
            _UnavailableNote(
              text:
                  'No mounted volumes were detected on this device, or '
                  'volume enumeration is not supported on this platform.',
              isDark: isDark,
            )
          else
            Column(
              children: [
                for (final volume in device.volumes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _VolumeRow(volume: volume, isDark: isDark),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.capacity, required this.isDark});

  final StorageCapacity capacity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fraction = ((capacity.usagePercent ?? 0) / 100).clamp(0.0, 1.0);
    final total = capacity.totalBytes;
    final used = capacity.usedBytes;
    final free = capacity.freeBytes;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                used != null && total != null
                    ? '${_formatBytes(used)} / ${_formatBytes(total)}'
                    : (total != null ? _formatBytes(total) : 'Unknown'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.lightText,
                ),
              ),
              if (capacity.usagePercent != null)
                Text(
                  '${capacity.usagePercent!.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: isDark
                  ? AppColors.bg2
                  : AppColors.lightSurfaceMuted,
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          if (free != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_formatBytes(free)} free',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.isDark});

  final StorageVolume volume;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final title = volume.volumeName?.trim().isNotEmpty == true
        ? volume.volumeName!
        : (volume.mountPoint ?? volume.id);
    final subtitleParts = <String>[
      if (volume.filesystem != null) volume.filesystem!,
      if (volume.mountPoint != null) volume.mountPoint!,
      if (volume.totalBytes != null) _formatBytes(volume.totalBytes!),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: volume.isBootVolume
                ? Icons.laptop_mac_rounded
                : Icons.storage_rounded,
            color: isDark ? AppColors.textSecondary : AppColors.lightText,
            size: 32,
            iconSize: 16,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (volume.isBootVolume) _VolumeBadge(text: 'Boot', isDark: isDark),
          if (volume.isReadOnly) ...[
            const SizedBox(width: AppSpacing.xs),
            _VolumeBadge(text: 'Read-only', isDark: isDark),
          ],
        ],
      ),
    );
  }
}

class _VolumeBadge extends StatelessWidget {
  const _VolumeBadge({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppColors.textSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({
    required this.device,
    required this.settings,
    required this.isDark,
  });

  final StorageDevice device;
  final dynamic settings;
  final bool isDark;

  String _ago(DateTime? t) {
    if (t == null) return 'Never';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final statusRows = <_DiagRow>[
      _DiagRow(
        label: 'Polling Interval',
        value: '${settings.pollingInterval.inSeconds}s',
        icon: Icons.schedule_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Sensor Source',
        value: device.primaryTemperature?.source.toString() ?? 'Not available',
        icon: Icons.sensors_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Sensor Availability',
        value: device.sensorAvailability.name,
        icon: Icons.thermostat_rounded,
        isDark: isDark,
        statusColor: device.sensorAvailability == SensorAvailability.available
            ? AppColors.normal
            : device.sensorAvailability == SensorAvailability.permissionDenied
            ? AppColors.warning
            : AppColors.textMuted,
      ),
      _DiagRow(
        label: 'Monitoring Status',
        value: device.monitoringStatus.name,
        icon: Icons.monitor_heart_outlined,
        isDark: isDark,
        statusColor: device.monitoringStatus == MonitoringStatus.active
            ? AppColors.normal
            : device.monitoringStatus == MonitoringStatus.error
            ? AppColors.critical
            : AppColors.warning,
      ),
      _DiagRow(
        label: 'Last Successful Reading',
        value: _ago(device.lastUpdated),
        icon: Icons.check_circle_outline_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Last Error',
        value: device.lastError ?? 'None',
        icon: Icons.error_outline_rounded,
        isDark: isDark,
        statusColor: device.lastError != null
            ? AppColors.warning
            : AppColors.normal,
      ),
      _DiagRow(
        label: 'Permission Status',
        value: device.sensorAvailability == SensorAvailability.permissionDenied
            ? 'Additional permissions required'
            : 'OK',
        icon: Icons.security_rounded,
        isDark: isDark,
        statusColor:
            device.sensorAvailability == SensorAvailability.permissionDenied
            ? AppColors.warning
            : AppColors.normal,
      ),
    ];

    final identifierRows = <_DiagRow>[
      _DiagRow(
        label: 'Device ID',
        value: device.id,
        icon: Icons.fingerprint_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Serial Number',
        value: device.serialNumber ?? '--',
        icon: Icons.numbers_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Firmware',
        value: '--',
        icon: Icons.system_update_alt_rounded,
        isDark: isDark,
      ),
      _DiagRow(
        label: 'Interface',
        value: device.interfaceType.name.toUpperCase(),
        icon: Icons.cable_rounded,
        isDark: isDark,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < statusRows.length; i++)
            EntranceFade(index: i, child: statusRows[i]),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Capabilities', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          _CapabilitiesGrid(
            capabilities: DeviceCapabilities.derive(device),
            startIndex: statusRows.length,
            isDark: isDark,
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Device Identifiers', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          for (var i = 0; i < identifierRows.length; i++)
            EntranceFade(
              index: statusRows.length + i,
              child: identifierRows[i],
            ),

          if (device.sensorAvailability ==
              SensorAvailability.permissionDenied) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.warning,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Temperature Unavailable',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          device.lastError ??
                              'This device requires additional permissions to '
                                  'read temperature data. Check your system settings '
                                  'or run the application with elevated privileges.',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    this.statusColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final badgeColor =
        statusColor ??
        (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: badgeColor, size: 26, iconSize: 13),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  statusColor ??
                  (isDark ? AppColors.textPrimary : AppColors.lightText),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilitiesGrid extends StatelessWidget {
  const _CapabilitiesGrid({
    required this.capabilities,
    required this.startIndex,
    required this.isDark,
  });

  final DeviceCapabilities capabilities;
  final int startIndex;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final entries = capabilities.entries;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (var i = 0; i < entries.length; i++)
          EntranceFade(
            index: startIndex + i,
            child: _CapabilityChip(
              label: entries[i].$1,
              available: entries[i].$2,
            ),
          ),
      ],
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label, required this.available});

  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = available ? AppColors.normal : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: available
            ? AppColors.normal.withValues(alpha: isDark ? 0.1 : 0.07)
            : (isDark ? AppColors.bg1 : AppColors.lightCard),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: available
              ? AppColors.normal.withValues(alpha: 0.25)
              : (isDark ? AppColors.border : AppColors.lightBorder),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available
                ? Icons.check_circle_outline_rounded
                : Icons.remove_circle_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: available
                  ? color
                  : (isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
