import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/monitoring/metric_history_store.dart';
import '../../application/providers.dart';
import '../../application/storage_sense/storage_sense_controller.dart';
import '../../domain/entities/cleanup_item.dart';
import '../components/app_shell.dart';
import '../components/ui_kit.dart';
import '../theme/app_theme.dart';
import 'parts/cleanup_tiles.dart';
import 'parts/trend_sparkline.dart';
import 'parts/usage_donut.dart';

/// Disk-space cleaner: what is using space, grouped by how risky it is to
/// delete, and a safe way to remove it.
class StorageSenseScreen extends ConsumerStatefulWidget {
  const StorageSenseScreen({super.key});

  @override
  ConsumerState<StorageSenseScreen> createState() => _StorageSenseScreenState();
}

class _StorageSenseScreenState extends ConsumerState<StorageSenseScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!ref.read(storageSenseProvider).hasScanned) {
        ref.read(storageSenseProvider.notifier).scan();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(List<CleanupItem> items) async {
    if (items.isEmpty) return;
    final permanent = items.where((i) => i.safety == CleanupSafety.safe);
    final trash = items.where((i) => i.safety != CleanupSafety.safe);
    final adminCount = items.where((i) => i.requiresAdmin).length;
    final permBytes = permanent.fold<int>(0, (s, i) => s + i.sizeBytes);
    final trashBytes = trash.fold<int>(0, (s, i) => s + i.sizeBytes);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clean ${items.length} item${items.length == 1 ? '' : 's'}?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (permanent.isNotEmpty)
                _ConfirmLine(
                  icon: Icons.verified_user_outlined,
                  color: AppColors.normal,
                  text:
                      '${permanent.length} safe item${permanent.length == 1 ? '' : 's'} '
                      '(${formatBytes(permBytes)}) will be deleted permanently. '
                      'Apps recreate them automatically.',
                ),
              if (trash.isNotEmpty)
                _ConfirmLine(
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.warning,
                  text:
                      '${trash.length} item${trash.length == 1 ? '' : 's'} '
                      '(${formatBytes(trashBytes)}) will be moved to the Trash, '
                      'so you can still restore them.',
                ),
              if (adminCount > 0)
                _ConfirmLine(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.accent,
                  text:
                      '$adminCount system folder${adminCount == 1 ? '' : 's'} '
                      'need administrator permission. Your computer will ask for '
                      'your password once. DriveGuard never sees it.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clean'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(storageSenseProvider.notifier).deleteItems({
        for (final i in items) i.id,
      });
    }
  }

  Future<void> _confirmEmptyTrash(int bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty the Trash?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const Text(
            'This permanently deletes everything in your Trash — including '
            'files that were there before you used DriveGuard — and cannot be '
            'undone.',
            style: TextStyle(height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.critical,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(storageSenseProvider.notifier).emptyTrash();
    }
  }

  List<SenseGroup> _groups(StorageSenseState state) {
    final items = state.visible;
    final byKey = <String, List<CleanupItem>>{};
    final meta = <String, (String, IconData)>{};
    for (final i in items) {
      final String key;
      if (state.groupByProject && i.project != null) {
        key = 'p:${i.project}';
        meta[key] = (i.project!, Icons.folder_special_outlined);
      } else {
        key = 'c:${i.category.name}';
        meta[key] = (i.category.label, categoryIcon(i.category));
      }
      byKey.putIfAbsent(key, () => []).add(i);
    }
    final groups = [
      for (final e in byKey.entries)
        SenseGroup(e.key, meta[e.key]!.$1, meta[e.key]!.$2, e.value),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storageSenseProvider);
    final ctl = ref.read(storageSenseProvider.notifier);
    final devices = ref.watch(devicesProvider);
    final usage = homeVolumeUsage(devices);
    final busy =
        state.status == SenseStatus.scanning ||
        state.status == SenseStatus.deleting;
    final groups = _groups(state);

    return AppShell(
      section: AppSection.storage,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    PageHeader(
                      title: 'Storage Sense',
                      subtitle: usage == null
                          ? 'Find and remove files you don’t need'
                          : '${usage.name}  ·  ${formatBytes(usage.used)} used of ${formatBytes(usage.total)}',
                      actions: [
                        OutlinedButton.icon(
                          onPressed: busy ? null : ctl.scan,
                          icon: state.status == SenseStatus.scanning
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            state.status == SenseStatus.scanning
                                ? 'Scanning…'
                                : 'Scan again',
                          ),
                        ),
                      ],
                    ),
                    _ScanStrip(state: state, onStop: ctl.cancelScan),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.page,
                          AppSpacing.xs,
                          AppSpacing.page,
                          AppSpacing.page,
                        ),
                        children: [
                          _HeroCard(
                            state: state,
                            usage: usage,
                            onSelectSafe: busy ? null : ctl.selectSafe,
                          ),
                          const SizedBox(height: AppSpacing.section),
                          Row(
                            children: [
                              SegmentedSwitch<bool>(
                                value: state.groupByProject,
                                options: const [
                                  (
                                    false,
                                    'By category',
                                    Icons.grid_view_rounded,
                                  ),
                                  (true, 'By project', Icons.folder_outlined),
                                ],
                                onChanged: ctl.setGroupByProject,
                              ),
                              const Spacer(),
                              SizedBox(
                                width: 240,
                                child: _SearchField(
                                  controller: _search,
                                  onChanged: ctl.setQuery,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (state.message != null) ...[
                            _Notice(text: state.message!),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          if (state.hasScanned && groups.isEmpty)
                            _EmptyState(query: state.query),
                          for (final g in groups)
                            CategoryGroup(
                              key: ValueKey(g.key),
                              group: g,
                              selected: state.selected,
                              busy: busy,
                              onToggle: ctl.toggle,
                              onToggleAll: (v) {
                                for (final i in g.items) {
                                  final has = state.selected.contains(i.id);
                                  if (v != has) ctl.toggle(i.id);
                                }
                              },
                              onDelete: (item) => _confirmDelete([item]),
                              onReveal: ctl.reveal,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _BottomBar(
            state: state,
            busy: busy,
            onClear: ctl.clearSelection,
            onEmptyTrash: () => _confirmEmptyTrash(state.trashedBytes),
            onClean: () => _confirmDelete([
              for (final i in state.items)
                if (state.selected.contains(i.id)) i,
            ]),
          ),
        ],
      ),
    );
  }
}

/// Live scan status: determinate bar, "n of m", what is being read right now
/// and how much has been found so far. Collapses away when idle.
class _ScanStrip extends StatelessWidget {
  const _ScanStrip({required this.state, required this.onStop});
  final StorageSenseState state;
  final VoidCallback onStop;

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'moments ago';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final scanning = state.status == SenseStatus.scanning;
    final p = state.scanProgress;
    final frac = p?.fraction;
    String left;
    if (p == null || p.listing) {
      left = 'Preparing scan…';
    } else {
      left = 'Scanning · ${p.done} of ${p.total}';
    }
    final stale = state.cachedAt;

    return AnimatedSize(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      child: !scanning
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.gap,
              ),
              child: Surface(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            left,
                            style: AppText.body(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (p != null && p.foundBytes > 0)
                          Text(
                            '${formatBytes(p.foundBytes)} found',
                            style: AppText.body(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.normal,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: onStop,
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 4,
                          backgroundColor: isDarkOf(context)
                              ? AppColors.bg3
                              : AppColors.lightBorder,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        stale != null
                            ? 'Showing your last scan from ${_ago(stale)} while it refreshes'
                            : (p == null || p.current.isEmpty
                                  ? 'Reading folders…'
                                  : 'Reading ${p.current}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ConfirmLine extends StatelessWidget {
  const _ConfirmLine({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Filter',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        fillColor: dark ? AppColors.bg1 : AppColors.lightSurfaceMuted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: dark ? AppColors.border : AppColors.lightBorder,
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({
    required this.state,
    required this.usage,
    required this.onSelectSafe,
  });

  final StorageSenseState state;
  final VolumeUsage? usage;
  final VoidCallback? onSelectSafe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDarkOf(context);
    final safe = state.bytesFor(CleanupSafety.safe);
    final review = state.bytesFor(CleanupSafety.review);
    final manual = state.bytesFor(CleanupSafety.manual);
    final scanned = safe + review + manual;
    final used = usage?.used ?? scanned;
    final other = (used - scanned).clamp(0, 1 << 62).toInt();
    final free = usage?.free ?? 0;
    final scanning = state.status == SenseStatus.scanning;
    final otherColor = dark ? const Color(0xFF39414C) : const Color(0xFFC3CBD6);

    final legend = <(String, int, Color?)>[
      ('Safe to remove', safe, AppColors.normal),
      ('Needs review', review, AppColors.warning),
      ('Personal files', manual, AppColors.accent),
      ('Everything else', other, otherColor),
      ('Free space', free, null),
    ];

    // Usage trend for the sparkline (persisted across restarts).
    final List<MetricPoint> history = usage?.deviceId == null
        ? const []
        : ref.read(capacityHistoryStoreProvider).pointsFor(usage!.deviceId!);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recent = [
      for (final p in history)
        if (p.timestamp.isAfter(weekAgo)) p,
    ];
    String? trendText;
    if (recent.length >= 2 && usage != null) {
      final delta =
          (recent.last.value - recent.first.value) / 100 * usage!.total;
      trendText =
          '${delta >= 0 ? '+' : '−'}${formatBytes(delta.abs().round())} this week';
    }

    return Surface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UsageDonut(
                size: 176,
                thickness: 14,
                trackColor: dark ? Colors.white10 : Colors.black12,
                // Same key for the whole scan → no restarts while results
                // stream in; the breakdown animates in once when it ends.
                animationKey: scanning ? 'scan' : 'done',
                total: scanning ? 1.0 : null,
                segments: scanning
                    ? [
                        DonutSegment(
                          state.progress.clamp(0.02, 1.0),
                          AppColors.accent,
                        ),
                      ]
                    : [
                        DonutSegment(safe.toDouble(), AppColors.normal),
                        DonutSegment(review.toDouble(), AppColors.warning),
                        DonutSegment(manual.toDouble(), AppColors.accent),
                        DonutSegment(other.toDouble(), otherColor),
                      ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scanning
                          ? '${(state.progress * 100).round()}%'
                          : formatBytes(safe),
                      style: AppText.metric(context, size: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scanning ? 'scanning' : 'safe to free',
                      style: AppText.caption(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanning
                          ? 'Looking for files you can remove…'
                          : (safe > 0
                                ? 'You can free ${formatBytes(safe)} right now'
                                : 'Nothing safe to remove right now'),
                      style: AppText.heading(context).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review > 0
                          ? '${formatBytes(review)} more is worth a look before deleting.'
                          : 'Safe items are caches and logs that apps recreate.',
                      style: AppText.secondary(context),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final r in legend)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: r.$3 ?? Colors.transparent,
                                shape: BoxShape.circle,
                                border: r.$3 == null
                                    ? Border.all(
                                        color: faintOf(context),
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                r.$1,
                                style: AppText.secondary(context),
                              ),
                            ),
                            Text(
                              formatBytes(r.$2),
                              style: AppText.body(context).copyWith(
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: onSelectSafe,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Select all safe items'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: hairlineOf(context)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text('USAGE · LAST 7 DAYS', style: AppText.label(context)),
                const Spacer(),
                if (trendText != null)
                  Text(
                    trendText,
                    style: AppText.secondary(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (recent.length >= 2)
              TrendSparkline(points: recent)
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'The trend appears after DriveGuard has watched this drive for a while.',
                  style: AppText.caption(context),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            _FreeSpaceNote(usage: usage!),
          ],
        ],
      ),
    );
  }
}

class _FreeSpaceNote extends StatelessWidget {
  const _FreeSpaceNote({required this.usage});
  final VolumeUsage usage;

  @override
  Widget build(BuildContext context) {
    final freePct = usage.total == 0 ? 0 : usage.free / usage.total * 100;
    final low = freePct < 15;
    final text = usage.isSsd
        ? (low
              ? 'Only ${freePct.toStringAsFixed(0)}% free. SSDs run hotter and wear faster when nearly full — aim for 15–20% free.'
              : '${freePct.toStringAsFixed(0)}% free. Keeping 15–20% free helps your SSD last longer.')
        : '${freePct.toStringAsFixed(0)}% free on this volume.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          low ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
          size: 16,
          color: low ? AppColors.warning : faintOf(context),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.secondary(context))),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    borderColor: AppColors.normal.withValues(alpha: 0.4),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          size: 18,
          color: AppColors.normal,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: AppText.body(context))),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Icon(
          query.isEmpty
              ? Icons.check_circle_outline_rounded
              : Icons.search_off_rounded,
          size: 28,
          color: faintOf(context),
        ),
        const SizedBox(height: 12),
        Text(
          query.isEmpty ? 'Nothing to clean up' : 'No matches for “$query”',
          style: AppText.heading(context),
        ),
      ],
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.busy,
    required this.onClear,
    required this.onClean,
    required this.onEmptyTrash,
  });
  final StorageSenseState state;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onClean;
  final VoidCallback onEmptyTrash;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    final count = state.selected.length;
    final reclaimed = state.reclaimedBytes;
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(top: BorderSide(color: hairlineOf(context))),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: 12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 960 - AppSpacing.page * 2,
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_rounded,
                size: 16,
                color: reclaimed > 0 ? AppColors.normal : faintOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reclaimed > 0
                      ? 'Reclaimed this session: ${formatBytes(reclaimed)}'
                      : 'Nothing reclaimed yet',
                  style: AppText.secondary(context),
                ),
              ),
              if (state.trashedBytes > 0)
                TextButton.icon(
                  onPressed: busy ? null : onEmptyTrash,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                  label: Text(
                    'Empty Trash · ${formatBytes(state.trashedBytes)}',
                  ),
                ),
              if (count > 0)
                TextButton(
                  onPressed: busy ? null : onClear,
                  child: const Text('Clear'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: count == 0 || busy ? null : onClean,
                icon: state.status == SenseStatus.deleting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 17),
                label: Text(
                  count == 0
                      ? 'Clean selected'
                      : 'Clean $count · ${formatBytes(state.selectedBytes)}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
