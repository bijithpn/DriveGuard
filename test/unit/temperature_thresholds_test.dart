import 'package:driveguard/domain/entities/temperature_thresholds.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const thresholds = TemperatureThresholds(
    warningCelsius: 60,
    criticalCelsius: 70,
  );

  group('TemperatureThresholds.classify', () {
    test('below warning band is normal', () {
      expect(thresholds.classify(45), TemperatureSeverity.normal);
    });

    test('just under warning is warm', () {
      expect(thresholds.classify(55), TemperatureSeverity.warm);
    });

    test('at warning threshold is warning', () {
      expect(thresholds.classify(60), TemperatureSeverity.warning);
    });

    test('at critical threshold is critical', () {
      expect(thresholds.classify(70), TemperatureSeverity.critical);
    });

    test('well above critical is still critical', () {
      expect(thresholds.classify(95), TemperatureSeverity.critical);
    });
  });

  test(
    'recovery points sit below their threshold by the hysteresis margin',
    () {
      const custom = TemperatureThresholds(
        warningCelsius: 60,
        criticalCelsius: 70,
        recoveryHysteresisCelsius: 5,
      );
      expect(custom.criticalRecoveryCelsius, 65);
      expect(custom.warningRecoveryCelsius, 55);
    },
  );

  test('round-trips through JSON', () {
    final json = thresholds.toJson();
    final restored = TemperatureThresholds.fromJson(json);
    expect(restored.warningCelsius, thresholds.warningCelsius);
    expect(restored.criticalCelsius, thresholds.criticalCelsius);
  });
}
