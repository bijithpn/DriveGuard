import 'package:driveguard/application/alerts/predictive_engine.dart';
import 'package:driveguard/application/prediction/trend_analyzer.dart';
import 'package:driveguard/domain/entities/storage_thresholds.dart';
import 'package:driveguard/domain/entities/temperature_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = PredictiveEngine();
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);
  const thresholds = TemperatureThresholds(
    warningCelsius: 60,
    criticalCelsius: 70,
  );
  const storageThresholds = StorageThresholds(
    warningPercent: 85,
    criticalPercent: 95,
  );

  List<TrendPoint> rising(
    double start,
    double perSecond, {
    int n = 6,
    Duration step = const Duration(seconds: 30),
  }) => [
    for (var i = 0; i < n; i++)
      TrendPoint(t0.add(step * i), start + perSecond * (step.inSeconds * i)),
  ];

  group('evaluateTemperature', () {
    test('fires a critical hit when trending to critical within lead time', () {
      // 40C rising 1C every 30s -> reaches 70C in 900s (15min).
      final hit = engine.evaluateTemperature(
        points: rising(40, 1 / 30),
        currentCelsius: 40,
        thresholds: thresholds,
        leadTime: const Duration(minutes: 20),
      );
      expect(hit, isNotNull);
      expect(hit!.critical, isTrue);
    });

    test('fires a warning hit when only warning is within lead time', () {
      // Reaches 60C in 600s (10min) but 70C would take 900s - outside the
      // 12-minute lead time, so only the warning threshold qualifies.
      final hit = engine.evaluateTemperature(
        points: rising(40, 1 / 30),
        currentCelsius: 40,
        thresholds: thresholds,
        leadTime: const Duration(minutes: 12),
      );
      expect(hit, isNotNull);
      expect(hit!.critical, isFalse);
    });

    test('does not fire when trend is too slow for the lead time', () {
      final hit = engine.evaluateTemperature(
        points: rising(40, 0.001),
        currentCelsius: 40,
        thresholds: thresholds,
        leadTime: const Duration(minutes: 15),
      );
      expect(hit, isNull);
    });

    test('does not fire on flat/normal readings', () {
      final hit = engine.evaluateTemperature(
        points: rising(40, 0),
        currentCelsius: 40,
        thresholds: thresholds,
        leadTime: const Duration(minutes: 15),
      );
      expect(hit, isNull);
    });

    test(
      'does not fire on noisy, inconsistent data even if rising overall',
      () {
        final noisy = [
          TrendPoint(t0, 40),
          TrendPoint(t0.add(const Duration(seconds: 30)), 55),
          TrendPoint(t0.add(const Duration(seconds: 60)), 38),
          TrendPoint(t0.add(const Duration(seconds: 90)), 58),
          TrendPoint(t0.add(const Duration(seconds: 120)), 41),
        ];
        final hit = engine.evaluateTemperature(
          points: noisy,
          currentCelsius: 41,
          thresholds: thresholds,
          leadTime: const Duration(minutes: 15),
        );
        expect(hit, isNull);
      },
    );

    test('does not fire with fewer than minSamples points', () {
      final hit = engine.evaluateTemperature(
        points: rising(40, 1, n: 2),
        currentCelsius: 40,
        thresholds: thresholds,
        leadTime: const Duration(minutes: 15),
      );
      expect(hit, isNull);
    });
  });

  group('evaluateCapacity', () {
    test('projects days-to-full and fires within lead time', () {
      // 80% rising 1%/day -> reaches 95% critical in 15 days.
      final points = rising(
        80,
        1 / 86400,
        n: 6,
        step: const Duration(hours: 6),
      );
      final hit = engine.evaluateCapacity(
        points: points,
        currentUsagePercent: 80,
        thresholds: storageThresholds,
        leadTime: const Duration(days: 20),
      );
      expect(hit, isNotNull);
      expect(hit!.critical, isTrue);
      expect(hit.etaText, contains('day'));
    });

    test('does not fire when already past lead time', () {
      final points = rising(
        80,
        1 / 86400,
        n: 6,
        step: const Duration(hours: 6),
      );
      final hit = engine.evaluateCapacity(
        points: points,
        currentUsagePercent: 80,
        thresholds: storageThresholds,
        leadTime: const Duration(days: 1),
      );
      expect(hit, isNull);
    });
  });

  group('evaluateHealthWear', () {
    test('projects toward 100% wear and fires within lead time', () {
      final points = rising(
        70,
        1 / 86400,
        n: 6,
        step: const Duration(hours: 12),
      );
      final hit = engine.evaluateHealthWear(
        points: points,
        currentPercentageUsed: 70,
        leadTime: const Duration(days: 40),
      );
      expect(hit, isNotNull);
      expect(hit!.critical, isTrue);
    });

    test('does not fire once already at or past the target', () {
      final points = rising(
        100,
        0.01 / 86400,
        n: 6,
        step: const Duration(hours: 12),
      );
      final hit = engine.evaluateHealthWear(
        points: points,
        currentPercentageUsed: 100,
        leadTime: const Duration(days: 40),
      );
      expect(hit, isNull);
    });
  });
}
