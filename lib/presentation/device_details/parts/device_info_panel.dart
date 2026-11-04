part of '../device_details_screen.dart';

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

  void _exportReport(BuildContext context) {
    final health = device.health;
    final primaryTemp = device.primaryTemperature;
    final report = StringBuffer();
    report.writeln('========================================');
    report.writeln('DriveGuard Storage Diagnostic Report');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('========================================\n');
    report.writeln('DEVICE IDENTIFICATION:');
    report.writeln('  Display Name:    ${device.displayName}');
    report.writeln('  Device ID:       ${device.id}');
    report.writeln('  Type:            ${_typeLabel()}');
    report.writeln(
      '  Interface:       ${device.interfaceType.name.toUpperCase()}',
    );
    report.writeln('  Serial Number:   ${device.serialNumber ?? "N/A"}');
    report.writeln('  Firmware:        ${device.firmwareVersion ?? "N/A"}');
    report.writeln('  Capacity:        ${_capacityText()}\n');
    report.writeln('TEMPERATURE METRICS:');
    report.writeln(
      '  Current Temp:    ${primaryTemp != null ? "${primaryTemp.celsius.toStringAsFixed(1)} °C" : "Unavailable"}',
    );
    report.writeln(
      '  Severity:        ${presentation.severity.name.toUpperCase()}',
    );
    report.writeln(
      '  Sensor Source:   ${primaryTemp?.source.toString() ?? "N/A"}\n',
    );
    report.writeln('S.M.A.R.T. & HEALTH:');
    report.writeln('  Health Status:   ${health.status.name.toUpperCase()}');
    report.writeln(
      '  SMART Passed:    ${health.smartPassed == null ? "N/A" : (health.smartPassed! ? "PASSED" : "FAILED")}',
    );
    report.writeln(
      '  Percentage Used: ${health.percentageUsed != null ? "${health.percentageUsed}%" : "N/A"}',
    );
    report.writeln(
      '  Life Remaining:  ${health.percentageUsed != null ? "${(100 - health.percentageUsed!).clamp(0, 100)}%" : "N/A"}',
    );
    report.writeln(
      '  Available Spare: ${health.availableSparePercent != null ? "${health.availableSparePercent}%" : "N/A"}',
    );
    report.writeln('  Power Cycles:    ${health.powerCycles ?? "N/A"}');
    report.writeln(
      '  Power-On Hours:  ${health.powerOnHours != null ? "${health.powerOnHours} h" : "N/A"}',
    );
    report.writeln('  Media Errors:    ${health.mediaErrors ?? "0"}');
    report.writeln(
      '  Total Read:      ${health.totalBytesRead != null ? _formatBytes(health.totalBytesRead!) : "N/A"}',
    );
    report.writeln(
      '  Total Written:   ${health.totalBytesWritten != null ? _formatBytes(health.totalBytesWritten!) : "N/A"}\n',
    );
    if (device.volumes.isNotEmpty) {
      report.writeln('VOLUMES:');
      for (final v in device.volumes) {
        report.writeln(
          '  - ${v.volumeName ?? v.mountPoint ?? v.id} (${v.filesystem ?? "Unknown FS"}, Total: ${v.totalBytes != null ? _formatBytes(v.totalBytes!) : "N/A"})',
        );
      }
    }
    report.writeln('\n========================================');

    Clipboard.setData(ClipboardData(text: report.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic report copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        backgroundColor: AppColors.accent,
      ),
    );
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
      child: SingleChildScrollView(
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
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(
                        Icons.file_download_outlined,
                        color: isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      onPressed: () => _exportReport(context),
                      tooltip: 'Export Diagnostic Report',
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
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.2,
                    colors: [
                      style.color.withValues(alpha: isDark ? 0.16 : 0.10),
                      style.color.withValues(alpha: 0.0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                    color: style.color.withValues(alpha: 0.18),
                  ),
                ),
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
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _HealthGrid(
                entries: [
                  _HealthEntry(
                    label: 'Type',
                    value: _typeLabel(),
                    icon: _typeIcon(),
                  ),
                  _HealthEntry(
                    label: 'Capacity',
                    value: _capacityText(),
                    icon: Icons.pie_chart_outline_rounded,
                  ),
                  _HealthEntry(
                    label: 'Health',
                    value: _healthLabel(),
                    icon: Icons.favorite_rounded,
                    statusColor:
                        device.health.status == DeviceHealthStatus.healthy
                        ? AppColors.normal
                        : device.health.status == DeviceHealthStatus.warning
                        ? AppColors.warning
                        : device.health.status == DeviceHealthStatus.critical
                        ? AppColors.critical
                        : null,
                  ),
                  _HealthEntry(
                    label: 'Last Updated',
                    value: _lastUpdatedText(),
                    icon: Icons.schedule_rounded,
                  ),
                  _HealthEntry(
                    label: 'Interface',
                    value: device.interfaceType.name.toUpperCase(),
                    icon: Icons.cable_rounded,
                  ),
                  _HealthEntry(
                    label: 'Monitoring',
                    value:
                        device.monitoringStatus.name[0].toUpperCase() +
                        device.monitoringStatus.name.substring(1),
                    icon: Icons.monitor_heart_outlined,
                    statusColor:
                        device.monitoringStatus == MonitoringStatus.active
                        ? AppColors.normal
                        : device.monitoringStatus == MonitoringStatus.error
                        ? AppColors.critical
                        : null,
                  ),
                  _HealthEntry(
                    label: 'Sensor Source',
                    value:
                        device.primaryTemperature?.source.toString() ?? 'N/A',
                    icon: Icons.sensors_rounded,
                  ),
                  _HealthEntry(
                    label: 'Serial Number',
                    value: device.serialNumber ?? '--',
                    icon: Icons.numbers_rounded,
                  ),
                ],
                isDark: isDark,
                minTileWidth: 110,
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg0 : AppColors.lightBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2.5,
        labelColor: AppColors.accent,
        unselectedLabelColor: isDark
            ? AppColors.textSecondary
            : AppColors.lightTextSecondary,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: const [
          Tab(
            height: 44,
            icon: Icon(Icons.thermostat_rounded, size: 16),
            iconMargin: EdgeInsets.only(bottom: 2),
            text: 'Temperature',
          ),
          Tab(
            height: 44,
            icon: Icon(Icons.favorite_rounded, size: 16),
            iconMargin: EdgeInsets.only(bottom: 2),
            text: 'Health',
          ),
          Tab(
            height: 44,
            icon: Icon(Icons.storage_rounded, size: 16),
            iconMargin: EdgeInsets.only(bottom: 2),
            text: 'Storage',
          ),
          Tab(
            height: 44,
            icon: Icon(Icons.build_rounded, size: 16),
            iconMargin: EdgeInsets.only(bottom: 2),
            text: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}
