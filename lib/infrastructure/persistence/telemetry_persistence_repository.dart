import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/logging/app_logger.dart';

class LocalTelemetryPoint {
  const LocalTelemetryPoint({required this.timestamp, required this.celsius});

  final DateTime timestamp;
  final double celsius;

  Map<String, dynamic> toJson() => {
    't': timestamp.millisecondsSinceEpoch,
    'c': celsius,
  };

  factory LocalTelemetryPoint.fromJson(Map<String, dynamic> json) =>
      LocalTelemetryPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        celsius: (json['c'] as num).toDouble(),
      );
}

class TelemetryPersistenceRepository {
  static const _tag = 'TelemetryPersistenceRepository';
  static const _keyPrefix = 'driveguard.history.v1.';
  static const int _maxPersistedPointsPerDevice = 500;

  Future<Map<String, List<LocalTelemetryPoint>>> loadAll() async {
    final result = <String, List<LocalTelemetryPoint>>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
      for (final key in keys) {
        final deviceId = key.substring(_keyPrefix.length);
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => LocalTelemetryPoint.fromJson(e as Map<String, dynamic>))
            .toList();
        result[deviceId] = list;
      }
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed loading persisted telemetry', e);
    }
    return result;
  }

  Future<void> saveDevicePoints(
    String deviceId,
    List<LocalTelemetryPoint> points,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$deviceId';
      final toSave = points.length > _maxPersistedPointsPerDevice
          ? points.sublist(points.length - _maxPersistedPointsPerDevice)
          : points;
      final raw = jsonEncode(toSave.map((p) => p.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (e) {
      AppLogger.instance.error(
        _tag,
        'Failed saving telemetry for $deviceId',
        e,
      );
    }
  }

  Future<void> clearDevice(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$deviceId');
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed clearing device $deviceId', e);
    }
  }
}
