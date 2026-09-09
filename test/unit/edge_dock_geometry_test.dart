import 'dart:ui';

import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/edge_dock_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const displayPosition = Offset.zero;
  const displaySize = Size(1920, 1080);

  group('EdgeDockGeometry.stripRect', () {
    test('left edge sits flush to x=0, vertically centered', () {
      final rect = EdgeDockGeometry.stripRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
      );
      expect(rect.left, 0);
      expect(rect.width, EdgeDockGeometry.stripThickness);
      expect(rect.height, EdgeDockGeometry.stripLength);
      expect(rect.center.dy, closeTo(displaySize.height / 2, 0.01));
    });

    test('right edge sits flush to the display width', () {
      final rect = EdgeDockGeometry.stripRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
      );
      expect(rect.right, displaySize.width);
    });

    test('top edge sits flush to y=0, horizontally centered', () {
      final rect = EdgeDockGeometry.stripRect(
        displayPosition,
        displaySize,
        ScreenEdge.top,
      );
      expect(rect.top, 0);
      expect(rect.width, EdgeDockGeometry.stripLength);
      expect(rect.height, EdgeDockGeometry.stripThickness);
      expect(rect.center.dx, closeTo(displaySize.width / 2, 0.01));
    });

    test('bottom edge sits flush to the display height', () {
      final rect = EdgeDockGeometry.stripRect(
        displayPosition,
        displaySize,
        ScreenEdge.bottom,
      );
      expect(rect.bottom, displaySize.height);
    });

    test('accounts for a non-zero display origin (secondary monitor)', () {
      final rect = EdgeDockGeometry.stripRect(
        const Offset(1920, 0),
        displaySize,
        ScreenEdge.right,
      );
      expect(rect.right, 1920 + displaySize.width);
    });
  });

  group('EdgeDockGeometry.panelRect', () {
    test('left-docked panel starts flush at x=0', () {
      final rect = EdgeDockGeometry.panelRect(
        displayPosition,
        displaySize,
        ScreenEdge.left,
      );
      expect(rect.left, 0);
      expect(rect.width, EdgeDockGeometry.panelWidth);
      expect(rect.height, EdgeDockGeometry.panelHeight);
    });

    test('right-docked panel ends flush at the display width', () {
      final rect = EdgeDockGeometry.panelRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
      );
      expect(rect.right, displaySize.width);
    });
  });

  group('EdgeDockHoverTracker', () {
    late Rect strip;
    late Rect panel;

    setUp(() {
      strip = EdgeDockGeometry.stripRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
      );
      panel = EdgeDockGeometry.panelRect(
        displayPosition,
        displaySize,
        ScreenEdge.right,
      );
    });

    test('expands when the cursor enters the strip', () {
      final tracker = EdgeDockHoverTracker();
      final now = DateTime(2026);

      final changed = tracker.update(
        cursor: strip.center,
        stripRect: strip,
        panelRect: panel,
        now: now,
      );

      expect(changed, isTrue);
      expect(tracker.expanded, isTrue);
    });

    test('stays expanded while the cursor is inside the panel', () {
      final tracker = EdgeDockHoverTracker();
      final now = DateTime(2026);
      tracker.update(
        cursor: strip.center,
        stripRect: strip,
        panelRect: panel,
        now: now,
      );

      final changed = tracker.update(
        cursor: panel.center,
        stripRect: strip,
        panelRect: panel,
        now: now.add(const Duration(milliseconds: 100)),
      );

      expect(changed, isFalse);
      expect(tracker.expanded, isTrue);
    });

    test(
      'does not collapse immediately after leaving both rects (grace period)',
      () {
        final tracker = EdgeDockHoverTracker(
          collapseGrace: const Duration(milliseconds: 400),
        );
        final now = DateTime(2026);
        tracker.update(
          cursor: strip.center,
          stripRect: strip,
          panelRect: panel,
          now: now,
        );

        final changed = tracker.update(
          cursor: const Offset(0, 0),
          stripRect: strip,
          panelRect: panel,
          now: now.add(const Duration(milliseconds: 100)),
        );

        expect(changed, isFalse);
        expect(tracker.expanded, isTrue);
      },
    );

    test('collapses once the grace period elapses outside both rects', () {
      final tracker = EdgeDockHoverTracker(
        collapseGrace: const Duration(milliseconds: 400),
      );
      final now = DateTime(2026);
      tracker.update(
        cursor: strip.center,
        stripRect: strip,
        panelRect: panel,
        now: now,
      );

      final changed = tracker.update(
        cursor: const Offset(0, 0),
        stripRect: strip,
        panelRect: panel,
        now: now.add(const Duration(milliseconds: 500)),
      );

      expect(changed, isTrue);
      expect(tracker.expanded, isFalse);
    });

    test('stays collapsed when the cursor never enters either rect', () {
      final tracker = EdgeDockHoverTracker();
      final changed = tracker.update(
        cursor: const Offset(0, 0),
        stripRect: strip,
        panelRect: panel,
        now: DateTime(2026),
      );

      expect(changed, isFalse);
      expect(tracker.expanded, isFalse);
    });
  });
}
