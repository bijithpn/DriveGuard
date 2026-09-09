import 'dart:ui';

import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/edge_dock_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const displayPosition = Offset.zero;
  const displaySize = Size(1920, 1080);

  group('EdgeDockGeometry Constants', () {
    test('thickness constants match design specifications', () {
      expect(EdgeDockGeometry.railThickness, 68.0);
      expect(EdgeDockGeometry.collapsedThickness, 14.0);
      expect(EdgeDockGeometry.ringDiameter, 40.0);
      expect(EdgeDockGeometry.itemBlockLength, 58.0);
    });
  });

  group('EdgeDockGeometry.collapsedRailRect', () {
    test('left edge sits flush to x=0 with collapsedThickness width', () {
      final rect = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        2,
      );
      expect(rect.left, 0.0);
      expect(rect.width, EdgeDockGeometry.collapsedThickness);
      expect(rect.height, EdgeDockGeometry.railLength(2));
      expect(rect.center.dy, closeTo(displaySize.height / 2, 0.01));
    });

    test('right edge sits flush to display width with collapsedThickness width', () {
      final rect = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
        2,
      );
      expect(rect.right, displaySize.width);
      expect(rect.width, EdgeDockGeometry.collapsedThickness);
      expect(rect.height, EdgeDockGeometry.railLength(2));
      expect(rect.center.dy, closeTo(displaySize.height / 2, 0.01));
    });

    test('top edge sits flush to y=0 with collapsedThickness height', () {
      final rect = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.top,
        2,
      );
      expect(rect.top, 0.0);
      expect(rect.height, EdgeDockGeometry.collapsedThickness);
      expect(rect.width, EdgeDockGeometry.railLength(2));
      expect(rect.center.dx, closeTo(displaySize.width / 2, 0.01));
    });

    test('bottom edge sits flush to display height with collapsedThickness height', () {
      final rect = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.bottom,
        2,
      );
      expect(rect.bottom, displaySize.height);
      expect(rect.height, EdgeDockGeometry.collapsedThickness);
      expect(rect.width, EdgeDockGeometry.railLength(2));
      expect(rect.center.dx, closeTo(displaySize.width / 2, 0.01));
    });

    test('shifts along offset and clamps within screen bounds', () {
      final shifted = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        1,
        alongOffset: 100,
      );
      final normal = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        1,
      );
      expect(shifted.top, normal.top + 100);

      final clampedTop = EdgeDockGeometry.collapsedRailRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
        1,
        alongOffset: -10000,
      );
      expect(clampedTop.top, displayPosition.dy);
    });
  });

  group('EdgeDockGeometry.windowRectFor (collapsed / expanded / panel)', () {
    final rail = Rect.fromLTWH(1852, 400, 68, 200);
    final collapsedRail = Rect.fromLTWH(1906, 400, 14, 200);
    final panel = Rect.fromLTWH(1604, 350, 240, 168);

    test('returns collapsedRail when isExpanded is false and panel is null', () {
      final windowRect = EdgeDockGeometry.windowRectFor(
        rail,
        null,
        collapsedRail: collapsedRail,
        isExpanded: false,
      );
      expect(windowRect, collapsedRail);
    });

    test('returns rail when isExpanded is true and panel is null', () {
      final windowRect = EdgeDockGeometry.windowRectFor(
        rail,
        null,
        collapsedRail: collapsedRail,
        isExpanded: true,
      );
      expect(windowRect, rail);
    });

    test('returns union of rail and panel when panel is present', () {
      final windowRect = EdgeDockGeometry.windowRectFor(
        rail,
        panel,
        collapsedRail: collapsedRail,
        isExpanded: true,
      );
      expect(windowRect.left, panel.left);
      expect(windowRect.right, rail.right);
      expect(windowRect.top, panel.top);
      expect(windowRect.bottom, rail.bottom);
    });
  });
}
