import 'package:driveguard/application/prediction/trend_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const analyzer = TrendAnalyzer();
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  List<TrendPoint> linear(int n, {double start = 40, double perSecond = 1}) => [
    for (var i = 0; i < n; i++)
      TrendPoint(
        t0.add(Duration(seconds: i * 30)),
        start + perSecond * (i * 30),
      ),
  ];

  test('returns null with fewer than minSamples points', () {
    expect(analyzer.fit(linear(3)), isNull);
  });

  test('fits a clean rising line with high R^2 and correct slope', () {
    final result = analyzer.fit(linear(6, start: 40, perSecond: 0.5));
    expect(result, isNotNull);
    expect(result!.slopePerSecond, closeTo(0.5, 0.001));
    expect(result.rSquared, closeTo(1.0, 0.001));
  });

  test('flat data has zero slope and no timeToReach', () {
    final result = analyzer.fit(linear(6, start: 40, perSecond: 0));
    expect(result, isNotNull);
    expect(result!.slopePerSecond, 0);
    expect(result.timeToReach(40, 70), isNull);
  });

  test('noisy data around a flat mean has low R^2', () {
    final points = [
      TrendPoint(t0, 40),
      TrendPoint(t0.add(const Duration(seconds: 30)), 55),
      TrendPoint(t0.add(const Duration(seconds: 60)), 38),
      TrendPoint(t0.add(const Duration(seconds: 90)), 52),
      TrendPoint(t0.add(const Duration(seconds: 120)), 41),
    ];
    final result = analyzer.fit(points);
    expect(result, isNotNull);
    expect(result!.rSquared, lessThan(0.5));
  });

  test('timeToReach projects forward correctly for a rising trend', () {
    final result = analyzer.fit(linear(6, start: 40, perSecond: 1));
    final eta = result!.timeToReach(40, 100);
    expect(eta, const Duration(seconds: 60));
  });

  test('timeToReach is null when target is behind the current trend', () {
    final result = analyzer.fit(linear(6, start: 40, perSecond: 1));
    expect(result!.timeToReach(40, 30), isNull);
  });

  test('timeToReach is null for a falling trend moving away from target', () {
    final result = analyzer.fit(linear(6, start: 80, perSecond: -1));
    expect(result!.timeToReach(80, 100), isNull);
  });

  test('returns null when all samples share the same timestamp', () {
    final points = [
      TrendPoint(t0, 10),
      TrendPoint(t0, 20),
      TrendPoint(t0, 30),
      TrendPoint(t0, 40),
    ];
    expect(analyzer.fit(points), isNull);
  });
}
