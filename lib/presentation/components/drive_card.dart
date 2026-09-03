import 'package:flutter/material.dart';

import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';
import 'device_presentation.dart';
import 'temperature_gauge.dart';

/// Flat drive card. No gradients, no glow, no pulsing.
/// Hover shows a subtle border/background change only.
class DriveCard extends StatefulWidget {
  const DriveCard({
    super.key,
    required this.device,
    required this.thresholds,
    required this.unit,
    required this.onTap,
  });

  final StorageDevice device;
  final TemperatureThresholds thresholds;
  final TemperatureUnit unit;
  final VoidCallback onTap;

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

  String _capacityText() {
    final bytes = widget.device.capacityBytes;
    if (bytes == null) return '--';
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
          '${widget.device.displayName}, ${_typeLabel()}, ${style.label}, ${presentation.valueText}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: AppDurations.fast,
          decoration: BoxDecoration(
            color: isDark
                ? (_isHovered ? AppColors.bg2 : AppColors.bg1)
                : (_isHovered
                      ? AppColors.lightSurfaceMuted
                      : AppColors.lightCard),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: _isHovered
                  ? (isDark ? AppColors.bg3 : AppColors.lightBorder)
                  : (isDark ? AppColors.border : AppColors.lightBorder),
              width: _isHovered ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      _TypeBadge(icon: _typeIcon(), color: style.color),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.device.displayName,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: isDark
                                        ? AppColors.textPrimary
                                        : AppColors.lightText,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _typeLabel(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Static status indicator (no pulse)
                      _StatusIndicator(
                        severity: presentation.severity,
                        color: style.color,
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Temperature gauge
                  Center(
                    child: TemperatureGauge(
                      valueText: presentation.valueText,
                      fraction: presentation.fraction,
                      severity: presentation.severity,
                      size: 120,
                      labelText: style.label,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Stale data
                  if (presentation.isStaleLike)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 11,
                            color: AppColors.warning.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Stale data',
                            style: TextStyle(
                              color: AppColors.warning.withValues(alpha: 0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Divider
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? AppColors.divider : AppColors.lightBorder,
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Stats row
                  Row(
                    children: [
                      _StatColumn(
                        label: 'Health',
                        value: _healthLabel(),
                        valueColor: _healthColor(context),
                      ),
                      _StatColumn(label: 'Capacity', value: _capacityText()),
                      _StatColumn(label: 'Updated', value: _updatedText()),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

/// Static colored dot + icon indicating severity.
/// No pulsing animation; warning/critical are clear through color and the
/// icon label on the gauge itself.
class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.severity, required this.color});
  final TemperatureSeverity severity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // For critical/warning show an icon in addition to the dot for clarity.
    if (severity == TemperatureSeverity.critical ||
        severity == TemperatureSeverity.warning) {
      return Icon(
        severity == TemperatureSeverity.critical
            ? Icons.error_outline_rounded
            : Icons.warning_amber_rounded,
        size: 16,
        color: color,
      );
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
