import '../../domain/entities/storage_thresholds.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../prediction/trend_analyzer.dart';



class PredictiveHit {
  const PredictiveHit({required this.etaText, required this.critical});

  
  final String etaText;

  
  final bool critical;
}








class PredictiveEngine {
  const PredictiveEngine({this.minRSquared = 0.6, this.minSamples = 4});

  
  
  
  final double minRSquared;

  
  final int minSamples;

  static const _analyzer = TrendAnalyzer();

  TrendResult? _fit(List<TrendPoint> points) {
    final result = _analyzer.fit(points, minSamples: minSamples);
    if (result == null || result.rSquared < minRSquared) return null;
    return result;
  }

  
  PredictiveHit? evaluateTemperature({
    required List<TrendPoint> points,
    required double currentCelsius,
    required TemperatureThresholds thresholds,
    required Duration leadTime,
  }) {
    final trend = _fit(points);
    if (trend == null) return null;
    return _nearestHit(
      trend: trend,
      current: currentCelsius,
      warningTarget: thresholds.warningCelsius,
      criticalTarget: thresholds.criticalCelsius,
      leadTime: leadTime,
      formatEta: _formatShortEta,
    );
  }

  
  PredictiveHit? evaluateCapacity({
    required List<TrendPoint> points,
    required double currentUsagePercent,
    required StorageThresholds thresholds,
    required Duration leadTime,
  }) {
    final trend = _fit(points);
    if (trend == null) return null;
    return _nearestHit(
      trend: trend,
      current: currentUsagePercent,
      warningTarget: thresholds.warningPercent,
      criticalTarget: thresholds.criticalPercent,
      leadTime: leadTime,
      formatEta: _formatDayEta,
    );
  }

  
  
  PredictiveHit? evaluateHealthWear({
    required List<TrendPoint> points,
    required double currentPercentageUsed,
    required Duration leadTime,
    double targetPercentageUsed = 100,
  }) {
    final trend = _fit(points);
    if (trend == null || currentPercentageUsed >= targetPercentageUsed) {
      return null;
    }
    final eta = trend.timeToReach(currentPercentageUsed, targetPercentageUsed);
    if (eta == null || eta > leadTime) return null;
    return PredictiveHit(etaText: _formatDayEta(eta), critical: true);
  }

  PredictiveHit? _nearestHit({
    required TrendResult trend,
    required double current,
    required double warningTarget,
    required double criticalTarget,
    required Duration leadTime,
    required String Function(Duration) formatEta,
  }) {
    if (current < criticalTarget) {
      final eta = trend.timeToReach(current, criticalTarget);
      if (eta != null && eta <= leadTime) {
        return PredictiveHit(etaText: formatEta(eta), critical: true);
      }
    }
    if (current < warningTarget) {
      final eta = trend.timeToReach(current, warningTarget);
      if (eta != null && eta <= leadTime) {
        return PredictiveHit(etaText: formatEta(eta), critical: false);
      }
    }
    return null;
  }

  String _formatShortEta(Duration d) {
    if (d.inMinutes < 1) return 'under a minute';
    if (d.inMinutes < 60) return '~${d.inMinutes} min';
    return '~${d.inHours}h ${d.inMinutes % 60}m';
  }

  String _formatDayEta(Duration d) {
    if (d.inHours < 24) return '~${d.inHours}h';
    return '~${d.inDays} day${d.inDays == 1 ? '' : 's'}';
  }
}
