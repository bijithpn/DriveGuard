import 'package:flutter/material.dart';

import '../../../application/storage_sense/storage_sense_controller.dart';
import '../../../domain/entities/cleanup_item.dart';
import '../../theme/app_theme.dart';

Color safetyColor(CleanupSafety s) => switch (s) {
  CleanupSafety.safe => AppColors.normal,
  CleanupSafety.review => AppColors.warning,
  CleanupSafety.manual => AppColors.accent,
};

String safetyLabel(CleanupSafety s) => switch (s) {
  CleanupSafety.safe => 'Safe',
  CleanupSafety.review => 'Review',
  CleanupSafety.manual => 'Manual',
};

IconData safetyIcon(CleanupSafety s) => switch (s) {
  CleanupSafety.safe => Icons.verified_user_rounded,
  CleanupSafety.review => Icons.visibility_rounded,
  CleanupSafety.manual => Icons.pan_tool_alt_rounded,
};

IconData categoryIcon(CleanupCategory c) => switch (c) {
  CleanupCategory.systemCaches => Icons.layers_rounded,
  CleanupCategory.logs => Icons.receipt_long_rounded,
  CleanupCategory.trash => Icons.delete_sweep_rounded,
  CleanupCategory.developer => Icons.construction_rounded,
  CleanupCategory.packages => Icons.inventory_2_rounded,
  CleanupCategory.downloads => Icons.download_rounded,
};

Color categoryColor(CleanupCategory c) => switch (c) {
  CleanupCategory.systemCaches => const Color(0xFF7C8CFF),
  CleanupCategory.logs => const Color(0xFF9AA5B4),
  CleanupCategory.trash => const Color(0xFFFF7A90),
  CleanupCategory.developer => const Color(0xFFB36BFF),
  CleanupCategory.packages => const Color(0xFF39C5CF),
  CleanupCategory.downloads => const Color(0xFF5B9DFF),
};

class SafetyBadge extends StatelessWidget {
  const SafetyBadge(this.safety, {super.key});
  final CleanupSafety safety;

  @override
  Widget build(BuildContext context) {
    final c = safetyColor(safety);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(safetyIcon(safety), size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            safetyLabel(safety),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryGroup extends StatefulWidget {
  const CategoryGroup({
    super.key,
    required this.category,
    required this.items,
    required this.selected,
    required this.maxBytes,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
    required this.onReveal,
    required this.onToggleAll,
  });

  final CleanupCategory category;
  final List<CleanupItem> items;
  final Set<String> selected;
  final int maxBytes;
  final bool busy;
  final ValueChanged<String> onToggle;
  final ValueChanged<CleanupItem> onDelete;
  final ValueChanged<String> onReveal;
  final ValueChanged<bool> onToggleAll;

  @override
  State<CategoryGroup> createState() => _CategoryGroupState();
}

class _CategoryGroupState extends State<CategoryGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.items.fold<int>(0, (s, i) => s + i.sizeBytes);
    int bytes(CleanupSafety s) => widget.items
        .where((i) => i.safety == s)
        .fold<int>(0, (a, i) => a + i.sizeBytes);
    final color = categoryColor(widget.category);
    final allSelected = widget.items.every(
      (i) => widget.selected.contains(i.id),
    );
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final fraction = widget.maxBytes == 0 ? 0.0 : total / widget.maxBytes;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppDecorations.card(isDark: isDark, elevated: false),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _open
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 20,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Checkbox(
                        value: allSelected,
                        onChanged: widget.busy
                            ? null
                            : (v) => widget.onToggleAll(v ?? false),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          categoryIcon(widget.category),
                          size: 18,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.category.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${widget.items.length} item'
                              '${widget.items.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 11.5, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatBytes(total),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: _StackedBar(
                      fraction: fraction,
                      safe: bytes(CleanupSafety.safe),
                      review: bytes(CleanupSafety.review),
                      manual: bytes(CleanupSafety.manual),
                      track: isDark ? AppColors.bg3 : AppColors.lightBorder,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            for (final item in widget.items)
              CleanupTile(
                item: item,
                selected: widget.selected.contains(item.id),
                busy: widget.busy,
                onToggle: () => widget.onToggle(item.id),
                onDelete: () => widget.onDelete(item),
                onReveal: () => widget.onReveal(item.path),
              ),
        ],
      ),
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({
    required this.fraction,
    required this.safe,
    required this.review,
    required this.manual,
    required this.track,
  });

  final double fraction;
  final int safe;
  final int review;
  final int manual;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final total = safe + review + manual;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 6,
        color: track,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.02, 1.0),
          child: total == 0
              ? null
              : Row(
                  children: [
                    if (safe > 0)
                      Expanded(
                        flex: safe,
                        child: Container(color: AppColors.normal),
                      ),
                    if (review > 0)
                      Expanded(
                        flex: review,
                        child: Container(color: AppColors.warning),
                      ),
                    if (manual > 0)
                      Expanded(
                        flex: manual,
                        child: Container(color: AppColors.accent),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class CleanupTile extends StatefulWidget {
  const CleanupTile({
    super.key,
    required this.item,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
    required this.onReveal,
  });

  final CleanupItem item;
  final bool selected;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onReveal;

  @override
  State<CleanupTile> createState() => _CleanupTileState();
}

class _CleanupTileState extends State<CleanupTile> {
  bool _hover = false;

  String? _age() {
    final m = widget.item.lastModified;
    if (m == null) return null;
    final d = DateTime.now().difference(m);
    if (d.inDays >= 365) return '${d.inDays ~/ 365}y idle';
    if (d.inDays >= 30) return '${d.inDays ~/ 30} mo idle';
    if (d.inDays >= 2) return '${d.inDays}d idle';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.textSecondary
        : AppColors.lightTextSecondary;
    final item = widget.item;
    final age = _age();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.busy ? null : widget.onToggle,
        child: Container(
          decoration: BoxDecoration(
            color: _hover
                ? (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.035,
                  )
                : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.divider : AppColors.lightBorder,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(46, 10, 12, 10),
          child: Row(
            children: [
              Checkbox(
                value: widget.selected,
                onChanged: widget.busy ? null : (_) => widget.onToggle(),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SafetyBadge(item.safety),
                        if (item.requiresAdmin) ...[
                          const SizedBox(width: 6),
                          const _AdminChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [?age, item.description].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${item.sizeIsPartial ? '≥ ' : ''}${formatBytes(item.sizeBytes)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              AnimatedOpacity(
                duration: AppDurations.fast,
                opacity: _hover ? 1 : 0.55,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Show in file manager',
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      onPressed: widget.onReveal,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: item.safety == CleanupSafety.safe
                          ? 'Delete'
                          : 'Move to Trash',
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      onPressed: widget.busy ? null : widget.onDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminChip extends StatelessWidget {
  const _AdminChip();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'System folder — asks for your administrator password',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 11),
          SizedBox(width: 4),
          Text(
            'Admin',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
