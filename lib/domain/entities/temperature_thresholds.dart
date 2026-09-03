import '../../core/constants/app_constants.dart';
import '../enums/storage_enums.dart';

/// Configurable severity bands for one device (or the global default).
///
/// Deliberately distinct from any manufacturer-reported limit: this is the
/// *user's* (or app default's) alerting policy, never presented as a
/// hardware safety fact.
class TemperatureThresholds {
  const TemperatureThresholds({
    this.warningCelsius = AppConstants.defaultWarningCelsius,
    this.criticalCelsius = AppConstants.defaultCriticalCelsius,
    this.recoveryHysteresisCelsius = AppConstants.recoveryHysteresisCelsius,
  });

  final double warningCelsius;
  final double criticalCelsius;
  final double recoveryHysteresisCelsius;

  static const defaults = TemperatureThresholds();

  TemperatureSeverity classify(double celsius) {
    if (celsius >= criticalCelsius) return TemperatureSeverity.critical;
    if (celsius >= warningCelsius) return TemperatureSeverity.warning;
    if (celsius >= warningCelsius - 10) return TemperatureSeverity.warm;
    return TemperatureSeverity.normal;
  }

  /// Temperature below which a critical alert is considered "recovered"
  /// and may fire again on a subsequent breach (hysteresis, section 8).
  double get criticalRecoveryCelsius => criticalCelsius - recoveryHysteresisCelsius;

  double get warningRecoveryCelsius => warningCelsius - recoveryHysteresisCelsius;

  TemperatureThresholds copyWith({
    double? warningCelsius,
    double? criticalCelsius,
    double? recoveryHysteresisCelsius,
  }) {
    return TemperatureThresholds(
      warningCelsius: warningCelsius ?? this.warningCelsius,
      criticalCelsius: criticalCelsius ?? this.criticalCelsius,
      recoveryHysteresisCelsius:
          recoveryHysteresisCelsius ?? this.recoveryHysteresisCelsius,
    );
  }

  Map<String, dynamic> toJson() => {
        'warningCelsius': warningCelsius,
        'criticalCelsius': criticalCelsius,
        'recoveryHysteresisCelsius': recoveryHysteresisCelsius,
      };

  factory TemperatureThresholds.fromJson(Map<String, dynamic> json) {
    return TemperatureThresholds(
      warningCelsius: (json['warningCelsius'] as num?)?.toDouble() ??
          AppConstants.defaultWarningCelsius,
      criticalCelsius: (json['criticalCelsius'] as num?)?.toDouble() ??
          AppConstants.defaultCriticalCelsius,
      recoveryHysteresisCelsius:
          (json['recoveryHysteresisCelsius'] as num?)?.toDouble() ??
              AppConstants.recoveryHysteresisCelsius,
    );
  }
}
