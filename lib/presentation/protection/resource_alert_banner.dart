import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/protection/process_controller.dart';
import '../../application/protection/thermal_models.dart';
import '../../application/providers.dart';
import '../theme/app_theme.dart';
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  for (final a in alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final color = alert.severity == ResourceSeverity.critical
        ? AppColors.critical
        : AppColors.warning;
    final icon = switch (alert.kind) {
      ResourceAlertKind.heavyWrites => Icons.edit_note_rounded,
      _ => Icons.memory_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  alert.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            alert.detail,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
          ),
          if (alert.advice.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final a in alert.advice)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right_rounded, size: 18, color: color),
                    Expanded(
                      child: Text(a, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
          ],
          if (alert.culprit != null) ...[
            const SizedBox(height: 12),
            ProcessQuitButtons(
              key: ValueKey('${alert.id}-${alert.culprit!.pid}'),
              processName: alert.culprit!.name,
              needsAdmin: needsAdmin,
              onQuit: onQuit,
              onFinished: onFinished,
            ),
          ],
        ],
      ),
    );
  }
}
