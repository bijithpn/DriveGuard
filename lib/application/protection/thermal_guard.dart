import '../../domain/entities/temperature_thresholds.dart';
import '../prediction/trend_analyzer.dart';
import '../settings/app_settings.dart';
import 'thermal_models.dart';

/// Per-device state machine that decides how dangerous a temperature is.
///
/// It avoids acting on a single spurious reading: the emergency stage needs
/// several consecutive hot samples (or an unmistakable spike / a fast rise
/// that will cross the limit within a minute), and once latched it only
/// releases after the drive has cooled by a hysteresis margin. That keeps the
/// drive from being power-cycled by flapping around a threshold, which is
/// itself bad for SSD longevity.
class ThermalGuard {
  ThermalGuard({this.analyzer = const TrendAnalyzer()});

  final TrendAnalyzer analyzer;

  int _hotStreak = 0;
  bool _emergencyLatched = false;

  /// Extra degrees above the emergency limit that count as an immediate,
  /// unambiguous emergency (no need to wait for a streak).
  static const double spikeMarginCelsius = 5;
  static const double releaseHysteresisCelsius = 5;
  static const double fastRiseCelsiusPerMinute = 3;
  static const int predictionHorizonSeconds = 60;

  bool get inEmergency => _emergencyLatched;

  void reset() {
    _hotStreak = 0;
    _emergencyLatched = false;
  }

  ThermalAssessment assess({
    required double celsius,
    required List<TrendPoint> recent,
    required TemperatureThresholds thresholds,
    required ThermalProtectionSettings settings,
  }) {
    final emergency = settings.emergencyCelsius;
    final trend = analyzer.fit(recent, minSamples: 4);
    final slopePerMinute = (trend != null && trend.rSquared >= 0.6)
        ? trend.slopePerSecond * 60
        : null;

    int? eta;
    if (trend != null && trend.rSquared >= 0.6 && slopePerMinute! > 0) {
      eta = trend.timeToReach(celsius, emergency)?.inSeconds;
    }

    if (celsius >= emergency) {
      _hotStreak++;
    } else {
      _hotStreak = 0;
    }

    String? reason;
    if (celsius >= emergency + spikeMarginCelsius) {
      _emergencyLatched = true;
      reason = 'Reached ${celsius.toStringAsFixed(0)}°C';
    } else if (_hotStreak >= settings.sustainedReadings) {
      _emergencyLatched = true;
      reason = 'Stayed at or above ${emergency.toStringAsFixed(0)}°C';
    } else if (celsius >= thresholds.criticalCelsius &&
        slopePerMinute != null &&
        slopePerMinute >= fastRiseCelsiusPerMinute &&
        eta != null &&
        eta <= predictionHorizonSeconds) {
      _emergencyLatched = true;
      reason =
          'Rising ${slopePerMinute.toStringAsFixed(1)}°C/min — will reach '
          '${emergency.toStringAsFixed(0)}°C in about ${eta}s';
    } else if (_emergencyLatched &&
        celsius < emergency - releaseHysteresisCelsius) {
      _emergencyLatched = false;
    }

    final ThermalStage stage;
    if (_emergencyLatched) {
      stage = ThermalStage.emergency;
    } else if (celsius >= thresholds.criticalCelsius) {
      stage = ThermalStage.danger;
    } else if (celsius >= thresholds.warningCelsius) {
      stage = ThermalStage.elevated;
    } else {
      stage = ThermalStage.nominal;
    }

    return ThermalAssessment(
      stage: stage,
      celsius: celsius,
      slopePerMinute: slopePerMinute,
      secondsToEmergency: eta,
      reason: reason,
    );
  }
}
