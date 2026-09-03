import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/enums/storage_enums.dart';
import '../components/animated_entrance.dart';
import '../components/device_presentation.dart';
import '../components/temperature_gauge.dart';
import '../theme/app_theme.dart';

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
  ConsumerState<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends ConsumerState<DeviceDetailsScreen>
    with SingleTickerProviderStateMixin {
  String _windowLabel = '1 hour';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    final device =
        devices.where((d) => d.id == widget.deviceId).cast<StorageDevice?>().firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (device == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
        appBar: _buildAppBar(context, 'Device', isDark),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.device_unknown_rounded,
                  size: 48, color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary),
              const SizedBox(height: AppSpacing.md),
              Text('This device is no longer available.',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    final thresholds = settings.thresholdsFor(device.id);
    final presentation = DevicePresentation.of(device, thresholds, settings.temperatureUnit);

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Column(
        children: [
          // Hero header
          _DeviceHero(
            device: device,
            presentation: presentation,
            isDark: isDark,
          ),
          // Tab bar
          _PremiumTabBar(controller: _tabController, isDark: isDark),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Temperature tab
                _TemperatureTab(
                  device: device,
                  windowLabel: _windowLabel,
                  onWindowChanged: (w) => setState(() => _windowLabel = w),
                  thresholds: thresholds,
                  unit: settings.temperatureUnit,
                  isDark: isDark,
                ),
                // Health tab
                _HealthTab(device: device, isDark: isDark),
                // Diagnostics tab
                _DiagnosticsTab(device: device, settings: settings, isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String title, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded,
            color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(title),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Section
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({
    required this.device,
    required this.presentation,
    required this.isDark,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
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

  IconData _typeIcon() {
    switch (device.type) {
      case StorageDeviceType.nvme:
        return Icons.memory_rounded;
      case StorageDeviceType.ssd:
        return Icons.storage_rounded;
      case StorageDeviceType.hdd:
        return Icons.album_rounded;
      case StorageDeviceType.unknown:
        return Icons.device_unknown_rounded;
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

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(presentation.severity, context);

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.bg2,
                  AppColors.bg0,
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFEDE8FF),
                  AppColors.lightBg,
                ],
              ),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back button
              _BackButton(isDark: isDark),
              const SizedBox(width: AppSpacing.md),
              // Device icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: style.color.withValues(alpha: 0.25)),
                ),
                child: Icon(_typeIcon(), color: style.color, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: isDark ? AppColors.textPrimary : AppColors.lightText,
                            fontSize: 20,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _typeLabel(),
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (device.capacityBytes != null) ...[
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                            ),
                          ),
                          Text(
                            _capacityText(),
                            style: TextStyle(
                              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Temperature
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    presentation.valueText,
                    style: TextStyle(
                      color: style.color,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(style.icon, size: 12, color: style.color),
                      const SizedBox(width: 4),
                      Text(
                        style.label,
                        style: TextStyle(
                          color: style.color.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg2 : const Color(0xFFEDE8FF),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Bar
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumTabBar extends StatelessWidget {
  const _PremiumTabBar({required this.controller, required this.isDark});
  final TabController controller;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? AppColors.bg0 : AppColors.lightBg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: isDark ? AppColors.bg2 : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: isDark ? AppColors.textPrimary : AppColors.lightText,
        unselectedLabelColor: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        splashBorderRadius: BorderRadius.circular(AppRadius.sm),
        tabs: const [
          Tab(text: 'Temperature'),
          Tab(text: 'Health'),
          Tab(text: 'Diagnostics'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Temperature Tab
// ─────────────────────────────────────────────────────────────────────────────

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
        device, ref.watch(settingsProvider).thresholdsFor(device.id), unit);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gauge + stats row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TemperatureGauge(
                valueText: presentation.valueText,
                fraction: presentation.fraction,
                severity: presentation.severity,
                size: 160,
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  children: [
                    _StatCard(
                      label: 'Current',
                      value: device.primaryTemperature != null
                          ? TemperatureUtils.format(device.primaryTemperature!.celsius, unit)
                          : 'Unavailable',
                      icon: Icons.thermostat_rounded,
                      isDark: isDark,
                      color: presentation.severity == TemperatureSeverity.unavailable
                          ? AppColors.textMuted
                          : SeverityStyle.of(presentation.severity, context).color,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Min',
                            value: stats.min != null
                                ? TemperatureUtils.format(stats.min!, unit)
                                : '—',
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
                                : '—',
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
                          : '—',
                      icon: Icons.analytics_outlined,
                      isDark: isDark,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Source info
          if (device.primaryTemperature != null)
            _SourceChip(
              source: device.primaryTemperature!.source.toString(),
              timestamp: device.lastUpdated,
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),

          // Chart
          _SectionTitle(title: 'Temperature History', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          // Time window selector
          Wrap(
            spacing: AppSpacing.sm,
            children: _historyWindows.keys.map((label) {
              final selected = label == windowLabel;
              return GestureDetector(
                onTap: () => onWindowChanged(label),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.purpleMid
                        : (isDark ? AppColors.bg2 : Colors.white),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected
                          ? AppColors.purpleMid
                          : (isDark ? AppColors.border : AppColors.lightBorder),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),

          // Chart container
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg1 : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.border : AppColors.lightBorder,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: samples.length < 2
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.show_chart_rounded,
                            size: 36,
                            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Not enough history yet',
                          style: TextStyle(
                            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : _PremiumHistoryChart(
                    samples: samples,
                    thresholds: thresholds,
                    unit: unit,
                    isDark: isDark,
                  ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Sensors
          _SectionTitle(title: 'Sensors', isDark: isDark),
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
    final effectiveColor = color ?? (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
      ),
      child: compact
          ? Row(
              children: [
                Icon(icon, size: 14, color: effectiveColor),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary)),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: effectiveColor)),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: effectiveColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? AppColors.textMuted : AppColors.lightTextSecondary)),
                      Text(value,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: effectiveColor,
                              letterSpacing: -0.5)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, required this.timestamp, required this.isDark});
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.purpleMid.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.purpleMid.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.purpleLight),
          const SizedBox(width: 6),
          Text('Source: $source', style: const TextStyle(fontSize: 12, color: AppColors.purpleLight)),
          const SizedBox(width: 12),
          const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text('Updated ${_ago()}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.textPrimary : AppColors.lightText,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _PremiumHistoryChart extends StatelessWidget {
  const _PremiumHistoryChart({
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
        .map<FlSpot>((p) => FlSpot(
              (p.timestamp as DateTime).difference(first).inSeconds.toDouble(),
              TemperatureUtils.convert(p.celsius as double, unit),
            ))
        .toList();

    final allTemps = spots.map((s) => s.y).toList();
    final minTemp = allTemps.reduce(min) - 5;
    final maxTemp = allTemps.reduce(max) + 5;

    final warn = TemperatureUtils.convert(thresholds.warningCelsius as double, unit);
    final crit = TemperatureUtils.convert(thresholds.criticalCelsius as double, unit);

    return LineChart(
      LineChartData(
        minY: minTemp,
        maxY: maxTemp,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}${TemperatureUtils.unitSuffix(unit)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: warn,
            color: AppColors.warning.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [8, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600),
              labelResolver: (_) => 'Warning',
            ),
          ),
          HorizontalLine(
            y: crit,
            color: AppColors.critical.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [8, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.critical, fontWeight: FontWeight.w600),
              labelResolver: (_) => 'Critical',
            ),
          ),
        ]),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.purpleLight,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.purpleLight.withValues(alpha: 0.25),
                  AppColors.purpleLight.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => isDark ? AppColors.bg3 : Colors.white,
            tooltipRoundedRadius: AppRadius.sm,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}${TemperatureUtils.unitSuffix(unit)}',
                      TextStyle(
                        color: AppColors.purpleLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
      duration: AppDurations.medium,
    );
  }
}

class _SensorsList extends ConsumerStatefulWidget {
  const _SensorsList({required this.deviceId, required this.unit, required this.isDark});
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
              color: widget.isDark ? AppColors.bg1 : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: widget.isDark ? AppColors.border : AppColors.lightBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.thermostat_outlined,
                    size: 20,
                    color: widget.isDark ? AppColors.textMuted : AppColors.lightTextSecondary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'No additional sensor detail available.',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: widget.isDark ? AppColors.bg1 : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: widget.isDark ? AppColors.border : AppColors.lightBorder),
          ),
          child: Column(
            children: sensors.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              final isLast = index == sensors.length - 1;
              final tempText = s.reading != null
                  ? TemperatureUtils.format(s.reading!.celsius, widget.unit)
                  : '—';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          s.isPrimary ? Icons.star_rounded : Icons.thermostat_rounded,
                          size: 16,
                          color: s.isPrimary
                              ? AppColors.purpleLight
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.purpleMid.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Primary',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.purpleLight,
                                    fontWeight: FontWeight.w600)),
                          ),
                        Text(
                          tempText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: widget.isDark ? AppColors.textPrimary : AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: widget.isDark ? AppColors.divider : AppColors.lightBorder,
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

// ─────────────────────────────────────────────────────────────────────────────
// Health Tab
// ─────────────────────────────────────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final health = device.health;
    final statusColor = _statusColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall health status card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    device.health.status == DeviceHealthStatus.healthy
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 24,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        _healthDescription(device.health.status),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'SMART & NVMe Data', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          // Health grid
          _HealthGrid(
            entries: [
              _HealthEntry(
                label: 'SMART Status',
                value: health.smartPassed == null
                    ? 'Not available'
                    : (health.smartPassed! ? 'Passed' : 'Failed'),
                icon: Icons.check_circle_outline_rounded,
                statusColor: health.smartPassed == true ? AppColors.normal : AppColors.critical,
                available: health.smartPassed != null,
              ),
              _HealthEntry(
                label: 'Percentage Used',
                value: health.percentageUsed != null ? '${health.percentageUsed}%' : '—',
                icon: Icons.pie_chart_outline_rounded,
                available: health.percentageUsed != null,
              ),
              _HealthEntry(
                label: 'Available Spare',
                value: health.availableSparePercent != null
                    ? '${health.availableSparePercent}%'
                    : '—',
                icon: Icons.disc_full_rounded,
                available: health.availableSparePercent != null,
              ),
              _HealthEntry(
                label: 'Critical Warnings',
                value: _na(health.criticalWarning),
                icon: Icons.warning_amber_rounded,
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
                value: health.powerOnHours != null ? '${health.powerOnHours} h' : '—',
                icon: Icons.timer_outlined,
                available: health.powerOnHours != null,
              ),
              _HealthEntry(
                label: 'Unsafe Shutdowns',
                value: _na(health.unsafeShutdowns),
                icon: Icons.power_off_rounded,
                available: health.unsafeShutdowns != null,
              ),
            ],
            isDark: isDark,
          ),
        ],
      ),
    );
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
          EntranceFade(index: i, child: _HealthTile(entry: entries[i], isDark: isDark)),
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
        ? (entry.statusColor ?? (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary))
        : AppColors.textMuted;
    return SizedBox(
      width: 200,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bg1 : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: entry.icon, color: color, size: 26, iconSize: 13),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.value,
              style: TextStyle(
                fontSize: 17,
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

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostics Tab
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({required this.device, required this.settings, required this.isDark});
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
        statusColor: device.lastError != null ? AppColors.warning : AppColors.normal,
      ),
      _DiagRow(
        label: 'Permission Status',
        value: device.sensorAvailability == SensorAvailability.permissionDenied
            ? 'Additional permissions required'
            : 'OK',
        icon: Icons.security_rounded,
        isDark: isDark,
        statusColor: device.sensorAvailability == SensorAvailability.permissionDenied
            ? AppColors.warning
            : AppColors.normal,
      ),
    ];

    final identifierRows = <_DiagRow>[
      _DiagRow(label: 'Device ID', value: device.id, icon: Icons.fingerprint_rounded, isDark: isDark),
      _DiagRow(
          label: 'Serial Number',
          value: device.serialNumber ?? '—',
          icon: Icons.numbers_rounded,
          isDark: isDark),
      _DiagRow(
          label: 'Firmware', value: '—', icon: Icons.system_update_alt_rounded, isDark: isDark),
      _DiagRow(
          label: 'Interface',
          value: device.interfaceType.name.toUpperCase(),
          icon: Icons.cable_rounded,
          isDark: isDark),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status overview
          for (var i = 0; i < statusRows.length; i++) EntranceFade(index: i, child: statusRows[i]),

          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'Capabilities', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _CapabilitiesGrid(
            capabilities: DeviceCapabilities.derive(device),
            startIndex: statusRows.length,
            isDark: isDark,
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'Device Identifiers', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          for (var i = 0; i < identifierRows.length; i++)
            EntranceFade(index: statusRows.length + i, child: identifierRows[i]),

          // Permission warning if needed
          if (device.sensorAvailability == SensorAvailability.permissionDenied) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Temperature Unavailable',
                          style: TextStyle(
                              color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          device.lastError ??
                              'This device requires additional permissions to read temperature data. Check your system settings or run the application with elevated privileges.',
                          style: const TextStyle(color: AppColors.warning, fontSize: 13),
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
        statusColor ?? (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: badgeColor, size: 28, iconSize: 14),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: statusColor ?? (isDark ? AppColors.textPrimary : AppColors.lightText),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-device capabilities (spec section 10)
// ─────────────────────────────────────────────────────────────────────────────

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
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < entries.length; i++)
          EntranceFade(
            index: startIndex + i,
            child: _CapabilityChip(label: entries[i].$1, available: entries[i].$2),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? AppColors.normal.withValues(alpha: isDark ? 0.12 : 0.08)
            : (isDark ? AppColors.bg1 : Colors.white),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: available ? AppColors.normal.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: available ? color : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
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
