import 'dart:convert';

import 'package:driveguard/application/widget/mini_widget_snapshot.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const device = MiniWidgetDeviceSnapshot(
    id: 'a',
    name: 'SSD',
    valueText: '49°C',
    fraction: 0.5,
    severity: TemperatureSeverity.normal,
    usedFraction: 0.66,
  );

  test('capacity usage survives the trip to the floating window', () {
    final decoded = MiniWidgetDeviceSnapshot.fromJson(
      jsonDecode(jsonEncode(device.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.usedFraction, 0.66);
    expect(decoded, device);
  });

  test('capacity usage is part of equality, so a change is pushed', () {
    const other = MiniWidgetDeviceSnapshot(
      id: 'a',
      name: 'SSD',
      valueText: '49°C',
      fraction: 0.5,
      severity: TemperatureSeverity.normal,
      usedFraction: 0.67,
    );
    expect(other == device, isFalse);
  });

  test('older payloads without capacity still decode', () {
    final json = device.toJson()..remove('usedFraction');
    expect(MiniWidgetDeviceSnapshot.fromJson(json).usedFraction, isNull);
  });
}
