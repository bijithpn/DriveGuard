import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../../application/settings/app_settings.dart' show kAllEdgeDockMetrics;
import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../../infrastructure/tray/edge_dock_geometry.dart'
    show EdgeDockGeometry;
import '../theme/app_theme.dart';

/// Resolved colors for the edge dock's own surfaces (panel background, body
/// text) plus severity overrides, kept in one place instead of scattering
/// `AppColors.*`/user-color decisions across widgets. `null` fields on
/// [EdgeDockSettings] fall back to the app's normal design-system colors.
class EdgeDockTheme {
  const EdgeDockTheme({
    required this.background,
    required this.text,
    required this.mutedText,
    required this.warning,
    required this.critical,
  });

  final Color background;
  final Color text;
  final Color mutedText;
  final Color warning;
  final Color critical;

  static const EdgeDockTheme defaults = EdgeDockTheme(
    background: AppColors.bg1,
    text: AppColors.textPrimary,
    mutedText: AppColors.textMuted,
    warning: AppColors.warning,
    critical: AppColors.critical,
  );

  factory EdgeDockTheme.resolve({
    int? backgroundColor,
    int? textColor,
    int? warningColor,
    int? criticalColor,
  }) {
    final text = textColor != null ? Color(textColor) : AppColors.textPrimary;
    return EdgeDockTheme(
      background: backgroundColor != null
          ? Color(backgroundColor)
          : AppColors.bg1,
      text: text,
      mutedText: textColor != null
          ? text.withValues(alpha: 0.6)
          : AppColors.textMuted,
      warning: warningColor != null ? Color(warningColor) : AppColors.warning,
      critical: criticalColor != null
          ? Color(criticalColor)
          : AppColors.critical,
    );
  }
}

Color severityColor(TemperatureSeverity severity, [EdgeDockTheme? theme]) {
  final t = theme ?? EdgeDockTheme.defaults;
  switch (severity) {
    case TemperatureSeverity.critical:
      return t.critical;
    case TemperatureSeverity.warning:
      return t.warning;
    case TemperatureSeverity.warm:
    case TemperatureSeverity.normal:
      return AppColors.normal;
    case TemperatureSeverity.unavailable:
      return t.mutedText;
  }
}

/// Resolves a user-chosen accent to a concrete color, or `null` for
/// [EdgeDockAccent.auto] (caller falls back to per-device severity color).
Color? resolveAccent(EdgeDockAccent accent) {
  switch (accent) {
    case EdgeDockAccent.auto:
      return null;
    case EdgeDockAccent.blue:
      return AppColors.accent;
    case EdgeDockAccent.teal:
      return const Color(0xFF2DD4BF);
    case EdgeDockAccent.purple:
      return const Color(0xFF9B7BFF);
    case EdgeDockAccent.pink:
      return const Color(0xFFEC6BAE);
    case EdgeDockAccent.orange:
      return const Color(0xFFFF9F45);
    case EdgeDockAccent.red:
      return AppColors.critical;
  }
}

bool isVerticalEdge(ScreenEdge edge) =>
    edge == ScreenEdge.left || edge == ScreenEdge.right;

/// The full edge-dock surface: a rail of per-device ring indicators
/// docked to a screen edge, plus a detail card that appears beside
/// whichever ring is hovered or pinned. Hover is driven entirely by native
/// [MouseRegion] events (no cursor polling) - the rail and the open detail
/// card are one interactive zone, so moving from a ring toward its card
/// never flickers.
///
/// [onHover] is called with the newly hovered device index, or `null` when
/// the pointer leaves the whole surface. [onTapRing] pins/unpins a ring's
/// panel open independent of the pointer - the click-to-pin interaction
/// this doubles as the non-hover accessibility fallback for: the panel
/// doesn't require the pointer to keep hovering once pinned, and the same
/// mechanism is reachable from the keyboard via [onArrowKey] (move which
/// ring is targeted) plus Enter/Space (pin it) once the dock has keyboard
/// focus - never grabbed automatically, only by a deliberate click, so this
/// doesn't count as stealing focus from the main app window. The caller
/// (EdgeDockApp) owns the actual OS window resize this implies - this
/// widget only lays out content within whatever bounds it's given.
class EdgeDockContent extends StatelessWidget {
  const EdgeDockContent({
    super.key,
    required this.snapshot,
    required this.edge,
    required this.accentOverride,
    required this.hoveredIndex,
    required this.onHover,
    required this.railLocalRect,
    required this.panelLocalRect,
    this.pinnedIndex,
    this.onTapRing,
    this.onArrowKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.theme = EdgeDockTheme.defaults,
    this.visibleMetrics = kAllEdgeDockMetrics,
  });

  final MiniWidgetSnapshot snapshot;
  final ScreenEdge edge;
  final Color? accentOverride;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final void Function({required bool forward})? onArrowKey;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Rect railLocalRect;
  final Rect? panelLocalRect;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final onArrow = onArrowKey;
    final key = event.logicalKey;
    final vertical = isVerticalEdge(edge);
    final forwardKey = vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    final backwardKey = vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    if (onArrow != null && key == forwardKey) {
      onArrow(forward: true);
      return KeyEventResult.handled;
    }
    if (onArrow != null && key == backwardKey) {
      onArrow(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      onTapRing?.call(hoveredIndex ?? pinnedIndex ?? 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      onTapRing?.call(null);
      onHover(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;
    final panelRect = panelLocalRect;
    final displayed = pinnedIndex ?? hoveredIndex;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Focus(
      canRequestFocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onExit: (_) => onHover(null),
        child: Stack(
          children: [
            const Positioned.fill(child: SizedBox.expand()),
            Positioned.fromRect(
              rect: railLocalRect,
              child: _Rail(
                devices: devices,
                edge: edge,
                hoveredIndex: displayed,
                pinnedIndex: pinnedIndex,
                onHover: onHover,
                onTapRing: onTapRing,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
                accentOverride: accentOverride,
                theme: theme,
                reducedMotion: reducedMotion,
              ),
            ),
            if (displayed != null &&
                panelRect != null &&
                displayed < devices.length)
              Positioned.fromRect(
                rect: panelRect,
                child: _DetailCard(
                  device: devices[displayed],
                  accentOverride: accentOverride,
                  theme: theme,
                  visibleMetrics: visibleMetrics,
                  reducedMotion: reducedMotion,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.devices,
    required this.edge,
    required this.hoveredIndex,
    required this.onHover,
    required this.accentOverride,
    required this.theme,
    required this.reducedMotion,
    this.pinnedIndex,
    this.onTapRing,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final List<MiniWidgetDeviceSnapshot> devices;
  final ScreenEdge edge;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final vertical = isVerticalEdge(edge);
    final items = devices.isEmpty
        ? [_EmptyRingItem(theme: theme)]
        : List.generate(
            devices.length,
            (i) => _RingItem(
              device: devices[i],
              selected: hoveredIndex == i,
              pinned: pinnedIndex == i,
              accentOverride: accentOverride,
              theme: theme,
              reducedMotion: reducedMotion,
              onEnter: () => onHover(i),
              onTap: onTapRing == null ? null : () => onTapRing!(i),
            ),
          );

    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.bg3, width: 1),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: _withSpacing(items, vertical: true),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: _withSpacing(items, vertical: false),
            ),
    );

    if (onDragUpdate == null) return content;
    // The grip is drawn *over* the rail rather than taking its own layout
    // space in the Column/Row above - the rail's measured size (and every
    // EdgeDockGeometry calculation) stays exactly what it was without
    // drag-to-reposition, so there's no risk of it silently drifting out
    // of sync with the geometry math the way the fixed-height detail panel
    // once did. Dragging starts from the rail's own background/padding,
    // not from a ring, so it never competes with a ring's tap-to-pin.
    return Stack(
      children: [
        MouseRegion(
          cursor: vertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart?.call(),
            onPanUpdate: (d) =>
                onDragUpdate!(vertical ? d.delta.dy : d.delta.dx),
            onPanEnd: (_) => onDragEnd?.call(),
            child: content,
          ),
        ),
        Positioned(
          top: vertical ? 4 : null,
          left: vertical ? 0 : 4,
          right: vertical ? 0 : null,
          bottom: vertical ? null : 0,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: Icon(
                vertical
                    ? Icons.drag_indicator_rounded
                    : Icons.drag_handle_rounded,
                size: 12,
                color: theme.mutedText.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _withSpacing(List<Widget> items, {required bool vertical}) {
    final spaced = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        spaced.add(
          vertical ? const SizedBox(height: 10) : const SizedBox(width: 10),
        );
      }
      spaced.add(items[i]);
    }
    return spaced;
  }
}

class _RingItem extends StatelessWidget {
  const _RingItem({
    required this.device,
    required this.selected,
    required this.accentOverride,
    required this.theme,
    required this.reducedMotion,
    required this.onEnter,
    this.pinned = false,
    this.onTap,
  });

  final MiniWidgetDeviceSnapshot device;
  final bool selected;
  final bool pinned;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final bool reducedMotion;
  final VoidCallback onEnter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity, theme);
    final scaleDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 120);

    return MouseRegion(
      onEnter: (_) => onEnter(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                Focus.of(context).requestFocus();
                onTap!();
              },
        child: Semantics(
          button: true,
          label: '${device.name}, ${device.valueText}',
          hint: pinned
              ? 'Details pinned open. Activate to unpin.'
              : 'Activate to pin details open.',
          child: AnimatedScale(
            scale: selected ? 1.08 : 1.0,
            duration: scaleDuration,
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: EdgeDockGeometry.ringDiameter,
                  height: EdgeDockGeometry.ringDiameter,
                  child: CustomPaint(
                    painter: _RingPainter(
                      fraction: device.fraction,
                      color: color,
                      pinned: pinned,
                    ),
                    child: Center(
                      child: Icon(
                        device.type == StorageDeviceType.nvme
                            ? Icons.memory_rounded
                            : device.type == StorageDeviceType.ssd
                            ? Icons.storage_rounded
                            : Icons.album_rounded,
                        size: 14,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRingItem extends StatelessWidget {
  const _EmptyRingItem({required this.theme});

  final EdgeDockTheme theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: EdgeDockGeometry.ringDiameter,
          height: EdgeDockGeometry.ringDiameter,
          child: CustomPaint(
            painter: _RingPainter(fraction: 0, color: theme.mutedText),
            child: Center(
              child: Icon(
                Icons.hourglass_empty_rounded,
                size: 13,
                color: theme.mutedText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('--', style: TextStyle(color: theme.mutedText, fontSize: 9.5)),
      ],
    );
  }
}

/// The rows the detail panel renders for [device], given which optional
/// [EdgeDockMetric]s are enabled - temperature is always first and always
/// present. Shared between the widget (to build the rows) and the
/// window-geometry code (`EdgeDockGeometry.panelHeightFor`, via this list's
/// length) so the panel is sized to fit exactly what it renders instead of
/// a fixed height that can overflow once more rows are toggled on.
List<(String, String)> edgeDockDetailRows(
  MiniWidgetDeviceSnapshot device,
  Set<EdgeDockMetric> visibleMetrics,
) {
  return [
    ('Temperature', device.valueText),
    if (visibleMetrics.contains(EdgeDockMetric.health) &&
        device.lifePercent != null)
      ('Health', '${device.lifePercent}%'),
    if (visibleMetrics.contains(EdgeDockMetric.smart))
      ('SMART', device.healthStatus),
    if (visibleMetrics.contains(EdgeDockMetric.powerOnHours) &&
        device.powerOnHoursText != null)
      ('Power on', device.powerOnHoursText!),
    if (visibleMetrics.contains(EdgeDockMetric.transferSpeed) &&
        device.readSpeedText != null)
      ('Read', device.readSpeedText!),
    if (visibleMetrics.contains(EdgeDockMetric.transferSpeed) &&
        device.writeSpeedText != null)
      ('Write', device.writeSpeedText!),
    if (visibleMetrics.contains(EdgeDockMetric.freeCapacity) &&
        device.freeCapacityText != null)
      ('Free', device.freeCapacityText!),
  ];
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.device,
    required this.accentOverride,
    required this.theme,
    this.visibleMetrics = kAllEdgeDockMetrics,
    this.reducedMotion = false,
  });

  final MiniWidgetDeviceSnapshot device;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity, theme);
    final rows = edgeDockDetailRows(device, visibleMetrics);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.96 + 0.04 * t,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.bg3, width: 1),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowDark,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    border: Border(
                      bottom: BorderSide(color: color.withValues(alpha: 0.18)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (label, value) in rows)
                        _DetailRow(label: label, value: value, theme: theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final EdgeDockTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: theme.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    this.pinned = false,
  });

  final double fraction;
  final Color color;
  final bool pinned;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2.5;
    const strokeWidth = 3.0;

    final track = Paint()
      ..color = AppColors.bg3
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped > 0) {
      final value = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * clamped,
        false,
        value,
      );
    }

    if (pinned) {
      // A thin outer ring, distinct from the progress arc, so a pinned
      // ring (details staying open without the pointer) reads differently
      // from a merely-hovered one.
      final pin = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius + 1.75, pin);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.pinned != pinned;
}

/// Debounces the "pointer left the whole dock" event by a short grace
/// period, so a fast cursor movement between the rail and the detail card
/// (both inside the same window, but Flutter can report a same-frame
/// exit+re-enter at the boundary) doesn't cause a visible flicker. Pure
/// timer wrapper - the actual hover-zone containment is handled by
/// [EdgeDockContent]'s own MouseRegion.
class EdgeDockCollapseDebouncer {
  EdgeDockCollapseDebouncer({this.grace = const Duration(milliseconds: 150)});

  final Duration grace;
  Timer? _timer;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void schedule(VoidCallback onCollapse) {
    _timer?.cancel();
    _timer = Timer(grace, onCollapse);
  }

  void dispose() => cancel();
}
