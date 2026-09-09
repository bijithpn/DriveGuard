import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/presentation/widget/edge_dock_organic_painter.dart';
import 'package:driveguard/presentation/widget/edge_dock_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testSnapshot = const MiniWidgetSnapshot(
    devices: [
      MiniWidgetDeviceSnapshot(
        id: 'nvme-1',
        name: 'Samsung 980 Pro',
        valueText: '42°C',
        fraction: 0.42,
        severity: TemperatureSeverity.normal,
        healthStatus: 'HEALTHY',
        type: StorageDeviceType.nvme,
      ),
      MiniWidgetDeviceSnapshot(
        id: 'ssd-1',
        name: 'Crucial MX500',
        valueText: '58°C',
        fraction: 0.75,
        severity: TemperatureSeverity.warning,
        healthStatus: 'WARNING',
        type: StorageDeviceType.ssd,
      ),
      MiniWidgetDeviceSnapshot(
        id: 'hdd-1',
        name: 'WD Black HDD',
        valueText: '35°C',
        fraction: 0.35,
        severity: TemperatureSeverity.normal,
        healthStatus: 'HEALTHY',
        type: StorageDeviceType.hdd,
      ),
    ],
    compact: false,
  );

  Widget testHarness({
    MiniWidgetSnapshot? snapshot,
    ScreenEdge edge = ScreenEdge.left,
    int? hoveredIndex,
    int? pinnedIndex,
    ValueChanged<int?>? onHover,
    ValueChanged<int?>? onTapRing,
    VoidCallback? onTapActionPod,
  }) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox(
          width: 500,
          height: 500,
          child: EdgeDockContent(
            snapshot: snapshot ?? testSnapshot,
            edge: edge,
            accentOverride: null,
            hoveredIndex: hoveredIndex,
            pinnedIndex: pinnedIndex,
            onHover: onHover ?? (_) {},
            onTapRing: onTapRing,
            onTapActionPod: onTapActionPod,
            railLocalRect: const Rect.fromLTWH(0, 50, 64, 300),
            panelLocalRect: hoveredIndex != null
                ? const Rect.fromLTWH(72, 50, 240, 168)
                : null,
          ),
        ),
      ),
    );
  }

  group('Circular Ring Gauges', () {
    testWidgets('renders all device ring items with percentage text and icons', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());

      expect(find.text('42°C'), findsOneWidget);
      expect(find.text('58°C'), findsOneWidget);
      expect(find.text('35°C'), findsOneWidget);

      expect(find.byIcon(Icons.memory_rounded), findsOneWidget); // NVMe
      expect(find.byIcon(Icons.storage_rounded), findsOneWidget); // SSD
      expect(find.byIcon(Icons.album_rounded), findsOneWidget); // HDD
    });

    testWidgets('renders empty ring placeholder when snapshot has no devices', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(snapshot: MiniWidgetSnapshot.empty),
      );

      expect(find.text('--'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
    });

    testWidgets('scales up hovered ring item with AnimatedScale', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness(hoveredIndex: 0));
      await tester.pumpAndSettle();

      final animatedScales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .toList();
      expect(animatedScales.isNotEmpty, isTrue);
      // The first item should be scaled up (1.08) while others are at 1.0
      expect(animatedScales.first.scale, 1.08);
      if (animatedScales.length > 1) {
        expect(animatedScales[1].scale, 1.0);
      }
    });

    testWidgets('displays pinned state on ring item', (tester) async {
      await tester.pumpWidget(testHarness(pinnedIndex: 1));
      await tester.pumpAndSettle();

      final semantics = find.bySemanticsLabel(RegExp('Crucial MX500'));
      expect(semantics, findsOneWidget);
    });
  });

  group('Bottom Action Pod', () {
    testWidgets('renders action pod with settings icon', (tester) async {
      await tester.pumpWidget(testHarness());

      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });

    testWidgets('tapping action pod triggers onTapActionPod callback', (
      tester,
    ) async {
      var actionTapped = false;
      await tester.pumpWidget(
        testHarness(onTapActionPod: () => actionTapped = true),
      );

      final podFinder = find.byIcon(Icons.tune_rounded);
      expect(podFinder, findsOneWidget);

      await tester.tap(podFinder);
      await tester.pumpAndSettle();

      expect(actionTapped, isTrue);
    });

    testWidgets('action pod responds to mouse hover with scale transition', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      final podCenter = tester.getCenter(find.byIcon(Icons.tune_rounded));
      await gesture.moveTo(podCenter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final podScaleFinder = find.ancestor(
        of: find.byIcon(Icons.tune_rounded),
        matching: find.byType(AnimatedScale),
      );
      expect(podScaleFinder, findsOneWidget);
      final scaleWidget = tester.widget<AnimatedScale>(podScaleFinder);
      expect(scaleWidget.scale, greaterThan(1.0));
    });
  });

  group('Organic Background Integration', () {
    testWidgets('integrates EdgeDockOrganicPainter in the rail background', (
      tester,
    ) async {
      await tester.pumpWidget(testHarness());

      final customPaints = tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      );
      final hasOrganicPainter = customPaints.any(
        (cp) => cp.painter is EdgeDockOrganicPainter,
      );
      expect(hasOrganicPainter, isTrue);
    });
  });
}
