part of '../settings_screen.dart';

/// Paints a tray icon exactly as the real tray would.
class _TrayPreview extends StatelessWidget {
  const _TrayPreview({required this.spec});
  final TrayIconSpec spec;
  static const double size = 38;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(size),
    painter: _TrayPreviewPainter(spec),
  );
}

class _TrayPreviewPainter extends CustomPainter {
  _TrayPreviewPainter(this.spec);
  final TrayIconSpec spec;

  @override
  void paint(Canvas canvas, Size size) =>
      paintTrayIcon(canvas, size.width, spec);

  @override
  bool shouldRepaint(_TrayPreviewPainter old) =>
      old.spec.cacheKey != spec.cacheKey;
}

class _TraySection extends ConsumerWidget {
  const _TraySection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final tray = settings.tray;
    void update(TraySettings Function(TraySettings) f) =>
        notifier.updateWith((s) => s.copyWith(tray: f(s.tray)));

    final iconShowsNumber =
        tray.style == TrayIconStyle.temperature ||
        tray.style == TrayIconStyle.ring;
    final textSupported = Platform.isMacOS || Platform.isLinux;
    final textEnabled = textSupported && !iconShowsNumber;
    final where = Platform.isMacOS ? 'menu bar' : 'system tray';

    TrayIconSpec spec(
      TrayIconStyle style,
      TemperatureSeverity sev, {
      String number = '42°',
      double fraction = 0.55,
    }) => TrayIconSpec(
      style: style,
      severity: sev,
      numberText: number.replaceAll('°', ''),
      unit: settings.temperatureUnit == TemperatureUnit.fahrenheit ? 'F' : 'C',
      fraction: fraction,
      darkBackground: isDark,
    );

    // A faux tray strip so previews are judged on a realistic background.
    Widget strip({required Widget child}) => Container(
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0B0D) : const Color(0xFFE9ECF1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoSection(
          title: 'Icon style',
          caption: 'How DriveGuard appears in your $where',
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final cols = c.maxWidth >= 640 ? 5 : (c.maxWidth >= 440 ? 3 : 2);
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final s in TrayIconStyle.values)
                    SizedBox(
                      width: w,
                      child: _StyleTile(
                        style: s,
                        selected: tray.style == s,
                        isDark: isDark,
                        preview: strip(
                          child: _TrayPreview(
                            spec: spec(s, TemperatureSeverity.normal),
                          ),
                        ),
                        onTap: () => update((t) => t.copyWith(style: s)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        InfoSection(
          title: 'Status preview',
          caption: tray.style.description,
          child: Row(
            children: [
              for (final (label, sev, num, frac) in const [
                ('Normal', TemperatureSeverity.normal, '42°', 0.45),
                ('Warning', TemperatureSeverity.warning, '64°', 0.80),
                ('Critical', TemperatureSeverity.critical, '73°', 1.0),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: label == 'Critical' ? 0 : AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        strip(
                          child: _TrayPreview(
                            spec: spec(
                              tray.style,
                              sev,
                              number: num,
                              fraction: frac,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(label, style: AppText.caption(context)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.section),
        InfoSection(
          title: 'Options',
          child: _SectionGroup(
            isDark: isDark,
            children: [
              _SettingRow(
                label: 'Show',
                subtitle: 'Which reading the icon represents',
                isDark: isDark,
                trailing: _SegmentedControl<TrayMetric>(
                  options: [for (final m in TrayMetric.values) (m, m.label)],
                  selected: tray.metric,
                  onChanged: (m) => update((t) => t.copyWith(metric: m)),
                  isDark: isDark,
                ),
              ),
              _SettingRow(
                label: 'Text beside icon',
                subtitle: !textSupported
                    ? 'Not supported by the Windows taskbar'
                    : (iconShowsNumber
                          ? 'Not needed — this style already shows the number'
                          : 'Adds the temperature as text next to the icon'),
                isDark: isDark,
                trailing: Switch(
                  value: tray.showText && textEnabled,
                  onChanged: textEnabled
                      ? (v) => update((t) => t.copyWith(showText: v))
                      : null,
                ),
              ),
              _SettingRow(
                label: 'Drive list in menu',
                subtitle:
                    'Compact shows name and temperature; detailed adds '
                    'status and used space',
                isDark: isDark,
                isLast: true,
                trailing: _SegmentedControl<TrayMenuDetail>(
                  options: [
                    for (final d in TrayMenuDetail.values) (d, d.label),
                  ],
                  selected: tray.menuDetail,
                  onChanged: (d) => update((t) => t.copyWith(menuDetail: d)),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StyleTile extends StatefulWidget {
  const _StyleTile({
    required this.style,
    required this.selected,
    required this.isDark,
    required this.preview,
    required this.onTap,
  });

  final TrayIconStyle style;
  final bool selected;
  final bool isDark;
  final Widget preview;
  final VoidCallback onTap;

  @override
  State<_StyleTile> createState() => _StyleTileState();
}

class _StyleTileState extends State<_StyleTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isDark ? AppColors.bg1 : AppColors.lightCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: sel
                  ? AppColors.accent
                  : (_hover
                        ? hairlineOf(context).withValues(alpha: 1)
                        : hairlineOf(context)),
              width: sel ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              widget.preview,
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (sel) ...[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      widget.style.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(context).copyWith(
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
