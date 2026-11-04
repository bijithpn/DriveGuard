part of '../dashboard_screen.dart';

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
