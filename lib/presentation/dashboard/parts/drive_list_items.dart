part of '../dashboard_screen.dart';

class _DriveScrollBody extends StatelessWidget {
  const _DriveScrollBody({
    required this.ids,
    required this.settings,
    required this.isDark,
    required this.compactView,
    required this.onOpenDevice,
  });

  final List<String> ids;
  final dynamic settings;
  final bool isDark;
  final bool compactView;
  final ValueChanged<String> onOpenDevice;

  @override
  Widget build(BuildContext context) {
    if (compactView) {
      return _DriveListView(
        ids: ids,
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
                  final id = ids[index];
                  return KeyedSubtree(
                    key: ValueKey(id),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final device = ref.watch(deviceProvider(id));
                        if (device == null) return const SizedBox.shrink();
                        return RepaintBoundary(
                          child: DriveCard(
                            device: device,
                            thresholds: settings.thresholdsFor(device.id),
                            unit: settings.temperatureUnit,
                            onTap: () => onOpenDevice(device.id),
                          ),
                        );
                      },
                    ),
                  );
                }, childCount: ids.length),
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
    required this.ids,
    required this.settings,
    required this.isDark,
    required this.onOpenDevice,
  });

  final List<String> ids;
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
            itemCount: ids.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final id = ids[index];
              return KeyedSubtree(
                key: ValueKey(id),
                child: Consumer(
                  builder: (context, ref, _) {
                    final device = ref.watch(deviceProvider(id));
                    if (device == null) return const SizedBox.shrink();
                    return _DriveListItem(
                      device: device,
                      thresholds: settings.thresholdsFor(device.id),
                      unit: settings.temperatureUnit,
                      isDark: isDark,
                      onTap: () => onOpenDevice(device.id),
                    );
                  },
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
                boxShadow: [
                  BoxShadow(
                    color: widget.isDark
                        ? AppColors.shadowDark
                        : AppColors.lightShadow,
                    blurRadius: _hovered ? 16 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
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
