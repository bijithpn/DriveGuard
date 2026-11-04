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
    final available = presentation.tempCelsius != null;
    final m = RegExp(r'^(-?[\d.]+)(.*)$').firstMatch(presentation.valueText);
    final number = m?.group(1) ?? presentation.valueText;
    final unit = m?.group(2) ?? '';

    Color? healthColor;
    switch (device.health.status) {
      case DeviceHealthStatus.healthy:
        healthColor = AppColors.normal;
      case DeviceHealthStatus.warning:
        healthColor = AppColors.warning;
      case DeviceHealthStatus.critical:
        healthColor = AppColors.critical;
      default:
        healthColor = null;
    }
    final monitoring =
        device.monitoringStatus.name[0].toUpperCase() +
        device.monitoringStatus.name.substring(1);

    Widget row(String label, String value, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairlineOf(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.secondary(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                context,
              ).copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(right: BorderSide(color: hairlineOf(context))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(Icons.arrow_back_rounded, color: mutedOf(context)),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              device.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.title(context),
            ),
            const SizedBox(height: 4),
            Text(_typeLabel(), style: AppText.secondary(context)),
            const SizedBox(height: AppSpacing.lg),

            if (available)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(number, style: AppText.metric(context, size: 48)),
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: mutedOf(context),
                    ),
                  ),
                ],
              )
            else
              Text(
                presentation.valueText,
                style: AppText.metric(
                  context,
                  size: 28,
                ).copyWith(color: faintOf(context)),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                StatusDot(style.color, size: 7),
                const SizedBox(width: 8),
                Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: style.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: isDark ? AppColors.bg3 : AppColors.lightBorder,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        heightFactor: 1,
                        widthFactor: available
                            ? presentation.fraction.clamp(0.02, 1.0)
                            : 0,
                        child: ColoredBox(color: style.color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('DETAILS', style: AppText.label(context)),
            const SizedBox(height: 4),
            row('Capacity', _capacityText()),
            row('Health', _healthLabel(), color: healthColor),
            row('Interface', device.interfaceType.name.toUpperCase()),
            row(
              'Monitoring',
              monitoring,
              color: device.monitoringStatus == MonitoringStatus.active
                  ? AppColors.normal
                  : (device.monitoringStatus == MonitoringStatus.error
                        ? AppColors.critical
                        : null),
            ),
            row('Serial', device.serialNumber ?? '--'),
            row(
              'Sensor',
              device.primaryTemperature?.source.toString() ?? 'N/A',
            ),
            row('Updated', _lastUpdatedText()),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairlineOf(context))),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2,
        labelColor: primaryTextOf(context),
        unselectedLabelColor: mutedOf(context),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: const [
          Tab(height: 52, text: 'Temperature'),
          Tab(height: 52, text: 'Health'),
          Tab(height: 52, text: 'Storage'),
          Tab(height: 52, text: 'Diagnostics'),
        ],
      ),
    );
  }
}
