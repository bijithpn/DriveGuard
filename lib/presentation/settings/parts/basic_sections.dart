part of '../settings_screen.dart';

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final rows = [
      _SettingRow(
        label: 'Start with OS',
        subtitle: 'Launch DriveGuard automatically at login',
        isDark: isDark,
        trailing: Switch(
          value: settings.startWithOS,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(startWithOS: v)),
        ),
      ),
      _SettingRow(
        label: 'Start minimized',
        isDark: isDark,
        trailing: Switch(
          value: settings.startMinimized,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(startMinimized: v)),
        ),
      ),
      _SettingRow(
        label: 'System tray icon',
        subtitle:
            'Show temperature and quick menu in the system tray / menu bar',
        isDark: isDark,
        trailing: Switch(
          value: settings.showTrayIcon,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(showTrayIcon: v)),
        ),
      ),
      _SettingRow(
        label: 'Minimize to tray',
        isDark: isDark,
        trailing: Switch(
          value: settings.minimizeToTray && settings.showTrayIcon,
          onChanged: settings.showTrayIcon
              ? (v) => notifier.updateWith((s) => s.copyWith(minimizeToTray: v))
              : null,
        ),
      ),
      _SettingRow(
        label: 'Close to tray',
        subtitle: 'Closing the window keeps DriveGuard running in the tray',
        isDark: isDark,
        isLast: true,
        trailing: Switch(
          value: settings.closeToTray && settings.showTrayIcon,
          onChanged: settings.showTrayIcon
              ? (v) => notifier.updateWith((s) => s.copyWith(closeToTray: v))
              : null,
        ),
      ),
    ];

    return _SectionGroup(isDark: isDark, children: rows);
  }
}

class _MonitoringSection extends ConsumerWidget {
  const _MonitoringSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final rows = [
      _SettingRow(
        label: 'Polling interval',
        isDark: isDark,
        trailing: _NativeDropdown<Duration>(
          value: settings.pollingInterval,
          items: AppConstants.allowedPollingIntervals
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    '${d.inSeconds}s',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              notifier.updateWith((s) => s.copyWith(pollingInterval: v));
            }
          },
          isDark: isDark,
        ),
      ),
      _SettingRow(
        label: 'Temperature unit',
        isDark: isDark,
        trailing: _SegmentedControl<TemperatureUnit>(
          options: const [
            (TemperatureUnit.celsius, 'C'),
            (TemperatureUnit.fahrenheit, 'F'),
          ],
          selected: settings.temperatureUnit,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(temperatureUnit: v)),
          isDark: isDark,
        ),
      ),
      _SettingRow(
        label: 'Health/SMART polling interval',
        subtitle: 'How often wear, power-on hours, etc. are refreshed',
        isDark: isDark,
        trailing: _NativeDropdown<Duration>(
          value: settings.healthPollingInterval,
          items: AppConstants.allowedHealthPollingIntervals
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    d.inSeconds < 60 ? '${d.inSeconds}s' : '${d.inMinutes}m',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              notifier.updateWith((s) => s.copyWith(healthPollingInterval: v));
            }
          },
          isDark: isDark,
        ),
      ),
      _SettingRow(
        label: 'Enable monitoring',
        isDark: isDark,
        isLast: true,
        trailing: Switch(
          value: settings.monitoringEnabled,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(monitoringEnabled: v)),
        ),
      ),
    ];

    return _SectionGroup(isDark: isDark, children: rows);
  }
}

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final rows = [
      _SettingRow(
        label: 'Enable notifications',
        isDark: isDark,
        trailing: Switch(
          value: settings.notificationsEnabled,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(notificationsEnabled: v)),
        ),
      ),
      _SettingRow(
        label: 'Warning threshold',
        isDark: isDark,
        trailing: _ThresholdField(
          key: ValueKey('warning-${settings.globalThresholds.warningCelsius}'),
          value: settings.globalThresholds.warningCelsius,
          color: AppColors.warning,
          onSubmit: (v) => _submitThreshold(
            context,
            notifier,
            current: settings.globalThresholds,
            rawValue: v,
            isWarningField: true,
            apply: (s, updated) => s.copyWith(globalThresholds: updated),
          ),
        ),
      ),
      _SettingRow(
        label: 'Critical threshold',
        isDark: isDark,
        trailing: _ThresholdField(
          key: ValueKey(
            'critical-${settings.globalThresholds.criticalCelsius}',
          ),
          value: settings.globalThresholds.criticalCelsius,
          color: AppColors.critical,
          onSubmit: (v) => _submitThreshold(
            context,
            notifier,
            current: settings.globalThresholds,
            rawValue: v,
            isWarningField: false,
            apply: (s, updated) => s.copyWith(globalThresholds: updated),
          ),
        ),
      ),
      _SettingRow(
        label: 'Rapid temperature rise alerts',
        subtitle: 'Notify on a sudden spike, even below the warning threshold',
        isDark: isDark,
        trailing: Switch(
          value: settings.rapidRiseAlertsEnabled,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(rapidRiseAlertsEnabled: v)),
        ),
      ),
      _SettingRow(
        label: 'Rapid rise delta',
        subtitle: 'Degrees within the rise window to trigger an alert',
        isDark: isDark,
        trailing: _ThresholdField(
          key: ValueKey('rapid-rise-${settings.rapidRiseDeltaCelsius}'),
          value: settings.rapidRiseDeltaCelsius,
          color: AppColors.warning,
          onSubmit: (v) => _submitRapidRiseDelta(context, notifier, v),
        ),
      ),
      _SettingRow(
        label: 'Rapid rise window',
        subtitle: 'Time span the delta above is measured over',
        isDark: isDark,
        trailing: _NativeDropdown<Duration>(
          value: settings.rapidRiseWindow,
          items: AppConstants.allowedRapidRiseWindows
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    '${d.inMinutes} min',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              notifier.updateWith((s) => s.copyWith(rapidRiseWindow: v));
            }
          },
          isDark: isDark,
        ),
      ),
      _SettingRow(
        label: 'Health/SMART alerts',
        subtitle:
            'Notify on a health downgrade, wear jump, or new media errors',
        isDark: isDark,
        trailing: Switch(
          value: settings.healthAlertsEnabled,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(healthAlertsEnabled: v)),
        ),
      ),
      _SettingRow(
        label: 'Predictive early warnings',
        subtitle:
            'Warn ahead of a threshold breach based on the recent trend '
            '(temperature, storage, and drive wear)',
        isDark: isDark,
        trailing: Switch(
          value: settings.predictiveAlertsEnabled,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(predictiveAlertsEnabled: v),
          ),
        ),
      ),
      _SettingRow(
        label: 'Notification cooldown',
        isDark: isDark,
        trailing: _NativeDropdown<Duration>(
          value: settings.notificationCooldown,
          items: AppConstants.allowedNotificationCooldowns
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} hr',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              notifier.updateWith((s) => s.copyWith(notificationCooldown: v));
            }
          },
          isDark: isDark,
        ),
      ),
      _SettingRow(
        label: 'Recovery notifications',
        subtitle: 'Notify when a drive returns to normal temperature',
        isDark: isDark,
        trailing: Switch(
          value: settings.recoveryNotificationsEnabled,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(recoveryNotificationsEnabled: v),
          ),
        ),
      ),
      _SettingRow(
        label: 'Low disk space alerts',
        subtitle: 'Notify when a volume runs low on free space',
        isDark: isDark,
        trailing: Switch(
          value: settings.storageAlertsEnabled,
          onChanged: (v) =>
              notifier.updateWith((s) => s.copyWith(storageAlertsEnabled: v)),
        ),
      ),
      _SettingRow(
        label: 'Disk warning threshold',
        isDark: isDark,
        trailing: _ThresholdField(
          key: ValueKey(
            'storage-warning-${settings.storageThresholds.warningPercent}',
          ),
          value: settings.storageThresholds.warningPercent,
          color: AppColors.warning,
          suffixText: '%',
          onSubmit: (v) => _submitStorageThreshold(
            context,
            notifier,
            current: settings.storageThresholds,
            rawValue: v,
            isWarningField: true,
          ),
        ),
      ),
      _SettingRow(
        label: 'Disk critical threshold',
        isDark: isDark,
        isLast: true,
        trailing: _ThresholdField(
          key: ValueKey(
            'storage-critical-${settings.storageThresholds.criticalPercent}',
          ),
          value: settings.storageThresholds.criticalPercent,
          color: AppColors.critical,
          suffixText: '%',
          onSubmit: (v) => _submitStorageThreshold(
            context,
            notifier,
            current: settings.storageThresholds,
            rawValue: v,
            isWarningField: false,
          ),
        ),
      ),
    ];

    return _SectionGroup(isDark: isDark, children: rows);
  }
}

class _ThresholdsSection extends ConsumerWidget {
  const _ThresholdsSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final devices = ref.watch(devicesProvider);

    if (devices.isEmpty) {
      return _SectionGroup(
        isDark: isDark,
        children: [
          _SettingRow(
            label: 'No devices detected yet',
            subtitle:
                'Per-device overrides will appear here once drives are found.',
            isDark: isDark,
            isLast: true,
          ),
        ],
      );
    }

    final rows = List.generate(devices.length, (i) {
      final d = devices[i];
      final tempOverride = settings.perDeviceThresholds[d.id];
      final storageOverride = settings.perDeviceStorageThresholds[d.id];
      final rapidRiseOverride = settings.perDeviceRapidRiseDelta[d.id];
      final hasOverride =
          tempOverride != null ||
          storageOverride != null ||
          rapidRiseOverride != null;
      final isLast = i == devices.length - 1;

      final subtitleParts = <String>[
        if (tempOverride != null)
          'temp ${tempOverride.warningCelsius.toStringAsFixed(0)}°/${tempOverride.criticalCelsius.toStringAsFixed(0)}°',
        if (storageOverride != null)
          'disk ${storageOverride.warningPercent.toStringAsFixed(0)}%/${storageOverride.criticalPercent.toStringAsFixed(0)}%',
        if (rapidRiseOverride != null)
          'rise +${rapidRiseOverride.toStringAsFixed(0)}°',
      ];

      return _SettingRow(
        label: d.displayName,
        subtitle: hasOverride
            ? 'Custom: ${subtitleParts.join(' · ')}'
            : 'Using global defaults',
        isDark: isDark,
        isLast: isLast,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallButton(
              label: hasOverride ? 'Edit' : 'Override',
              onTap: () => _editDeviceThresholds(
                context,
                notifier,
                deviceId: d.id,
                settings: settings,
              ),
              isDark: isDark,
              useAccent: true,
            ),
            if (hasOverride) ...[
              const SizedBox(width: AppSpacing.xs),
              _SmallButton(
                label: 'Reset',
                onTap: () {
                  final temp = Map.of(settings.perDeviceThresholds)
                    ..remove(d.id);
                  final storage = Map.of(settings.perDeviceStorageThresholds)
                    ..remove(d.id);
                  final rapidRise = Map.of(settings.perDeviceRapidRiseDelta)
                    ..remove(d.id);
                  notifier.updateWith(
                    (s) => s.copyWith(
                      perDeviceThresholds: temp,
                      perDeviceStorageThresholds: storage,
                      perDeviceRapidRiseDelta: rapidRise,
                    ),
                  );
                },
                isDark: isDark,
              ),
            ],
          ],
        ),
      );
    });

    return _SectionGroup(isDark: isDark, children: rows);
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _SectionGroup(
      isDark: isDark,
      children: [
        _SettingRow(
          label: 'Theme',
          isDark: isDark,
          isLast: true,
          trailing: _SegmentedControl<ThemeMode>(
            options: const [
              (ThemeMode.system, 'System'),
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ],
            selected: settings.themeMode,
            onChanged: (v) =>
                notifier.updateWith((s) => s.copyWith(themeMode: v)),
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _ProtectionSection extends ConsumerWidget {
  const _ProtectionSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cfg = settings.thermalProtection;
    void update(
      ThermalProtectionSettings Function(ThermalProtectionSettings) f,
    ) => notifier.updateWith(
      (s) => s.copyWith(thermalProtection: f(s.thermalProtection)),
    );

    final minLimit = settings.globalThresholds.criticalCelsius;
    final limits = <double>{
      for (final v in const [70.0, 72.0, 75.0, 78.0, 80.0, 85.0])
        if (v >= minLimit) v,
      cfg.emergencyCelsius,
    }.toList()..sort();

    TextStyle label() =>
        TextStyle(color: isDark ? AppColors.textPrimary : AppColors.lightText);

    return _SectionGroup(
      isDark: isDark,
      children: [
        _SettingRow(
          label: 'Overheat protection',
          subtitle:
              'Detects sustained or fast-rising heat, finds the cause and '
              'alerts you before the drive is damaged',
          isDark: isDark,
          trailing: Switch(
            value: cfg.enabled,
            onChanged: (v) => update((c) => c.copyWith(enabled: v)),
          ),
        ),
        _SettingRow(
          label: 'Memory & write protection',
          subtitle:
              'Warns when low memory (swapping) or heavy sustained writes are '
              'wearing the SSD, and names the app responsible',
          isDark: isDark,
          trailing: Switch(
            value: settings.resourceGuardEnabled,
            onChanged: (v) =>
                notifier.updateWith((s) => s.copyWith(resourceGuardEnabled: v)),
          ),
        ),
        _SettingRow(
          label: 'Shut down automatically',
          subtitle:
              'Off by default. When on, the computer shuts down after a '
              'countdown if a drive stays dangerously hot. You can cancel.',
          isDark: isDark,
          trailing: Switch(
            value: cfg.shutdownEnabled && cfg.enabled,
            onChanged: cfg.enabled
                ? (v) => update((c) => c.copyWith(shutdownEnabled: v))
                : null,
          ),
        ),
        _SettingRow(
          label: 'Emergency temperature',
          subtitle: 'Must be at or above the critical threshold',
          isDark: isDark,
          trailing: _NativeDropdown<double>(
            value: cfg.emergencyCelsius,
            items: [
              for (final v in limits)
                DropdownMenuItem(
                  value: v,
                  child: Text('${v.toStringAsFixed(0)}°C', style: label()),
                ),
            ],
            onChanged: (v) {
              if (v != null) update((c) => c.copyWith(emergencyCelsius: v));
            },
            isDark: isDark,
          ),
        ),
        _SettingRow(
          label: 'Cancel window',
          subtitle: 'Time you have to cancel before shutting down',
          isDark: isDark,
          isLast: true,
          trailing: _NativeDropdown<int>(
            value: const [30, 60, 90, 120].contains(cfg.countdownSeconds)
                ? cfg.countdownSeconds
                : 60,
            items: [
              for (final v in const [30, 60, 90, 120])
                DropdownMenuItem(
                  value: v,
                  child: Text('${v}s', style: label()),
                ),
            ],
            onChanged: (v) {
              if (v != null) update((c) => c.copyWith(countdownSeconds: v));
            },
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}
