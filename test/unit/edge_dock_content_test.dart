import 'package:driveguard/application/settings/app_settings.dart'
    show kAllEdgeDockMetrics;
import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/presentation/theme/app_theme.dart';
import 'package:driveguard/presentation/widget/edge_dock_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = const MiniWidgetSnapshot(
    devices: [
      MiniWidgetDeviceSnapshot(
        id: 'a',
        name: 'NVMe SSD',
        valueText: '47°C',
        fraction: 0.5,
        severity: TemperatureSeverity.normal,
        healthStatus: 'HEALTHY',
      ),
      MiniWidgetDeviceSnapshot(
        id: 'b',
        name: 'SATA SSD',
        valueText: '39°C',
        fraction: 0.3,
        severity: TemperatureSeverity.normal,
        healthStatus: 'HEALTHY',
      ),
    ],
    compact: false,
  );

  Widget harness({
    required int? hoveredIndex,
    required ValueChanged<int?> onHover,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: EdgeDockContent(
            snapshot: snapshot,
            edge: ScreenEdge.right,
            accentOverride: null,
            hoveredIndex: hoveredIndex,
            onHover: onHover,
            railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
            panelLocalRect: hoveredIndex == null
                ? null
                : const Rect.fromLTWH(40, 50, 240, 168),
          ),
        ),
      ),
    );
  }

  testWidgets('hovering a ring reports its index', (tester) async {
    int? reported;
    await tester.pumpWidget(
      harness(hoveredIndex: null, onHover: (i) => reported = i),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();

    // The first ring sits near the top of the rail rect (300,50,64,200).
    await gesture.moveTo(const Offset(332, 80));
    await tester.pump();

    expect(reported, 0);
  });

  testWidgets('leaving the whole surface (rail + panel) reports null', (
    tester,
  ) async {
    int? reported = 0;
    await tester.pumpWidget(
      harness(hoveredIndex: 0, onHover: (i) => reported = i),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(332, 80));
    await tester.pump();

    // In production this widget is only ever given exactly the OS
    // window's client area (rail ∪ panel, via window_manager.setBounds),
    // so "leaving the surface" is "leaving the render area entirely" -
    // simulated here by moving well past this harness's 400x400 canvas.
    await gesture.moveTo(const Offset(1000, 1000));
    await tester.pump();

    expect(reported, isNull);
  });

  testWidgets(
    'moving from the rail into the open detail panel does not report a '
    'different or null index (no flicker)',
    (tester) async {
      final reportedValues = <int?>[];
      await tester.pumpWidget(
        harness(hoveredIndex: 0, onHover: reportedValues.add),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: const Offset(332, 80));
      await tester.pump();
      reportedValues.clear(); // Discard the initial hover-in from ring 0.

      // Move into the detail panel's region (40,50,240,168) - still inside
      // the same MouseRegion-wrapped surface, so onExit must not fire and
      // no null/other index should be reported.
      await gesture.moveTo(const Offset(160, 130));
      await tester.pump();

      expect(reportedValues, everyElement(0));
    },
  );

  testWidgets('shows the hovered device name in the detail panel', (
    tester,
  ) async {
    await tester.pumpWidget(harness(hoveredIndex: 1, onHover: (_) {}));

    expect(find.text('SATA SSD'), findsOneWidget);
  });

  final snapshotWithAllFields = MiniWidgetSnapshot(
    devices: [
      const MiniWidgetDeviceSnapshot(
        id: 'a',
        name: 'NVMe SSD',
        valueText: '47°C',
        fraction: 0.5,
        severity: TemperatureSeverity.normal,
        healthStatus: 'HEALTHY',
        lifePercent: 98,
        powerOnHoursText: '1,284h on',
        readSpeedText: '2.1 GB/s',
        writeSpeedText: '850 MB/s',
        freeCapacityText: '820 GB free',
      ),
    ],
    compact: false,
  );

  Widget metricHarness({required Set<EdgeDockMetric> visibleMetrics}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: EdgeDockContent(
            snapshot: snapshotWithAllFields,
            edge: ScreenEdge.right,
            accentOverride: null,
            hoveredIndex: 0,
            onHover: (_) {},
            railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
            panelLocalRect: const Rect.fromLTWH(40, 50, 240, 168),
            visibleMetrics: visibleMetrics,
          ),
        ),
      ),
    );
  }

  testWidgets('temperature always shows regardless of visibleMetrics', (
    tester,
  ) async {
    await tester.pumpWidget(metricHarness(visibleMetrics: const {}));
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Health'), findsNothing);
    expect(find.text('SMART'), findsNothing);
  });

  testWidgets('shows only the toggled-on rows', (tester) async {
    await tester.pumpWidget(
      metricHarness(visibleMetrics: const {EdgeDockMetric.health}),
    );
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('SMART'), findsNothing);
    expect(find.text('Power on'), findsNothing);
    expect(find.text('Read'), findsNothing);
    expect(find.text('Write'), findsNothing);
    expect(find.text('Free'), findsNothing);
  });

  testWidgets('shows all rows when every metric is enabled', (tester) async {
    await tester.pumpWidget(metricHarness(visibleMetrics: kAllEdgeDockMetrics));
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('SMART'), findsOneWidget);
    expect(find.text('Power on'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
  });

  group('edgeDockDetailRows', () {
    test('row count matches what panelHeightFor was designed to fit', () {
      final device = snapshotWithAllFields.devices.first;
      final rows = edgeDockDetailRows(device, kAllEdgeDockMetrics);
      // Temperature + all 6 optional rows (read/write count as one metric
      // each contributing a row) present on this device.
      expect(rows.length, 7);
    });

    test('temperature is always present even with no metrics enabled', () {
      final device = snapshotWithAllFields.devices.first;
      final rows = edgeDockDetailRows(device, const {});
      expect(rows, [('Temperature', device.valueText)]);
    });
  });

  group('click-to-pin (also the non-hover accessibility fallback)', () {
    Widget pinHarness({int? hoveredIndex, int? pinnedIndex}) {
      final displayed = pinnedIndex ?? hoveredIndex;
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: EdgeDockContent(
              snapshot: snapshot,
              edge: ScreenEdge.right,
              accentOverride: null,
              hoveredIndex: hoveredIndex,
              pinnedIndex: pinnedIndex,
              onHover: (_) {},
              onTapRing: (_) {},
              railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
              panelLocalRect: displayed == null
                  ? null
                  : const Rect.fromLTWH(40, 50, 240, 168),
            ),
          ),
        ),
      );
    }

    testWidgets('panel stays visible when pinned even without hover', (
      tester,
    ) async {
      await tester.pumpWidget(pinHarness(hoveredIndex: null, pinnedIndex: 1));
      expect(find.text('SATA SSD'), findsOneWidget);
    });

    testWidgets('tapping a ring invokes onTapRing with its index', (
      tester,
    ) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: EdgeDockContent(
                snapshot: snapshot,
                edge: ScreenEdge.right,
                accentOverride: null,
                hoveredIndex: null,
                onHover: (_) {},
                onTapRing: (i) => tapped = i,
                railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
                panelLocalRect: null,
              ),
            ),
          ),
        ),
      );

      // Ring 0 sits near the top of the rail rect (300,50,64,200).
      await tester.tapAt(const Offset(332, 80));
      await tester.pump();

      expect(tapped, 0);
    });
  });

  group('reduced motion', () {
    testWidgets('panel appears instantly when disableAnimations is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: EdgeDockContent(
                  snapshot: snapshot,
                  edge: ScreenEdge.right,
                  accentOverride: null,
                  hoveredIndex: 0,
                  onHover: (_) {},
                  railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
                  panelLocalRect: const Rect.fromLTWH(40, 50, 240, 168),
                ),
              ),
            ),
          ),
        ),
      );

      // No pump-and-settle needed: with reduced motion the fade-in tween
      // completes on the very first frame instead of over 180ms.
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('NVMe SSD'), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('EdgeDockTheme', () {
    testWidgets('applies a custom background/text color to the panel', (
      tester,
    ) async {
      const theme = EdgeDockTheme(
        background: Color(0xFF000000),
        text: Color(0xFFFFFFFF),
        mutedText: Color(0x80FFFFFF),
        warning: AppColors.warning,
        critical: AppColors.critical,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: EdgeDockContent(
                snapshot: snapshot,
                edge: ScreenEdge.right,
                accentOverride: null,
                hoveredIndex: 1,
                onHover: (_) {},
                railLocalRect: const Rect.fromLTWH(300, 50, 64, 200),
                panelLocalRect: const Rect.fromLTWH(40, 50, 240, 168),
                theme: theme,
              ),
            ),
          ),
        ),
      );

      final nameText = tester.widget<Text>(find.text('SATA SSD'));
      expect(nameText.style?.color, const Color(0xFFFFFFFF));
    });

    test('resolve falls back to app defaults when colors are null', () {
      final theme = EdgeDockTheme.resolve();
      expect(theme.background, AppColors.bg1);
      expect(theme.text, AppColors.textPrimary);
      expect(theme.warning, AppColors.warning);
      expect(theme.critical, AppColors.critical);
    });

    test('resolve applies the given color overrides', () {
      final theme = EdgeDockTheme.resolve(
        backgroundColor: 0xFF000000,
        textColor: 0xFFFFFFFF,
        warningColor: 0xFFFFC107,
        criticalColor: 0xFFE53935,
      );
      expect(theme.background, const Color(0xFF000000));
      expect(theme.text, const Color(0xFFFFFFFF));
      expect(theme.warning, const Color(0xFFFFC107));
      expect(theme.critical, const Color(0xFFE53935));
    });
  });
}
