import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/settings/app_settings.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/device_capabilities.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final devices = ref.watch(devicesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg0 : AppColors.lightBg,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.divider : AppColors.lightBorder,
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm + 2,
                ),
                child: Row(
                  children: [
                    _BackButton(isDark: isDark),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _Section(
                  title: 'General',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.launch_rounded,
                      title: 'Start with OS',
                      subtitle: 'Launch DriveGuard automatically at login',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.startWithOS,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(startWithOS: v),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.minimize_rounded,
                      title: 'Start minimized',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.startMinimized,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(startMinimized: v),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.open_in_full_rounded,
                      title: 'Minimize to tray',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.minimizeToTray,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(minimizeToTray: v),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.close_rounded,
                      title: 'Close to tray',
                      subtitle:
                          'Closing the window keeps DriveGuard running in the tray',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.closeToTray,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(closeToTray: v),
                        ),
                      ),
                    ),
                  ],
                ),

                _Section(
                  title: 'Monitoring',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.timer_outlined,
                      title: 'Polling interval',
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
                            notifier.updateWith(
                              (s) => s.copyWith(pollingInterval: v),
                            );
                          }
                        },
                        isDark: isDark,
                      ),
                    ),
                    _Tile(
                      icon: Icons.thermostat_rounded,
                      title: 'Temperature unit',
                      isDark: isDark,
                      trailing: _SegmentedControl<TemperatureUnit>(
                        options: const [
                          (TemperatureUnit.celsius, 'C'),
                          (TemperatureUnit.fahrenheit, 'F'),
                        ],
                        selected: settings.temperatureUnit,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(temperatureUnit: v),
                        ),
                        isDark: isDark,
                      ),
                    ),
                    _Tile(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Enable monitoring',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.monitoringEnabled,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(monitoringEnabled: v),
                        ),
                      ),
                    ),
                  ],
                ),

                _Section(
                  title: 'Alerts & Notifications',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.notifications_outlined,
                      title: 'Enable notifications',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.notificationsEnabled,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(notificationsEnabled: v),
                        ),
                      ),
                    ),
                    _ThresholdTile(
                      icon: Icons.warning_amber_rounded,
                      title: 'Warning threshold',
                      isDark: isDark,
                      value: settings.globalThresholds.warningCelsius,
                      color: AppColors.warning,
                      onSubmit: (v) => _submitThreshold(
                        context,
                        notifier,
                        current: settings.globalThresholds,
                        rawValue: v,
                        isWarningField: true,
                        apply: (s, updated) =>
                            s.copyWith(globalThresholds: updated),
                      ),
                    ),
                    _ThresholdTile(
                      icon: Icons.error_outline_rounded,
                      title: 'Critical threshold',
                      isDark: isDark,
                      value: settings.globalThresholds.criticalCelsius,
                      color: AppColors.critical,
                      onSubmit: (v) => _submitThreshold(
                        context,
                        notifier,
                        current: settings.globalThresholds,
                        rawValue: v,
                        isWarningField: false,
                        apply: (s, updated) =>
                            s.copyWith(globalThresholds: updated),
                      ),
                    ),
                    _Tile(
                      icon: Icons.timer_outlined,
                      title: 'Notification cooldown',
                      isDark: isDark,
                      trailing: _NativeDropdown<Duration>(
                        value: settings.notificationCooldown,
                        items: AppConstants.allowedNotificationCooldowns
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text(
                                  d.inMinutes < 60
                                      ? '${d.inMinutes} min'
                                      : '${d.inHours} hr',
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
                            notifier.updateWith(
                              (s) => s.copyWith(notificationCooldown: v),
                            );
                          }
                        },
                        isDark: isDark,
                      ),
                    ),
                    _Tile(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Recovery notifications',
                      subtitle:
                          'Notify when a drive returns to normal temperature',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.recoveryNotificationsEnabled,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(recoveryNotificationsEnabled: v),
                        ),
                      ),
                    ),
                  ],
                ),

                _Section(
                  title: 'Per-Device Thresholds',
                  isDark: isDark,
                  children: devices.isEmpty
                      ? [_EmptyDevicesHint(isDark: isDark)]
                      : devices.map((d) {
                          final thresholdOverride =
                              settings.perDeviceThresholds[d.id];
                          return _PerDeviceTile(
                            device: d,
                            thresholdOverride: thresholdOverride,
                            settings: settings,
                            notifier: notifier,
                            isDark: isDark,
                            onEdit: () => _editDeviceThresholds(
                              context,
                              notifier,
                              deviceId: d.id,
                              current: settings.thresholdsFor(d.id),
                              currentOverrides: settings.perDeviceThresholds,
                            ),
                            onReset: thresholdOverride != null
                                ? () {
                                    final overrides = Map.of(
                                      settings.perDeviceThresholds,
                                    )..remove(d.id);
                                    notifier.updateWith(
                                      (s) => s.copyWith(
                                        perDeviceThresholds: overrides,
                                      ),
                                    );
                                  }
                                : null,
                          );
                        }).toList(),
                ),

                _Section(
                  title: 'Appearance',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.palette_outlined,
                      title: 'Theme',
                      isDark: isDark,
                      trailing: _SegmentedControl<ThemeMode>(
                        options: const [
                          (ThemeMode.system, 'System'),
                          (ThemeMode.light, 'Light'),
                          (ThemeMode.dark, 'Dark'),
                        ],
                        selected: settings.themeMode,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(themeMode: v),
                        ),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),

                _Section(
                  title: 'Desktop Widget',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.widgets_outlined,
                      title: 'Enable mini monitor widget',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.widget.enabled,
                        onChanged: (v) => notifier.updateWith(
                          (s) =>
                              s.copyWith(widget: s.widget.copyWith(enabled: v)),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.push_pin_outlined,
                      title: 'Always on top',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.widget.alwaysOnTop,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(
                            widget: s.widget.copyWith(alwaysOnTop: v),
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.compress_rounded,
                      title: 'Compact mode',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.widget.compact,
                        onChanged: (v) => notifier.updateWith(
                          (s) =>
                              s.copyWith(widget: s.widget.copyWith(compact: v)),
                        ),
                      ),
                    ),
                  ],
                ),

                _Section(
                  title: 'Advanced',
                  isDark: isDark,
                  children: [
                    _Tile(
                      icon: Icons.bug_report_outlined,
                      title: 'Diagnostic logging',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.diagnosticLoggingEnabled,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(diagnosticLoggingEnabled: v),
                        ),
                      ),
                    ),
                    _Tile(
                      icon: Icons.science_outlined,
                      title: 'Use simulated devices (developer mode)',
                      isDark: isDark,
                      trailing: Switch(
                        value: settings.mockBackendForced,
                        onChanged: (v) => notifier.updateWith(
                          (s) => s.copyWith(mockBackendForced: v),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.refresh_rounded,
                      title: 'Rescan drives',
                      isDark: isDark,
                      onTap: () => ref.read(monitoringServiceProvider).rescan(),
                    ),
                    FutureBuilder(
                      future: ref
                          .read(storageMonitorProvider)
                          .getCapabilities(),
                      builder: (context, snapshot) {
                        final caps = snapshot.data;
                        if (caps == null) return const SizedBox.shrink();
                        return _Tile(
                          icon: Icons.info_outline_rounded,
                          title: 'Backend: ${caps.backendName}',
                          subtitle: caps.missingTools.isEmpty
                              ? 'All required tools available'
                              : 'Missing: ${caps.missingTools.join(', ')}',
                          isDark: isDark,
                          trailing: Icon(
                            caps.missingTools.isEmpty
                                ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded,
                            color: caps.missingTools.isEmpty
                                ? AppColors.normal
                                : AppColors.warning,
                            size: 18,
                          ),
                        );
                      },
                    ),
                    _ActionTile(
                      icon: Icons.download_outlined,
                      title: 'Export diagnostic report',
                      subtitle:
                          'Copies OS, backend and device info to the clipboard',
                      isDark: isDark,
                      onTap: () async {
                        final caps = await ref
                            .read(storageMonitorProvider)
                            .getCapabilities();
                        final report = StringBuffer()
                          ..writeln('DriveGuard diagnostic report')
                          ..writeln('Backend: ${caps.backendName}')
                          ..writeln(
                            'Can enumerate devices: ${caps.canEnumerateDevices}',
                          )
                          ..writeln(
                            'Can read temperature: ${caps.canReadTemperature}',
                          )
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
                            builder: (context) =>
                                _DiagnosticDialog(report: report.toString()),
                          );
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Sub-widgets

class _BackButton extends StatelessWidget {
  const _BackButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 16,
            color: isDark
                ? AppColors.textSecondary
                : AppColors.lightTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    required this.isDark,
  });
  final String title;
  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg1 : AppColors.lightCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark ? AppColors.border : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: children.asMap().entries.map((entry) {
                final index = entry.key;
                final child = entry.value;
                final isLast = index == children.length - 1;
                return Column(
                  children: [
                    child,
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Divider(
                          height: 1,
                          color: isDark
                              ? AppColors.divider
                              : AppColors.lightBorder,
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.isDark,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              size: 15,
              color: isDark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  icon,
                  size: 15,
                  color: isDark
                      ? AppColors.textSecondary
                      : AppColors.lightTextSecondary,
                ),
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
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.lightText,
                      ),
                    ),
                    if (subtitle != null)
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
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: isDark
                    ? AppColors.textMuted
                    : AppColors.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThresholdTile extends StatelessWidget {
  const _ThresholdTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.value,
    required this.color,
    required this.onSubmit,
  });

  final IconData icon;
  final String title;
  final bool isDark;
  final double value;
  final Color color;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.textPrimary : AppColors.lightText,
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: TextFormField(
              key: ValueKey('threshold-$value'),
              initialValue: value.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              decoration: InputDecoration(
                suffixText: 'C',
                suffixStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
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
          ),
        ],
      ),
    );
  }
}

class _PerDeviceTile extends StatelessWidget {
  const _PerDeviceTile({
    required this.device,
    required this.thresholdOverride,
    required this.settings,
    required this.notifier,
    required this.isDark,
    required this.onEdit,
    this.onReset,
  });

  final dynamic device;
  final dynamic thresholdOverride;
  final dynamic settings;
  final dynamic notifier;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.storage_rounded,
              size: 15,
              color: isDark
                  ? AppColors.textSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  thresholdOverride != null
                      ? 'Custom: warn ${thresholdOverride.warningCelsius.toStringAsFixed(0)} C / crit ${thresholdOverride.criticalCelsius.toStringAsFixed(0)} C'
                      : 'Using global defaults',
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
          Row(
            children: [
              _SmallButton(
                label: thresholdOverride != null ? 'Edit' : 'Override',
                onTap: onEdit,
                isDark: isDark,
                useAccent: true,
              ),
              if (onReset != null) ...[
                const SizedBox(width: AppSpacing.xs),
                _SmallButton(label: 'Reset', onTap: onReset!, isDark: isDark),
              ],
            ],
          ),
        ],
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

class _EmptyDevicesHint extends StatelessWidget {
  const _EmptyDevicesHint({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        'No devices detected yet. Per-device overrides will appear here once drives are found.',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
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

// Validation helpers (preserved exactly from original)

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

Future<void> _editDeviceThresholds(
  BuildContext context,
  SettingsNotifier notifier, {
  required String deviceId,
  required TemperatureThresholds current,
  required Map<String, TemperatureThresholds> currentOverrides,
}) async {
  final result = await showDialog<TemperatureThresholds>(
    context: context,
    builder: (dialogContext) => _ThresholdEditorDialog(current: current),
  );

  if (result != null) {
    final overrides = Map.of(currentOverrides)..[deviceId] = result;
    await notifier.updateWith(
      (s) => s.copyWith(perDeviceThresholds: overrides),
    );
  }
}

/// Dialog for editing per-device warning/critical thresholds.
/// Controllers are owned by State (not the caller) to avoid a disposal
/// race with the exit animation.
class _ThresholdEditorDialog extends StatefulWidget {
  const _ThresholdEditorDialog({required this.current});

  final TemperatureThresholds current;

  @override
  State<_ThresholdEditorDialog> createState() => _ThresholdEditorDialogState();
}

class _ThresholdEditorDialogState extends State<_ThresholdEditorDialog> {
  late final _warningController = TextEditingController(
    text: widget.current.warningCelsius.toStringAsFixed(0),
  );
  late final _criticalController = TextEditingController(
    text: widget.current.criticalCelsius.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _warningController.dispose();
    _criticalController.dispose();
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
    Navigator.of(context).pop(
      widget.current.copyWith(
        warningCelsius: warning,
        criticalCelsius: critical,
      ),
    );
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThresholdField(
            controller: _warningController,
            label: 'Warning',
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ThresholdField(
            controller: _criticalController,
            label: 'Critical',
            color: AppColors.critical,
          ),
        ],
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

class _ThresholdField extends StatelessWidget {
  const _ThresholdField({
    required this.controller,
    required this.label,
    required this.color,
  });

  final TextEditingController controller;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color),
        suffixText: 'C',
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
