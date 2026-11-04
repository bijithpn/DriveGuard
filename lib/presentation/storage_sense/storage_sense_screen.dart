import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/storage_sense/storage_sense_controller.dart';
import '../../domain/entities/cleanup_item.dart';
import '../theme/app_theme.dart';
import 'parts/cleanup_tiles.dart';
import 'parts/usage_donut.dart';

/// Disk-space cleaner: shows what is using space, groups reclaimable data by
/// how risky it is to delete, and removes it safely.
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clean ${items.length} item${items.length == 1 ? '' : 's'}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (permanent.isNotEmpty)
              _ConfirmLine(
                icon: Icons.verified_user_rounded,
                color: AppColors.normal,
                text:
                    '${permanent.length} safe item${permanent.length == 1 ? '' : 's'} '
                    '(${formatBytes(permBytes)}) will be deleted permanently. '
                    'Apps recreate them automatically.',
              ),
            if (adminCount > 0)
              _ConfirmLine(
                icon: Icons.admin_panel_settings_outlined,
                color: AppColors.accent,
                text:
                    '$adminCount system folder${adminCount == 1 ? '' : 's'} '
                    'need administrator permission. Your computer will ask for '
                    'your password once. DriveGuard never sees it.',
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: const Text('Clean'),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storageSenseProvider);
    final ctl = ref.read(storageSenseProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final devices = ref.watch(devicesProvider);
    final usage = homeVolumeUsage(devices);
    final busy =
        state.status == SenseStatus.scanning ||
        state.status == SenseStatus.deleting;

    final grouped = <CleanupCategory, List<CleanupItem>>{};
    for (final i in state.visible) {
      grouped.putIfAbsent(i.category, () => []).add(i);
    }
    final order = grouped.keys.toList()
      ..sort((a, b) {
        int sum(CleanupCategory c) =>
            grouped[c]!.fold<int>(0, (s, i) => s + i.sizeBytes);
        return sum(b).compareTo(sum(a));
      });
    final maxBytes = order.isEmpty
        ? 0
        : grouped[order.first]!.fold<int>(0, (s, i) => s + i.sizeBytes);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              children: [
                _Header(
                  usage: usage,
                  scanning: state.status == SenseStatus.scanning,
                  onRescan: busy ? null : ctl.scan,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _SearchField(
                    controller: _search,
                    onChanged: ctl.setQuery,
                    isDark: isDark,
                  ),
                ),
                if (state.status == SenseStatus.scanning)
                  LinearProgressIndicator(
                    value: state.progress == 0 ? null : state.progress,
                    minHeight: 2,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [
                      _HeroCard(
                        state: state,
                        usage: usage,
                        isDark: isDark,
                        onSelectSafe: busy ? null : ctl.selectSafe,
                      ),
                      const SizedBox(height: 14),
                      if (state.message != null)
                        _Banner(
                          text: state.message!,
                          color: AppColors.normal,
                          icon: Icons.check_circle_rounded,
                        ),
                      if (state.hasScanned && order.isEmpty)
                        _EmptyState(scanning: busy, query: state.query),
                      for (final c in order)
                        CategoryGroup(
                          key: ValueKey(c),
                          category: c,
                          items: grouped[c]!,
                          selected: state.selected,
                          maxBytes: maxBytes,
                          busy: busy,
                          onToggle: ctl.toggle,
                          onToggleAll: (v) {
                            for (final i in grouped[c]!) {
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
                _BottomBar(
                  state: state,
                  busy: busy,
                  isDark: isDark,
                  onClear: ctl.clearSelection,
                  onClean: () => _confirmDelete([
                    for (final i in state.items)
                      if (state.selected.contains(i.id)) i,
                  ]),
                ),
              ],
            ),
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
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Flexible(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.usage, required this.scanning, this.onRescan});
  final VolumeUsage? usage;
  final bool scanning;
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.normal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.cleaning_services_rounded,
              color: AppColors.normal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Storage Sense',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  usage == null
                      ? 'Find and remove files you don’t need'
                      : '${usage!.name} · ${formatBytes(usage!.used)} used of ${formatBytes(usage!.total)}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Scan again',
            icon: scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: onRescan,
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.isDark,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Filter',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        filled: true,
        fillColor: isDark ? AppColors.bg1 : AppColors.lightSurfaceMuted,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.state,
    required this.usage,
    required this.isDark,
    required this.onSelectSafe,
  });

  final StorageSenseState state;
  final VolumeUsage? usage;
  final bool isDark;
  final VoidCallback? onSelectSafe;

  @override
  Widget build(BuildContext context) {
    final safe = state.bytesFor(CleanupSafety.safe);
    final review = state.bytesFor(CleanupSafety.review);
    final manual = state.bytesFor(CleanupSafety.manual);
    final scanned = safe + review + manual;
    final used = usage?.used ?? scanned;
    final other = (used - scanned).clamp(0, 1 << 62);
    final free = usage?.free ?? 0;
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final lowFree =
        usage != null && usage!.total > 0 && usage!.free / usage!.total < 0.15;

    final rows = <(String, int, Color)>[
      ('Safe', safe, AppColors.normal),
      ('Review', review, AppColors.warning),
      ('Manual', manual, AppColors.accent),
      (
        'Other files',
        other.toInt(),
        isDark ? AppColors.bg3 : const Color(0xFFB9C2CE),
      ),
      ('Free', free, Colors.transparent),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.normal.withValues(alpha: isDark ? 0.22 : 0.3),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF12301F), AppColors.bg1]
              : [const Color(0xFFE6F8EE), Colors.white],
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 20,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              UsageDonut(
                trackColor: isDark ? Colors.white10 : Colors.black12,
                segments: [
                  DonutSegment(safe.toDouble(), AppColors.normal),
                  DonutSegment(review.toDouble(), AppColors.warning),
                  DonutSegment(manual.toDouble(), AppColors.accent),
                  DonutSegment(
                    other.toDouble(),
                    isDark ? const Color(0xFF3A4350) : const Color(0xFFB9C2CE),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.status == SenseStatus.scanning && !state.hasScanned
                          ? '…'
                          : formatBytes(safe),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.normal,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'safe to free now',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      onPressed: onSelectSafe,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.normal,
                        foregroundColor: const Color(0xFF06260F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Select safe'),
                    ),
                    const SizedBox(height: 16),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: r.$3,
                                borderRadius: BorderRadius.circular(4),
                                border: r.$3 == Colors.transparent
                                    ? Border.all(color: muted, width: 1.5)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                r.$1,
                                style: TextStyle(fontSize: 13.5, color: muted),
                              ),
                            ),
                            Text(
                              formatBytes(r.$2),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: 18),
            _FreeSpaceStrip(usage: usage!, low: lowFree, muted: muted),
          ],
        ],
      ),
    );
  }
}

class _FreeSpaceStrip extends StatelessWidget {
  const _FreeSpaceStrip({
    required this.usage,
    required this.low,
    required this.muted,
  });
  final VolumeUsage usage;
  final bool low;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final freePct = usage.total == 0 ? 0 : usage.free / usage.total * 100;
    final color = low ? AppColors.warning : AppColors.normal;
    final tip = usage.isSsd
        ? (low
              ? 'Only ${freePct.toStringAsFixed(0)}% free. SSDs run hotter and wear faster when nearly full — aim for 15–20% free.'
              : 'Healthy: ${freePct.toStringAsFixed(0)}% free. Keeping 15–20% free helps your SSD last longer.')
        : '${freePct.toStringAsFixed(0)}% free on this volume.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            low ? Icons.warning_amber_rounded : Icons.favorite_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: AppDecorations.statusHighlight(color: color, radius: 14),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, required this.query});
  final bool scanning;
  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(
          query.isEmpty ? Icons.celebration_rounded : Icons.search_off_rounded,
          size: 40,
          color: AppColors.normal,
        ),
        const SizedBox(height: 12),
        Text(
          query.isEmpty ? 'Nothing to clean up' : 'No matches for “$query”',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.busy,
    required this.isDark,
    required this.onClean,
    required this.onClear,
  });
  final VoidCallback onClear;
  final StorageSenseState state;
  final bool busy;
  final bool isDark;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final count = state.selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg1 : AppColors.lightCard,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.divider : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: AppColors.normal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.reclaimedBytes > 0 || state.trashedBytes > 0
                  ? 'Reclaimed this session: ${formatBytes(state.reclaimedBytes)}'
                        '${state.trashedBytes > 0 ? ' (+${formatBytes(state.trashedBytes)} in Trash)' : ''}'
                  : 'Nothing reclaimed yet',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.normal,
              ),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.critical,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            icon: state.status == SenseStatus.deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_rounded, size: 18),
            label: Text(
              count == 0
                  ? 'Delete selected'
                  : 'Delete $count · ${formatBytes(state.selectedBytes)}',
            ),
          ),
        ],
      ),
    );
  }
}
