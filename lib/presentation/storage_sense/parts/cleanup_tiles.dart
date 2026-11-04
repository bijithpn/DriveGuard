import 'package:flutter/material.dart';

import '../../../application/storage_sense/storage_sense_controller.dart';
import '../../../domain/entities/cleanup_item.dart';
import '../../components/ui_kit.dart';
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

IconData categoryIcon(CleanupCategory c) => switch (c) {
  CleanupCategory.systemCaches => Icons.layers_outlined,
  CleanupCategory.logs => Icons.receipt_long_outlined,
  CleanupCategory.trash => Icons.delete_sweep_outlined,
  CleanupCategory.developer => Icons.construction_rounded,
  CleanupCategory.packages => Icons.inventory_2_outlined,
  CleanupCategory.downloads => Icons.download_outlined,
  CleanupCategory.projects => Icons.folder_outlined,
};

/// A named bundle of items shown as one collapsible group.
class SenseGroup {
  const SenseGroup(this.key, this.label, this.icon, this.items);
  final String key;
  final String label;
  final IconData icon;
  final List<CleanupItem> items;

  int get bytes => items.fold<int>(0, (s, i) => s + i.sizeBytes);
}

/// "● Safe" — colour only on a small dot; the word stays quiet.
class SafetyTag extends StatelessWidget {
  const SafetyTag(this.safety, {super.key});
  final CleanupSafety safety;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(safetyColor(safety), size: 6),
      const SizedBox(width: 5),
      Text(
        safetyLabel(safety),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: safetyColor(safety),
        ),
      ),
    ],
  );
}

class CategoryGroup extends StatefulWidget {
  const CategoryGroup({
    super.key,
    required this.group,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
    required this.onReveal,
    required this.onToggleAll,
  });

  final SenseGroup group;
  final Set<String> selected;
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
    final g = widget.group;
    final selectedCount = g.items
        .where((i) => widget.selected.contains(i.id))
        .length;
    final all = selectedCount == g.items.length;
    final some = selectedCount > 0 && !all;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.gap),
      child: Surface(
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Checkbox(
                          tristate: true,
                          value: all ? true : (some ? null : false),
                          onChanged: widget.busy
                              ? null
                              : (_) => widget.onToggleAll(!all),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(g.icon, size: 18, color: mutedOf(context)),
                      const SizedBox(width: 10),
                      Text(g.label, style: AppText.heading(context)),
                      const SizedBox(width: 8),
                      Text(
                        '${g.items.length}',
                        style: AppText.caption(context),
                      ),
                      const Spacer(),
                      Text(
                        formatBytes(g.bytes),
                        style: AppText.heading(context).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              _open
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: faintOf(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_open)
              for (final item in g.items)
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
    if (d.inDays >= 365) return 'Unused for ${d.inDays ~/ 365} y';
    if (d.inDays >= 30) return 'Unused for ${d.inDays ~/ 30} mo';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dark = isDarkOf(context);
    final age = _age();
    final sub = [?age, item.description].join('  ·  ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.busy ? null : widget.onToggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accent.withValues(alpha: dark ? 0.08 : 0.06)
                : (_hover
                      ? (dark ? Colors.white : Colors.black).withValues(
                          alpha: 0.025,
                        )
                      : Colors.transparent),
            border: Border(top: BorderSide(color: hairlineOf(context))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: widget.busy ? null : (_) => widget.onToggle(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 12),
              // Aligns with the group header's icon column.
              const SizedBox(width: 28),
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
                            style: AppText.body(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SafetyTag(item.safety),
                        if (item.requiresAdmin) ...[
                          const SizedBox(width: 10),
                          Tooltip(
                            message:
                                'System folder — asks for your administrator password',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 12,
                                  color: faintOf(context),
                                ),
                                const SizedBox(width: 3),
                                Text('Admin', style: AppText.caption(context)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondary(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${item.sizeIsPartial ? '≥ ' : ''}${formatBytes(item.sizeBytes)}',
                style: AppText.body(context).copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(
                width: 80,
                child: AnimatedOpacity(
                  duration: AppDurations.fast,
                  opacity: _hover ? 1 : 0,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Show in file manager',
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        onPressed: widget.onReveal,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: item.safety == CleanupSafety.safe
                            ? 'Delete'
                            : 'Move to Trash',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        onPressed: widget.busy ? null : widget.onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
