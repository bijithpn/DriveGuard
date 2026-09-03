import 'package:flutter/material.dart';

import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';
import 'device_presentation.dart';

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

  
  
  
  
  String _capacityText() {
    final capacity = widget.device.capacity;
    if (capacity.isValid && capacity.freeBytes != null) {
      return '${_formatBytes(capacity.freeBytes!)} free';
    }
    final bytes = widget.device.capacityBytes;
    if (bytes == null) return '--';
    return _formatBytes(bytes);
  }

  String _healthLabel() {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label:
          '${widget.device.displayName}, ${_typeLabel()}, '
          '${style.label}, ${presentation.valueText}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: widget.compactMode
            ? _CompactRow(
                device: widget.device,
                presentation: presentation,
                style: style,
                isDark: isDark,
                isHovered: _isHovered,
                typeLabel: _typeLabel(),
                typeIcon: _typeIcon(),
                onTap: widget.onTap,
              )
            : _GridCard(
                device: widget.device,
                presentation: presentation,
                style: style,
                isDark: isDark,
                isHovered: _isHovered,
                typeLabel: _typeLabel(),
                typeIcon: _typeIcon(),
                healthLabel: _healthLabel(),
                healthColor: _healthColor(context),
                capacityLabel:
                    widget.device.capacity.isValid &&
                        widget.device.capacity.freeBytes != null
                    ? 'Free'
                    : 'Capacity',
                capacityText: _capacityText(),
                updatedText: _updatedText(),
                onTap: widget.onTap,
              ),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.device,
    required this.presentation,
    required this.style,
    required this.isDark,
    required this.isHovered,
    required this.typeLabel,
    required this.typeIcon,
    required this.onTap,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
  final SeverityStyle style;
  final bool isDark;
  final bool isHovered;
  final String typeLabel;
  final IconData typeIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isHovered
        ? (isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted)
        : (isDark ? AppColors.bg1 : AppColors.lightCard);

    final showStatusLabel =
        presentation.severity == TemperatureSeverity.warning ||
        presentation.severity == TemperatureSeverity.critical;

    return AnimatedContainer(
      duration: AppDurations.fast,
      height: 52,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 3, height: 52, color: style.color),

            SizedBox(
              width: 40,
              child: Center(
                child: Icon(
                  typeIcon,
                  size: 28,
                  color: style.color.withValues(alpha: isDark ? 0.8 : 0.7),
                ),
              ),
            ),

            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    presentation.valueText,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: style.color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (showStatusLabel) ...[
                    const SizedBox(height: 1),
                    Text(
                      style.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: style.color.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({
    required this.device,
    required this.presentation,
    required this.style,
    required this.isDark,
    required this.isHovered,
    required this.typeLabel,
    required this.typeIcon,
    required this.healthLabel,
    required this.healthColor,
    required this.capacityLabel,
    required this.capacityText,
    required this.updatedText,
    required this.onTap,
  });

  final StorageDevice device;
  final DevicePresentation presentation;
  final SeverityStyle style;
  final bool isDark;
  final bool isHovered;
  final String typeLabel;
  final IconData typeIcon;
  final String healthLabel;
  final Color healthColor;
  final String capacityLabel;
  final String capacityText;
  final String updatedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isHovered
        ? style.color.withValues(alpha: 0.4)
        : (isDark ? AppColors.border : AppColors.lightBorder);

    return AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: style.color),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _IconBadge(
                          icon: typeIcon,
                          color: style.color,
                          isDark: isDark,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textPrimary
                                      : AppColors.lightText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                typeLabel,
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

                    const SizedBox(height: AppSpacing.md),

                    Center(
                      child: Text(
                        presentation.valueText,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: style.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    _TempProgressBar(
                      fraction: presentation.fraction,
                      color: style.color,
                      isDark: isDark,
                    ),

                    const SizedBox(height: AppSpacing.md),

                    Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark ? AppColors.divider : AppColors.lightBorder,
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    Row(
                      children: [
                        _StatColumn(
                          label: 'Health',
                          value: healthLabel,
                          valueColor: healthColor,
                        ),
                        _StatColumn(label: capacityLabel, value: capacityText),
                        _StatColumn(label: 'Updated', value: updatedText),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _TempProgressBar extends StatelessWidget {
  const _TempProgressBar({
    required this.fraction,
    required this.color,
    required this.isDark,
  });

  final double fraction;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final filled = (total * fraction.clamp(0.0, 1.0)).roundToDouble();
        return Container(
          height: 3,
          width: total,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: AppDurations.medium,
              width: filled,
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  valueColor ??
                  (isDark ? AppColors.textPrimary : AppColors.lightText),
            ),
          ),
        ],
      ),
    );
  }
}
