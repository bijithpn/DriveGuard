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
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} h ago';
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// One honest sentence about whether monitoring is healthy.
  (Color, String, String) _verdict() {
    final updated = _ago(device.lastUpdated);
    if (device.sensorAvailability == SensorAvailability.permissionDenied) {
      return (
        AppColors.warning,
        'Temperature needs extra permission',
        'DriveGuard can see this drive but is not allowed to read its sensor.',
      );
    }
    switch (device.monitoringStatus) {
      case MonitoringStatus.active:
        return (
          AppColors.normal,
          'Monitoring is working normally',
          'Last reading $updated  ·  every ${settings.pollingInterval.inSeconds}s',
        );
      case MonitoringStatus.error:
        return (
          AppColors.critical,
          'Something went wrong reading this drive',
          device.lastError ?? 'The last read failed.',
        );
      case MonitoringStatus.disconnected:
        return (
          AppColors.warning,
          'This drive is disconnected',
          'Reconnect it and DriveGuard will resume automatically.',
        );
      case MonitoringStatus.sensorUnavailable:
        return (
          AppColors.warning,
          'This drive has no temperature sensor',
          'Health and capacity can still be monitored.',
        );
      case MonitoringStatus.staleData:
        return (
          AppColors.warning,
          'Readings are out of date',
          'Last successful reading $updated.',
        );
      case MonitoringStatus.permissionDenied:
        return (
          AppColors.warning,
          'Temperature needs extra permission',
          'DriveGuard can see this drive but is not allowed to read its sensor.',
        );
      case MonitoringStatus.paused:
        return (
          AppColors.warning,
          'Monitoring is paused',
          'Resume it from the sidebar.',
        );
      case MonitoringStatus.initializing:
        return (
          AppColors.accent,
          'Starting up…',
          'The first reading will arrive in a moment.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (verdictColor, verdictTitle, verdictSub) = _verdict();
    final permDenied =
        device.sensorAvailability == SensorAvailability.permissionDenied;
    final avail = device.sensorAvailability;

    final monitoring = <DetailRowData>[
      DetailRowData(
        'Status',
        _titleCase(device.monitoringStatus.name),
        dot: verdictColor,
      ),
      DetailRowData(
        'Polling interval',
        'Every ${settings.pollingInterval.inSeconds} seconds',
      ),
      DetailRowData(
        'Sensor source',
        device.primaryTemperature?.source.toString() ?? 'Not available',
      ),
      DetailRowData(
        'Sensor access',
        avail == SensorAvailability.available
            ? 'Available'
            : (permDenied ? 'Permission required' : _titleCase(avail.name)),
        dot: avail == SensorAvailability.available
            ? AppColors.normal
            : (permDenied ? AppColors.warning : null),
      ),
      DetailRowData('Last reading', _ago(device.lastUpdated)),
      DetailRowData(
        'Last error',
        device.lastError ?? 'None',
        dot: device.lastError == null ? AppColors.normal : AppColors.warning,
      ),
    ];

    final identifiers = <DetailRowData>[
      DetailRowData('Device ID', device.id, copyable: true),
      DetailRowData(
        'Serial number',
        device.serialNumber ?? '--',
        copyable: device.serialNumber != null,
      ),
      DetailRowData('Firmware', device.firmwareVersion ?? '--'),
      DetailRowData('Interface', device.interfaceType.name.toUpperCase()),
    ];

    final caps = DeviceCapabilities.derive(device).entries;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Surface(
            child: Row(
              children: [
                StatusDot(verdictColor, size: 10),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(verdictTitle, style: AppText.heading(context)),
                      const SizedBox(height: 3),
                      Text(verdictSub, style: AppText.secondary(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (permDenied) ...[
            const SizedBox(height: AppSpacing.gap),
            AlertCard(
              color: AppColors.warning,
              icon: Icons.lock_outline_rounded,
              title: 'Temperature unavailable',
              children: [
                Text(
                  device.lastError ??
                      'This drive needs additional permission to read temperature '
                          'data. Check your system settings or run DriveGuard with '
                          'elevated privileges.',
                  style: AppText.secondary(context),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          InfoSection(title: 'Monitoring', child: DetailTable(monitoring)),
          const SizedBox(height: AppSpacing.section),
          InfoSection(
            title: 'Capabilities',
            caption: 'What DriveGuard can read from this drive',
            child: Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 520 ? 2 : 1;
                  final w = (c.maxWidth - (cols - 1) * 16) / cols;
                  return Wrap(
                    spacing: 16,
                    children: [
                      for (final e in caps)
                        SizedBox(
                          width: w,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Icon(
                                  e.$2
                                      ? Icons.check_circle_rounded
                                      : Icons.remove_circle_outline_rounded,
                                  size: 16,
                                  color: e.$2
                                      ? AppColors.normal
                                      : faintOf(context),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  e.$1,
                                  style: e.$2
                                      ? AppText.body(context)
                                      : AppText.secondary(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          InfoSection(title: 'Identifiers', child: DetailTable(identifiers)),
        ],
      ),
    );
  }
}
