class TrendPoint {
  const TrendPoint(this.timestamp, this.value);
  final DateTime timestamp;
  final double value;
}

class TrendResult {
  const TrendResult({
    required this.slopePerSecond,
    required this.rSquared,
    required this.sampleCount,
  });

  final double slopePerSecond;

  final double rSquared;

  final int sampleCount;

  Duration? timeToReach(double from, double target) {
    if (slopePerSecond == 0) return null;
    final seconds = (target - from) / slopePerSecond;
    if (!seconds.isFinite || seconds <= 0) return null;
    return Duration(seconds: seconds.round());
  }
}

class TrendAnalyzer {
  const TrendAnalyzer();

  TrendResult? fit(List<TrendPoint> points, {int minSamples = 4}) {
    if (points.length < minSamples) return null;

    final t0 = points.first.timestamp;
    final xs = <double>[
      for (final p in points)
        p.timestamp.difference(t0).inMilliseconds / 1000.0,
    ];
    final ys = <double>[for (final p in points) p.value];
    final n = xs.length;

    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;

    var sxy = 0.0;
    var sxx = 0.0;
    var syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    if (sxx == 0) return null;

    final slope = sxy / sxx;
    final intercept = meanY - slope * meanX;

    double rSquared;
    if (syy == 0) {
      rSquared = 1.0;
    } else {
      var ssRes = 0.0;
      for (var i = 0; i < n; i++) {
        final residual = ys[i] - (intercept + slope * xs[i]);
        ssRes += residual * residual;
      }
      rSquared = 1 - (ssRes / syy);
    }

    return TrendResult(
      slopePerSecond: slope,
      rSquared: rSquared,
      sampleCount: n,
    );
  }
}
