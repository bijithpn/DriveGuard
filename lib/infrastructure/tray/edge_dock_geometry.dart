import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart' show Display;

import '../../domain/enums/ui_enums.dart';

/// Pure geometry for the edge-docked hover widget: a rail of per-device
/// ring indicators docked to a screen edge, plus a detail panel that
/// appears beside whichever ring is hovered. Kept free of window_manager/
/// screen_retriever so it's unit-testable without a real window. See
/// docs/superpowers/specs/2026-09-09-edge-dock-widget-design.md.
class EdgeDockGeometry {
  const EdgeDockGeometry._();

  static const double ringDiameter = 40;
  static const double itemBlockLength = 58; // ring (40) + spacing (4) + value label (14)
  static const double itemSpacing = 14;
  static const double filletRadius = 18;
  static const double railPadding = 18;
  static const double podDiameter = 36;
  static const double podSpacing = 12;
  static const double railThickness = 68;
  static const double collapsedThickness = 14;

  static const double panelWidth = 264;
  static const double panelGap = 8;

  // Kept as the fallback used when a caller doesn't pass an explicit
  // content-derived height to panelRectFor (e.g. existing tests) - actual
  // rendering always computes a real height via panelHeightFor so the
  // window is sized to fit its content instead of overflowing it.
  static const double panelHeightDefault = 168;

  // Matches edge_dock_view.dart's _DetailCard layout closely enough to
  // avoid overflow: header padding+text, the content column's vertical
  // padding, and one row's height (padding + single-line text), each with
  // a small margin for font-metric variance across platforms.
  static const double panelHeaderHeight = 48;
  static const double panelContentVerticalPadding = 28;
  static const double panelRowHeight = 26;
  static const double panelMinHeight = 100;

  /// The detail panel's height for a card that will render [rowCount] rows
  /// (always >= 1 - temperature is always shown). Content-driven instead of
  /// a fixed constant, since the number of optional rows varies with which
  /// data a device has and which [EdgeDockMetric]s are enabled.
  static double panelHeightFor(int rowCount) {
    final rows = rowCount < 1 ? 1 : rowCount;
    final height =
        panelHeaderHeight + panelContentVerticalPadding + rows * panelRowHeight;
    return height < panelMinHeight ? panelMinHeight : height;
  }

  static double railLength(int deviceCount, {bool showPod = true}) {
    final count = deviceCount < 1 ? 1 : deviceCount;
    return filletRadius * 2 +
        count * itemBlockLength +
        (count - 1) * itemSpacing +
        (showPod ? podSpacing + podDiameter : 0);
  }

  /// The rail's rect (the always-visible expanded state), in screen
  /// coordinates, centered on [edge] of a display occupying
  /// [visiblePosition]/[visibleSize] and shifted along the edge by
  /// [alongOffset] (positive = down for left/right, right for top/bottom) -
  /// how the user-draggable position is applied. Clamped so the rail always
  /// stays fully within the display's visible bounds, however far
  /// [alongOffset] asks it to move.
  static Rect railRect(
    Offset visiblePosition,
    Size visibleSize,
    ScreenEdge edge,
    int deviceCount, {
    double alongOffset = 0,
  }) {
    final length = railLength(deviceCount);
    switch (edge) {
      case ScreenEdge.left:
        return Rect.fromLTWH(
          visiblePosition.dx,
          _clampAlong(
            visiblePosition.dy +
                (visibleSize.height - length) / 2 +
                alongOffset,
            visiblePosition.dy,
            visiblePosition.dy + visibleSize.height - length,
          ),
          railThickness,
          length,
        );
      case ScreenEdge.right:
        return Rect.fromLTWH(
          visiblePosition.dx + visibleSize.width - railThickness,
          _clampAlong(
            visiblePosition.dy +
                (visibleSize.height - length) / 2 +
                alongOffset,
            visiblePosition.dy,
            visiblePosition.dy + visibleSize.height - length,
          ),
          railThickness,
          length,
        );
      case ScreenEdge.top:
        return Rect.fromLTWH(
          _clampAlong(
            visiblePosition.dx + (visibleSize.width - length) / 2 + alongOffset,
            visiblePosition.dx,
            visiblePosition.dx + visibleSize.width - length,
          ),
          visiblePosition.dy,
          length,
          railThickness,
        );
      case ScreenEdge.bottom:
        return Rect.fromLTWH(
          _clampAlong(
            visiblePosition.dx + (visibleSize.width - length) / 2 + alongOffset,
            visiblePosition.dx,
            visiblePosition.dx + visibleSize.width - length,
          ),
          visiblePosition.dy + visibleSize.height - railThickness,
          length,
          railThickness,
        );
    }
  }

  /// The minimal screen rect for the collapsed state along the configured [edge],
  /// centered and shifted by [alongOffset] identically to [railRect].
  static Rect collapsedRailRect(
    Offset visiblePosition,
    Size visibleSize,
    ScreenEdge edge,
    int deviceCount, {
    double alongOffset = 0,
  }) {
    final length = railLength(deviceCount);
    switch (edge) {
      case ScreenEdge.left:
        return Rect.fromLTWH(
          visiblePosition.dx,
          _clampAlong(
            visiblePosition.dy +
                (visibleSize.height - length) / 2 +
                alongOffset,
            visiblePosition.dy,
            visiblePosition.dy + visibleSize.height - length,
          ),
          collapsedThickness,
          length,
        );
      case ScreenEdge.right:
        return Rect.fromLTWH(
          visiblePosition.dx + visibleSize.width - collapsedThickness,
          _clampAlong(
            visiblePosition.dy +
                (visibleSize.height - length) / 2 +
                alongOffset,
            visiblePosition.dy,
            visiblePosition.dy + visibleSize.height - length,
          ),
          collapsedThickness,
          length,
        );
      case ScreenEdge.top:
        return Rect.fromLTWH(
          _clampAlong(
            visiblePosition.dx + (visibleSize.width - length) / 2 + alongOffset,
            visiblePosition.dx,
            visiblePosition.dx + visibleSize.width - length,
          ),
          visiblePosition.dy,
          length,
          collapsedThickness,
        );
      case ScreenEdge.bottom:
        return Rect.fromLTWH(
          _clampAlong(
            visiblePosition.dx + (visibleSize.width - length) / 2 + alongOffset,
            visiblePosition.dx,
            visiblePosition.dx + visibleSize.width - length,
          ),
          visiblePosition.dy + visibleSize.height - collapsedThickness,
          length,
          collapsedThickness,
        );
    }
  }

  static double _clampAlong(double value, double min, double max) =>
      max < min ? min : value.clamp(min, max);

  /// The screen-space center of the [index]th device's ring within [rail].
  static Offset ringCenter(Rect rail, ScreenEdge edge, int index) {
    final along =
        filletRadius +
        ringDiameter / 2 +
        index * (itemBlockLength + itemSpacing);
    if (edge == ScreenEdge.left || edge == ScreenEdge.right) {
      return Offset(rail.center.dx, rail.top + along);
    }
    return Offset(rail.left + along, rail.center.dy);
  }

  /// The detail panel's rect for a ring centered at [ringCenter], placed
  /// beside the rail on the side that opens away from the screen edge, and
  /// clamped so it never renders outside the display's visible bounds.
  /// [panelHeight] should come from [panelHeightFor] for the panel's actual
  /// row count - the default only exists so existing callers/tests that
  /// don't care about a specific height keep compiling.
  static Rect panelRectFor(
    Rect rail,
    ScreenEdge edge,
    Offset ringCenter,
    Offset visiblePosition,
    Size visibleSize, {
    double panelHeight = panelHeightDefault,
  }) {
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

  /// The OS window rect that must contain either the collapsed trigger, the
  /// expanded rail, or both the rail and the detail panel.
  static Rect windowRectFor(
    Rect rail,
    Rect? panel, {
    Rect? collapsedRail,
    bool isExpanded = true,
  }) {
    if (!isExpanded && collapsedRail != null && panel == null) {
      return collapsedRail;
    }
    return panel == null ? rail : rail.expandToInclude(panel);
  }

  /// Picks the display the dock should attach to: the one whose `id`
  /// matches [displayId], or [primary] if [displayId] is `null` or no
  /// longer among [displays] (e.g. that monitor was unplugged). Pure and
  /// unit-testable without a real `screen_retriever` platform channel.
  static Display pickDisplay(
    List<Display> displays,
    Display primary,
    String? displayId,
  ) {
    if (displayId == null) return primary;
    for (final d in displays) {
      if (d.id == displayId) return d;
    }
    return primary;
  }
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
