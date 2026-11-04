part of '../dashboard_screen.dart';

class _DriveListPane extends StatelessWidget {
  const _DriveListPane({
    required this.settings,
    required this.isDark,
    required this.onOpenDevice,
    required this.onToggleCompactView,
  });

  final dynamic settings;
  final bool isDark;
  final ValueChanged<String> onOpenDevice;
  final ValueChanged<bool> onToggleCompactView;

  @override
  Widget build(BuildContext context) {
    final compactView = settings.dashboardCompactView as bool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer(
          builder: (context, ref, _) => _DriveListToolbar(
            deviceCount: ref.watch(deviceIdsProvider).length,
            compactView: compactView,
            isDark: isDark,
            onToggleCompactView: onToggleCompactView,
          ),
        ),

        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? AppColors.divider : AppColors.lightBorder,
        ),

        Consumer(
          builder: (context, ref, _) {
            final devices = ref.watch(devicesProvider);
            if (devices.isEmpty) return const SizedBox.shrink();
            return _OverviewStrip(
              devices: devices,
              settings: settings,
              isDark: isDark,
            );
          },
        ),

        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final ids = ref.watch(deviceIdsProvider);
              if (ids.isEmpty) return const _EmptyState();
              return _DriveScrollBody(
                ids: ids,
                settings: settings,
                isDark: isDark,
                compactView: compactView,
                onOpenDevice: onOpenDevice,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({
    required this.devices,
    required this.settings,
    required this.isDark,
  });

  final List<StorageDevice> devices;
  final dynamic settings;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    var normalCount = 0;
    var warningCount = 0;
    var criticalCount = 0;
    var tempSum = 0.0;
    var tempCount = 0;

    for (final d in devices) {
      final presentation = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      switch (presentation.severity) {
        case TemperatureSeverity.critical:
          criticalCount++;
        case TemperatureSeverity.warning:
          warningCount++;
        case TemperatureSeverity.normal:
        case TemperatureSeverity.warm:
          normalCount++;
        case TemperatureSeverity.unavailable:
          break;
      }
      if (presentation.tempCelsius != null) {
        tempSum += presentation.tempCelsius!;
        tempCount++;
      }
    }

    final avgTempText = tempCount > 0
        ? TemperatureUtils.format(tempSum / tempCount, settings.temperatureUnit)
        : '--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _OverviewTile(
              icon: Icons.storage_rounded,
              label: 'Drives',
              value: '${devices.length}',
              color: AppColors.accent,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _OverviewTile(
              icon: Icons.check_circle_outline_rounded,
              label: 'Normal',
              value: '$normalCount',
              color: AppColors.normal,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _OverviewTile(
              icon: Icons.warning_amber_rounded,
              label: 'Warning',
              value: '$warningCount',
              color: AppColors.warning,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _OverviewTile(
              icon: Icons.error_outline_rounded,
              label: 'Critical',
              value: '$criticalCount',
              color: AppColors.critical,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _OverviewTile(
              icon: Icons.thermostat_rounded,
              label: 'Avg Temp',
              value: avgTempText,
              color: isDark ? AppColors.textPrimary : AppColors.lightText,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.md),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 30, iconSize: 15),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
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
