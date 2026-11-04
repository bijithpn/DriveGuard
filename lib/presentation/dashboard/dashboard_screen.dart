import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../app_root.dart' show widgetModeActiveProvider;
import '../components/animated_entrance.dart';
import '../components/device_presentation.dart';
import '../components/drive_card.dart';

import '../device_details/device_details_screen.dart';
import '../incidents/incident_history_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';

part 'parts/sidebar.dart';
part 'parts/drive_list_pane.dart';
part 'parts/toolbar.dart';
part 'parts/drive_list_items.dart';

Route<void> _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
    transitionDuration: AppDurations.medium,
  );
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final monitoringService = ref.watch(monitoringServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer(
            builder: (context, ref, _) => _Sidebar(
              devices: ref.watch(devicesProvider),
              settings: settings,
              isDark: isDark,
              monitoringEnabled: settings.monitoringEnabled,
              onToggleMonitoring: () => ref
                  .read(settingsProvider.notifier)
                  .updateWith(
                    (s) => s.copyWith(monitoringEnabled: !s.monitoringEnabled),
                  ),
              onRescan: monitoringService.rescan,
              onOpenSettings: () => Navigator.of(
                context,
              ).push(_slideRoute(const SettingsScreen())),
              onOpenIncidents: () => Navigator.of(
                context,
              ).push(_slideRoute(const IncidentHistoryScreen())),
            ),
          ),

          Expanded(
            child: _DriveListPane(
              settings: settings,
              isDark: isDark,
              onOpenDevice: (deviceId) => Navigator.of(
                context,
              ).push(_slideRoute(DeviceDetailsScreen(deviceId: deviceId))),
              onToggleCompactView: (value) => ref
                  .read(settingsProvider.notifier)
                  .updateWith((s) => s.copyWith(dashboardCompactView: value)),
            ),
          ),
        ],
      ),
    );
  }
}
