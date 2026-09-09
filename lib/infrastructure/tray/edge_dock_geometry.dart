import 'dart:ui';

import '../../domain/enums/ui_enums.dart';

/// Pure geometry for the edge-docked hover panel: where the collapsed strip
/// and expanded panel sit on a display, given the chosen edge. Kept free of
/// window_manager/screen_retriever so it's unit-testable without a real
/// window. See docs/superpowers/specs/2026-09-09-edge-dock-widget-design.md.
class EdgeDockGeometry {
  const EdgeDockGeometry._();

  static const double stripThickness = 6;
  static const double stripLength = 120;
  static const double panelWidth = 260;
  static const double panelHeight = 200;

  /// The collapsed strip's rect, in screen coordinates, centered on [edge]
  /// of a display occupying [visiblePosition]/[visibleSize].
  static Rect stripRect(
    Offset visiblePosition,
    Size visibleSize,
    ScreenEdge edge,
  ) {
    switch (edge) {
      case ScreenEdge.left:
        return Rect.fromLTWH(
          visiblePosition.dx,
          visiblePosition.dy + (visibleSize.height - stripLength) / 2,
          stripThickness,
          stripLength,
        );
      case ScreenEdge.right:
        return Rect.fromLTWH(
          visiblePosition.dx + visibleSize.width - stripThickness,
          visiblePosition.dy + (visibleSize.height - stripLength) / 2,
          stripThickness,
          stripLength,
        );
      case ScreenEdge.top:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - stripLength) / 2,
          visiblePosition.dy,
          stripLength,
          stripThickness,
        );
      case ScreenEdge.bottom:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - stripLength) / 2,
          visiblePosition.dy + visibleSize.height - stripThickness,
          stripLength,
          stripThickness,
        );
    }
  }

  /// The expanded panel's rect, sliding out from the same edge/anchor as
  /// the strip.
  static Rect panelRect(
    Offset visiblePosition,
    Size visibleSize,
    ScreenEdge edge,
  ) {
    switch (edge) {
      case ScreenEdge.left:
        return Rect.fromLTWH(
          visiblePosition.dx,
          visiblePosition.dy + (visibleSize.height - panelHeight) / 2,
          panelWidth,
          panelHeight,
        );
      case ScreenEdge.right:
        return Rect.fromLTWH(
          visiblePosition.dx + visibleSize.width - panelWidth,
          visiblePosition.dy + (visibleSize.height - panelHeight) / 2,
          panelWidth,
          panelHeight,
        );
      case ScreenEdge.top:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - panelWidth) / 2,
          visiblePosition.dy,
          panelWidth,
          panelHeight,
        );
      case ScreenEdge.bottom:
        return Rect.fromLTWH(
          visiblePosition.dx + (visibleSize.width - panelWidth) / 2,
          visiblePosition.dy + visibleSize.height - panelHeight,
          panelWidth,
          panelHeight,
        );
    }
  }
}

/// Decides expand/collapse from a periodically polled cursor position. A
/// short grace period after the cursor leaves both rects avoids flicker
/// while moving from the strip toward the panel (they aren't contiguous
/// during the slide animation).
class EdgeDockHoverTracker {
  EdgeDockHoverTracker({
    this.collapseGrace = const Duration(milliseconds: 400),
  });

  final Duration collapseGrace;
  bool _expanded = false;
  DateTime? _lastInsideAt;

  bool get expanded => _expanded;

  /// Feeds one polled cursor sample in. Returns true if [expanded] changed
  /// as a result.
  bool update({
    required Offset cursor,
    required Rect stripRect,
    required Rect panelRect,
    required DateTime now,
  }) {
    final inside = stripRect.contains(cursor) || panelRect.contains(cursor);
    if (inside) {
      _lastInsideAt = now;
      if (_expanded) return false;
      _expanded = true;
      return true;
    }

    if (!_expanded) return false;
    final last = _lastInsideAt;
    if (last != null && now.difference(last) < collapseGrace) return false;
    _expanded = false;
    return true;
  }
}
