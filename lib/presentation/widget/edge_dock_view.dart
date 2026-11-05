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
import 'edge_dock_organic_painter.dart';
import 'edge_dock_popover_bubble.dart';

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
    this.onTapActionPod,
    this.onArrowKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.theme = EdgeDockTheme.defaults,
    this.visibleMetrics = kAllEdgeDockMetrics,
    this.isExpanded = true,
    this.expansionProgress = 1.0,
    this.panelIndex,
    this.panelProgress = 1.0,
    this.onMouseEnterDock,
    this.onMouseExitDock,
  });

  /// The device whose card is rendered, when the host animates it in/out
  /// itself (it must outlive the hover during the exit animation). `null`
  /// falls back to the pinned/hovered device with the card fully shown.
  final int? panelIndex;

  /// 0..1 enter/exit progress of the detail card.
  final double panelProgress;

  final MiniWidgetSnapshot snapshot;
  final ScreenEdge edge;
  final Color? accentOverride;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final VoidCallback? onTapActionPod;
  final void Function({required bool forward})? onArrowKey;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Rect railLocalRect;
  final Rect? panelLocalRect;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;
  final bool isExpanded;
  final double expansionProgress;
  final VoidCallback? onMouseEnterDock;
  final VoidCallback? onMouseExitDock;

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
    final displayed = panelIndex ?? pinnedIndex ?? hoveredIndex;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Focus(
      canRequestFocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onEnter: (_) => onMouseEnterDock?.call(),
        onExit: (_) {
          onMouseExitDock?.call();
          onHover(null);
        },
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
                onTapActionPod: onTapActionPod,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
                accentOverride: accentOverride,
                theme: theme,
                reducedMotion: reducedMotion,
                isExpanded: isExpanded,
                expansionProgress: expansionProgress,
              ),
            ),
            if (displayed != null &&
                panelRect != null &&
                displayed < devices.length &&
                (panelIndex != null || expansionProgress > 0.3))
              Positioned.fromRect(
                rect: panelRect,
                child: _DetailCard(
                  device: devices[displayed],
                  edge: edge,
                  targetArrowPosition: isVerticalEdge(edge)
                      ? (EdgeDockGeometry.ringCenter(
                              railLocalRect,
                              edge,
                              displayed,
                            ).dy -
                            panelRect.top)
                      : (EdgeDockGeometry.ringCenter(
                              railLocalRect,
                              edge,
                              displayed,
                            ).dx -
                            panelRect.left),
                  accentOverride: accentOverride,
                  theme: theme,
                  visibleMetrics: visibleMetrics,
                  reducedMotion: reducedMotion,
                  progress: reducedMotion
                      ? (panelProgress > 0 ? 1 : 0)
                      : panelProgress,
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
    this.onTapActionPod,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.isExpanded = true,
    this.expansionProgress = 1.0,
  });

  final List<MiniWidgetDeviceSnapshot> devices;
  final ScreenEdge edge;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final VoidCallback? onTapActionPod;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final bool reducedMotion;
  final bool isExpanded;
  final double expansionProgress;

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

    final count = devices.isEmpty ? 1 : devices.length;
    final mainRailLength =
        count * EdgeDockGeometry.itemBlockLength +
        (count - 1) * EdgeDockGeometry.itemSpacing;

    final pod = _BottomActionPod(
      theme: theme,
      reducedMotion: reducedMotion,
      onTap: onTapActionPod,
    );

    final animatedItems = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (expansionProgress >= 1.0) {
        animatedItems.add(item);
        continue;
      }
      final staggerDelay = (i * 0.05).clamp(0.0, 0.3);
      final itemProgress = reducedMotion
          ? (expansionProgress > 0.0 ? 1.0 : 0.0)
          : ((expansionProgress - staggerDelay) / (1.0 - staggerDelay)).clamp(
              0.0,
              1.0,
            );
      final curvedItemProgress = Curves.easeOutCubic.transform(itemProgress);

      final slideDistance = 14.0 * (1.0 - curvedItemProgress);
      Offset slideOffset;
      switch (edge) {
        case ScreenEdge.left:
          slideOffset = Offset(-slideDistance, 0);
        case ScreenEdge.right:
          slideOffset = Offset(slideDistance, 0);
        case ScreenEdge.top:
          slideOffset = Offset(0, -slideDistance);
        case ScreenEdge.bottom:
          slideOffset = Offset(0, slideDistance);
      }

      animatedItems.add(
        Transform.translate(
          offset: slideOffset,
          child: Opacity(
            opacity: curvedItemProgress,
            child: IgnorePointer(
              ignoring: curvedItemProgress < 0.5,
              child: item,
            ),
          ),
        ),
      );
    }

    Widget animatedPod = pod;
    if (expansionProgress < 1.0) {
      final podProgress = reducedMotion
          ? (expansionProgress > 0.0 ? 1.0 : 0.0)
          : ((expansionProgress - 0.15) / 0.85).clamp(0.0, 1.0);
      final curvedPodProgress = Curves.easeOutCubic.transform(podProgress);
      final podSlideDistance = 14.0 * (1.0 - curvedPodProgress);
      Offset podSlideOffset;
      switch (edge) {
        case ScreenEdge.left:
          podSlideOffset = Offset(-podSlideDistance, 0);
        case ScreenEdge.right:
          podSlideOffset = Offset(podSlideDistance, 0);
        case ScreenEdge.top:
          podSlideOffset = Offset(0, -podSlideDistance);
        case ScreenEdge.bottom:
          podSlideOffset = Offset(0, podSlideDistance);
      }
      animatedPod = Transform.translate(
        offset: podSlideOffset,
        child: Opacity(
          opacity: curvedPodProgress,
          child: IgnorePointer(ignoring: curvedPodProgress < 0.5, child: pod),
        ),
      );
    }

    final content = CustomPaint(
      painter: EdgeDockOrganicPainter(
        edge: edge,
        backgroundColor: theme.background.withValues(alpha: 0.90),
        borderColor: Colors.white.withValues(alpha: 0.16),
        borderWidth: 1.0,
        glass: true,
        // The window is exactly the rail's size, so a drop shadow can only
        // be clipped - it showed up as a dark band along the rounded edge.
        shadows: const [],
        mainRailLength: mainRailLength,
        podDiameter: EdgeDockGeometry.podDiameter,
        podSpacing: EdgeDockGeometry.podSpacing,
        filletRadius: EdgeDockGeometry.filletRadius,
        showPod: true,
        dockDepth: EdgeDockGeometry.railThickness,
        collapsedDepth: EdgeDockGeometry.collapsedThickness,
        expansionProgress: expansionProgress,
      ),
      child: ClipRect(
        child: Container(
          // Content sits inside the body: past the concave sweep margin
          // (filletRadius) plus the body's own inner padding, centered on
          // the cross axis so ring centers match EdgeDockGeometry.
          padding: vertical
              ? const EdgeInsets.symmetric(
                  vertical:
                      EdgeDockGeometry.filletRadius +
                      EdgeDockGeometry.bodyPadding,
                )
              : const EdgeInsets.symmetric(
                  horizontal:
                      EdgeDockGeometry.filletRadius +
                      EdgeDockGeometry.bodyPadding,
                ),
          alignment: vertical ? Alignment.topCenter : Alignment.centerLeft,
          child: vertical
              ? SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _withSpacing(animatedItems, vertical: true),
                      ),
                      const SizedBox(height: EdgeDockGeometry.podSpacing),
                      animatedPod,
                    ],
                  ),
                )
              : SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _withSpacing(animatedItems, vertical: false),
                      ),
                      const SizedBox(width: EdgeDockGeometry.podSpacing),
                      animatedPod,
                    ],
                  ),
                ),
        ),
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
          vertical
              ? const SizedBox(height: EdgeDockGeometry.itemSpacing)
              : const SizedBox(width: EdgeDockGeometry.itemSpacing),
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
        : const Duration(milliseconds: 150);
    final displayValue = device.valueText.isNotEmpty
        ? device.valueText
        : '${(device.fraction * 100).round()}%';

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
          label: '${device.name}, $displayValue',
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
                      selected: selected,
                    ),
                    child: Center(
                      // Soft tinted disc instead of a dark fill, so the icon
                      // sits on the glass rather than on a black hole.
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.16),
                        ),
                        child: Icon(
                          _DetailCard._deviceIcon(device.type),
                          size: 16,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    height: 1.2,
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
                size: 14,
                color: theme.mutedText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '--',
          style: TextStyle(
            color: theme.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _BottomActionPod extends StatefulWidget {
  const _BottomActionPod({
    required this.theme,
    required this.reducedMotion,
    this.onTap,
  });

  final EdgeDockTheme theme;
  final bool reducedMotion;
  final VoidCallback? onTap;

  @override
  State<_BottomActionPod> createState() => _BottomActionPodState();
}

class _BottomActionPodState extends State<_BottomActionPod> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scaleDuration = widget.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                Focus.of(context).requestFocus();
                widget.onTap!();
              },
        child: Semantics(
          button: true,
          label: 'Settings',
          hint: 'Open settings and dock actions',
          child: AnimatedScale(
            scale: _hovered ? 1.12 : 1.0,
            duration: scaleDuration,
            curve: Curves.easeOutCubic,
            child: Container(
              width: EdgeDockGeometry.podDiameter,
              height: EdgeDockGeometry.podDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? widget.theme.text.withValues(alpha: 0.12)
                    : widget.theme.background.withValues(alpha: 0.6),
                border: Border.all(
                  color: _hovered
                      ? widget.theme.text.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: _hovered ? widget.theme.text : widget.theme.mutedText,
                ),
              ),
            ),
          ),
        ),
      ),
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
    this.edge = ScreenEdge.left,
    this.targetArrowPosition = 60.0,
    this.accentOverride,
    this.theme = EdgeDockTheme.defaults,
    this.visibleMetrics = kAllEdgeDockMetrics,
    this.reducedMotion = false,
    this.progress = 1.0,
  });

  /// 0..1 enter/exit progress, driven by the host (see EdgeDockApp).
  final double progress;

  final MiniWidgetDeviceSnapshot device;
  final ScreenEdge edge;
  final double targetArrowPosition;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity, theme);
    final rows = edgeDockDetailRows(device, visibleMetrics);
    final usedPercent = (device.fraction * 100).round();
    final leftPercent = (100 - usedPercent).clamp(0, 100);

    final metricRows = rows.skip(1).toList(growable: false);
    const tabular = [FontFeature.tabularFigures()];

    final t = progress.clamp(0.0, 1.0);

    // Staggered reveal: each block eases in slightly after the previous one,
    // so the card "builds" instead of popping in as one slab.
    double stage(double start, double end) => Curves.easeOutCubic.transform(
      ((t - start) / (end - start)).clamp(0.0, 1.0),
    );
    Widget reveal(double start, double end, Widget child) {
      final v = stage(start, end);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - v)),
          child: child,
        ),
      );
    }

    return Opacity(
      opacity: Curves.easeOut.transform(t),
      child: Transform.translate(
        offset: _enterOffset(edge, 14 * (1 - t)),
        child: Transform.scale(
          scale: 0.94 + 0.06 * t,
          alignment: _scaleAlignment(edge),
          child: Material(
            color: Colors.transparent,
            child: EdgeDockPopoverBubble(
              edge: edge,
              targetArrowPosition: targetArrowPosition,
              backgroundColor: theme.background.withValues(alpha: 0.82),
              borderColor: Colors.white.withValues(alpha: 0.14),
              borderRadius: 20.0,
              borderWidth: 1.0,
              arrowWidth: 8.0,
              arrowHeight: 16.0,
              glass: true,
              // The window is only as big as the card, so a drop shadow would
              // be clipped into a hard grey band under it.
              shadows: const [],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              // Every block below has a fixed height (see
              // EdgeDockGeometry.panelHeaderHeight) so the window is sized to
              // exactly what is rendered - nothing can overflow.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  reveal(
                    0.0,
                    0.5,
                    SizedBox(
                      height: 22,
                      child: Row(
                        children: [
                          Icon(
                            _deviceIcon(device.type),
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              device.healthStatus.isNotEmpty
                                  ? device.healthStatus
                                  : 'OK',
                              maxLines: 1,
                              style: TextStyle(
                                color: color,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  reveal(
                    0.1,
                    0.6,
                    SizedBox(
                      height: 34,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                device.valueText,
                                maxLines: 1,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 26,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Spacer(),
                          Text(
                            'Temperature',
                            style: TextStyle(
                              color: theme.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: device.fraction.clamp(0.0, 1.0) * stage(0.2, 0.95),
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  reveal(
                    0.3,
                    0.8,
                    SizedBox(
                      height: 14,
                      child: Text(
                        '$usedPercent% used · $leftPercent% free',
                        maxLines: 1,
                        style: TextStyle(
                          color: theme.mutedText,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          fontFeatures: tabular,
                        ),
                      ),
                    ),
                  ),
                  if (metricRows.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    reveal(
                      0.3,
                      0.8,
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Scrolls when the panel is height-capped (many metrics on a
                    // short display) instead of overflowing.
                    Flexible(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, (label, value))
                                  in metricRows.indexed)
                                reveal(
                                  (0.35 + 0.06 * i).clamp(0.0, 0.65),
                                  1.0,
                                  _DetailRow(
                                    label: label,
                                    value: value,
                                    theme: theme,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Scale about the side facing the dock, so the card grows out of it.
  static Alignment _scaleAlignment(ScreenEdge edge) => switch (edge) {
    ScreenEdge.left => Alignment.centerLeft,
    ScreenEdge.right => Alignment.centerRight,
    ScreenEdge.top => Alignment.topCenter,
    ScreenEdge.bottom => Alignment.bottomCenter,
  };

  static IconData _deviceIcon(StorageDeviceType type) => switch (type) {
    StorageDeviceType.nvme => Icons.memory_rounded,
    StorageDeviceType.ssd => Icons.storage_rounded,
    _ => Icons.album_rounded,
  };

  /// Small slide toward the card's resting position, from the dock side.
  static Offset _enterOffset(ScreenEdge edge, double d) => switch (edge) {
    ScreenEdge.left => Offset(-d, 0),
    ScreenEdge.right => Offset(d, 0),
    ScreenEdge.top => Offset(0, -d),
    ScreenEdge.bottom => Offset(0, d),
  };
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
    return SizedBox(
      height: EdgeDockGeometry.panelRowHeight,
      child: Row(
        children: [
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: theme.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: theme.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
    this.selected = false,
  });

  final double fraction;
  final Color color;
  final bool pinned;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2.5;
    const strokeWidth = 3.6;

    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
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

    if (pinned || selected) {
      // Outer glow / indicator ring distinct from the progress arc
      final indicator = Paint()
        ..color = color.withValues(alpha: pinned ? 0.85 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = pinned ? 1.5 : 1.0;
      canvas.drawCircle(center, radius + 2.0, indicator);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.pinned != pinned ||
      oldDelegate.selected != selected;
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
