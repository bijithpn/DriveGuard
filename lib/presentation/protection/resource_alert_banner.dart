import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/protection/process_controller.dart';
import '../../application/protection/thermal_models.dart';
import '../../application/providers.dart';
import '../theme/app_theme.dart';
import '../components/ui_kit.dart';
import 'alert_card.dart';
import 'process_actions.dart';

/// Lists active memory/swap and heavy-write alerts, each with the offending
/// app and quit actions. Collapses to nothing when all is well.
class ResourceAlertBanner extends ConsumerWidget {
  const ResourceAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(resourceAlertsProvider).value ?? const [];
    final guard = ref.read(resourceGuardProvider);
    return AnimatedSize(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      child: alerts.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.gap,
                AppSpacing.page,
                0,
              ),
              child: Column(
                children: [
                  for (final a in alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.gap),
                      child: _AlertCard(
                        alert: a,
                        needsAdmin:
                            a.culprit != null &&
                            guard.processes.accessFor(a.culprit!) ==
                                KillAccess.needsAdmin,
                        onQuit: ({bool force = false, bool admin = false}) =>
                            guard.processes.quit(
                              a.culprit!,
                              force: force,
                              admin: admin,
                            ),
                        onFinished: guard.refreshSoon,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.needsAdmin,
    required this.onQuit,
    required this.onFinished,
  });

  final ResourceAlert alert;
  final bool needsAdmin;
  final QuitCallback onQuit;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity == ResourceSeverity.critical
        ? AppColors.critical
        : AppColors.warning;
    final icon = switch (alert.kind) {
      ResourceAlertKind.heavyWrites => Icons.edit_note_rounded,
      _ => Icons.memory_rounded,
    };
    return AlertCard(
      color: color,
      icon: icon,
      title: alert.title,
      children: [
        Text(alert.detail, style: AppText.secondary(context)),
        if (alert.advice.isNotEmpty) ...[
          const SizedBox(height: 12),
          AdviceList(alert.advice),
        ],
        if (alert.culprit != null) ...[
          const SizedBox(height: 16),
          ProcessQuitButtons(
            key: ValueKey('${alert.id}-${alert.culprit!.pid}'),
            processName: alert.culprit!.name,
            needsAdmin: needsAdmin,
            onQuit: onQuit,
            onFinished: onFinished,
          ),
        ],
      ],
    );
  }
}
