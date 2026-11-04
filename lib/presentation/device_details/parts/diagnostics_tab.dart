part of '../device_details_screen.dart';

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
        value: device.primaryTemperature?.source.toString() ?? 'N/A',
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
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.md),
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
