import 'package:driveguard/core/utils/temperature_utils.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemperatureUtils conversion', () {
    test('celsius to fahrenheit', () {
      expect(TemperatureUtils.celsiusToFahrenheit(0), 32);
      expect(TemperatureUtils.celsiusToFahrenheit(100), 212);
    });

    test('fahrenheit to celsius', () {
      expect(TemperatureUtils.fahrenheitToCelsius(32), 0);
      expect(TemperatureUtils.fahrenheitToCelsius(212), 100);
    });

    test('convert respects requested unit', () {
      expect(TemperatureUtils.convert(50, TemperatureUnit.celsius), 50);
      expect(TemperatureUtils.convert(0, TemperatureUnit.fahrenheit), 32);
    });

    test('format includes correct suffix', () {
      expect(TemperatureUtils.format(48, TemperatureUnit.celsius), '48°C');
      expect(TemperatureUtils.format(0, TemperatureUnit.fahrenheit), '32°F');
    });
  });

  group('TemperatureUtils validation', () {
    test('rejects NaN and infinite values', () {
      expect(TemperatureUtils.isPlausibleValue(double.nan), isFalse);
      expect(TemperatureUtils.isPlausibleValue(double.infinity), isFalse);
    });

    test('rejects values far outside physically plausible range', () {
      expect(TemperatureUtils.isPlausibleValue(-100), isFalse);
      expect(TemperatureUtils.isPlausibleValue(500), isFalse);
    });

    test('accepts values within plausible range', () {
      expect(TemperatureUtils.isPlausibleValue(45), isTrue);
      expect(TemperatureUtils.isPlausibleValue(-10), isTrue);
    });

    test('rejects an impossible jump between consecutive readings', () {
      expect(TemperatureUtils.isPlausibleTransition(45, 46), isTrue);
      expect(TemperatureUtils.isPlausibleTransition(45, 120), isFalse);
    });

    test('detects stale readings relative to a threshold', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final fresh = now.subtract(const Duration(seconds: 5));
      final stale = now.subtract(const Duration(minutes: 5));
      expect(TemperatureUtils.isStale(fresh, const Duration(seconds: 20), now: now), isFalse);
      expect(TemperatureUtils.isStale(stale, const Duration(seconds: 20), now: now), isTrue);
    });
  });
}
