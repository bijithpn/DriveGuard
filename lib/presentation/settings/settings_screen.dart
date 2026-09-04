import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/settings/app_settings.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_thresholds.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../app_root.dart' show widgetModeActiveProvider;
import '../theme/app_theme.dart';

enum _Section {
  general,
  monitoring,
  alerts,
  thresholds,
  appearance,
  widget,
  advanced;

  String get label => switch (this) {
    _Section.general => 'General',
    _Section.monitoring => 'Monitoring',
    _Section.alerts => 'Alerts',
    _Section.thresholds => 'Thresholds',
    _Section.appearance => 'Appearance',
    _Section.widget => 'Widget',
    _Section.advanced => 'Advanced',
  };

  IconData get icon => switch (this) {
    _Section.general => Icons.tune_rounded,
    _Section.monitoring => Icons.monitor_heart_outlined,
    _Section.alerts => Icons.notifications_outlined,
    _Section.thresholds => Icons.device_thermostat_rounded,
    _Section.appearance => Icons.palette_outlined,
    _Section.widget => Icons.widgets_outlined,
    _Section.advanced => Icons.build_outlined,
  };
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _Section _selectedSection = _Section.general;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Row(
        children: [
          _SettingsSidebar(
            selected: _selectedSection,
            isDark: isDark,
            onSelect: (s) => setState(() => _selectedSection = s),
          ),

          Expanded(
            child: _ContentPanel(section: _selectedSection, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selected,
    required this.isDark,
    required this.onSelect,
  });

  final _Section selected;
  final bool isDark;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.border : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sidebarPad,
                AppSpacing.md,
                AppSpacing.sidebarPad,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  _SidebarBackButton(isDark: isDark),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                children: _Section.values.map((s) {
                  return _SidebarNavItem(
                    section: s,
                    isSelected: s == selected,
                    isDark: isDark,
                    onTap: () => onSelect(s),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBackButton extends StatelessWidget {
  const _SidebarBackButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 14,
            color: isDark
                ? AppColors.textSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.section,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final _Section section;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isDark = widget.isDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sidebarPad,
            vertical: 9,
          ),
          decoration: isSelected
              ? AppDecorations.sidebarItem(selected: true, isDark: isDark)
              : BoxDecoration(
                  color: _hovered
                      ? (isDark
                            ? AppColors.bg2.withValues(alpha: 0.6)
                            : AppColors.lightSurfaceMuted.withValues(
                                alpha: 0.7,
                              ))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
          child: Row(
            children: [
              Icon(
                widget.section.icon,
                size: 15,
                color: isSelected
                    ? AppColors.accent
                    : (isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.section.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                      : (isDark
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

class _ContentPanel extends ConsumerWidget {
  const _ContentPanel({required this.section, required this.isDark});

  final _Section section;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: isDark ? AppColors.bg0 : AppColors.lightBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.divider : AppColors.lightBorder,
                    width: 1,
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                section.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.lightText,
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _buildSection(context, ref, section),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, WidgetRef ref, _Section section) {
    return switch (section) {
      _Section.general => _GeneralSection(isDark: isDark),
      _Section.monitoring => _MonitoringSection(isDark: isDark),
      _Section.alerts => _AlertsSection(isDark: isDark),
      _Section.thresholds => _ThresholdsSection(isDark: isDark),
      _Section.appearance => _AppearanceSection(isDark: isDark),
      _Section.widget => _WidgetSection(isDark: isDark),
      _Section.advanced => _AdvancedSection(isDark: isDark),
    };
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.isDark,
    this.subtitle,
    this.trailing,
    this.isLast = false,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool isDark;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.divider : AppColors.lightBorder,
                  width: 1,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
          if (onTap != null && trailing == null)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
            ),
        ],
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    return content;
  }
}

class _SectionGroup extends StatelessWidget {
  const _SectionGroup({required this.children, required this.isDark});

  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(children.length, (i) {
          return children[i];
        }),
      ),
    );
  }
}

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
              ? (v) =>
                  notifier.updateWith((s) => s.copyWith(minimizeToTray: v))
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
              ? (v) =>
                  notifier.updateWith((s) => s.copyWith(closeToTray: v))
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

class _WidgetSection extends ConsumerWidget {
  const _WidgetSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final widgetActive = ref.watch(widgetModeActiveProvider);

    final rows = [
      _SettingRow(
        label: 'Enable mini monitor widget',
        isDark: isDark,
        trailing: Switch(
          value: widgetActive,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(enabled: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Always on top',
        isDark: isDark,
        trailing: Switch(
          value: settings.widget.alwaysOnTop,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(alwaysOnTop: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Compact mode',
        isDark: isDark,
        isLast: true,
        trailing: Switch(
          value: settings.widget.compact,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(compact: v)),
          ),
        ),
      ),
    ];

    return _SectionGroup(isDark: isDark, children: rows);
  }
}

class _AdvancedSection extends ConsumerWidget {
  const _AdvancedSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final devices = ref.watch(devicesProvider);

    return _SectionGroup(
      isDark: isDark,
      children: [
        _SettingRow(
          label: 'Diagnostic logging',
          isDark: isDark,
          trailing: Switch(
            value: settings.diagnosticLoggingEnabled,
            onChanged: (v) => notifier.updateWith(
              (s) => s.copyWith(diagnosticLoggingEnabled: v),
            ),
          ),
        ),
        _SettingRow(
          label: 'Simulated devices',
          subtitle: 'Developer mode — use mock data instead of real drives',
          isDark: isDark,
          trailing: Switch(
            value: settings.mockBackendForced,
            onChanged: (v) =>
                notifier.updateWith((s) => s.copyWith(mockBackendForced: v)),
          ),
        ),
        _SettingRow(
          label: 'Rescan drives',
          isDark: isDark,
          onTap: () => ref.read(monitoringServiceProvider).rescan(),
        ),
        FutureBuilder(
          future: ref.read(storageMonitorProvider).getCapabilities(),
          builder: (context, snapshot) {
            final caps = snapshot.data;
            final backendText = caps != null
                ? 'Backend: ${caps.backendName}'
                : 'Backend: detecting…';
            final subtitleText = caps == null
                ? null
                : caps.missingTools.isEmpty
                ? 'All required tools available'
                : 'Missing: ${caps.missingTools.join(', ')}';
            return _SettingRow(
              label: backendText,
              subtitle: subtitleText,
              isDark: isDark,
              trailing: caps != null
                  ? Icon(
                      caps.missingTools.isEmpty
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: caps.missingTools.isEmpty
                          ? AppColors.normal
                          : AppColors.warning,
                      size: 18,
                    )
                  : null,
            );
          },
        ),
        _SettingRow(
          label: 'Export diagnostic report',
          subtitle: 'Copies OS, backend and device info to the clipboard',
          isDark: isDark,
          isLast: true,
          onTap: () async {
            final caps = await ref
                .read(storageMonitorProvider)
                .getCapabilities();
            final report = StringBuffer()
              ..writeln('DriveGuard diagnostic report')
              ..writeln('Backend: ${caps.backendName}')
              ..writeln('Can enumerate devices: ${caps.canEnumerateDevices}')
              ..writeln('Can read temperature: ${caps.canReadTemperature}')
              ..writeln('Can read health: ${caps.canReadHealth}')
              ..writeln(
                'Missing tools: ${caps.missingTools.isEmpty ? 'None' : caps.missingTools.join(', ')}',
              );
            if (caps.notes.isNotEmpty) {
              report.writeln('Notes:');
              for (final note in caps.notes) {
                report.writeln('  - $note');
              }
            }
            report.writeln('Devices:');
            for (final d in devices) {
              final capabilities = DeviceCapabilities.derive(d);
              report.writeln(
                '  - ${d.type.name}/${d.interfaceType.name} status=${d.monitoringStatus.name} sensor=${d.sensorAvailability.name}',
              );
              report.writeln(
                '      capabilities: ${capabilities.entries.map((e) => '${e.$1}=${e.$2 ? 'yes' : 'no'}').join(', ')}',
              );
            }
            report.writeln('--- Log ---');
            report.writeln(AppLogger.instance.exportAsText());
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (ctx) => _DiagnosticDialog(report: report.toString()),
              );
            }
          },
        ),
      ],
    );
  }
}

class _ThresholdField extends StatelessWidget {
  const _ThresholdField({
    super.key,
    required this.value,
    required this.color,
    required this.onSubmit,
    this.suffixText = 'C',
  });

  final double value;
  final Color color;
  final ValueChanged<String> onSubmit;
  final String suffixText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        decoration: InputDecoration(
          suffixText: suffixText,
          suffixStyle: TextStyle(color: color, fontWeight: FontWeight.w500),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          filled: true,
          fillColor: color.withValues(alpha: 0.07),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: color, width: 1.5),
          ),
        ),
        onFieldSubmitted: onSubmit,
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    required this.isDark,
    this.useAccent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool useAccent;

  @override
  Widget build(BuildContext context) {
    final color = useAccent
        ? AppColors.accent
        : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _NativeDropdown<T> extends StatelessWidget {
  const _NativeDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        isDense: true,
        dropdownColor: isDark ? AppColors.bg2 : AppColors.lightCard,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
        ),
        icon: Icon(
          Icons.expand_more_rounded,
          size: 15,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final (value, label) = opt;
          final isSelected = value == selected;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? AppColors.bg3 : AppColors.lightCard)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                border: isSelected
                    ? Border.all(
                        color: isDark
                            ? AppColors.border
                            : AppColors.lightBorder,
                      )
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? (isDark ? AppColors.textPrimary : AppColors.lightText)
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DiagnosticDialog extends StatelessWidget {
  const _DiagnosticDialog({required this.report});
  final String report;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      title: Text(
        'Diagnostic Report',
        style: TextStyle(
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg0 : AppColors.lightBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isDark
                    ? AppColors.textSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: isDark
                ? AppColors.textSecondary
                : AppColors.lightTextSecondary,
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

const double _minThresholdSeparationCelsius = 1.0;

void _submitThreshold(
  BuildContext context,
  SettingsNotifier notifier, {
  required TemperatureThresholds current,
  required String rawValue,
  required bool isWarningField,
  required AppSettings Function(
    AppSettings settings,
    TemperatureThresholds updated,
  )
  apply,
}) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric temperature.');
    return;
  }
  if (value <= 0 || !value.isFinite) {
    _showThresholdError(context, 'Threshold must be a positive temperature.');
    return;
  }

  final updated = isWarningField
      ? current.copyWith(warningCelsius: value)
      : current.copyWith(criticalCelsius: value);

  if (updated.criticalCelsius - updated.warningCelsius <
      _minThresholdSeparationCelsius) {
    _showThresholdError(
      context,
      'Critical threshold must be higher than warning threshold.',
    );
    return;
  }

  notifier.updateWith((s) => apply(s, updated));
}

const double _minStorageThresholdSeparationPercent = 1.0;

void _submitStorageThreshold(
  BuildContext context,
  SettingsNotifier notifier, {
  required StorageThresholds current,
  required String rawValue,
  required bool isWarningField,
}) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric percentage.');
    return;
  }
  if (value <= 0 || value > 100 || !value.isFinite) {
    _showThresholdError(context, 'Threshold must be between 1 and 100.');
    return;
  }

  final updated = isWarningField
      ? current.copyWith(warningPercent: value)
      : current.copyWith(criticalPercent: value);

  if (updated.criticalPercent - updated.warningPercent <
      _minStorageThresholdSeparationPercent) {
    _showThresholdError(
      context,
      'Critical threshold must be higher than warning threshold.',
    );
    return;
  }

  notifier.updateWith((s) => s.copyWith(storageThresholds: updated));
}

void _submitRapidRiseDelta(
  BuildContext context,
  SettingsNotifier notifier,
  String rawValue,
) {
  final value = double.tryParse(rawValue.trim());
  if (value == null) {
    _showThresholdError(context, 'Enter a numeric temperature delta.');
    return;
  }
  if (value <= 0 || !value.isFinite) {
    _showThresholdError(context, 'Delta must be a positive temperature.');
    return;
  }
  notifier.updateWith((s) => s.copyWith(rapidRiseDeltaCelsius: value));
}

void _showThresholdError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.critical,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
}

typedef _DeviceOverrideResult = ({
  TemperatureThresholds temperature,
  StorageThresholds storage,
  double rapidRiseDelta,
});

Future<void> _editDeviceThresholds(
  BuildContext context,
  SettingsNotifier notifier, {
  required String deviceId,
  required AppSettings settings,
}) async {
  final result = await showDialog<_DeviceOverrideResult>(
    context: context,
    builder: (dialogContext) => _ThresholdEditorDialog(
      temperature: settings.thresholdsFor(deviceId),
      storage: settings.storageThresholdsFor(deviceId),
      rapidRiseDelta: settings.rapidRiseDeltaFor(deviceId),
    ),
  );

  if (result != null) {
    final temp = Map.of(settings.perDeviceThresholds)
      ..[deviceId] = result.temperature;
    final storage = Map.of(settings.perDeviceStorageThresholds)
      ..[deviceId] = result.storage;
    final rapidRise = Map.of(settings.perDeviceRapidRiseDelta)
      ..[deviceId] = result.rapidRiseDelta;
    await notifier.updateWith(
      (s) => s.copyWith(
        perDeviceThresholds: temp,
        perDeviceStorageThresholds: storage,
        perDeviceRapidRiseDelta: rapidRise,
      ),
    );
  }
}

class _ThresholdEditorDialog extends StatefulWidget {
  const _ThresholdEditorDialog({
    required this.temperature,
    required this.storage,
    required this.rapidRiseDelta,
  });

  final TemperatureThresholds temperature;
  final StorageThresholds storage;
  final double rapidRiseDelta;

  @override
  State<_ThresholdEditorDialog> createState() => _ThresholdEditorDialogState();
}

class _ThresholdEditorDialogState extends State<_ThresholdEditorDialog> {
  late final _warningController = TextEditingController(
    text: widget.temperature.warningCelsius.toStringAsFixed(0),
  );
  late final _criticalController = TextEditingController(
    text: widget.temperature.criticalCelsius.toStringAsFixed(0),
  );
  late final _storageWarningController = TextEditingController(
    text: widget.storage.warningPercent.toStringAsFixed(0),
  );
  late final _storageCriticalController = TextEditingController(
    text: widget.storage.criticalPercent.toStringAsFixed(0),
  );
  late final _rapidRiseController = TextEditingController(
    text: widget.rapidRiseDelta.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _warningController.dispose();
    _criticalController.dispose();
    _storageWarningController.dispose();
    _storageCriticalController.dispose();
    _rapidRiseController.dispose();
    super.dispose();
  }

  void _save() {
    final warning = double.tryParse(_warningController.text.trim());
    final critical = double.tryParse(_criticalController.text.trim());
    if (warning == null || critical == null || warning <= 0 || critical <= 0) {
      _showThresholdError(context, 'Enter positive numeric temperatures.');
      return;
    }
    if (critical - warning < _minThresholdSeparationCelsius) {
      _showThresholdError(
        context,
        'Critical threshold must be higher than warning threshold.',
      );
      return;
    }

    final storageWarning = double.tryParse(
      _storageWarningController.text.trim(),
    );
    final storageCritical = double.tryParse(
      _storageCriticalController.text.trim(),
    );
    if (storageWarning == null ||
        storageCritical == null ||
        storageWarning <= 0 ||
        storageWarning > 100 ||
        storageCritical <= 0 ||
        storageCritical > 100) {
      _showThresholdError(context, 'Enter disk percentages between 1 and 100.');
      return;
    }
    if (storageCritical - storageWarning <
        _minStorageThresholdSeparationPercent) {
      _showThresholdError(
        context,
        'Disk critical threshold must be higher than warning threshold.',
      );
      return;
    }

    final rapidRise = double.tryParse(_rapidRiseController.text.trim());
    if (rapidRise == null || rapidRise <= 0) {
      _showThresholdError(context, 'Enter a positive rapid-rise delta.');
      return;
    }

    Navigator.of(context).pop((
      temperature: widget.temperature.copyWith(
        warningCelsius: warning,
        criticalCelsius: critical,
      ),
      storage: widget.storage.copyWith(
        warningPercent: storageWarning,
        criticalPercent: storageCritical,
      ),
      rapidRiseDelta: rapidRise,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.bg1 : AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: isDark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      title: Text(
        'Device Thresholds',
        style: TextStyle(
          color: isDark ? AppColors.textPrimary : AppColors.lightText,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(title: 'Temperature', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _warningController,
              label: 'Warning',
              color: AppColors.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ThresholdEditorField(
              controller: _criticalController,
              label: 'Critical',
              color: AppColors.critical,
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionLabel(title: 'Disk usage', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _storageWarningController,
              label: 'Warning',
              color: AppColors.warning,
              suffixText: '%',
            ),
            const SizedBox(height: AppSpacing.sm),
            _ThresholdEditorField(
              controller: _storageCriticalController,
              label: 'Critical',
              color: AppColors.critical,
              suffixText: '%',
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionLabel(title: 'Rapid rise', isDark: isDark),
            const SizedBox(height: AppSpacing.xs),
            _ThresholdEditorField(
              controller: _rapidRiseController,
              label: 'Delta',
              color: AppColors.warning,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _save,
          child: const Text('Save'),
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
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
      ),
    );
  }
}

class _ThresholdEditorField extends StatelessWidget {
  const _ThresholdEditorField({
    required this.controller,
    required this.label,
    required this.color,
    this.suffixText = 'C',
  });

  final TextEditingController controller;
  final String label;
  final Color color;
  final String suffixText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color),
        suffixText: suffixText,
        suffixStyle: TextStyle(color: color),
        filled: true,
        fillColor: color.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: 1.5),
        ),
      ),
    );
  }
}
