import 'package:driveguard/application/settings/app_settings.dart'
    show kAllEdgeDockMetrics;
import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/edge_dock_geometry.dart';
import 'package:driveguard/presentation/widget/edge_dock_popover_bubble.dart';
import 'package:driveguard/presentation/widget/edge_dock_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleDevice = MiniWidgetDeviceSnapshot(
    id: 'nvme-1',
    name: 'Samsung 990 PRO',
    valueText: '45°C',
    fraction: 0.65,
    severity: TemperatureSeverity.normal,
    type: StorageDeviceType.nvme,
    healthStatus: 'GOOD',
    lifePercent: 99,
    powerOnHoursText: '2,400h on',
    readSpeedText: '3.5 GB/s',
    writeSpeedText: '2.8 GB/s',
    freeCapacityText: '700 GB free',
  );

  final sampleSnapshot = const MiniWidgetSnapshot(
    devices: [sampleDevice],
    compact: false,
  );

  Widget testHarness({
    MiniWidgetSnapshot? snapshot,
    ScreenEdge edge = ScreenEdge.right,
    Color? accentOverride,
    int? hoveredIndex = 0,
    int? pinnedIndex,
    EdgeDockTheme theme = EdgeDockTheme.defaults,
    Set<EdgeDockMetric> visibleMetrics = kAllEdgeDockMetrics,
    bool reducedMotion = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: SizedBox(
            width: 500,
            height: 500,
            child: EdgeDockContent(
              snapshot: snapshot ?? sampleSnapshot,
              edge: edge,
              accentOverride: accentOverride,
              hoveredIndex: hoveredIndex,
              pinnedIndex: pinnedIndex,
              onHover: (_) {},
              railLocalRect: const Rect.fromLTWH(400, 50, 64, 200),
              // sampleDevice populates all 7 possible detail rows - size the
              // panel the same way production does (EdgeDockGeometry) rather
              // than a hardcoded guess, so this doesn't silently drift stale
              // whenever the real layout's padding/type scale changes.
              panelLocalRect: Rect.fromLTWH(
                140,
                50,
                EdgeDockGeometry.panelWidth,
                EdgeDockGeometry.panelHeightFor(7),
              ),
              theme: theme,
              visibleMetrics: visibleMetrics,
            ),
          ),
        ),
      ),
    );
  }

  group('EdgeDockPopoverBubble & Detail Popover Structure', () {
    testWidgets('renders EdgeDockPopoverBubble with speech bubble painter', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());
      await tester.pumpAndSettle();

      expect(find.byType(EdgeDockPopoverBubble), findsOneWidget);
      final bubble = tester.widget<EdgeDockPopoverBubble>(
        find.byType(EdgeDockPopoverBubble),
      );
      expect(bubble.edge, ScreenEdge.right);
      expect(bubble.targetArrowPosition, isNonZero);
    });

    testWidgets('header section renders device icon, title, and status badge', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());
      await tester.pumpAndSettle();

      // NVMe icon inside the bubble
      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.byIcon(Icons.memory_rounded),
        ),
        findsOneWidget,
      );
      // Device name
      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.text('Samsung 990 PRO'),
        ),
        findsOneWidget,
      );
      // Status badge (and SMART row both display 'GOOD')
      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.text('GOOD'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('renders storage device icons according to device type', (
      tester,
    ) async {
      const ssdDevice = MiniWidgetDeviceSnapshot(
        id: 'ssd-1',
        name: 'Crucial MX500',
        valueText: '38°C',
        fraction: 0.4,
        severity: TemperatureSeverity.normal,
        type: StorageDeviceType.ssd,
        healthStatus: 'HEALTHY',
      );

      await tester.pumpWidget(
        testHarness(
          snapshot: const MiniWidgetSnapshot(
            devices: [ssdDevice],
            compact: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.byIcon(Icons.storage_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.text('Crucial MX500'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('linear progress bar reflects fraction and colors', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());
      await tester.pumpAndSettle();

      final progressIndicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progressIndicator.value, closeTo(0.65, 0.001));
      expect(progressIndicator.backgroundColor, const Color(0xFF1E1E28));
      expect(progressIndicator.minHeight, 5.0);
    });

    testWidgets('breakdown label displays % Used and % left', (tester) async {
      await tester.pumpWidget(testHarness());
      await tester.pumpAndSettle();

      // 65% used -> 35% left
      expect(find.text('65% Used · 35% left'), findsOneWidget);
    });

    testWidgets('telemetry rows render key-value metrics when enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(visibleMetrics: kAllEdgeDockMetrics),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EdgeDockPopoverBubble),
          matching: find.text('45°C'),
        ),
        findsOneWidget,
      );
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('99%'), findsOneWidget);
      expect(find.text('SMART'), findsOneWidget);
      expect(find.text('Power on'), findsOneWidget);
      expect(find.text('2,400h on'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('3.5 GB/s'), findsOneWidget);
      expect(find.text('Write'), findsOneWidget);
      expect(find.text('2.8 GB/s'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('700 GB free'), findsOneWidget);
    });

    testWidgets('telemetry rows filter properly according to visibleMetrics', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          visibleMetrics: const {
            EdgeDockMetric.health,
            EdgeDockMetric.freeCapacity,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('SMART'), findsNothing);
      expect(find.text('Power on'), findsNothing);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Write'), findsNothing);
    });
  });

  group('EdgeDockPopoverBubble Theme and Motion', () {
    testWidgets('applies accent override color to badge and progress bar', (
      tester,
    ) async {
      const testAccent = Color(0xFFFF9F45);
      await tester.pumpWidget(testHarness(accentOverride: testAccent));
      await tester.pumpAndSettle();

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      final valueColor = indicator.valueColor as AlwaysStoppedAnimation<Color>;
      expect(valueColor.value, testAccent);
    });

    testWidgets('reduced motion renders immediately without animation lag', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness(reducedMotion: true));
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Samsung 990 PRO'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('calculates targetArrowPosition relative to panelRect', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          edge: ScreenEdge.left,
        ),
      );
      await tester.pumpAndSettle();

      final bubble = tester.widget<EdgeDockPopoverBubble>(
        find.byType(EdgeDockPopoverBubble),
      );
      expect(bubble.edge, ScreenEdge.left);
      expect(bubble.targetArrowPosition, greaterThan(0));
    });
  });
}
