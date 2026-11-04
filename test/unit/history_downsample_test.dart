import 'package:driveguard/application/monitoring/temperature_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);

  test('short series is returned unchanged', () {
    final pts = [
      for (var i = 0; i < 50; i++)
        HistoryPoint(t0.add(Duration(seconds: i)), 40.0 + i % 3),
    ];
    expect(downsampleHistory(pts), same(pts));
  });

  test('long series is reduced but keeps ends, peak and trough, in order', () {
    final pts = [
      for (var i = 0; i < 5000; i++)
        HistoryPoint(t0.add(Duration(seconds: i)), 40.0 + (i % 7)),
    ];
    pts[2500] = HistoryPoint(pts[2500].timestamp, 90.0);
    pts[1234] = HistoryPoint(pts[1234].timestamp, 10.0);

    final out = downsampleHistory(pts, maxPoints: 300);

    expect(out.length, lessThanOrEqualTo(320));
    expect(out.first, pts.first);
    expect(out.last, pts.last);
    expect(out.map((p) => p.celsius).reduce((a, b) => a > b ? a : b), 90.0);
    expect(out.map((p) => p.celsius).reduce((a, b) => a < b ? a : b), 10.0);
    for (var i = 1; i < out.length; i++) {
      expect(out[i].timestamp.isBefore(out[i - 1].timestamp), isFalse);
    }
  });
}
