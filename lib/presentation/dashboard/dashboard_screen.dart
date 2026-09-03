import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../components/device_presentation.dart';
import '../components/drive_card.dart';
import '../components/temperature_gauge.dart';
import '../device_details/device_details_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final settings = ref.watch(settingsProvider);
    final monitoringService = ref.watch(monitoringServiceProvider);

    return Scaffold(
      body: Column(
        children: [
          _DashboardHeader(
            deviceCount: devices.length,
            monitoringEnabled: settings.monitoringEnabled,
            onToggleMonitoring: () => ref
                .read(settingsProvider.notifier)
                .updateWith(
                  (s) => s.copyWith(monitoringEnabled: !s.monitoringEnabled),
                ),
            onRescan: monitoringService.rescan,
            onOpenSettings: () =>
                Navigator.of(context).push(_slideRoute(const SettingsScreen())),
            compactView: settings.dashboardCompactView,
            onToggleCompactView: (value) => ref
                .read(settingsProvider.notifier)
                .updateWith((s) => s.copyWith(dashboardCompactView: value)),
            devices: devices,
            settings: settings,
          ),
          Expanded(
            child: _Body(devices: devices, settings: settings),
          ),
        ],
      ),
    );
  }
}

Route<void> _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
    transitionDuration: AppDurations.medium,
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.deviceCount,
    required this.monitoringEnabled,
    required this.onToggleMonitoring,
    required this.onRescan,
    required this.onOpenSettings,
    required this.compactView,
    required this.onToggleCompactView,
    required this.devices,
    required this.settings,
  });

  final int deviceCount;
  final bool monitoringEnabled;
  final VoidCallback onToggleMonitoring;
  final VoidCallback onRescan;
  final VoidCallback onOpenSettings;
  final bool compactView;
  final ValueChanged<bool> onToggleCompactView;
  final List<StorageDevice> devices;
  final dynamic settings;

  TemperatureSeverity _overallSeverity() {
    if (devices.isEmpty) return TemperatureSeverity.unavailable;
    TemperatureSeverity worst = TemperatureSeverity.normal;
    for (final d in devices) {
      final thresholds = settings.thresholdsFor(d.id);
      final presentation = DevicePresentation.of(
        d,
        thresholds,
        settings.temperatureUnit,
      );
      if (presentation.severity == TemperatureSeverity.critical) {
        return TemperatureSeverity.critical;
      }
      if (presentation.severity == TemperatureSeverity.warning) {
        worst = TemperatureSeverity.warning;
      }
    }
    return worst;
  }

  String _statusText(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.critical:
        return 'Critical temperature detected';
      case TemperatureSeverity.warning:
        return 'Temperature warning';
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return 'All drives normal';
      case TemperatureSeverity.unavailable:
        return 'Scanning for devices...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = _overallSeverity();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SeverityStyle.of(severity, context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg0 : AppColors.lightBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              _AppLogo(),
              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DriveGuard',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          deviceCount == 0
                              ? 'No devices'
                              : '$deviceCount drive${deviceCount == 1 ? '' : 's'} · ${_statusText(severity)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              _ViewToggle(compact: compactView, onChanged: onToggleCompactView),
              const SizedBox(width: AppSpacing.xs),
              _HeaderIconButton(
                icon: monitoringEnabled
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: monitoringEnabled
                    ? 'Pause monitoring'
                    : 'Resume monitoring',
                onPressed: onToggleMonitoring,
                isActive: !monitoringEnabled,
              ),
              const SizedBox(width: AppSpacing.xs),
              _HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Rescan drives',
                onPressed: onRescan,
              ),
              const SizedBox(width: AppSpacing.xs),
              _HeaderIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: onOpenSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: const Icon(
        Icons.storage_rounded,
        color: AppColors.accent,
        size: 18,
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.compact, required this.onChanged});

  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewToggleButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Grid view',
            selected: !compact,
            onTap: () => onChanged(false),
          ),
          _ViewToggleButton(
            icon: Icons.view_list_rounded,
            tooltip: 'List view',
            selected: compact,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.bg3 : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected
                ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                : (isDark ? AppColors.textMuted : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : (isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isActive
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : (isDark ? AppColors.border : AppColors.lightBorder),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isActive
                  ? AppColors.accent
                  : (isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.devices, required this.settings});
  final List<StorageDevice> devices;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const _EmptyState();
    }

    return Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(settingsProvider);

        Widget entranceAnimated({required int index, required Widget child}) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 200 + index * 40),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 12),
                child: child,
              ),
            ),
            child: child,
          );
        }

        if (settings.dashboardCompactView) {
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: SliverList.separated(
                  itemCount: devices.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return entranceAnimated(
                      index: index,
                      child: KeyedSubtree(
                        key: ValueKey(device.id),
                        child: _CompactDriveRow(
                          device: device,
                          thresholds: settings.thresholdsFor(device.id),
                          unit: settings.temperatureUnit,
                          onTap: () => Navigator.of(context).push(
                            _slideRoute(
                              DeviceDetailsScreen(deviceId: device.id),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double cardWidth;
            if (width >= 1400) {
              cardWidth = 300;
            } else if (width >= 1000) {
              cardWidth = 280;
            } else if (width >= 650) {
              cardWidth = 260;
            } else {
              cardWidth = width - AppSpacing.lg * 2;
            }

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: cardWidth,
                      mainAxisExtent: 288,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final device = devices[index];
                      return entranceAnimated(
                        index: index,
                        child: KeyedSubtree(
                          key: ValueKey(device.id),
                          child: DriveCard(
                            device: device,
                            thresholds: settings.thresholdsFor(device.id),
                            unit: settings.temperatureUnit,
                            onTap: () => Navigator.of(context).push(
                              _slideRoute(
                                DeviceDetailsScreen(deviceId: device.id),
                              ),
                            ),
                          ),
                        ),
                      );
                    }, childCount: devices.length),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CompactDriveRow extends StatefulWidget {
  const _CompactDriveRow({
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
  State<_CompactDriveRow> createState() => _CompactDriveRowState();
}

class _CompactDriveRowState extends State<_CompactDriveRow> {
  bool _isHovered = false;

  String _typeLabel(StorageDeviceType type) {
    switch (type) {
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

  IconData _typeIcon(StorageDeviceType type) {
    switch (type) {
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
          '${widget.device.displayName}, ${_typeLabel(widget.device.type)}, ${style.label}, ${presentation.valueText}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? (_isHovered ? AppColors.bg2 : AppColors.bg1)
                    : (_isHovered
                          ? AppColors.lightSurfaceMuted
                          : AppColors.lightCard),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: _isHovered
                      ? (isDark ? AppColors.border : AppColors.lightBorder)
                      : (isDark ? AppColors.divider : AppColors.lightBorder),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: style.color.withValues(
                        alpha: isDark ? 0.12 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: style.color.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _typeIcon(widget.device.type),
                      size: 17,
                      color: style.color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.device.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: isDark
                                    ? AppColors.textPrimary
                                    : AppColors.lightText,
                              ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_typeLabel(widget.device.type)} · ${style.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  const SizedBox(width: AppSpacing.md),

                  TemperatureGauge(
                    valueText: presentation.valueText,
                    fraction: presentation.fraction,
                    severity: presentation.severity,
                    size: 44,
                    showLabel: false,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isDark ? AppColors.border : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.storage_rounded,
                size: 28,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Scanning for storage devices',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isDark ? AppColors.textPrimary : AppColors.lightText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'DriveGuard detects NVMe, SATA, and USB drives automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                backgroundColor: isDark ? AppColors.bg3 : AppColors.lightBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.accent,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
