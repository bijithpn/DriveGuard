import 'dart:ui';

import '../../domain/enums/ui_enums.dart';

/// Pure geometry for the edge-docked hover widget: a rail of per-device
/// ring indicators docked to a screen edge, plus a detail panel that
/// appears beside whichever ring is hovered. Kept free of window_manager/
/// screen_retriever so it's unit-testable without a real window. See
/// docs/superpowers/specs/2026-09-09-edge-dock-widget-design.md.
class EdgeDockGeometry {
  const EdgeDockGeometry._();

  static const double ringDiameter = 40;
  static const double itemBlockLength = 60; // ring + value label, stacked
  static const double itemSpacing = 10;
  static const double railPadding = 12;
  static const double railThickness = 64;

  static const double panelWidth = 240;
  static const double panelHeight = 168;
  static const double panelGap = 8;

  static double railLength(int deviceCount) {
    final count = deviceCount < 1 ? 1 : deviceCount;
    return railPadding * 2 +
        count * itemBlockLength +
        (count - 1) * itemSpacing;
  }

  /// The rail's rect (the always-visible collapsed state), in screen
  /// coordinates, centered on [edge] of a display occupying
  /// [visiblePosition]/[visibleSize].
  static Rect railRect(
    Offset visiblePosition,
    Size visibleSize,
    ScreenEdge edge,
    int deviceCount,
  ) {
    final length = railLength(deviceCount);
    switch (edge) {
      case ScreenEdge.left:
        return Rect.fromLTWH(
          visiblePosition.dx,
          visiblePosition.dy + (visibleSize.height - length) / 2,
          railThickness,
          length,
        );
      case ScreenEdge.right:
        return Rect.fromLTWH(
          visiblePosition.dx + visibleSize.width - railThickness,
          visiblePosition.dy + (visibleSize.height - length) / 2,
          railThickness,
          length,
        );
      case ScreenEdge.top:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - length) / 2,
          visiblePosition.dy,
          length,
          railThickness,
        );
      case ScreenEdge.bottom:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - length) / 2,
          visiblePosition.dy + visibleSize.height - railThickness,
          length,
          railThickness,
        );
    }
  }

  /// The screen-space center of the [index]th device's ring within [rail].
  static Offset ringCenter(Rect rail, ScreenEdge edge, int index) {
    final along =
        railPadding +
        itemBlockLength / 2 +
        index * (itemBlockLength + itemSpacing);
    if (edge == ScreenEdge.left || edge == ScreenEdge.right) {
      return Offset(rail.center.dx, rail.top + along);
    }
    return Offset(rail.left + along, rail.center.dy);
  }

  /// The detail panel's rect for a ring centered at [ringCenter], placed
  /// beside the rail on the side that opens away from the screen edge, and
  /// clamped so it never renders outside the display's visible bounds.
  static Rect panelRectFor(
    Rect rail,
    ScreenEdge edge,
    Offset ringCenter,
    Offset visiblePosition,
    Size visibleSize,
  ) {
    double left;
    double top;
    switch (edge) {
      case ScreenEdge.left:
        left = rail.right + panelGap;
        top = ringCenter.dy - panelHeight / 2;
      case ScreenEdge.right:
        left = rail.left - panelGap - panelWidth;
        top = ringCenter.dy - panelHeight / 2;
      case ScreenEdge.top:
        left = ringCenter.dx - panelWidth / 2;
        top = rail.bottom + panelGap;
      case ScreenEdge.bottom:
        left = ringCenter.dx - panelWidth / 2;
        top = rail.top - panelGap - panelHeight;
    }

    const margin = 4.0;
    final minLeft = visiblePosition.dx + margin;
    final maxLeft =
        visiblePosition.dx + visibleSize.width - panelWidth - margin;
    final minTop = visiblePosition.dy + margin;
    final maxTop =
        visiblePosition.dy + visibleSize.height - panelHeight - margin;

    left = maxLeft < minLeft ? minLeft : left.clamp(minLeft, maxLeft);
    top = maxTop < minTop ? minTop : top.clamp(minTop, maxTop);
    return Rect.fromLTWH(left, top, panelWidth, panelHeight);
  }

  /// The OS window rect that must contain both the rail and, if hovering,
  /// the detail panel - window_manager only controls one rectangle, so the
  /// two are rendered as regions within this union.
  static Rect windowRectFor(Rect rail, Rect? panel) =>
      panel == null ? rail : rail.expandToInclude(panel);
}

/// Decides which ring (if any) is hovered from a periodically polled cursor
/// position. The rail and the currently-shown detail panel are treated as
/// one interactive zone - moving from a ring toward its panel keeps it
/// open - with a short grace period before collapsing so the transition
/// isn't flicker-prone.
class EdgeDockHoverTracker {
  EdgeDockHoverTracker({
    this.collapseGrace = const Duration(milliseconds: 400),
    this.ringHitRadius = EdgeDockGeometry.itemBlockLength / 2,
  });

  final Duration collapseGrace;
  final double ringHitRadius;

  int? _hoveredIndex;
  DateTime? _lastInsideAt;

  int? get hoveredIndex => _hoveredIndex;

  /// Feeds one polled cursor sample in. [currentPanelRect] is the panel
  /// rect for the *currently* hovered item (if any) - used so moving the
  /// cursor into that panel keeps the same item selected. Returns true if
  /// [hoveredIndex] changed as a result.
  bool update({
    required Offset cursor,
    required Rect railRect,
    required List<Offset> ringCenters,
    required Rect? currentPanelRect,
    required DateTime now,
  }) {
    int? candidate;
    if (railRect.contains(cursor)) {
      for (var i = 0; i < ringCenters.length; i++) {
        if ((ringCenters[i] - cursor).distance <= ringHitRadius) {
          candidate = i;
          break;
        }
      }
    } else if (currentPanelRect != null && currentPanelRect.contains(cursor)) {
      candidate = _hoveredIndex;
    }

    if (candidate != null) {
      _lastInsideAt = now;
      if (_hoveredIndex == candidate) return false;
      _hoveredIndex = candidate;
      return true;
    }

    if (_hoveredIndex == null) return false;
    final last = _lastInsideAt;
    if (last != null && now.difference(last) < collapseGrace) return false;
    _hoveredIndex = null;
    return true;
  }
}
