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
import 'dock_icons.dart';
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

    final animatedItems = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (expansionProgress >= 1.0) {
        animatedItems.add(item);
        continue;
      }
      // Content waits until the rail's shape has grown enough to hold it
      // (and, in reverse, is gone before the shape shrinks) - revealing and
      // dismissing are driven by the same progress, so they stay in sync.
      final staggerDelay = (0.4 + i * 0.05).clamp(0.4, 0.65);
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

    final shapePainter = EdgeDockOrganicPainter(
      edge: edge,
      backgroundColor: theme.background.withValues(alpha: 0.90),
      borderColor: Colors.white.withValues(alpha: 0.16),
      borderWidth: 1.0,
      glass: true,
      // The window is exactly the rail's size, so a drop shadow can only
      // be clipped - it showed up as a dark band along the rounded edge.
      shadows: const [],
      mainRailLength: mainRailLength,
      filletRadius: EdgeDockGeometry.filletRadius,
      endMargin: EdgeDockGeometry.endMargin,
      showPod: false,
      dockDepth: EdgeDockGeometry.railThickness,
      collapsedDepth: EdgeDockGeometry.collapsedThickness,
      expansionProgress: expansionProgress,
    );

    final content = CustomPaint(
      painter: shapePainter,
      child: ClipPath(
        clipper: _ShapeClipper(shapePainter),
        child: Container(
          // Content sits inside the body: past the concave sweep margin
          // (filletRadius) plus the body's own inner padding, centered on
          // the cross axis so ring centers match EdgeDockGeometry.
          padding: vertical
              ? const EdgeInsets.symmetric(
                  vertical:
                      EdgeDockGeometry.endMargin + EdgeDockGeometry.bodyPadding,
                )
              : const EdgeInsets.symmetric(
                  horizontal:
                      EdgeDockGeometry.endMargin + EdgeDockGeometry.bodyPadding,
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
                    ],
                  ),
                ),
        ),
      ),
    );

    // The two curved ends of the rail are interactive "handles". They sit
    // *over* the rail instead of in its layout flow, so the rail's measured
    // size (and every EdgeDockGeometry calculation) never depends on them.
    // Top/start end: a move handle (drag the whole dock along the edge).
    // Bottom/end: opens the DriveGuard window. Both fade in on hover.
    final handlesVisible = expansionProgress >= 0.9;
    const zone = EdgeDockGeometry.endMargin;

    // The zone is the reserved margin at one end of the rail, *outside* the
    // body: the button floats there, beyond the curved end, like the demo.
    Widget handleZone({required bool start, required Widget button}) {
      return Positioned(
        top: vertical ? (start ? 0 : null) : 0,
        bottom: vertical ? (start ? null : 0) : 0,
        left: vertical ? 0 : (start ? 0 : null),
        right: vertical ? 0 : (start ? null : 0),
        width: vertical ? null : zone,
        height: vertical ? zone : null,
        child: IgnorePointer(
          ignoring: !handlesVisible,
          child: Center(child: button),
        ),
      );
    }

    return Stack(
      children: [
        // Dragging also works from the rail's own padding (never from a ring,
        // so it doesn't compete with a ring's tap-to-pin).
        if (onDragUpdate == null)
          content
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart?.call(),
            onPanUpdate: (d) =>
                onDragUpdate!(vertical ? d.delta.dy : d.delta.dx),
            onPanEnd: (_) => onDragEnd?.call(),
            child: content,
          ),
        if (onDragUpdate != null)
          handleZone(
            start: true,
            button: _EdgeHandleButton(
              asset: DockAssets.hand,
              label: 'Move dock',
              theme: theme,
              reducedMotion: reducedMotion,
              cursor: SystemMouseCursors.grab,
              outward: vertical ? AxisDirection.down : AxisDirection.right,
              presence: ((expansionProgress - 0.6) / 0.4),
              onPanStart: onDragStart,
              onPanUpdate: (d) => onDragUpdate!(vertical ? d.dy : d.dx),
              onPanEnd: onDragEnd,
            ),
          ),
        handleZone(
          start: false,
          button: _EdgeHandleButton(
            icon: Icons.settings_rounded,
            label: 'Open DriveGuard',
            theme: theme,
            reducedMotion: reducedMotion,
            cursor: SystemMouseCursors.click,
            outward: vertical ? AxisDirection.up : AxisDirection.left,
            presence: ((expansionProgress - 0.6) / 0.4),
            onTap: onTapActionPod,
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
                        child: Center(
                          child: DockIcon.drive(
                            device.type,
                            size: 16,
                            color: color,
                          ),
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

/// Clips the rail's content to the rail's own animated silhouette, so
/// nothing (ring circles, labels) can ever paint outside the background
/// while it is still growing in - or already shrinking out.
class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.painter);

  final EdgeDockOrganicPainter painter;

  @override
  Path getClip(Size size) => painter.computePath(size);

  @override
  bool shouldReclip(covariant _ShapeClipper oldClipper) =>
      oldClipper.painter.expansionProgress != painter.expansionProgress ||
      oldClipper.painter.edge != painter.edge;
}

/// The thin curved hint drawn at each end of the rail while its handle is
/// hidden, so there is something to find with the pointer. [outward] is the
/// direction the arc bulges (away from the rail body).
class _ArcHintPainter extends CustomPainter {
  _ArcHintPainter({required this.outward, required this.color});

  final AxisDirection outward;
  final Color color;

  /// Same radius as the rail's concave end sweep, so the hint reads as part of
  /// the same outline instead of a differently-curved decoration.
  static const double radius = EdgeDockGeometry.filletRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.butt;
    final w = size.width;
    final h = size.height;
    const r = Radius.circular(radius);
    final path = Path();
    switch (outward) {
      case AxisDirection.up:
        path
          ..moveTo(0, h)
          ..arcToPoint(Offset(w, h), radius: r);
      case AxisDirection.down:
        path
          ..moveTo(0, 0)
          ..arcToPoint(Offset(w, 0), radius: r, clockwise: false);
      case AxisDirection.left:
        path
          ..moveTo(w, 0)
          ..arcToPoint(Offset(w, h), radius: r, clockwise: false);
      case AxisDirection.right:
        path
          ..moveTo(0, 0)
          ..arcToPoint(Offset(0, h), radius: r);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcHintPainter old) =>
      old.outward != outward || old.color != color;
}

/// A round glass button that floats beyond a curved end of the rail and only
/// appears while the pointer is over that end. It rises out of the rail
/// (fade + scale) and stays up for the whole drag once grabbed.
class _EdgeHandleButton extends StatefulWidget {
  const _EdgeHandleButton({
    required this.label,
    required this.theme,
    required this.reducedMotion,
    required this.cursor,
    required this.outward,
    this.presence = 1,
    this.icon,
    this.asset,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  }) : assert(icon != null || asset != null);

  final IconData? icon;
  final String? asset;
  final String label;
  final EdgeDockTheme theme;
  final bool reducedMotion;
  final MouseCursor cursor;
  final AxisDirection outward;

  /// 0..1: how far the rail itself has revealed - fades the resting arc hint
  /// in with the rail so it never shows before the background does.
  final double presence;
  final VoidCallback? onTap;
  final VoidCallback? onPanStart;
  final ValueChanged<Offset>? onPanUpdate;
  final VoidCallback? onPanEnd;

  @override
  State<_EdgeHandleButton> createState() => _EdgeHandleButtonState();
}

class _EdgeHandleButtonState extends State<_EdgeHandleButton> {
  bool _hovered = false;
  bool _grabbed = false;
  bool _pressed = false;

  bool get _active => _hovered || _grabbed;

  @override
  Widget build(BuildContext context) {
    final duration = widget.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final iconColor = widget.theme.text;
    return MouseRegion(
      cursor: _grabbed ? SystemMouseCursors.grabbing : widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onPanStart: widget.onPanStart == null
            ? null
            : (_) {
                setState(() => _grabbed = true);
                widget.onPanStart!();
              },
        onPanUpdate: widget.onPanUpdate == null
            ? null
            : (d) => widget.onPanUpdate!(d.delta),
        onPanEnd: widget.onPanEnd == null
            ? null
            : (_) {
                setState(() => _grabbed = false);
                widget.onPanEnd!();
              },
        child: Semantics(
          button: true,
          label: widget.label,
          child: SizedBox(
            // Generous hit area; the visible disc is smaller.
            width: 52,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Resting hint: a faint arc, replaced by the button on hover.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _active ? 0 : widget.presence.clamp(0.0, 1.0),
                    duration: duration,
                    curve: Curves.easeOut,
                    child: SizedBox(
                      width:
                          widget.outward == AxisDirection.up ||
                              widget.outward == AxisDirection.down
                          ? 28
                          : 6,
                      height:
                          widget.outward == AxisDirection.up ||
                              widget.outward == AxisDirection.down
                          ? 6
                          : 28,
                      child: CustomPaint(
                        painter: _ArcHintPainter(
                          outward: widget.outward,
                          // Exactly the rail's fill, so the hint is visibly the same
                          // surface as the dock.
                          color: widget.theme.background.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: _active ? 1 : 0,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: AnimatedScale(
                      scale: _pressed ? 0.92 : (_active ? 1 : 0.6),
                      duration: duration,
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.alphaBlend(
                            Colors.white.withValues(
                              alpha: _grabbed ? 0.22 : 0.14,
                            ),
                            widget.theme.background.withValues(alpha: 0.92),
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: widget.asset != null
                            ? DockIcon(
                                widget.asset!,
                                size: 17,
                                color: iconColor,
                              )
                            : Icon(widget.icon, size: 17, color: iconColor),
                      ),
                    ),
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
                          DockIcon.drive(device.type, size: 16, color: color),
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
