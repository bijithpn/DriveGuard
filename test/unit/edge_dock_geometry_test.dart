import 'dart:ui';

import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/edge_dock_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const displayPosition = Offset.zero;
  const displaySize = Size(1920, 1080);

  group('EdgeDockGeometry.railRect', () {
    test('left edge sits flush to x=0, vertically centered', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        2,
      );
      expect(rail.left, 0);
      expect(rail.width, EdgeDockGeometry.railThickness);
      expect(rail.height, EdgeDockGeometry.railLength(2));
      expect(rail.center.dy, closeTo(displaySize.height / 2, 0.01));
    });

    test('right edge sits flush to the display width', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      expect(rail.right, displaySize.width);
    });

    test('top edge sits flush to y=0, horizontally centered', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.top,
        3,
      );
      expect(rail.top, 0);
      expect(rail.width, EdgeDockGeometry.railLength(3));
      expect(rail.height, EdgeDockGeometry.railThickness);
      expect(rail.center.dx, closeTo(displaySize.width / 2, 0.01));
    });

    test('bottom edge sits flush to the display height', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.bottom,
        1,
      );
      expect(rail.bottom, displaySize.height);
    });

    test('grows with device count', () {
      final one = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      final three = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        3,
      );
      expect(three.height, greaterThan(one.height));
    });

    test('treats zero devices the same as one (placeholder slot)', () {
      final zero = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        0,
      );
      final one = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      expect(zero.height, one.height);
    });

    test('accounts for a non-zero display origin (secondary monitor)', () {
      final rail = EdgeDockGeometry.railRect(
        const Offset(1920, 0),
        displaySize,
        ScreenEdge.right,
        1,
      );
      expect(rail.right, 1920 + displaySize.width);
    });
  });

  group('EdgeDockGeometry.ringCenter', () {
    test('centers along the cross-axis for a vertical rail', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        2,
      );
      final center0 = EdgeDockGeometry.ringCenter(rail, ScreenEdge.right, 0);
      final center1 = EdgeDockGeometry.ringCenter(rail, ScreenEdge.right, 1);
      expect(center0.dx, closeTo(rail.center.dx, 0.01));
      expect(center1.dx, closeTo(rail.center.dx, 0.01));
      expect(center1.dy, greaterThan(center0.dy));
    });

    test('centers along the cross-axis for a horizontal rail', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.top,
        2,
      );
      final center0 = EdgeDockGeometry.ringCenter(rail, ScreenEdge.top, 0);
      final center1 = EdgeDockGeometry.ringCenter(rail, ScreenEdge.top, 1);
      expect(center0.dy, closeTo(rail.center.dy, 0.01));
      expect(center1.dx, greaterThan(center0.dx));
    });
  });

  group('EdgeDockGeometry.panelRectFor', () {
    test('opens to the left (away from the edge) when docked right', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      final center = EdgeDockGeometry.ringCenter(rail, ScreenEdge.right, 0);
      final panel = EdgeDockGeometry.panelRectFor(
        rail,
        ScreenEdge.right,
        center,
        displayPosition,
        displaySize,
      );
      expect(panel.right, lessThanOrEqualTo(rail.left));
    });

    test('opens to the right (away from the edge) when docked left', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        1,
      );
      final center = EdgeDockGeometry.ringCenter(rail, ScreenEdge.left, 0);
      final panel = EdgeDockGeometry.panelRectFor(
        rail,
        ScreenEdge.left,
        center,
        displayPosition,
        displaySize,
      );
      expect(panel.left, greaterThanOrEqualTo(rail.right));
    });

    test('clamps vertically so it never renders above the display top', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      // A ring center near the very top of the display would naturally
      // place the panel above y=0 - it must be clamped instead.
      final nearTopCenter = Offset(rail.center.dx, 2);
      final panel = EdgeDockGeometry.panelRectFor(
        rail,
        ScreenEdge.right,
        nearTopCenter,
        displayPosition,
        displaySize,
      );
      expect(panel.top, greaterThanOrEqualTo(displayPosition.dy));
    });

    test('clamps vertically so it never renders below the display bottom', () {
      final rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        1,
      );
      final nearBottomCenter = Offset(rail.center.dx, displaySize.height - 2);
      final panel = EdgeDockGeometry.panelRectFor(
        rail,
        ScreenEdge.right,
        nearBottomCenter,
        displayPosition,
        displaySize,
      );
      expect(
        panel.bottom,
        lessThanOrEqualTo(displayPosition.dy + displaySize.height),
      );
    });
  });

  group('EdgeDockGeometry.windowRectFor', () {
    test('equals the rail when no panel is open', () {
      final rail = Rect.fromLTWH(0, 0, 64, 200);
      expect(EdgeDockGeometry.windowRectFor(rail, null), rail);
    });

    test('is the bounding box of rail and panel when a panel is open', () {
      final rail = Rect.fromLTWH(1880, 400, 40, 200);
      final panel = Rect.fromLTWH(1600, 300, 240, 168);
      final union = EdgeDockGeometry.windowRectFor(rail, panel);
      expect(union.left, panel.left);
      expect(union.right, rail.right);
      expect(union.top, panel.top);
    });
  });

  group('EdgeDockHoverTracker', () {
    late Rect rail;
    late List<Offset> ringCenters;
    late Rect panel0;

    setUp(() {
      rail = EdgeDockGeometry.railRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        2,
      );
      ringCenters = [
        EdgeDockGeometry.ringCenter(rail, ScreenEdge.right, 0),
        EdgeDockGeometry.ringCenter(rail, ScreenEdge.right, 1),
      ];
      panel0 = EdgeDockGeometry.panelRectFor(
        rail,
        ScreenEdge.right,
        ringCenters[0],
        displayPosition,
        displaySize,
      );
    });

    test('selects the ring whose center the cursor is nearest to', () {
      final tracker = EdgeDockHoverTracker();
      final changed = tracker.update(
        cursor: ringCenters[0],
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: null,
        now: DateTime(2026),
      );
      expect(changed, isTrue);
      expect(tracker.hoveredIndex, 0);
    });

    test('switches selection when the cursor moves to another ring', () {
      final tracker = EdgeDockHoverTracker();
      final now = DateTime(2026);
      tracker.update(
        cursor: ringCenters[0],
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: null,
        now: now,
      );

      final changed = tracker.update(
        cursor: ringCenters[1],
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: panel0,
        now: now.add(const Duration(milliseconds: 50)),
      );

      expect(changed, isTrue);
      expect(tracker.hoveredIndex, 1);
    });

    test('stays selected while the cursor is inside the open panel', () {
      final tracker = EdgeDockHoverTracker();
      final now = DateTime(2026);
      tracker.update(
        cursor: ringCenters[0],
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: null,
        now: now,
      );

      final changed = tracker.update(
        cursor: panel0.center,
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: panel0,
        now: now.add(const Duration(milliseconds: 50)),
      );

      expect(changed, isFalse);
      expect(tracker.hoveredIndex, 0);
    });

    test(
      'stays selected briefly after leaving (grace period), then deselects',
      () {
        final tracker = EdgeDockHoverTracker(
          collapseGrace: const Duration(milliseconds: 400),
        );
        final now = DateTime(2026);
        tracker.update(
          cursor: ringCenters[0],
          railRect: rail,
          ringCenters: ringCenters,
          currentPanelRect: null,
          now: now,
        );

        final withinGrace = tracker.update(
          cursor: const Offset(0, 0),
          railRect: rail,
          ringCenters: ringCenters,
          currentPanelRect: panel0,
          now: now.add(const Duration(milliseconds: 100)),
        );
        expect(withinGrace, isFalse);
        expect(tracker.hoveredIndex, 0);

        final afterGrace = tracker.update(
          cursor: const Offset(0, 0),
          railRect: rail,
          ringCenters: ringCenters,
          currentPanelRect: panel0,
          now: now.add(const Duration(milliseconds: 500)),
        );
        expect(afterGrace, isTrue);
        expect(tracker.hoveredIndex, isNull);
      },
    );

    test('stays unselected when the cursor never enters the rail', () {
      final tracker = EdgeDockHoverTracker();
      final changed = tracker.update(
        cursor: const Offset(0, 0),
        railRect: rail,
        ringCenters: ringCenters,
        currentPanelRect: null,
        now: DateTime(2026),
      );

      expect(changed, isFalse);
      expect(tracker.hoveredIndex, isNull);
    });
  });
}
