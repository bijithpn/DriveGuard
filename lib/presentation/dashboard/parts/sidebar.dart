part of '../dashboard_screen.dart';

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.devices,
    required this.settings,
    required this.isDark,
    required this.monitoringEnabled,
    required this.onToggleMonitoring,
    required this.onRescan,
    required this.onOpenSettings,
    required this.onOpenIncidents,
    required this.onOpenStorageSense,
  });

  final List<StorageDevice> devices;
  final dynamic settings;
  final bool isDark;
  final bool monitoringEnabled;
  final VoidCallback onToggleMonitoring;
  final VoidCallback onRescan;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenIncidents;
  final VoidCallback onOpenStorageSense;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs + 2,
              AppSpacing.xxs,
              AppSpacing.xs + 2,
              0,
            ),
            child: _SidebarNavItem(
              icon: Icons.cleaning_services_rounded,
              label: 'Storage Sense',
              selected: false,
              isDark: isDark,
              onTap: onOpenStorageSense,
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
                  icon: Icons.history_rounded,
                  tooltip: 'Incident history',
                  isDark: isDark,
                  onPressed: onOpenIncidents,
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
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
