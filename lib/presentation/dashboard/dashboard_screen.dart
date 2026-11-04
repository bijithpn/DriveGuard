import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/utils/temperature_utils.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import '../app_root.dart' show widgetModeActiveProvider;
import '../components/device_presentation.dart';
import '../components/drive_card.dart';
import '../components/app_shell.dart';
import '../components/ui_kit.dart';

import '../device_details/device_details_screen.dart';
import '../theme/app_theme.dart';

part 'parts/drive_list_pane.dart';
part 'parts/toolbar.dart';
part 'parts/drive_list_items.dart';

Route<void> slideRoute(Widget page) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppShell(
      section: AppSection.drives,
      child: _DriveListPane(
        settings: settings,
        isDark: isDark,
        onOpenDevice: (deviceId) => Navigator.of(
          context,
        ).push(slideRoute(DeviceDetailsScreen(deviceId: deviceId))),
        onToggleCompactView: (value) => ref
            .read(settingsProvider.notifier)
            .updateWith((s) => s.copyWith(dashboardCompactView: value)),
      ),
    );
  }
}
