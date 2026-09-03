import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import '../components/device_presentation.dart';
import '../components/drive_card.dart';
import '../device_details/device_details_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final settings = ref.watch(settingsProvider);
    final monitoringService = ref.watch(monitoringServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bg0 : AppColors.lightBg,
      body: Column(
        children: [
          _DashboardHeader(
            deviceCount: devices.length,
            monitoringEnabled: settings.monitoringEnabled,
            onToggleMonitoring: () => ref.read(settingsProvider.notifier).updateWith(
                (s) => s.copyWith(monitoringEnabled: !s.monitoringEnabled)),
            onRescan: monitoringService.rescan,
            onOpenSettings: () => Navigator.of(context).push(
              _slideRoute(const SettingsScreen()),
            ),
            devices: devices,
            settings: settings,
          ),
          Expanded(
            child: _Body(devices: devices, settings: settings),
          ),
        ],
      ),
    );
  }
}

Route<void> _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    transitionDuration: AppDurations.medium,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Header
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.deviceCount,
    required this.monitoringEnabled,
    required this.onToggleMonitoring,
    required this.onRescan,
    required this.onOpenSettings,
    required this.devices,
    required this.settings,
  });

  final int deviceCount;
  final bool monitoringEnabled;
  final VoidCallback onToggleMonitoring;
  final VoidCallback onRescan;
  final VoidCallback onOpenSettings;
  final List<StorageDevice> devices;
  final dynamic settings;

  TemperatureSeverity _overallSeverity() {
    if (devices.isEmpty) return TemperatureSeverity.unavailable;
    TemperatureSeverity worst = TemperatureSeverity.normal;
    for (final d in devices) {
      final thresholds = settings.thresholdsFor(d.id);
      final presentation = DevicePresentation.of(d, thresholds, settings.temperatureUnit);
      if (presentation.severity == TemperatureSeverity.critical) return TemperatureSeverity.critical;
      if (presentation.severity == TemperatureSeverity.warning) {
        worst = TemperatureSeverity.warning;
      }
    }
    return worst;
  }

  String _statusText(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.critical:
        return 'Critical temperature detected';
      case TemperatureSeverity.warning:
        return 'Temperature warning';
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return 'All systems normal';
      case TemperatureSeverity.unavailable:
        return 'Scanning for devices…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = _overallSeverity();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SeverityStyle.of(severity, context);

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1640), AppColors.bg0],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFFEDE8FF), AppColors.lightBg],
              ),
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
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              // App icon / branding
              _AppLogo(),
              const SizedBox(width: AppSpacing.md),
              // Title block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DriveGuard',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: isDark ? AppColors.textPrimary : AppColors.lightText,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: AppDurations.medium,
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: style.color.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          deviceCount == 0
                              ? 'No devices'
                              : '$deviceCount drive${deviceCount == 1 ? '' : 's'} · ${_statusText(severity)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons
              _HeaderIconButton(
                icon: monitoringEnabled
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                tooltip: monitoringEnabled ? 'Pause monitoring' : 'Resume monitoring',
                onPressed: onToggleMonitoring,
                isActive: !monitoringEnabled,
              ),
              const SizedBox(width: AppSpacing.xs),
              _HeaderIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Rescan drives',
                onPressed: onRescan,
              ),
              const SizedBox(width: AppSpacing.xs),
              _HeaderIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: onOpenSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.purpleLight, AppColors.purpleDeep],
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: AppColors.purpleMid.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.storage_rounded, color: Colors.white, size: 22),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.purpleMid.withValues(alpha: 0.2)
                  : (isDark ? AppColors.bg2 : const Color(0xFFEDE8FF)),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isDark ? AppColors.border : AppColors.lightBorder,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive
                  ? AppColors.purpleLight
                  : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body({required this.devices, required this.settings});
  final List<StorageDevice> devices;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const _EmptyState();
    }

    return Consumer(builder: (context, ref, _) {
      final settings = ref.watch(settingsProvider);
      return LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Responsive card width drives the grid
        double cardWidth;
        if (width >= 1400) {
          cardWidth = 320;
        } else if (width >= 1000) {
          cardWidth = 300;
        } else if (width >= 650) {
          cardWidth = 280;
        } else {
          cardWidth = width - AppSpacing.lg * 2;
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: cardWidth,
                  mainAxisExtent: 320,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final device = devices[index];
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(device.id),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 300 + index * 60),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 20),
                          child: child,
                        ),
                      ),
                      child: DriveCard(
                        device: device,
                        thresholds: settings.thresholdsFor(device.id),
                        unit: settings.temperatureUnit,
                        onTap: () => Navigator.of(context).push(
                          _slideRoute(DeviceDetailsScreen(deviceId: device.id)),
                        ),
                      ),
                    );
                  },
                  childCount: devices.length,
                ),
              ),
            ),
          ],
        );
      });
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.purpleMid, AppColors.purpleDeep],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.purpleMid.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: const Icon(Icons.storage_rounded, size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Scanning for storage devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark ? AppColors.textPrimary : AppColors.lightText,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'DriveGuard automatically detects NVMe, SATA,\nand USB storage devices. This may take a moment.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: isDark ? AppColors.bg3 : AppColors.lightBorder,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.purpleLight),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
