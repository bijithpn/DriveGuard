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

class TemperatureHistoryStore {
  TemperatureHistoryStore({TelemetryPersistenceRepository? persistence})
    : _persistence = persistence ?? TelemetryPersistenceRepository();

  final TelemetryPersistenceRepository _persistence;
  final Map<String, Queue<HistoryPoint>> _raw = {};
  final Map<String, Queue<HistoryPoint>> _aggregated = {};
  final Map<String, int> _writesSinceLastSave = {};
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

    final count = (_writesSinceLastSave[deviceId] ?? 0) + 1;
    _writesSinceLastSave[deviceId] = count;

    if (count >= 10) {
      _writesSinceLastSave[deviceId] = 0;
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
    final points = <HistoryPoint>[
      ...(_aggregated[deviceId] ?? const <HistoryPoint>[]),
      ...(_raw[deviceId] ?? const <HistoryPoint>[]),
    ];
    return points.where((p) => p.timestamp.isAfter(cutoff)).toList();
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
    _writesSinceLastSave.remove(deviceId);
    _persistence.clearDevice(deviceId);
  }
}
