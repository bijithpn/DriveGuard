part of '../device_details_screen.dart';

class _SensorsList extends ConsumerStatefulWidget {
  const _SensorsList({
    required this.deviceId,
    required this.unit,
    required this.isDark,
    required this.isSpinDownRisk,
  });

  final String deviceId;
  final TemperatureUnit unit;
  final bool isDark;

  final bool isSpinDownRisk;

  @override
  ConsumerState<_SensorsList> createState() => _SensorsListState();
}

class _SensorsListState extends ConsumerState<_SensorsList> {
  Future<List<StorageSensor>>? _future;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();

    if (!widget.isSpinDownRisk) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _load(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _SensorsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) _load();
  }

  void _load() {
    setState(() {
      _future = ref.read(storageMonitorProvider).getSensors(widget.deviceId);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StorageSensor>>(
      future: _future,
      builder: (context, snapshot) {
        final sensors = snapshot.data ?? const [];
        if (sensors.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: AppDecorations.card(
              isDark: widget.isDark,
              radius: AppRadius.md,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.thermostat_outlined,
                  size: 18,
                  color: widget.isDark
                      ? AppColors.textMuted
                      : AppColors.lightTextSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'No additional sensor detail available.',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isDark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: AppDecorations.card(
            isDark: widget.isDark,
            radius: AppRadius.md,
          ),
          child: Column(
            children: sensors.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              final isLast = index == sensors.length - 1;
              final tempText = s.reading != null
                  ? TemperatureUtils.format(s.reading!.celsius, widget.unit)
                  : '--';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          s.isPrimary
                              ? Icons.radio_button_checked_rounded
                              : Icons.thermostat_rounded,
                          size: 15,
                          color: s.isPrimary
                              ? AppColors.accent
                              : (widget.isDark
                                    ? AppColors.textMuted
                                    : AppColors.lightTextSecondary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? AppColors.textPrimary
                                  : AppColors.lightText,
                            ),
                          ),
                        ),
                        if (s.isPrimary)
                          Container(
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppRadius.sm - 2,
                              ),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Text(
                              'Primary',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          tempText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? AppColors.textPrimary
                                : AppColors.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: widget.isDark
                          ? AppColors.divider
                          : AppColors.lightBorder,
                    ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
