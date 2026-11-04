part of '../device_details_screen.dart';

class _StorageTab extends ConsumerWidget {
  const _StorageTab({required this.device, required this.isDark});

  final StorageDevice device;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = device.capacity;
    final StorageActivity? activity = ref.watch(activityProvider)[device.id];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: 'Capacity', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (capacity.isValid)
            _CapacityBar(capacity: capacity, isDark: isDark)
          else
            _UnavailableNote(
              text:
                  'Capacity information is not available for this device yet.',
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Activity', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (activity != null)
            _HealthGrid(
              entries: [
                _HealthEntry(
                  label: 'Read Speed',
                  value: activity.readBytesPerSecond != null
                      ? _formatBytesPerSecond(activity.readBytesPerSecond!)
                      : '--',
                  icon: Icons.arrow_downward_rounded,
                  available: activity.readBytesPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Write Speed',
                  value: activity.writeBytesPerSecond != null
                      ? _formatBytesPerSecond(activity.writeBytesPerSecond!)
                      : '--',
                  icon: Icons.arrow_upward_rounded,
                  available: activity.writeBytesPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Read IOPS',
                  value: activity.readOperationsPerSecond != null
                      ? activity.readOperationsPerSecond!.toStringAsFixed(0)
                      : '--',
                  icon: Icons.speed_rounded,
                  available: activity.readOperationsPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Write IOPS',
                  value: activity.writeOperationsPerSecond != null
                      ? activity.writeOperationsPerSecond!.toStringAsFixed(0)
                      : '--',
                  icon: Icons.speed_rounded,
                  available: activity.writeOperationsPerSecond != null,
                ),
                _HealthEntry(
                  label: 'Utilization',
                  value: activity.utilizationPercent != null
                      ? '${activity.utilizationPercent!.toStringAsFixed(0)}%'
                      : '--',
                  icon: Icons.donut_large_rounded,
                  available: activity.utilizationPercent != null,
                ),
              ],
              isDark: isDark,
            )
          else
            _UnavailableNote(
              text:
                  'No activity samples yet. Real-time read/write activity '
                  'requires native platform support and appears once the '
                  'device has been active.',
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(title: 'Volumes', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          if (device.volumes.isEmpty)
            _UnavailableNote(
              text:
                  'No mounted volumes were detected on this device, or '
                  'volume enumeration is not supported on this platform.',
              isDark: isDark,
            )
          else
            Column(
              children: [
                for (final volume in device.volumes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _VolumeRow(volume: volume, isDark: isDark),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.capacity, required this.isDark});

  final StorageCapacity capacity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final usagePercent = capacity.usagePercent;
    final total = capacity.totalBytes;
    final used = capacity.usedBytes;
    final free = capacity.freeBytes;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                used != null && total != null
                    ? '${_formatBytes(used)} / ${_formatBytes(total)}'
                    : (total != null ? _formatBytes(total) : 'Unknown'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.lightText,
                ),
              ),
              if (capacity.usagePercent != null)
                Text(
                  '${capacity.usagePercent!.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (usagePercent != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: (usagePercent / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: isDark
                    ? AppColors.bg2
                    : AppColors.lightSurfaceMuted,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            )
          else
            Text(
              'Usage percentage unavailable',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
          if (free != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_formatBytes(free)} free',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.isDark});

  final StorageVolume volume;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final title = volume.volumeName?.trim().isNotEmpty == true
        ? volume.volumeName!
        : (volume.mountPoint ?? volume.id);
    final subtitleParts = <String>[
      if (volume.filesystem != null) volume.filesystem!,
      if (volume.mountPoint != null) volume.mountPoint!,
      if (volume.totalBytes != null) _formatBytes(volume.totalBytes!),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.md),
      child: Row(
        children: [
          IconBadge(
            icon: volume.isBootVolume
                ? Icons.laptop_mac_rounded
                : Icons.storage_rounded,
            color: isDark ? AppColors.textSecondary : AppColors.lightText,
            size: 32,
            iconSize: 16,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (volume.isBootVolume) _VolumeBadge(text: 'Boot', isDark: isDark),
          if (volume.isReadOnly) ...[
            const SizedBox(width: AppSpacing.xs),
            _VolumeBadge(text: 'Read-only', isDark: isDark),
          ],
        ],
      ),
    );
  }
}

class _VolumeBadge extends StatelessWidget {
  const _VolumeBadge({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppColors.textSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(isDark: isDark, radius: AppRadius.md),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}
