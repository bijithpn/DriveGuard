import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alerts survive a JSON round trip and affect equality', () {
    const alert = MiniWidgetAlert(
      id: 'memory',
      title: 'Memory is almost full',
      critical: true,
      culpritName: 'Claude',
      culpritPid: 4242,
      canQuit: true,
    );
    const snap = MiniWidgetSnapshot(
      devices: [],
      compact: false,
      alerts: [alert],
    );
    final back = MiniWidgetSnapshot.fromJson(snap.toJson());
    expect(back, snap);
    expect(back.alerts.single.culpritName, 'Claude');
    expect(back.alerts.single.canQuit, isTrue);
    expect(
      snap == const MiniWidgetSnapshot(devices: [], compact: false),
      isFalse,
    );
  });

  test('old payloads without alerts still parse', () {
    final s = MiniWidgetSnapshot.fromJson({'devices': [], 'compact': true});
    expect(s.alerts, isEmpty);
  });
}
