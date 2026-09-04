import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../app_root.dart' show widgetModeActiveProvider;
import '../components/device_presentation.dart';
import '../components/drive_card.dart';

import '../device_details/device_details_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final settings = ref.watch(settingsProvider);
    final monitoringService = ref.watch(monitoringServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            devices: devices,
            settings: settings,
            isDark: isDark,
            monitoringEnabled: settings.monitoringEnabled,
            onToggleMonitoring: () => ref
                .read(settingsProvider.notifier)
                .updateWith(
                  (s) => s.copyWith(monitoringEnabled: !s.monitoringEnabled),
                ),
            onRescan: monitoringService.rescan,
            onOpenSettings: () =>
                Navigator.of(context).push(_slideRoute(const SettingsScreen())),
          ),

          Expanded(
            child: _DriveListPane(
              devices: devices,
              settings: settings,
              isDark: isDark,
              onOpenDevice: (deviceId) => Navigator.of(
                context,
              ).push(_slideRoute(DeviceDetailsScreen(deviceId: deviceId))),
              onToggleCompactView: (value) => ref
                  .read(settingsProvider.notifier)
                  .updateWith((s) => s.copyWith(dashboardCompactView: value)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.devices,
    required this.settings,
    required this.isDark,
    required this.monitoringEnabled,
    required this.onToggleMonitoring,
    required this.onRescan,
    required this.onOpenSettings,
  });

  final List<StorageDevice> devices;
  final dynamic settings;
  final bool isDark;
  final bool monitoringEnabled;
  final VoidCallback onToggleMonitoring;
  final VoidCallback onRescan;
  final VoidCallback onOpenSettings;

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

  String _overallStatusText(TemperatureSeverity severity) {
    final count = devices.length;
    if (count == 0) return 'No drives found';
    switch (severity) {
      case TemperatureSeverity.critical:
        return '$count drive${count == 1 ? '' : 's'} — critical';
      case TemperatureSeverity.warning:
        return '$count drive${count == 1 ? '' : 's'} — warning';
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return '$count drive${count == 1 ? '' : 's'} normal';
      case TemperatureSeverity.unavailable:
        return 'Scanning…';
    }
  }

  Color _severityColor(TemperatureSeverity severity, BuildContext context) {
    switch (severity) {
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return AppColors.normal;
      case TemperatureSeverity.warning:
        return AppColors.warning;
      case TemperatureSeverity.critical:
        return AppColors.critical;
      case TemperatureSeverity.unavailable:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = _overallSeverity();
    final statusColor = _severityColor(severity, context);
    final statusText = _overallStatusText(severity);

    return Container(
      width: AppLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sidebarPad,
              AppSpacing.md,
              AppSpacing.sidebarPad,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(
                      alpha: isDark ? 0.15 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.30),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    color: AppColors.accent,
                    size: 14,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(
                  'DriveGuard',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                    letterSpacing: -0.1,
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

          const SizedBox(height: AppSpacing.xs),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
            child: _SidebarNavItem(
              icon: Icons.storage_rounded,
              label: 'Drives',
              selected: true,
              isDark: isDark,
              onTap: () {},
            ),
          ),

          const Spacer(),

          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sidebarPad,
              AppSpacing.sm,
              AppSpacing.sidebarPad,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs + 2,
              AppSpacing.xxs,
              AppSpacing.xs + 2,
              AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _SidebarIconButton(
                  icon: monitoringEnabled
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  tooltip: monitoringEnabled
                      ? 'Pause monitoring'
                      : 'Resume monitoring',
                  isActive: !monitoringEnabled,
                  isDark: isDark,
                  onPressed: onToggleMonitoring,
                ),
                const SizedBox(width: AppSpacing.xxs),
                _SidebarIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Rescan drives',
                  isDark: isDark,
                  onPressed: onRescan,
                ),
                const SizedBox(width: AppSpacing.xxs),
                _SidebarIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  isDark: isDark,
                  onPressed: onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.selected || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sidebarPad - 2,
          ),
          decoration: widget.selected
              ? AppDecorations.sidebarItem(
                  selected: true,
                  isDark: widget.isDark,
                )
              : BoxDecoration(
                  color: _hovered
                      ? AppColors.accent.withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.selected
                    ? AppColors.accent
                    : (isHighlighted
                          ? (widget.isDark
                                ? AppColors.textPrimary
                                : AppColors.lightText)
                          : (widget.isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary)),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: widget.selected
                      ? AppColors.accent
                      : (widget.isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: isActive
                  ? Border.all(
                      color: AppColors.accent.withValues(alpha: 0.30),
                      width: 1,
                    )
                  : null,
            ),
            child: Icon(
              icon,
              size: 15,
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

class _DriveListPane extends StatelessWidget {
  const _DriveListPane({
    required this.devices,
    required this.settings,
    required this.isDark,
    required this.onOpenDevice,
    required this.onToggleCompactView,
  });

  final List<StorageDevice> devices;
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
        _DriveListToolbar(
          deviceCount: devices.length,
          compactView: compactView,
          isDark: isDark,
          onToggleCompactView: onToggleCompactView,
        ),

        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? AppColors.divider : AppColors.lightBorder,
        ),

        Expanded(
          child: devices.isEmpty
              ? const _EmptyState()
              : _DriveScrollBody(
                  devices: devices,
                  settings: settings,
                  isDark: isDark,
                  compactView: compactView,
                  onOpenDevice: onOpenDevice,
                ),
        ),
      ],
    );
  }
}

class _DriveListToolbar extends StatelessWidget {
  const _DriveListToolbar({
    required this.deviceCount,
    required this.compactView,
    required this.isDark,
    required this.onToggleCompactView,
  });

  final int deviceCount;
  final bool compactView;
  final bool isDark;
  final ValueChanged<bool> onToggleCompactView;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: isDark ? AppColors.bg0 : AppColors.lightBg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Storage Devices',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimary : AppColors.lightText,
              letterSpacing: -0.1,
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          if (deviceCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isDark ? AppColors.border : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              child: Text(
                '$deviceCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),

          const Spacer(),

          Consumer(
            builder: (context, ref, _) {
              final isWidgetActive = ref.watch(widgetModeActiveProvider);
              return Container(
                margin: const EdgeInsets.only(right: 8),
                height: 26,
                child: Tooltip(
                  message: isWidgetActive
                      ? 'Close Mini Widget'
                      : 'Open Mini Widget (HUD)',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: isWidgetActive
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      side: BorderSide(
                        color: isWidgetActive
                            ? AppColors.accent.withValues(alpha: 0.6)
                            : (isDark
                                  ? AppColors.border
                                  : AppColors.lightBorder),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: Icon(
                      Icons.picture_in_picture_alt_rounded,
                      size: 13,
                      color: isWidgetActive
                          ? AppColors.accent
                          : (isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary),
                    ),
                    label: Text(
                      'Widget',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isWidgetActive
                            ? AppColors.accent
                            : (isDark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary),
                      ),
                    ),
                    onPressed: () {
                      ref
                          .read(settingsProvider.notifier)
                          .updateWith(
                            (s) => s.copyWith(
                              widget: s.widget.copyWith(
                                enabled: !isWidgetActive,
                              ),
                            ),
                          );
                    },
                  ),
                ),
              );
            },
          ),

          _ViewToggleSegment(
            compactView: compactView,
            isDark: isDark,
            onToggle: onToggleCompactView,
          ),
        ],
      ),
    );
  }
}

class _ViewToggleSegment extends StatelessWidget {
  const _ViewToggleSegment({
    required this.compactView,
    required this.isDark,
    required this.onToggle,
  });

  final bool compactView;
  final bool isDark;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
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
          _SegmentButton(
            icon: Icons.grid_view_rounded,
            tooltip: 'Grid view',
            selected: !compactView,
            isDark: isDark,
            onTap: () => onToggle(false),
          ),
          _SegmentButton(
            icon: Icons.view_list_rounded,
            tooltip: 'List view',
            selected: compactView,
            isDark: isDark,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.bg3 : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          ),
          child: Icon(
            icon,
            size: 13,
            color: selected
                ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                : (isDark ? AppColors.textMuted : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }
}

class _DriveScrollBody extends StatelessWidget {
  const _DriveScrollBody({
    required this.devices,
    required this.settings,
    required this.isDark,
    required this.compactView,
    required this.onOpenDevice,
  });

  final List<StorageDevice> devices;
  final dynamic settings;
  final bool isDark;
  final bool compactView;
  final ValueChanged<String> onOpenDevice;

  @override
  Widget build(BuildContext context) {
    if (compactView) {
      return _DriveListView(
        devices: devices,
        settings: settings,
        isDark: isDark,
        onOpenDevice: onOpenDevice,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final double cardWidth;
        if (width >= 1400) {
          cardWidth = 360;
        } else if (width >= 1000) {
          cardWidth = 340;
        } else if (width >= 650) {
          cardWidth = 320;
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
                  mainAxisExtent: 242,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final device = devices[index];
                  return KeyedSubtree(
                    key: ValueKey(device.id),
                    child: DriveCard(
                      device: device,
                      thresholds: settings.thresholdsFor(device.id),
                      unit: settings.temperatureUnit,
                      onTap: () => onOpenDevice(device.id),
                    ),
                  );
                }, childCount: devices.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DriveListView extends StatelessWidget {
  const _DriveListView({
    required this.devices,
    required this.settings,
    required this.isDark,
    required this.onOpenDevice,
  });

  final List<StorageDevice> devices;
  final dynamic settings;
  final bool isDark;
  final ValueChanged<String> onOpenDevice;

  @override
  Widget build(BuildContext context) {
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
              return KeyedSubtree(
                key: ValueKey(device.id),
                child: _DriveListItem(
                  device: device,
                  thresholds: settings.thresholdsFor(device.id),
                  unit: settings.temperatureUnit,
                  isDark: isDark,
                  onTap: () => onOpenDevice(device.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DriveListItem extends StatefulWidget {
  const _DriveListItem({
    required this.device,
    required this.thresholds,
    required this.unit,
    required this.isDark,
    required this.onTap,
  });

  final StorageDevice device;
  final TemperatureThresholds thresholds;
  final TemperatureUnit unit;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_DriveListItem> createState() => _DriveListItemState();
}

class _DriveListItemState extends State<_DriveListItem> {
  bool _hovered = false;

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

    return Semantics(
      button: true,
      label:
          '${widget.device.displayName}, '
          '${_typeLabel(widget.device.type)}, '
          '${style.label}, '
          '${presentation.valueText}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
                color: widget.isDark
                    ? (_hovered ? AppColors.bg2 : AppColors.bg1)
                    : (_hovered
                          ? AppColors.lightSurfaceMuted
                          : AppColors.lightCard),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: _hovered
                      ? (widget.isDark
                            ? AppColors.border
                            : AppColors.lightBorder)
                      : (widget.isDark
                            ? AppColors.divider
                            : AppColors.lightBorder),
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
                        alpha: widget.isDark ? 0.12 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: style.color.withValues(alpha: 0.20),
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.device.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? AppColors.textPrimary
                                : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_typeLabel(widget.device.type)} · ${style.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: widget.isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),

                  if (widget.device.capacity.isValid &&
                      widget.device.capacity.freeBytes != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? AppColors.bg0.withValues(alpha: 0.5)
                            : AppColors.lightSurfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: widget.isDark
                              ? AppColors.border.withValues(alpha: 0.6)
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.pie_chart_outline_rounded,
                            size: 11,
                            color: widget.isDark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(widget.device.capacity.freeBytes! / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB free',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: style.color.withValues(
                        alpha: widget.isDark ? 0.12 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: style.color.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      presentation.valueText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: style.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),

                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: widget.isDark
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
              width: 48,
              height: 48,
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
                size: 24,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No storage devices found',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimary : AppColors.lightText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'DriveGuard detects NVMe, SATA, and USB drives automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
