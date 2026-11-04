part of '../device_details_screen.dart';

class _TemperatureTab extends ConsumerWidget {
  const _TemperatureTab({
    required this.device,
    required this.windowLabel,
    required this.onWindowChanged,
    required this.thresholds,
    required this.unit,
    required this.isDark,
  });

  final StorageDevice device;
  final String windowLabel;
  final ValueChanged<String> onWindowChanged;
  final dynamic thresholds;
  final TemperatureUnit unit;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = _historyWindows[windowLabel]!;
    final historyStore = ref.watch(historyStoreProvider);
    final samples = historyStore.pointsFor(device.id, window);
    final stats = historyStore.statsFor(
      device.id,
      window,
      currentCelsius: device.primaryTemperature?.celsius,
    );
    final presentation = DevicePresentation.of(
      device,
      ref.watch(settingsProvider).thresholdsFor(device.id),
      unit,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats.isElevated) ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Temperature is higher than usual (+${TemperatureUtils.convertDelta(stats.elevationDelta, unit).toStringAsFixed(1)}${TemperatureUtils.unitSuffix(unit)} vs ${windowLabel.toLowerCase()} average)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _StatCard(
                      label: 'Current',
                      value: device.primaryTemperature != null
                          ? TemperatureUtils.format(
                              device.primaryTemperature!.celsius,
                              unit,
                            )
                          : 'N/A',
                      icon: Icons.thermostat_rounded,
                      isDark: isDark,
                      color:
                          presentation.severity ==
                              TemperatureSeverity.unavailable
                          ? AppColors.textMuted
                          : SeverityStyle.of(
                              presentation.severity,
                              context,
                            ).color,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Min',
                            value: stats.min != null
                                ? TemperatureUtils.format(stats.min!, unit)
                                : '--',
                            icon: Icons.arrow_downward_rounded,
                            isDark: isDark,
                            color: AppColors.normal,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _StatCard(
                            label: 'Max',
                            value: stats.max != null
                                ? TemperatureUtils.format(stats.max!, unit)
                                : '--',
                            icon: Icons.arrow_upward_rounded,
                            isDark: isDark,
                            color: AppColors.warning,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _StatCard(
                      label: 'Average',
                      value: stats.average != null
                          ? TemperatureUtils.format(stats.average!, unit)
                          : '--',
                      icon: Icons.show_chart_rounded,
                      isDark: isDark,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          if (device.primaryTemperature != null)
            _SourceRow(
              source: device.primaryTemperature!.source.toString(),
              timestamp: device.lastUpdated,
              isDark: isDark,
            ),

          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              _SectionLabel(title: 'Temperature History', isDark: isDark),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            device.monitoringStatus == MonitoringStatus.active
                            ? AppColors.normal
                            : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${samples.length} readings',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: _historyWindows.keys.map((label) {
              final selected = label == windowLabel;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onWindowChanged(label),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 4,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : (isDark ? AppColors.bg2 : AppColors.lightCard),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : (isDark
                                  ? AppColors.border
                                  : AppColors.lightBorder),
                        width: selected ? 1.5 : 1.0,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? Colors.white
                            : (isDark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),

          Container(
            decoration: AppDecorations.card(
              isDark: isDark,
              radius: AppRadius.lg,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: samples.length < 2
                ? _CollectingHistoryPlaceholder(
                    deviceId: device.id,
                    isDark: isDark,
                  )
                : _HistoryChart(
                    samples: samples,
                    thresholds: thresholds,
                    unit: unit,
                    isDark: isDark,
                    window: window,
                    windowLabel: windowLabel,
                    stats: stats,
                    currentCelsius: device.primaryTemperature?.celsius,
                  ),
          ),

          const SizedBox(height: AppSpacing.lg),

          _SectionLabel(title: 'Sensors', isDark: isDark),
          const SizedBox(height: AppSpacing.sm),
          _SensorsList(
            deviceId: device.id,
            unit: unit,
            isDark: isDark,
            isSpinDownRisk:
                device.type == StorageDeviceType.hdd || device.isRemovable,
          ),
        ],
      ),
    );
  }
}

class _CollectingHistoryPlaceholder extends ConsumerStatefulWidget {
  const _CollectingHistoryPlaceholder({
    required this.deviceId,
    required this.isDark,
  });

  final String deviceId;
  final bool isDark;

  @override
  ConsumerState<_CollectingHistoryPlaceholder> createState() =>
      _CollectingHistoryPlaceholderState();
}

class _CollectingHistoryPlaceholderState
    extends ConsumerState<_CollectingHistoryPlaceholder> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref
          .read(monitoringServiceProvider)
          .refreshNow(deviceId: widget.deviceId);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.show_chart_rounded,
                size: 24,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Collecting temperature history…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimary : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Readings will appear here as the drive is monitored',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(_refreshing ? 'Refreshing…' : 'Refresh now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return Container(
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: AppDecorations.card(
        isDark: isDark,
        radius: AppRadius.md,
        color: isDark ? AppColors.bg2 : AppColors.lightCard,
      ),
      child: compact
          ? Row(
              children: [
                Icon(icon, size: 13, color: effectiveColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 15, color: effectiveColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.textMuted
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: effectiveColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.timestamp,
    required this.isDark,
  });

  final String source;
  final DateTime? timestamp;
  final bool isDark;

  String _ago() {
    if (timestamp == null) return 'Never';
    final diff = DateTime.now().difference(timestamp!);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
        const SizedBox(width: 5),
        Text(
          'Source: $source',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Icon(
          Icons.schedule_rounded,
          size: 12,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          'Updated ${_ago()}',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textPrimary : AppColors.lightText,
      ),
    );
  }
}
