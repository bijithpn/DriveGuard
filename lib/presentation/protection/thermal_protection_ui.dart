import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/ui_kit.dart';
import 'alert_card.dart';
import 'process_actions.dart';

import '../../application/protection/thermal_models.dart';
import '../../application/providers.dart';
import '../theme/app_theme.dart';

Color _stageColor(ThermalStage s) =>
    s == ThermalStage.emergency ? AppColors.critical : AppColors.warning;

/// Persistent strip shown at the top of the dashboard while a drive is in
/// the danger/emergency zone. Names the cause and offers direct actions.
class ThermalAlertBanner extends ConsumerWidget {
  const ThermalAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(thermalProtectionStateProvider).value ??
        ThermalProtectionState.idle;
    final svc = ref.read(thermalProtectionServiceProvider);
    return AnimatedSize(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      child: !state.isActive
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                0,
              ),
              child: _ThermalCard(
                state: state,
                onCancel: svc.cancelShutdown,
                onShutdown: svc.shutdownNow,
                onQuit: state.deviceId == null
                    ? null
                    : ({bool force = false, bool admin = false}) =>
                          svc.quitCulprit(
                            state.deviceId!,
                            force: force,
                            admin: admin,
                          ),
              ),
            ),
    );
  }
}

class _ThermalCard extends StatelessWidget {
  const _ThermalCard({
    required this.state,
    required this.onCancel,
    required this.onShutdown,
    required this.onQuit,
  });

  final ThermalProtectionState state;
  final VoidCallback onCancel;
  final VoidCallback onShutdown;
  final QuitCallback? onQuit;

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(state.stage);
    final cause = state.cause;
    final culprit = cause?.culprit;
    final name = state.deviceName ?? 'Drive';
    final reading = [
      if (state.celsius != null) '${state.celsius!.toStringAsFixed(0)}°C',
      ?state.message,
    ].join('  ·  ');

    return AlertCard(
      color: color,
      icon: Icons.local_fire_department_rounded,
      title: state.stage == ThermalStage.emergency
          ? '$name is overheating'
          : '$name is running too hot',
      subtitle: reading.isEmpty ? null : reading,
      trailing: state.countdown == null
          ? null
          : Text(
              '${state.countdown!.inSeconds}s',
              style: AppText.metric(context, size: 28).copyWith(color: color),
            ),
      children: [
        if (cause != null) ...[
          Text('MAIN CAUSE', style: AppText.label(context)),
          const SizedBox(height: 6),
          Text(cause.headline, style: AppText.heading(context)),
          const SizedBox(height: 4),
          Text(cause.detail, style: AppText.secondary(context)),
          if (culprit != null) ...[
            const SizedBox(height: 10),
            Text(
              '${cause.culpritMeasured ? 'Confirmed source' : 'Likely source'}: '
              '${culprit.name} (${culprit.cpuPercent.toStringAsFixed(0)}% CPU'
              '${culprit.rssBytes != null ? ', ${(culprit.rssBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB memory' : ''})',
              style: AppText.body(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (cause.secondary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Also: ${cause.secondary.join('  ·  ')}',
              style: AppText.caption(context),
            ),
          ],
          if (cause.advice.isNotEmpty) ...[
            const SizedBox(height: 12),
            AdviceList(cause.advice),
          ],
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (state.shutdownScheduled)
              FilledButton(
                onPressed: onCancel,
                child: const Text('Cancel shutdown'),
              ),
            if (culprit != null && onQuit != null)
              ProcessQuitButtons(
                key: ValueKey('${state.deviceId}-${culprit.pid}'),
                processName: culprit.name,
                onQuit: onQuit!,
              ),
            if (state.stage == ThermalStage.emergency)
              OutlinedButton(
                onPressed: onShutdown,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.critical,
                  side: BorderSide(
                    color: AppColors.critical.withValues(alpha: 0.5),
                  ),
                ),
                child: const Text('Shut down now'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Modal shown when an automatic shutdown countdown starts. Closes itself as
/// soon as the countdown ends or is cancelled.
Future<void> showThermalShutdownDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ThermalDialog(),
  );
}

class _ThermalDialog extends ConsumerWidget {
  const _ThermalDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(thermalProtectionStateProvider).value ??
        ThermalProtectionState.idle;
    final svc = ref.read(thermalProtectionServiceProvider);
    if (!state.shutdownScheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          child: SingleChildScrollView(
            child: _ThermalCard(
              state: state,
              onCancel: svc.cancelShutdown,
              onShutdown: svc.shutdownNow,
              onQuit: state.deviceId == null
                  ? null
                  : ({bool force = false, bool admin = false}) =>
                        svc.quitCulprit(
                          state.deviceId!,
                          force: force,
                          admin: admin,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}
