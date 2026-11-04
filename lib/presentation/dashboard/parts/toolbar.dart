part of '../dashboard_screen.dart';

/// Page header: "Drives" + a one-line live summary, with view controls.
class _DriveListToolbar extends StatelessWidget {
  const _DriveListToolbar({
    required this.summary,
    required this.compactView,
    required this.isDark,
    required this.onToggleCompactView,
  });

  final String summary;
  final bool compactView;
  final bool isDark;
  final ValueChanged<bool> onToggleCompactView;

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      title: 'Drives',
      subtitle: summary,
      actions: [
        Consumer(
          builder: (context, ref, _) {
            final active = ref.watch(widgetModeActiveProvider);
            return OutlinedButton.icon(
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .updateWith(
                    (s) =>
                        s.copyWith(widget: s.widget.copyWith(enabled: !active)),
                  ),
              style: OutlinedButton.styleFrom(
                foregroundColor: active ? AppColors.accent : mutedOf(context),
                side: BorderSide(
                  color: active
                      ? AppColors.accent.withValues(alpha: 0.6)
                      : hairlineOf(context),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
              ),
              icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 16),
              label: Text(active ? 'Close widget' : 'Mini widget'),
            );
          },
        ),
        const SizedBox(width: 4),
        SegmentedSwitch<bool>(
          value: compactView,
          options: const [
            (false, 'Grid', Icons.grid_view_rounded),
            (true, 'List', Icons.view_list_rounded),
          ],
          onChanged: onToggleCompactView,
        ),
      ],
    );
  }
}
