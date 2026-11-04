part of '../dashboard_screen.dart';

class _DriveScrollBody extends StatelessWidget {
  const _DriveScrollBody({
    required this.ids,
    required this.settings,
    required this.isDark,
    required this.compactView,
    required this.onOpenDevice,
  });

  final List<String> ids;
  final dynamic settings;
  final bool isDark;
  final bool compactView;
  final ValueChanged<String> onOpenDevice;

  Widget _card(String id, {required bool compact}) {
    return KeyedSubtree(
      key: ValueKey(id),
      child: Consumer(
        builder: (context, ref, _) {
          final device = ref.watch(deviceProvider(id));
          if (device == null) return const SizedBox.shrink();
          return RepaintBoundary(
            child: DriveCard(
              device: device,
              thresholds: settings.thresholdsFor(device.id),
              unit: settings.temperatureUnit,
              onTap: () => onOpenDevice(device.id),
              compactMode: compact,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compactView) {
      // One surface, hairline-separated rows (a table, not a stack of cards).
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xs,
          AppSpacing.page,
          AppSpacing.page,
        ),
        child: Surface(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                if (i > 0) Divider(height: 1, color: hairlineOf(context)),
                _card(ids[i], compact: true),
              ],
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.xs,
            AppSpacing.page,
            AppSpacing.page,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 208,
              crossAxisSpacing: AppSpacing.gap,
              mainAxisSpacing: AppSpacing.gap,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _card(ids[index], compact: false),
              childCount: ids.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_rounded, size: 28, color: faintOf(context)),
            const SizedBox(height: AppSpacing.md),
            Text('No storage devices found', style: AppText.heading(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'DriveGuard detects NVMe, SATA, and USB drives automatically.',
              textAlign: TextAlign.center,
              style: AppText.secondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
