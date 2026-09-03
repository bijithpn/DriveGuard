import 'dart:collection';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/temperature_reading.dart';

class HistoryPoint {
  const HistoryPoint(this.timestamp, this.celsius);
  final DateTime timestamp;
  final double celsius;
}

class HistoryStats {
  const HistoryStats({this.min, this.max, this.average});
  final double? min;
  final double? max;
  final double? average;
}

/// Bounded in-memory temperature history per device (section 17).
///
/// Raw samples are kept at full resolution for [AppConstants.rawHistoryRetention];
/// older points are downsampled into 1-minute buckets so memory stays
/// bounded regardless of how long the app runs, instead of growing
/// unboundedly or being dropped outright once the raw window rolls off.
class TemperatureHistoryStore {
  final Map<String, Queue<HistoryPoint>> _raw = {};
  final Map<String, Queue<HistoryPoint>> _aggregated = {};

  void record(String deviceId, TemperatureReading reading) {
    if (!reading.isValid) return;
    final raw = _raw.putIfAbsent(deviceId, () => Queue<HistoryPoint>());
    raw.addLast(HistoryPoint(reading.timestamp, reading.celsius));
    _rollOff(deviceId);
  }

  void _rollOff(String deviceId) {
    final raw = _raw[deviceId]!;
    final now = DateTime.now();
    final rawCutoff = now.subtract(AppConstants.rawHistoryRetention);
    while (raw.isNotEmpty && raw.first.timestamp.isBefore(rawCutoff)) {
      final point = raw.removeFirst();
      final agg = _aggregated.putIfAbsent(deviceId, () => Queue<HistoryPoint>());
      final bucketStart = DateTime(point.timestamp.year, point.timestamp.month,
          point.timestamp.day, point.timestamp.hour, point.timestamp.minute);
      if (agg.isNotEmpty && agg.last.timestamp == bucketStart) {
        // averaged in-place would need mutable state; simplest correct
        // approach is to keep one representative sample per minute bucket.
        continue;
      }
      agg.addLast(HistoryPoint(bucketStart, point.celsius));
    }
    final aggCutoff = now.subtract(AppConstants.maxHistoryRetention);
    final agg = _aggregated[deviceId];
    if (agg != null) {
      while (agg.isNotEmpty && agg.first.timestamp.isBefore(aggCutoff)) {
        agg.removeFirst();
      }
    }
  }

  List<HistoryPoint> pointsFor(String deviceId, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    final points = <HistoryPoint>[
      ...(_aggregated[deviceId] ?? const <HistoryPoint>[]),
      ...(_raw[deviceId] ?? const <HistoryPoint>[]),
    ];
    return points.where((p) => p.timestamp.isAfter(cutoff)).toList();
  }

  HistoryStats statsFor(String deviceId, Duration window) {
    final points = pointsFor(deviceId, window);
    if (points.isEmpty) return const HistoryStats();
    double min = points.first.celsius;
    double max = points.first.celsius;
    double sum = 0;
    for (final p in points) {
      if (p.celsius < min) min = p.celsius;
      if (p.celsius > max) max = p.celsius;
      sum += p.celsius;
    }
    return HistoryStats(min: min, max: max, average: sum / points.length);
  }

  void clearDevice(String deviceId) {
    _raw.remove(deviceId);
    _aggregated.remove(deviceId);
  }
}
