import 'package:driveguard/application/settings/app_settings.dart'
    show kAllEdgeDockMetrics;
import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/edge_dock_geometry.dart';
import 'package:driveguard/presentation/widget/edge_dock_view.dart';
import 'package:driveguard/presentation/widget/mini_monitor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alert = MiniWidgetAlert(
    id: 'memory',
    title: 'Memory is almost full',
    critical: true,
    culpritName: 'Claude',
    culpritPid: 4242,
    canQuit: true,
  );
  const device = MiniWidgetDeviceSnapshot(
    id: 'd1',
    name: 'Internal SSD',
    valueText: '42°C',
    fraction: 0.4,
    severity: TemperatureSeverity.normal,
    type: StorageDeviceType.nvme,
  );
  const snap = MiniWidgetSnapshot(
    devices: [device],
    compact: false,
    alerts: [alert],
  );

  testWidgets('mini widget shows the alert and quits the culprit', (t) async {
    int? quit;
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 280,
          child: MiniMonitorView(
            snapshot: snap,
            onExpand: () {},
            onQuitProcess: (pid) => quit = pid,
          ),
        ),
      ),
    );
    expect(find.text('Memory is almost full'), findsOneWidget);
    await t.tap(find.text('Quit Claude'));
    expect(quit, 4242);
    expect(t.takeException(), isNull);
  });

  testWidgets('dock card shows alert, quits, and does not overflow', (t) async {
    int? quit;
    final panelHeight = EdgeDockGeometry.panelHeightFor(
      edgeDockDetailRows(device, kAllEdgeDockMetrics).length - 1,
      hasAlert: true,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 500,
            child: EdgeDockContent(
              snapshot: snap,
              edge: ScreenEdge.left,
              accentOverride: null,
              hoveredIndex: 0,
              onHover: (_) {},
              onQuitProcess: (pid) => quit = pid,
              railLocalRect: const Rect.fromLTWH(0, 50, 76, 200),
              panelLocalRect: Rect.fromLTWH(
                72,
                50,
                EdgeDockGeometry.panelWidth,
                panelHeight,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Memory is almost full'), findsOneWidget);
    await t.tap(find.text('Quit Claude'));
    expect(quit, 4242);
    expect(t.takeException(), isNull);
  });
}
