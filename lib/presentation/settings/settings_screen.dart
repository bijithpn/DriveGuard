import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart'
    show Display, screenRetriever;

import '../../application/providers.dart';
import '../../application/settings/app_settings.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/storage_thresholds.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../app_root.dart' show edgeDockActiveProvider, widgetModeActiveProvider;
import '../theme/app_theme.dart';
import '../widget/edge_dock_view.dart' show resolveAccent;

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
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.shadowDark : AppColors.lightShadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
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

    final edgeDockActive = ref.watch(edgeDockActiveProvider);
    final edgeDockRows = [
      _SettingRow(
        label: 'Enable edge dock',
        subtitle: 'A slim hover strip docked to a screen edge',
        isDark: isDark,
        trailing: Switch(
          value: edgeDockActive,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(enabled: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock position',
        isDark: isDark,
        trailing: _SegmentedControl<ScreenEdge>(
          isDark: isDark,
          selected: settings.edgeDock.edge,
          options: const [
            (ScreenEdge.left, 'Left'),
            (ScreenEdge.right, 'Right'),
            (ScreenEdge.top, 'Top'),
            (ScreenEdge.bottom, 'Bottom'),
          ],
          onChanged: (edge) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(edge: edge)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock color',
        isDark: isDark,
        trailing: _EdgeDockAccentPicker(
          selected: settings.edgeDock.accent,
          onChanged: (accent) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(accent: accent)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock opacity',
        isDark: isDark,
        trailing: SizedBox(
          width: 140,
          child: _EdgeDockOpacitySlider(
            value: settings.edgeDock.opacity,
            onChangeEnd: (v) => notifier.updateWith(
              (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(opacity: v)),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock display',
        subtitle: 'Which monitor the dock attaches to',
        isDark: isDark,
        trailing: _EdgeDockDisplayPicker(
          selected: settings.edgeDock.displayId,
          isDark: isDark,
          onChanged: (id) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                displayId: id,
                clearDisplayId: id == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Panel background',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _backgroundSwatches,
          selected: settings.edgeDock.backgroundColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                backgroundColor: v,
                clearBackgroundColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Panel text',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _textSwatches,
          selected: settings.edgeDock.textColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                textColor: v,
                clearTextColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Warning color',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _warningSwatches,
          selected: settings.edgeDock.warningColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                warningColor: v,
                clearWarningColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Critical color',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _criticalSwatches,
          selected: settings.edgeDock.criticalColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                criticalColor: v,
                clearCriticalColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Hover panel fields',
        subtitle:
            'Which rows show in the detail panel (temperature always shows)',
        isDark: isDark,
        isLast: true,
        trailing: _EdgeDockMetricToggles(
          selected: settings.edgeDock.visibleMetrics,
          isDark: isDark,
          onChanged: (metrics) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(visibleMetrics: metrics),
            ),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionGroup(isDark: isDark, children: rows),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(title: 'Edge Dock', isDark: isDark),
        const SizedBox(height: AppSpacing.sm),
        _SectionGroup(isDark: isDark, children: edgeDockRows),
      ],
    );
  }
}

class _EdgeDockAccentPicker extends StatelessWidget {
  const _EdgeDockAccentPicker({
    required this.selected,
    required this.onChanged,
  });

  final EdgeDockAccent selected;
  final ValueChanged<EdgeDockAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: EdgeDockAccent.values.map((accent) {
        final isSelected = accent == selected;
        final color = resolveAccent(accent) ?? AppColors.textMuted;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: accent == EdgeDockAccent.auto
                ? 'Auto (by severity)'
                : accent.name,
            child: GestureDetector(
              onTap: () => onChanged(accent),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accent == EdgeDockAccent.auto
                      ? Colors.transparent
                      : color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? color : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: accent == EdgeDockAccent.auto
                    ? const Icon(
                        Icons.auto_awesome_rounded,
                        size: 11,
                        color: AppColors.textMuted,
                      )
                    : (isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Colors.white,
                            )
                          : null),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Opacity slider for the edge dock. Keeps the dragged value in local state
/// and only commits it (via [onChangeEnd]) once the drag finishes, instead
/// of on every [Slider.onChanged] tick. Committing on every tick used to
/// write straight into [AppSettings] and re-dock the whole edge-dock window
/// (close + reopen) on each intermediate value while dragging - visibly
/// laggy, and it could drop/reset the current hover state mid-drag.
class _EdgeDockOpacitySlider extends StatefulWidget {
  const _EdgeDockOpacitySlider({
    required this.value,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_EdgeDockOpacitySlider> createState() => _EdgeDockOpacitySliderState();
}

class _EdgeDockOpacitySliderState extends State<_EdgeDockOpacitySlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(_EdgeDockOpacitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _value,
      min: 0.4,
      max: 1.0,
      divisions: 12,
      label: '${(_value * 100).round()}%',
      onChanged: (v) => setState(() => _value = v),
      onChangeEnd: widget.onChangeEnd,
    );
  }
}

/// A single curated color choice for [_ColorSwatchPicker]. `value == null`
/// means "use the app's default" for that slot.
class _ColorSwatchOption {
  const _ColorSwatchOption(this.value, this.label, this.color);
  final int? value;
  final String label;
  final Color color;
}

const _backgroundSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.bg1),
  _ColorSwatchOption(0xFF000000, 'Black', Colors.black),
  _ColorSwatchOption(0xFF0B1220, 'Navy', Color(0xFF0B1220)),
  _ColorSwatchOption(0xFF14181D, 'Graphite', Color(0xFF14181D)),
];

const _textSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.textPrimary),
  _ColorSwatchOption(0xFFFFFFFF, 'White', Colors.white),
  _ColorSwatchOption(0xFFE5E7EB, 'Light gray', Color(0xFFE5E7EB)),
  _ColorSwatchOption(0xFFB8C4D9, 'Blue gray', Color(0xFFB8C4D9)),
];

const _warningSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.warning),
  _ColorSwatchOption(0xFFFFC107, 'Amber', Color(0xFFFFC107)),
  _ColorSwatchOption(0xFFFF7A45, 'Orange', Color(0xFFFF7A45)),
];

const _criticalSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.critical),
  _ColorSwatchOption(0xFFE53935, 'Red', Color(0xFFE53935)),
  _ColorSwatchOption(0xFFD6336C, 'Rose', Color(0xFFD6336C)),
];

/// A small curated color-swatch picker, matching [_EdgeDockAccentPicker]'s
/// pattern - used for the edge dock's background/text/warning/critical
/// color overrides so colors stay a fixed, glanceable set rather than an
/// open-ended picker dependency.
class _ColorSwatchPicker extends StatelessWidget {
  const _ColorSwatchPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<_ColorSwatchOption> options;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final knownValues = options.map((o) => o.value).toSet();
    final isCustom = selected != null && !knownValues.contains(selected);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final opt in options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _Swatch(
              color: opt.color,
              label: opt.label,
              selected: opt.value == selected,
              onTap: () => onChanged(opt.value),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: _Swatch(
            color: isCustom ? Color(selected!) : null,
            label: 'Custom…',
            selected: isCustom,
            child: isCustom
                ? null
                : const Icon(
                    Icons.add_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
            onTap: () async {
              final picked = await _showCustomColorPickerDialog(
                context,
                initial: selected ?? (options.first.value ?? 0xFF000000),
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ),
      ],
    );
  }
}

/// One round swatch button, shared by [_ColorSwatchPicker]'s curated
/// options and its trailing "Custom…" entry.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.child,
  });

  final Color? color;
  final String label;
  final bool selected;
  final Widget? child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child:
              child ??
              (selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: (color?.computeLuminance() ?? 0) > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null),
        ),
      ),
    );
  }
}

/// Opens the free-form color picker dialog and resolves to the chosen ARGB
/// int, or `null` if the user cancelled.
Future<int?> _showCustomColorPickerDialog(
  BuildContext context, {
  required int initial,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _CustomColorPickerDialog(initial: initial),
  );
}

/// A self-contained RGB/hex color picker - no package dependency, since
/// this is the one slot in the edge dock's settings that intentionally
/// isn't a curated swatch list. Three 0-255 sliders plus a hex field stay
/// in sync with each other and a live preview swatch.
class _CustomColorPickerDialog extends StatefulWidget {
  const _CustomColorPickerDialog({required this.initial});

  final int initial;

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late Color _color = Color(widget.initial).withValues(alpha: 1.0);
  late final _hexController = TextEditingController(text: _hexOf(_color));

  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _setColor(Color next, {bool updateHexField = true}) {
    setState(() => _color = next);
    if (updateHexField) _hexController.text = _hexOf(next);
  }

  void _setChannel({int? r, int? g, int? b}) {
    _setColor(
      Color.fromARGB(
        255,
        r ?? (_color.r * 255).round(),
        g ?? (_color.g * 255).round(),
        b ?? (_color.b * 255).round(),
      ),
    );
  }

  void _applyHex(String raw) {
    final cleaned = raw.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return;
    final value = int.parse(cleaned, radix: 16);
    _setColor(Color(0xFF000000 | value), updateHexField: false);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = (_color.r * 255).round();
    final g = (_color.g * 255).round();
    final b = (_color.b * 255).round();

    return AlertDialog(
      title: const Text('Custom color'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              decoration: const InputDecoration(labelText: 'Hex'),
              maxLength: 7,
              onSubmitted: _applyHex,
              onChanged: _applyHex,
            ),
            _ChannelSlider(
              label: 'R',
              value: r,
              color: Colors.red,
              onChanged: (v) => _setChannel(r: v),
            ),
            _ChannelSlider(
              label: 'G',
              value: g,
              color: Colors.green,
              onChanged: (v) => _setChannel(g: v),
            ),
            _ChannelSlider(
              label: 'B',
              value: b,
              color: Colors.blue,
              onChanged: (v) => _setChannel(b: v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_color.toARGB32() | 0xFF000000),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Picks which connected display the edge dock attaches to. Loads
/// `screenRetriever.getAllDisplays()` once (this is a settings screen, not
/// the always-on dock window, so there's no need to poll or subscribe).
/// Falls back to a plain "Primary display" label when there's only one
/// display, or while the list is still loading.
class _EdgeDockDisplayPicker extends StatefulWidget {
  const _EdgeDockDisplayPicker({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool isDark;

  @override
  State<_EdgeDockDisplayPicker> createState() => _EdgeDockDisplayPickerState();
}

class _EdgeDockDisplayPickerState extends State<_EdgeDockDisplayPicker> {
  static const _tag = 'EdgeDockDisplayPicker';
  List<Display>? _displays;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (mounted) setState(() => _displays = displays);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'getAllDisplays failed: $e');
      if (mounted) setState(() => _displays = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displays = _displays;
    final mutedStyle = TextStyle(
      fontSize: 12,
      color: widget.isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
    );
    if (displays == null) {
      return Text('Loading…', style: mutedStyle);
    }
    if (displays.length <= 1) {
      return Text('Primary display', style: mutedStyle);
    }
    final resolvedValue = displays.any((d) => d.id == widget.selected)
        ? widget.selected
        : null;
    return _NativeDropdown<String?>(
      value: resolvedValue,
      isDark: widget.isDark,
      items: [
        const DropdownMenuItem(value: null, child: Text('Primary display')),
        for (final d in displays)
          DropdownMenuItem(
            value: d.id,
            child: Text(
              '${(d.name?.isNotEmpty ?? false) ? d.name : 'Display'} — '
              '${d.size.width.toInt()}×${d.size.height.toInt()}',
            ),
          ),
      ],
      onChanged: widget.onChanged,
    );
  }
}

/// Checkbox-style toggles for which optional rows appear in the edge dock's
/// hover detail panel. Temperature is always shown, so it has no toggle.
class _EdgeDockMetricToggles extends StatelessWidget {
  const _EdgeDockMetricToggles({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final Set<EdgeDockMetric> selected;
  final ValueChanged<Set<EdgeDockMetric>> onChanged;
  final bool isDark;

  static const _labels = {
    EdgeDockMetric.health: 'Health',
    EdgeDockMetric.smart: 'SMART',
    EdgeDockMetric.powerOnHours: 'Power on',
    EdgeDockMetric.transferSpeed: 'Read/write',
    EdgeDockMetric.freeCapacity: 'Free space',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: EdgeDockMetric.values.map((metric) {
          final isOn = selected.contains(metric);
          return GestureDetector(
            onTap: () {
              final next = Set<EdgeDockMetric>.from(selected);
              if (isOn) {
                next.remove(metric);
              } else {
                next.add(metric);
              }
              onChanged(next);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isOn
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : (isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isOn
                      ? AppColors.accent
                      : (isDark ? AppColors.border : AppColors.lightBorder),
                ),
              ),
              child: Text(
                _labels[metric]!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isOn
                      ? AppColors.accent
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
