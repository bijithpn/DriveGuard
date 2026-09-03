import '../../domain/enums/storage_enums.dart';

/// Pure temperature math + validation. No I/O, no platform code — this is
/// what unit tests target directly.
class TemperatureUtils {
  const TemperatureUtils._();

  /// Anything outside this range cannot be a real storage-device
  /// temperature (electronics don't survive it, and negative readings from
  /// consumer NAND/SMART are always sensor noise, not physical fact).
  /// Used only to reject garbage - NOT a safety/danger threshold.
  static const double minPlausibleCelsius = -40.0;
  static const double maxPlausibleCelsius = 125.0;

  /// A single poll interval's worth of drift is normal; a jump larger than
  /// this between two consecutive *valid* readings is almost certainly a
  /// sensor glitch or a misparsed value, not a real thermal event.
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

  static String format(double celsius, TemperatureUnit unit,
      {int decimals = 0}) {
    final value = convert(celsius, unit);
    return '${value.toStringAsFixed(decimals)}${unitSuffix(unit)}';
  }

  /// Rejects values that cannot possibly be a real reading. Does not know
  /// about the previous reading - see [isPlausibleTransition] for that.
  static bool isPlausibleValue(double celsius) {
    if (celsius.isNaN || celsius.isInfinite) return false;
    return celsius >= minPlausibleCelsius && celsius <= maxPlausibleCelsius;
  }

  /// Rejects a physically-impossible jump from [previous] to [next] within
  /// a single poll interval. A single spurious sample should not be
  /// believed just because it's individually in-range.
  static bool isPlausibleTransition(double previous, double next) {
    return (next - previous).abs() <= maxPlausibleJumpPerReadingCelsius;
  }

  /// A reading is stale once it is older than [staleAfter], which callers
  /// derive from the configured polling interval (see
  /// [AppConstants.staleThresholdMultiplier]).
  static bool isStale(DateTime timestamp, Duration staleAfter,
      {DateTime? now}) {
    final reference = now ?? DateTime.now();
    return reference.difference(timestamp) > staleAfter;
  }
}
