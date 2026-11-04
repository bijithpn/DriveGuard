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
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoSection(
            title: 'Capacity',
            child: capacity.isValid
                ? _CapacityCard(capacity: capacity, device: device)
                : const _UnavailableNote(
                    text:
                        'Capacity information is not available for this device yet.',
                  ),
          ),
          const SizedBox(height: AppSpacing.section),
          InfoSection(
            title: 'Activity',
            caption: activity == null ? null : 'Live read and write throughput',
            child: activity == null
                ? const _UnavailableNote(
                    text:
                        'No activity samples yet. Live read/write activity appears '
                        'once the drive has been active.',
                  )
                : _ActivityCard(activity: activity),
          ),
          const SizedBox(height: AppSpacing.section),
          InfoSection(
            title: 'Volumes',
            caption: device.volumes.isEmpty
                ? null
                : '${device.volumes.length} mounted',
            child: device.volumes.isEmpty
                ? const _UnavailableNote(
                    text:
                        'No mounted volumes were detected on this device, or volume '
                        'enumeration is not supported on this platform.',
                  )
                : Surface(
                    padding: EdgeInsets.zero,
                    clip: true,
                    child: Column(
                      children: [
                        for (var i = 0; i < device.volumes.length; i++)
                          _VolumeRow(volume: device.volumes[i], first: i == 0),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

Color _usageColor(double percent) {
  if (percent >= 95) return AppColors.critical;
  if (percent >= 85) return AppColors.warning;
  return AppColors.accent;
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.percent, this.height = 8});
  final double percent;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: isDarkOf(context) ? AppColors.bg3 : AppColors.lightBorder,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              heightFactor: 1,
              widthFactor: (percent / 100).clamp(0.0, 1.0),
              child: ColoredBox(color: _usageColor(percent)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.capacity, required this.device});

  final StorageCapacity capacity;
  final StorageDevice device;

  @override
  Widget build(BuildContext context) {
    final total = capacity.totalBytes;
    final used = capacity.usedBytes;
    final free = capacity.freeBytes;
    final percent = capacity.usagePercent;
    final isSsd =
        device.type == StorageDeviceType.ssd ||
        device.type == StorageDeviceType.nvme;
    final lowFree = percent != null && percent >= 85;

    return Surface(
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                used != null ? _formatBytes(used) : '--',
                style: AppText.metric(context, size: 30),
              ),
              const SizedBox(width: 8),
              Text(
                total != null ? 'used of ${_formatBytes(total)}' : 'used',
                style: AppText.secondary(context),
              ),
              const Spacer(),
              if (percent != null)
                Text(
                  '${percent.toStringAsFixed(0)}%',
                  style: AppText.heading(
                    context,
                  ).copyWith(color: _usageColor(percent), fontSize: 16),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (percent != null) _UsageBar(percent: percent),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Legend(
                color: percent == null
                    ? faintOf(context)
                    : _usageColor(percent),
                label: 'Used',
                value: used != null ? _formatBytes(used) : '--',
              ),
              const SizedBox(width: AppSpacing.lg),
              _Legend(
                color: isDarkOf(context)
                    ? AppColors.bg3
                    : AppColors.lightBorder,
                label: 'Free',
                value: free != null ? _formatBytes(free) : '--',
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    goToSection(Navigator.of(context), AppSection.storage),
                icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('Free up space'),
              ),
            ],
          ),
          if (isSsd && lowFree) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This SSD is getting full. Nearly full SSDs run hotter and wear '
              'faster — aim to keep 15–20% free.',
              style: AppText.secondary(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(color, size: 9),
      const SizedBox(width: 8),
      Text('$label  ', style: AppText.secondary(context)),
      Text(
        value,
        style: AppText.body(context).copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});
  final StorageActivity activity;

  String _rate(double? v) => v == null ? '--' : _formatBytesPerSecond(v);

  @override
  Widget build(BuildContext context) {
    Widget half(IconData icon, String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: faintOf(context)),
                const SizedBox(width: 6),
                Text(label, style: AppText.caption(context)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: AppText.metric(context, size: 24)),
          ],
        ),
      ),
    );

    return Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.card),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  half(
                    Icons.arrow_downward_rounded,
                    'Read',
                    _rate(activity.readBytesPerSecond),
                  ),
                  VerticalDivider(width: 1, color: hairlineOf(context)),
                  half(
                    Icons.arrow_upward_rounded,
                    'Write',
                    _rate(activity.writeBytesPerSecond),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: hairlineOf(context)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.card,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                KeyValueRow(
                  'Read operations',
                  activity.readOperationsPerSecond == null
                      ? '--'
                      : '${activity.readOperationsPerSecond!.toStringAsFixed(0)} IOPS',
                ),
                KeyValueRow(
                  'Write operations',
                  activity.writeOperationsPerSecond == null
                      ? '--'
                      : '${activity.writeOperationsPerSecond!.toStringAsFixed(0)} IOPS',
                ),
                KeyValueRow(
                  'Utilization',
                  activity.utilizationPercent == null
                      ? '--'
                      : '${activity.utilizationPercent!.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.first});

  final StorageVolume volume;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final title = volume.volumeName?.trim().isNotEmpty == true
        ? volume.volumeName!
        : (volume.mountPoint ?? volume.id);
    final sub = [?volume.filesystem, ?volume.mountPoint].join('  ·  ');
    final tags = [
      if (volume.isBootVolume) 'Boot',
      if (volume.isReadOnly) 'Read-only',
      if (volume.isEncrypted == true) 'Encrypted',
    ];
    final percent = volume.usagePercent;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: hairlineOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                volume.isBootVolume
                    ? Icons.laptop_mac_rounded
                    : Icons.storage_rounded,
                size: 18,
                color: mutedOf(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.heading(context),
                          ),
                        ),
                        for (final t in tags) ...[
                          const SizedBox(width: 10),
                          Text(t, style: AppText.caption(context)),
                        ],
                      ],
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(context),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (volume.totalBytes != null)
                Text(
                  volume.usedBytes != null
                      ? '${_formatBytes(volume.usedBytes!)} / ${_formatBytes(volume.totalBytes!)}'
                      : _formatBytes(volume.totalBytes!),
                  style: AppText.body(context).copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: _UsageBar(percent: percent, height: 5),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Surface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: faintOf(context)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: AppText.secondary(context))),
      ],
    ),
  );
}
