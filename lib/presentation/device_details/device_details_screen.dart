import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/monitoring/temperature_history_store.dart';
import '../../application/providers.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_capacity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/storage_volume.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../components/animated_entrance.dart';
import '../components/device_presentation.dart';
import '../components/ui_kit.dart';
import '../protection/alert_card.dart';
import '../components/app_shell.dart';
import '../theme/app_theme.dart';

part 'parts/device_info_panel.dart';
part 'parts/temperature_tab.dart';
part 'parts/history_chart.dart';
part 'parts/sensors_list.dart';
part 'parts/health_tab.dart';
part 'parts/storage_tab.dart';
part 'parts/diagnostics_tab.dart';

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
  '7 days': Duration(days: 7),
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
    final settings = ref.watch(settingsProvider);
    final device = ref.watch(deviceProvider(widget.deviceId));
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
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
