part of '../settings_screen.dart';

class _WidgetSection extends ConsumerWidget {
  const _WidgetSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final widgetActive = ref.watch(widgetModeActiveProvider);

    final rows = [
      _SettingRow(
        label: 'Enable mini monitor widget',
        isDark: isDark,
        trailing: Switch(
          value: widgetActive,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(enabled: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Always on top',
        isDark: isDark,
        trailing: Switch(
          value: settings.widget.alwaysOnTop,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(alwaysOnTop: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Compact mode',
        isDark: isDark,
        isLast: true,
        trailing: Switch(
          value: settings.widget.compact,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(widget: s.widget.copyWith(compact: v)),
          ),
        ),
      ),
    ];

    final edgeDockActive = ref.watch(edgeDockActiveProvider);
    final edgeDockRows = [
      _SettingRow(
        label: 'Enable edge dock',
        subtitle: 'A slim hover strip docked to a screen edge',
        isDark: isDark,
        trailing: Switch(
          value: edgeDockActive,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(enabled: v)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock position',
        isDark: isDark,
        trailing: _SegmentedControl<ScreenEdge>(
          isDark: isDark,
          selected: settings.edgeDock.edge,
          options: const [
            (ScreenEdge.left, 'Left'),
            (ScreenEdge.right, 'Right'),
            (ScreenEdge.top, 'Top'),
            (ScreenEdge.bottom, 'Bottom'),
          ],
          onChanged: (edge) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(edge: edge)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock color',
        isDark: isDark,
        trailing: _EdgeDockAccentPicker(
          selected: settings.edgeDock.accent,
          onChanged: (accent) => notifier.updateWith(
            (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(accent: accent)),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock opacity',
        isDark: isDark,
        trailing: SizedBox(
          width: 140,
          child: _EdgeDockOpacitySlider(
            value: settings.edgeDock.opacity,
            onChangeEnd: (v) => notifier.updateWith(
              (s) => s.copyWith(edgeDock: s.edgeDock.copyWith(opacity: v)),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Edge dock display',
        subtitle: 'Which monitor the dock attaches to',
        isDark: isDark,
        trailing: _EdgeDockDisplayPicker(
          selected: settings.edgeDock.displayId,
          isDark: isDark,
          onChanged: (id) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                displayId: id,
                clearDisplayId: id == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Panel background',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _backgroundSwatches,
          selected: settings.edgeDock.backgroundColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                backgroundColor: v,
                clearBackgroundColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Panel text',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _textSwatches,
          selected: settings.edgeDock.textColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                textColor: v,
                clearTextColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Warning color',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _warningSwatches,
          selected: settings.edgeDock.warningColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                warningColor: v,
                clearWarningColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Critical color',
        isDark: isDark,
        trailing: _ColorSwatchPicker(
          options: _criticalSwatches,
          selected: settings.edgeDock.criticalColor,
          onChanged: (v) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(
                criticalColor: v,
                clearCriticalColor: v == null,
              ),
            ),
          ),
        ),
      ),
      _SettingRow(
        label: 'Hover panel fields',
        subtitle:
            'Which rows show in the detail panel (temperature always shows)',
        isDark: isDark,
        isLast: true,
        trailing: _EdgeDockMetricToggles(
          selected: settings.edgeDock.visibleMetrics,
          isDark: isDark,
          onChanged: (metrics) => notifier.updateWith(
            (s) => s.copyWith(
              edgeDock: s.edgeDock.copyWith(visibleMetrics: metrics),
            ),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionGroup(isDark: isDark, children: rows),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(title: 'Edge Dock', isDark: isDark),
        const SizedBox(height: AppSpacing.sm),
        _SectionGroup(isDark: isDark, children: edgeDockRows),
      ],
    );
  }
}

class _EdgeDockAccentPicker extends StatelessWidget {
  const _EdgeDockAccentPicker({
    required this.selected,
    required this.onChanged,
  });

  final EdgeDockAccent selected;
  final ValueChanged<EdgeDockAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: EdgeDockAccent.values.map((accent) {
        final isSelected = accent == selected;
        final color = resolveAccent(accent) ?? AppColors.textMuted;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: accent == EdgeDockAccent.auto
                ? 'Auto (by severity)'
                : accent.name,
            child: GestureDetector(
              onTap: () => onChanged(accent),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accent == EdgeDockAccent.auto
                      ? Colors.transparent
                      : color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? color : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: accent == EdgeDockAccent.auto
                    ? const Icon(
                        Icons.auto_awesome_rounded,
                        size: 11,
                        color: AppColors.textMuted,
                      )
                    : (isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Colors.white,
                            )
                          : null),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Opacity slider for the edge dock. Keeps the dragged value in local state
/// and only commits it (via [onChangeEnd]) once the drag finishes, instead
/// of on every [Slider.onChanged] tick. Committing on every tick used to
/// write straight into [AppSettings] and re-dock the whole edge-dock window
/// (close + reopen) on each intermediate value while dragging - visibly
/// laggy, and it could drop/reset the current hover state mid-drag.
class _EdgeDockOpacitySlider extends StatefulWidget {
  const _EdgeDockOpacitySlider({
    required this.value,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_EdgeDockOpacitySlider> createState() => _EdgeDockOpacitySliderState();
}

class _EdgeDockOpacitySliderState extends State<_EdgeDockOpacitySlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(_EdgeDockOpacitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _value,
      min: 0.85,
      max: 1.0,
      divisions: 3,
      label: '${(_value * 100).round()}%',
      onChanged: (v) => setState(() => _value = v),
      onChangeEnd: widget.onChangeEnd,
    );
  }
}

/// A single curated color choice for [_ColorSwatchPicker]. `value == null`
/// means "use the app's default" for that slot.
class _ColorSwatchOption {
  const _ColorSwatchOption(this.value, this.label, this.color);
  final int? value;
  final String label;
  final Color color;
}

const _backgroundSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.bg1),
  _ColorSwatchOption(0xFF000000, 'Black', Colors.black),
  _ColorSwatchOption(0xFF0B1220, 'Navy', Color(0xFF0B1220)),
  _ColorSwatchOption(0xFF14181D, 'Graphite', Color(0xFF14181D)),
];

const _textSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.textPrimary),
  _ColorSwatchOption(0xFFFFFFFF, 'White', Colors.white),
  _ColorSwatchOption(0xFFE5E7EB, 'Light gray', Color(0xFFE5E7EB)),
  _ColorSwatchOption(0xFFB8C4D9, 'Blue gray', Color(0xFFB8C4D9)),
];

const _warningSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.warning),
  _ColorSwatchOption(0xFFFFC107, 'Amber', Color(0xFFFFC107)),
  _ColorSwatchOption(0xFFFF7A45, 'Orange', Color(0xFFFF7A45)),
];

const _criticalSwatches = [
  _ColorSwatchOption(null, 'Default', AppColors.critical),
  _ColorSwatchOption(0xFFE53935, 'Red', Color(0xFFE53935)),
  _ColorSwatchOption(0xFFD6336C, 'Rose', Color(0xFFD6336C)),
];

/// A small curated color-swatch picker, matching [_EdgeDockAccentPicker]'s
/// pattern - used for the edge dock's background/text/warning/critical
/// color overrides so colors stay a fixed, glanceable set rather than an
/// open-ended picker dependency.
class _ColorSwatchPicker extends StatelessWidget {
  const _ColorSwatchPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<_ColorSwatchOption> options;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final knownValues = options.map((o) => o.value).toSet();
    final isCustom = selected != null && !knownValues.contains(selected);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final opt in options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _Swatch(
              color: opt.color,
              label: opt.label,
              selected: opt.value == selected,
              onTap: () => onChanged(opt.value),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: _Swatch(
            color: isCustom ? Color(selected!) : null,
            label: 'Custom…',
            selected: isCustom,
            child: isCustom
                ? null
                : const Icon(
                    Icons.add_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
            onTap: () async {
              final picked = await _showCustomColorPickerDialog(
                context,
                initial: selected ?? (options.first.value ?? 0xFF000000),
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ),
      ],
    );
  }
}

/// One round swatch button, shared by [_ColorSwatchPicker]'s curated
/// options and its trailing "Custom…" entry.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.child,
  });

  final Color? color;
  final String label;
  final bool selected;
  final Widget? child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child:
              child ??
              (selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: (color?.computeLuminance() ?? 0) > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null),
        ),
      ),
    );
  }
}

/// Opens the free-form color picker dialog and resolves to the chosen ARGB
/// int, or `null` if the user cancelled.
Future<int?> _showCustomColorPickerDialog(
  BuildContext context, {
  required int initial,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _CustomColorPickerDialog(initial: initial),
  );
}

/// A self-contained RGB/hex color picker - no package dependency, since
/// this is the one slot in the edge dock's settings that intentionally
/// isn't a curated swatch list. Three 0-255 sliders plus a hex field stay
/// in sync with each other and a live preview swatch.
class _CustomColorPickerDialog extends StatefulWidget {
  const _CustomColorPickerDialog({required this.initial});

  final int initial;

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late Color _color = Color(widget.initial).withValues(alpha: 1.0);
  late final _hexController = TextEditingController(text: _hexOf(_color));

  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _setColor(Color next, {bool updateHexField = true}) {
    setState(() => _color = next);
    if (updateHexField) _hexController.text = _hexOf(next);
  }

  void _setChannel({int? r, int? g, int? b}) {
    _setColor(
      Color.fromARGB(
        255,
        r ?? (_color.r * 255).round(),
        g ?? (_color.g * 255).round(),
        b ?? (_color.b * 255).round(),
      ),
    );
  }

  void _applyHex(String raw) {
    final cleaned = raw.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return;
    final value = int.parse(cleaned, radix: 16);
    _setColor(Color(0xFF000000 | value), updateHexField: false);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = (_color.r * 255).round();
    final g = (_color.g * 255).round();
    final b = (_color.b * 255).round();

    return AlertDialog(
      title: const Text('Custom color'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              decoration: const InputDecoration(labelText: 'Hex'),
              maxLength: 7,
              onSubmitted: _applyHex,
              onChanged: _applyHex,
            ),
            _ChannelSlider(
              label: 'R',
              value: r,
              color: Colors.red,
              onChanged: (v) => _setChannel(r: v),
            ),
            _ChannelSlider(
              label: 'G',
              value: g,
              color: Colors.green,
              onChanged: (v) => _setChannel(g: v),
            ),
            _ChannelSlider(
              label: 'B',
              value: b,
              color: Colors.blue,
              onChanged: (v) => _setChannel(b: v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_color.toARGB32() | 0xFF000000),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Picks which connected display the edge dock attaches to. Loads
/// `screenRetriever.getAllDisplays()` once (this is a settings screen, not
/// the always-on dock window, so there's no need to poll or subscribe).
/// Falls back to a plain "Primary display" label when there's only one
/// display, or while the list is still loading.
class _EdgeDockDisplayPicker extends StatefulWidget {
  const _EdgeDockDisplayPicker({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool isDark;

  @override
  State<_EdgeDockDisplayPicker> createState() => _EdgeDockDisplayPickerState();
}

class _EdgeDockDisplayPickerState extends State<_EdgeDockDisplayPicker> {
  static const _tag = 'EdgeDockDisplayPicker';
  List<Display>? _displays;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (mounted) setState(() => _displays = displays);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'getAllDisplays failed: $e');
      if (mounted) setState(() => _displays = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displays = _displays;
    final mutedStyle = TextStyle(
      fontSize: 12,
      color: widget.isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
    );
    if (displays == null) {
      return Text('Loading…', style: mutedStyle);
    }
    if (displays.length <= 1) {
      return Text('Primary display', style: mutedStyle);
    }
    final resolvedValue = displays.any((d) => d.id == widget.selected)
        ? widget.selected
        : null;
    return _NativeDropdown<String?>(
      value: resolvedValue,
      isDark: widget.isDark,
      items: [
        const DropdownMenuItem(value: null, child: Text('Primary display')),
        for (final d in displays)
          DropdownMenuItem(
            value: d.id,
            child: Text(
              '${(d.name?.isNotEmpty ?? false) ? d.name : 'Display'} — '
              '${d.size.width.toInt()}×${d.size.height.toInt()}',
            ),
          ),
      ],
      onChanged: widget.onChanged,
    );
  }
}

/// Checkbox-style toggles for which optional rows appear in the edge dock's
/// hover detail panel. Temperature is always shown, so it has no toggle.
class _EdgeDockMetricToggles extends StatelessWidget {
  const _EdgeDockMetricToggles({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  final Set<EdgeDockMetric> selected;
  final ValueChanged<Set<EdgeDockMetric>> onChanged;
  final bool isDark;

  static const _labels = {
    EdgeDockMetric.health: 'Health',
    EdgeDockMetric.smart: 'SMART',
    EdgeDockMetric.powerOnHours: 'Power on',
    EdgeDockMetric.transferSpeed: 'Read/write',
    EdgeDockMetric.freeCapacity: 'Free space',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: EdgeDockMetric.values.map((metric) {
          final isOn = selected.contains(metric);
          return GestureDetector(
            onTap: () {
              final next = Set<EdgeDockMetric>.from(selected);
              if (isOn) {
                next.remove(metric);
              } else {
                next.add(metric);
              }
              onChanged(next);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isOn
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : (isDark ? AppColors.bg2 : AppColors.lightSurfaceMuted),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isOn
                      ? AppColors.accent
                      : (isDark ? AppColors.border : AppColors.lightBorder),
                ),
              ),
              child: Text(
                _labels[metric]!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isOn
                      ? AppColors.accent
                      : (isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
