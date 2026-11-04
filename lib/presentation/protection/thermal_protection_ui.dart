import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;

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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.local_fire_department_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.stage == ThermalStage.emergency
                          ? '${state.deviceName ?? 'Drive'} is overheating'
                          : '${state.deviceName ?? 'Drive'} is running too hot',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [
                        if (state.celsius != null)
                          '${state.celsius!.toStringAsFixed(0)}°C',
                        ?state.message,
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              if (state.countdown != null)
                Text(
                  '${state.countdown!.inSeconds}s',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (cause != null) ...[
            const SizedBox(height: 14),
            Text(
              'Main cause',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cause.headline,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              cause.detail,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
            ),
            if (culprit != null) ...[
              const SizedBox(height: 8),
              Text(
                '${cause.culpritMeasured ? 'Confirmed source' : 'Likely source'}: '
                '${culprit.name} (${culprit.cpuPercent.toStringAsFixed(0)}% CPU'
                '${culprit.rssBytes != null ? ', ${(culprit.rssBytes! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB memory' : ''})',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (cause.secondary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Also: ${cause.secondary.join(' · ')}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
            if (cause.advice.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final a in cause.advice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
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
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (state.shutdownScheduled)
                FilledButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancel shutdown'),
                ),
              if (culprit != null && onQuit != null)
                ProcessQuitButtons(
                  key: ValueKey('${state.deviceId}-${culprit.pid}'),
                  processName: culprit.name,
                  onQuit: onQuit!,
                ),
              if (state.stage == ThermalStage.emergency)
                OutlinedButton.icon(
                  onPressed: onShutdown,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.critical,
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                  label: const Text('Shut down now'),
                ),
            ],
          ),
        ],
      ),
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
