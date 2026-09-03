import '../../domain/enums/storage_enums.dart';

class TemperatureUtils {
  const TemperatureUtils._();

  static const double minPlausibleCelsius = -40.0;
  static const double maxPlausibleCelsius = 125.0;

  static const double maxPlausibleJumpPerReadingCelsius = 40.0;

  static double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

  static double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

  static double convert(double celsius, TemperatureUnit unit) {
    switch (unit) {
      case TemperatureUnit.celsius:
        return celsius;
      case TemperatureUnit.fahrenheit:
        return celsiusToFahrenheit(celsius);
    }
  }

  static String unitSuffix(TemperatureUnit unit) =>
      unit == TemperatureUnit.celsius ? '°C' : '°F';

  static String format(
    double celsius,
    TemperatureUnit unit, {
    int decimals = 0,
  }) {
    final value = convert(celsius, unit);
    return '${value.toStringAsFixed(decimals)}${unitSuffix(unit)}';
  }

  static bool isPlausibleValue(double celsius) {
    if (celsius.isNaN || celsius.isInfinite) return false;
    return celsius >= minPlausibleCelsius && celsius <= maxPlausibleCelsius;
  }

  static bool isPlausibleTransition(double previous, double next) {
    return (next - previous).abs() <= maxPlausibleJumpPerReadingCelsius;
  }

  static bool isStale(
    DateTime timestamp,
    Duration staleAfter, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    return reference.difference(timestamp) > staleAfter;
  }
}
