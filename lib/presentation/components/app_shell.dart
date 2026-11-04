import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import '../dashboard/dashboard_screen.dart' show slideRoute;
import '../incidents/incident_history_screen.dart';
import '../protection/resource_alert_banner.dart';
import '../protection/thermal_protection_ui.dart';
import '../settings/settings_screen.dart';
import '../storage_sense/storage_sense_screen.dart';
import '../theme/app_theme.dart';
import 'device_presentation.dart';
import 'ui_kit.dart';

/// Top-level places in the app. They all share one sidebar.
enum AppSection { drives, storage, incidents }

/// Switches to [section]: the stack is reset to the dashboard and the section
/// (if not Drives) is shown on top, so the back stack never grows.
void goToSection(NavigatorState nav, AppSection section) {
  nav.popUntil((r) => r.isFirst);
  switch (section) {
    case AppSection.drives:
      return;
    case AppSection.storage:
      nav.push(_fade(const StorageSenseScreen()));
    case AppSection.incidents:
      nav.push(_fade(const IncidentHistoryScreen()));
  }
}

Route<void> _fade(Widget page) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, a, _, child) =>
      FadeTransition(opacity: a, child: child),
  transitionDuration: AppDurations.fast,
  reverseTransitionDuration: AppDurations.fast,
);

/// Sidebar + content. Urgent alerts (overheating, memory pressure) appear
/// above the content on every section.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.section, required this.child});

  final AppSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSidebar(section: section),
          Expanded(
            child: Column(
              children: [
                const ThermalAlertBanner(),
                const ResourceAlertBanner(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.section});
  final AppSection section;

  TemperatureSeverity _overall(List<StorageDevice> devices, dynamic settings) {
    if (devices.isEmpty) return TemperatureSeverity.unavailable;
    var worst = TemperatureSeverity.normal;
    for (final d in devices) {
      final p = DevicePresentation.of(
        d,
        settings.thresholdsFor(d.id),
        settings.temperatureUnit,
      );
      if (p.severity == TemperatureSeverity.critical) {
        return TemperatureSeverity.critical;
      }
      if (p.severity == TemperatureSeverity.warning) {
        worst = TemperatureSeverity.warning;
      }
    }
    return worst;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final devices = ref.watch(devicesProvider);
    final monitoring = settings.monitoringEnabled;
    final severity = _overall(devices, settings);
    final isDark = isDarkOf(context);
    final nav = Navigator.of(context);

    final n = devices.length;
    final noun = '$n drive${n == 1 ? '' : 's'}';
    final status = !monitoring
        ? 'Monitoring paused'
        : (n == 0
              ? 'No drives found'
              : switch (severity) {
                  TemperatureSeverity.critical => '$noun — critical',
                  TemperatureSeverity.warning => '$noun — warning',
                  TemperatureSeverity.unavailable => 'Scanning…',
                  _ => '$noun healthy',
                });
    final statusColor = !monitoring
        ? faintOf(context)
        : switch (severity) {
            TemperatureSeverity.critical => AppColors.critical,
            TemperatureSeverity.warning => AppColors.warning,
            TemperatureSeverity.unavailable => faintOf(context),
            _ => AppColors.normal,
          };

    void select(AppSection s) {
      if (s != section) goToSection(nav, s);
    }

    return Container(
      width: AppLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(right: BorderSide(color: hairlineOf(context))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 26,
                    height: 26,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.shield_outlined,
                      size: 22,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'DriveGuard',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.heading(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _NavItem(
            icon: Icons.dns_outlined,
            label: 'Drives',
            selected: section == AppSection.drives,
            onTap: () => select(AppSection.drives),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.cleaning_services_outlined,
            label: 'Storage Sense',
            selected: section == AppSection.storage,
            onTap: () => select(AppSection.storage),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.history_rounded,
            label: 'Incidents',
            selected: section == AppSection.incidents,
            onTap: () => select(AppSection.incidents),
          ),
          const Spacer(),
          _NavItem(
            icon: monitoring
                ? Icons.pause_circle_outline_rounded
                : Icons.play_circle_outline_rounded,
            label: monitoring ? 'Pause monitoring' : 'Resume monitoring',
            muted: true,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .updateWith(
                  (s) => s.copyWith(monitoringEnabled: !s.monitoringEnabled),
                ),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.refresh_rounded,
            label: 'Rescan drives',
            muted: true,
            onTap: () => ref.read(monitoringServiceProvider).rescan(),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => nav.push(slideRoute(const SettingsScreen())),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: hairlineOf(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Row(
              children: [
                StatusDot(statusColor, size: 7),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context),
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

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool muted;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final fg = (widget.selected || _hovered)
        ? primaryTextOf(context)
        : (widget.muted ? faintOf(context) : mutedOf(context));
    final tint = dark ? Colors.white : Colors.black;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? tint.withValues(alpha: dark ? 0.07 : 0.06)
                : (_hovered
                      ? tint.withValues(alpha: dark ? 0.04 : 0.035)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
