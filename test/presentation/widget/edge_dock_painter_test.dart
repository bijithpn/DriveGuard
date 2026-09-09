import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/presentation/widget/edge_dock_organic_painter.dart';
import 'package:driveguard/presentation/widget/edge_dock_popover_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgeDockOrganicPainter Tests', () {
    test('computes valid closed path for left edge without throwing', () {
      const painter = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        mainRailLength: 180,
        podDiameter: 36,
        podSpacing: 12,
        expansionProgress: 1.0,
        showPod: true,
      );

      const size = Size(60, 300);
      final path = painter.computePath(size);

      expect(path, isNotNull);
      final bounds = path.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(0.0));
      expect(bounds.right, greaterThan(0.0));
      expect(bounds.top, greaterThanOrEqualTo(0.0));
      expect(bounds.bottom, greaterThan(0.0));
    });

    test('computes valid paths for right, top, and bottom edges', () {
      for (final edge in ScreenEdge.values) {
        final painter = EdgeDockOrganicPainter(
          edge: edge,
          mainRailLength: 180,
          podDiameter: 36,
          podSpacing: 12,
          expansionProgress: 1.0,
          showPod: true,
        );

        const size = Size(100, 300);
        final path = painter.computePath(size);
        expect(path, isNotNull);
        final bounds = path.getBounds();
        expect(bounds.isEmpty, isFalse);
      }
    });

    test('collapsed progress produces narrower bounds than expanded progress', () {
      const collapsedPainter = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        dockDepth: 52.0,
        collapsedDepth: 8.0,
        expansionProgress: 0.0,
      );

      const expandedPainter = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        dockDepth: 52.0,
        collapsedDepth: 8.0,
        expansionProgress: 1.0,
      );

      const size = Size(60, 300);
      final collapsedBounds = collapsedPainter.computePath(size).getBounds();
      final expandedBounds = expandedPainter.computePath(size).getBounds();

      expect(collapsedBounds.width, lessThan(expandedBounds.width));
      expect(collapsedBounds.width, closeTo(8.0, 1.0));
      expect(expandedBounds.width, closeTo(52.0, 1.0));
    });

    test('showPod: false computes shorter path than showPod: true', () {
      const withPod = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        mainRailLength: 150,
        podDiameter: 40,
        podSpacing: 16,
        showPod: true,
      );

      const withoutPod = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        mainRailLength: 150,
        podDiameter: 40,
        podSpacing: 16,
        showPod: false,
      );

      const size = Size(60, 400);
      final withPodBounds = withPod.computePath(size).getBounds();
      final withoutPodBounds = withoutPod.computePath(size).getBounds();

      expect(withoutPodBounds.height, lessThan(withPodBounds.height));
    });

    testWidgets('paints correctly onto Canvas', (tester) async {
      const painter = EdgeDockOrganicPainter(
        edge: ScreenEdge.left,
        expansionProgress: 1.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(60, 300),
              painter: painter,
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is EdgeDockOrganicPainter,
        ),
        findsOneWidget,
      );
    });
  });

  group('EdgeDockSpeechBubblePainter & EdgeDockPopoverBubble Tests', () {
    test('computes speech bubble path including arrow beak pointing left', () {
      const bubblePainter = EdgeDockSpeechBubblePainter(
        edge: ScreenEdge.left,
        targetArrowPosition: 60.0,
        arrowWidth: 10.0,
        arrowHeight: 14.0,
        borderRadius: 16.0,
      );

      const size = Size(200, 120);
      final path = bubblePainter.computePath(size);

      expect(path, isNotNull);
      final bounds = path.getBounds();
      expect(bounds.left, equals(0.0));
      expect(bounds.right, equals(200.0));
      // Tip of the beak should be at x = 0, y = 60
      expect(path.contains(const Offset(0.5, 60.0)), isTrue);
    });

    test('clamps arrow beak safely away from rounded corners', () {
      const bubblePainter = EdgeDockSpeechBubblePainter(
        edge: ScreenEdge.left,
        targetArrowPosition: 2.0, // Near the top corner
        arrowWidth: 10.0,
        arrowHeight: 14.0,
        borderRadius: 16.0,
      );

      const size = Size(200, 120);
      final path = bubblePainter.computePath(size);
      final bounds = path.getBounds();
      expect(bounds.isEmpty, isFalse);

      // Clamped Y position should be at least borderRadius + arrowHeight / 2 = 16 + 7 = 23
      expect(path.contains(const Offset(0.5, 23.0)), isTrue);
    });

    testWidgets('renders EdgeDockPopoverBubble with child and custom decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EdgeDockPopoverBubble(
              edge: ScreenEdge.left,
              targetArrowPosition: 50,
              child: Text('Popover Content'),
            ),
          ),
        ),
      );

      expect(find.text('Popover Content'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is EdgeDockSpeechBubblePainter,
        ),
        findsOneWidget,
      );
    });
  });
}
