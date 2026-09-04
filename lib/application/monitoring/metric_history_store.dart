import 'dart:collection';


class MetricPoint {
  const MetricPoint(this.timestamp, this.value);
  final DateTime timestamp;
  final double value;
}










class MetricHistoryStore {
  MetricHistoryStore({
    required this.retention,
    required this.minSampleInterval,
  });

  final Duration retention;
  final Duration minSampleInterval;

  final Map<String, Queue<MetricPoint>> _points = {};

  void record(String deviceId, double value, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final points = _points.putIfAbsent(deviceId, () => Queue<MetricPoint>());
    if (points.isNotEmpty &&
        now.difference(points.last.timestamp) < minSampleInterval) {
      return;
    }
    points.addLast(MetricPoint(now, value));

    final cutoff = now.subtract(retention);
    while (points.isNotEmpty && points.first.timestamp.isBefore(cutoff)) {
      points.removeFirst();
    }
  }

  List<MetricPoint> pointsFor(String deviceId) =>
      List.unmodifiable(_points[deviceId] ?? const <MetricPoint>[]);

  void clearDevice(String deviceId) => _points.remove(deviceId);
}
