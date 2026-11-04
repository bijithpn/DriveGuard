import 'package:flutter/material.dart';

import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';
import 'device_presentation.dart';
import 'ui_kit.dart';

class DriveCard extends StatefulWidget {
  const DriveCard({
    super.key,
    required this.device,
    required this.thresholds,
    required this.unit,
    required this.onTap,
    this.compactMode = false,
  });

  final StorageDevice device;
  final TemperatureThresholds thresholds;
  final TemperatureUnit unit;
  final VoidCallback onTap;

  final bool compactMode;

  @override
  State<DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends State<DriveCard> {
  bool _isHovered = false;

  String _typeLabel() {
    switch (widget.device.type) {
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
    switch (widget.device.type) {
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

  String _usageStatLabel() {
    if (widget.device.health.totalBytesWritten != null) {
      return 'Written';
    }
    if (widget.device.health.powerOnHours != null) {
      return 'Power-On';
    }
    return 'Capacity';
  }

  String _usageStatText() {
    final tbw = widget.device.health.totalBytesWritten;
    if (tbw != null) {
      final tb = tbw / (1024 * 1024 * 1024 * 1024);
      if (tb >= 1.0) {
        return '${tb.toStringAsFixed(1)} TB';
      }
      final gb = tbw / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(0)} GB';
    }
    final hours = widget.device.health.powerOnHours;
    if (hours != null) {
      if (hours >= 24) {
        return '${(hours / 24).toStringAsFixed(0)}d (${hours}h)';
      }
      return '${hours}h';
    }
    final bytes = widget.device.capacityBytes;
    if (bytes != null && bytes > 0) {
      return _formatBytes(bytes);
    }
    return 'Active';
  }

  String _healthLabel() {
    if (widget.device.health.percentageUsed != null) {
      final life = (100 - widget.device.health.percentageUsed!).clamp(0, 100);
      return '$life% Life';
    }
    switch (widget.device.health.status) {
      case DeviceHealthStatus.healthy:
        return 'Healthy';
      case DeviceHealthStatus.warning:
        return 'Warning';
      case DeviceHealthStatus.critical:
        return 'Critical';
      case DeviceHealthStatus.unknown:
        return 'Unknown';
      case DeviceHealthStatus.unavailable:
        return '--';
    }
  }

  Color _healthColor(BuildContext context) {
    switch (widget.device.health.status) {
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

  String _updatedText() {
    final updated = widget.device.lastUpdated;
    if (updated == null) return 'Never';
    final diff = DateTime.now().difference(updated);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final presentation = DevicePresentation.of(
      widget.device,
      widget.thresholds,
      widget.unit,
    );
    final style = SeverityStyle.of(presentation.severity, context);

    return Semantics(
      button: true,
      label:
          '${widget.device.displayName}, ${_typeLabel()}, '
          '${style.label}, ${presentation.valueText}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: widget.compactMode
              ? _CompactRow(
                  device: widget.device,
                  presentation: presentation,
                  style: style,
                  hovered: _isHovered,
                  typeLabel: _typeLabel(),
                  healthLabel: _healthLabel(),
                  healthColor: _healthColor(context),
                  statText: _usageStatText(),
                )
              : _GridCard(
                  device: widget.device,
                  presentation: presentation,
                  style: style,
                  hovered: _isHovered,
                  typeLabel: _typeLabel(),
                  typeIcon: _typeIcon(),
                  healthLabel: _healthLabel(),
                  healthColor: _healthColor(context),
                  statLabel: _usageStatLabel(),
                  statText: _usageStatText(),
                  updatedText: _updatedText(),
                ),
        ),
      ),
    );
  }
}

/// Splits "42°C" into the number and its unit so the unit can be quieter.
(String, String) _splitValue(String valueText) {
  final m = RegExp(r'^(-?[\d.]+)(.*)$').firstMatch(valueText);
  if (m == null) return (valueText, '');
  return (m.group(1)!, m.group(2)!);
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.device,
    required this.presentation,
    required this.style,
    required this.hovered,
    required this.typeLabel,
    required this.typeIcon,
    required this.healthLabel,
    required this.healthColor,
    required this.statLabel,
    required this.statText,
    required this.updatedText,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
  final SeverityStyle style;
  final bool hovered;
  final String typeLabel;
  final IconData typeIcon;
  final String healthLabel;
  final Color healthColor;
  final String statLabel;
  final String statText;
  final String updatedText;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final available = presentation.tempCelsius != null;
    final (number, unit) = _splitValue(presentation.valueText);
    final statusColor = style.color;

    return AnimatedContainer(
      duration: AppDurations.fast,
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: BoxDecoration(
        color: dark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: hovered
              ? AppColors.accent.withValues(alpha: 0.55)
              : (dark ? AppColors.border : AppColors.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(typeIcon, size: 18, color: mutedOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.heading(context),
                    ),
                    const SizedBox(height: 2),
                    Text(typeLabel, style: AppText.caption(context)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(statusColor, size: 7),
                    const SizedBox(width: 6),
                    Text(
                      style.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Temperature
          if (available)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(number, style: AppText.metric(context, size: 38)),
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 20,
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
                size: 22,
              ).copyWith(color: faintOf(context), letterSpacing: -0.3),
            ),
          const SizedBox(height: AppSpacing.md),

          // Gauge
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: dark ? AppColors.bg3 : AppColors.lightBorder,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      heightFactor: 1,
                      widthFactor: available
                          ? presentation.fraction.clamp(0.02, 1.0)
                          : 0,
                      child: ColoredBox(color: statusColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),

          // Secondary stats — plain columns, no boxes.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Stat(
                  label: 'Health',
                  value: healthLabel,
                  valueColor: healthColor == AppColors.textMuted
                      ? null
                      : healthColor,
                ),
              ),
              Expanded(
                child: _Stat(label: statLabel, value: statText),
              ),
              Text(updatedText, style: AppText.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppText.caption(context)),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(
          context,
        ).copyWith(fontWeight: FontWeight.w600, color: valueColor),
      ),
    ],
  );
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.device,
    required this.presentation,
    required this.style,
    required this.hovered,
    required this.typeLabel,
    required this.healthLabel,
    required this.healthColor,
    required this.statText,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
  final SeverityStyle style;
  final bool hovered;
  final String typeLabel;
  final String healthLabel;
  final Color healthColor;
  final String statText;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    return AnimatedContainer(
      duration: AppDurations.fast,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
      color: hovered
          ? (dark ? Colors.white : Colors.black).withValues(alpha: 0.03)
          : Colors.transparent,
      child: Row(
        children: [
          StatusDot(style.color),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(context),
                ),
                const SizedBox(height: 2),
                Text(typeLabel, style: AppText.caption(context)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              presentation.valueText,
              style: AppText.heading(
                context,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              healthLabel,
              style: AppText.body(context).copyWith(
                color: healthColor == AppColors.textMuted ? null : healthColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(statText, style: AppText.secondary(context)),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: faintOf(context)),
        ],
      ),
    );
  }
}
