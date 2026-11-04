part of '../device_details_screen.dart';

class _HealthTab extends StatelessWidget {
  const _HealthTab({required this.device, required this.isDark});

  final StorageDevice device;
  final bool isDark;

  String _na(Object? v) => v?.toString() ?? 'N/A';

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
                    ? 'N/A'
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
              _HealthEntry(
                label: 'Life Remaining',
                value: health.percentageUsed != null
                    ? '${(100 - health.percentageUsed!).clamp(0, 100)}%'
                    : '--',
                icon: Icons.favorite_rounded,
                statusColor: health.percentageUsed != null
                    ? (health.percentageUsed! > 90
                          ? AppColors.critical
                          : health.percentageUsed! > 75
                          ? AppColors.warning
                          : AppColors.normal)
                    : null,
                available: health.percentageUsed != null,
              ),
            ],
            isDark: isDark,
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'ATA SMART Attributes', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          _HealthGrid(
            entries: [
              _HealthEntry(
                label: 'Reallocated Sectors',
                value: _na(health.reallocatedSectorCount),
                icon: Icons.grid_off_rounded,
                statusColor: (health.reallocatedSectorCount ?? 0) > 0
                    ? AppColors.critical
                    : null,
                available: health.reallocatedSectorCount != null,
              ),
              _HealthEntry(
                label: 'Reallocated Events',
                value: _na(health.reallocatedEventCount),
                icon: Icons.history_toggle_off_rounded,
                statusColor: (health.reallocatedEventCount ?? 0) > 0
                    ? AppColors.warning
                    : null,
                available: health.reallocatedEventCount != null,
              ),
              _HealthEntry(
                label: 'Pending Sectors',
                value: _na(health.currentPendingSectorCount),
                icon: Icons.pending_outlined,
                statusColor: (health.currentPendingSectorCount ?? 0) > 0
                    ? AppColors.critical
                    : null,
                available: health.currentPendingSectorCount != null,
              ),
              _HealthEntry(
                label: 'Offline Uncorrectable',
                value: _na(health.offlineUncorrectableCount),
                icon: Icons.report_gmailerrorred_rounded,
                statusColor: (health.offlineUncorrectableCount ?? 0) > 0
                    ? AppColors.critical
                    : null,
                available: health.offlineUncorrectableCount != null,
              ),
              _HealthEntry(
                label: 'SSD Life Left',
                value: health.ssdLifeLeftPercent != null
                    ? '${health.ssdLifeLeftPercent}%'
                    : '--',
                icon: Icons.battery_charging_full_rounded,
                statusColor: health.ssdLifeLeftPercent != null
                    ? (health.ssdLifeLeftPercent! < 10
                          ? AppColors.critical
                          : health.ssdLifeLeftPercent! < 25
                          ? AppColors.warning
                          : AppColors.normal)
                    : null,
                available: health.ssdLifeLeftPercent != null,
              ),
            ],
            isDark: isDark,
          ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'TBW & Lifespan Estimation', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),

          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: AppDecorations.card(
              isDark: isDark,
              radius: AppRadius.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Endurance Status',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightText,
                      ),
                    ),
                    Text(
                      health.percentageUsed != null
                          ? '${(100 - health.percentageUsed!).clamp(0, 100)}% Estimated Health'
                          : 'Health Estimation Pending',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: health.percentageUsed != null
                            ? (health.percentageUsed! > 90
                                  ? AppColors.critical
                                  : health.percentageUsed! > 75
                                  ? AppColors.warning
                                  : AppColors.normal)
                            : (isDark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: health.percentageUsed != null
                        ? ((100 - health.percentageUsed!) / 100.0).clamp(
                            0.0,
                            1.0,
                          )
                        : 1.0,
                    minHeight: 8,
                    backgroundColor: isDark
                        ? AppColors.bg2
                        : AppColors.lightSurfaceMuted,
                    valueColor: AlwaysStoppedAnimation(
                      health.percentageUsed != null &&
                              health.percentageUsed! > 90
                          ? AppColors.critical
                          : health.percentageUsed != null &&
                                health.percentageUsed! > 75
                          ? AppColors.warning
                          : AppColors.normal,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  health.totalBytesWritten != null
                      ? 'Total Written: ${_formatBytes(health.totalBytesWritten!)} · Power-on: ${health.powerOnHours != null ? "${health.powerOnHours} hours" : "N/A"}'
                      : 'Accumulated TBW and endurance telemetry are queried via WMI / sysfs.',
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
  const _HealthGrid({
    required this.entries,
    required this.isDark,
    this.minTileWidth = 170,
  });

  final List<_HealthEntry> entries;
  final bool isDark;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rawCols = (width / (minTileWidth + AppSpacing.sm)).floor();
        final cols = rawCols.clamp(1, entries.length).toInt();
        final tileWidth = (width - AppSpacing.sm * (cols - 1)) / cols;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < entries.length; i++)
              EntranceFade(
                index: i,
                child: SizedBox(
                  width: tileWidth,
                  child: _HealthTile(entry: entries[i], isDark: isDark),
                ),
              ),
          ],
        );
      },
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: entry.icon, color: color, size: 24, iconSize: 12),
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
    );
  }
}
