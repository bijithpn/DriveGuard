import 'dart:collection';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/temperature_reading.dart';
import '../../infrastructure/persistence/telemetry_persistence_repository.dart';

class HistoryPoint {
  const HistoryPoint(this.timestamp, this.celsius);
  final DateTime timestamp;
  final double celsius;
}

class HistoryStats {
  const HistoryStats({
    this.min,
    this.max,
    this.average,
    this.isElevated = false,
    this.elevationDelta = 0.0,
    this.samplesCount = 0,
  });

  final double? min;
  final double? max;
  final double? average;
  final bool isElevated;
  final double elevationDelta;
  final int samplesCount;
}

/// Reduces [points] (assumed time-ordered) to at most ~[maxPoints] by keeping
/// the min and max sample of each bucket, so peaks and troughs survive but
/// the chart has far fewer spots to lay out and paint.
List<HistoryPoint> downsampleHistory(
  List<HistoryPoint> points, {
  int maxPoints = 300,
}) {
  if (points.length <= maxPoints || maxPoints < 4) return points;
  final bucketCount = maxPoints ~/ 2;
  final bucketSize = points.length / bucketCount;
  final out = <HistoryPoint>[points.first];
  for (var b = 0; b < bucketCount; b++) {
    final start = (b * bucketSize).floor();
    final end = (((b + 1) * bucketSize).floor()).clamp(
      start + 1,
      points.length,
    );
    var minI = start;
    var maxI = start;
    for (var i = start; i < end; i++) {
      if (points[i].celsius < points[minI].celsius) minI = i;
      if (points[i].celsius > points[maxI].celsius) maxI = i;
    }
    if (minI == maxI) {
      out.add(points[minI]);
    } else if (minI < maxI) {
      out
        ..add(points[minI])
        ..add(points[maxI]);
    } else {
      out
        ..add(points[maxI])
        ..add(points[minI]);
    }
  }
  if (out.last != points.last) out.add(points.last);
  return out;
}

class TemperatureHistoryStore {
  TemperatureHistoryStore({TelemetryPersistenceRepository? persistence})
    : _persistence = persistence ?? TelemetryPersistenceRepository();

  final TelemetryPersistenceRepository _persistence;
  final Map<String, Queue<HistoryPoint>> _raw = {};
  final Map<String, Queue<HistoryPoint>> _aggregated = {};
  final Map<String, DateTime> _lastSavedAt = {};

  /// Minimum time between writes of a device's history to disk.
  static const Duration persistInterval = Duration(minutes: 5);
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final saved = await _persistence.loadAll();
    for (final entry in saved.entries) {
      final agg = _aggregated.putIfAbsent(
        entry.key,
        () => Queue<HistoryPoint>(),
      );
      for (final p in entry.value) {
        agg.addLast(HistoryPoint(p.timestamp, p.celsius));
      }
    }
  }

  void record(String deviceId, TemperatureReading reading) {
    if (!reading.isValid) return;
    final raw = _raw.putIfAbsent(deviceId, () => Queue<HistoryPoint>());
    raw.addLast(HistoryPoint(reading.timestamp, reading.celsius));
    _rollOff(deviceId);

    // Persist at most every few minutes: rewriting the telemetry blob on every
    // handful of readings is pointless SSD wear for a tool that exists to
    // protect the SSD. A crash loses at most a few minutes of chart history;
    // incident data is stored separately and flushed on shutdown/overheat.
    final now = DateTime.now();
    final last = _lastSavedAt[deviceId];
    if (last == null) {
      _lastSavedAt[deviceId] = now;
    } else if (now.difference(last) >= persistInterval) {
      _lastSavedAt[deviceId] = now;
      persistDevice(deviceId);
    }
  }

  Future<void> persistDevice(String deviceId) async {
    final points = pointsFor(deviceId, const Duration(days: 7));
    if (points.isEmpty) return;
    final toSave = points
        .map(
          (p) =>
              LocalTelemetryPoint(timestamp: p.timestamp, celsius: p.celsius),
        )
        .toList();
    await _persistence.saveDevicePoints(deviceId, toSave);
  }

  Future<void> persistAll() async {
    final ids = {..._raw.keys, ..._aggregated.keys};
    for (final id in ids) {
      await persistDevice(id);
    }
  }

  void _rollOff(String deviceId) {
    final raw = _raw[deviceId]!;
    final now = DateTime.now();
    final rawCutoff = now.subtract(AppConstants.rawHistoryRetention);
    while (raw.isNotEmpty && raw.first.timestamp.isBefore(rawCutoff)) {
      final point = raw.removeFirst();
      final agg = _aggregated.putIfAbsent(
        deviceId,
        () => Queue<HistoryPoint>(),
      );
      final bucketStart = DateTime(
        point.timestamp.year,
        point.timestamp.month,
        point.timestamp.day,
        point.timestamp.hour,
        point.timestamp.minute,
      );
      if (agg.isNotEmpty && agg.last.timestamp == bucketStart) {
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
    final points = <HistoryPoint>[];
    for (final p in _aggregated[deviceId] ?? const <HistoryPoint>[]) {
      if (p.timestamp.isAfter(cutoff)) points.add(p);
    }
    for (final p in _raw[deviceId] ?? const <HistoryPoint>[]) {
      if (p.timestamp.isAfter(cutoff)) points.add(p);
    }
    return points;
  }

  HistoryStats statsFor(
    String deviceId,
    Duration window, {
    double? currentCelsius,
    double elevatedThresholdDelta = 4.0,
  }) {
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
    final avg = sum / points.length;

    bool isElevated = false;
    double delta = 0.0;
    if (currentCelsius != null) {
      delta = currentCelsius - avg;
      if (delta >= elevatedThresholdDelta) {
        isElevated = true;
      }
    }

    return HistoryStats(
      min: min,
      max: max,
      average: avg,
      isElevated: isElevated,
      elevationDelta: delta,
      samplesCount: points.length,
    );
  }

  void clearDevice(String deviceId) {
    _raw.remove(deviceId);
    _aggregated.remove(deviceId);
    _lastSavedAt.remove(deviceId);
    _persistence.clearDevice(deviceId);
  }
}
