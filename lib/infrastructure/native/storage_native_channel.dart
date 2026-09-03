import 'package:flutter/services.dart';

import '../../core/errors/storage_exceptions.dart';
import '../../core/logging/app_logger.dart';

class StorageNativeChannel {
  StorageNativeChannel._();
  static final StorageNativeChannel instance = StorageNativeChannel._();

  static const MethodChannel _channel = MethodChannel(
    'driveguard/storage_native',
  );
  static const EventChannel _deviceEventsChannel = EventChannel(
    'driveguard/storage_device_events',
  );
  static const EventChannel _activityChannel = EventChannel(
    'driveguard/storage_activity',
  );
  static const _tag = 'StorageNativeChannel';

  Stream<Map<String, dynamic>> activityEvents() {
    return _activityChannel.receiveBroadcastStream().map((raw) {
      final map = _asMap(raw);
      return map ?? const <String, dynamic>{};
    });
  }

  Stream<Map<String, dynamic>> deviceEvents() {
    return _deviceEventsChannel.receiveBroadcastStream().map((raw) {
      final map = _asMap(raw);
      return map ?? const <String, dynamic>{};
    });
  }

  Future<Map<String, dynamic>> getCapabilities() async {
    final raw = await _invoke('getCapabilities', null);
    return _asMap(raw) ?? const {};
  }

  Future<List<Map<String, dynamic>>> getDevices() async {
    final raw = await _invoke('getDevices', null);
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>?> readTemperature(String deviceId) async {
    final raw = await _invoke('readTemperature', {'deviceId': deviceId});
    return _asMap(raw);
  }

  Future<Map<String, dynamic>?> getHealth(String deviceId) async {
    final raw = await _invoke('getHealth', {'deviceId': deviceId});
    return _asMap(raw);
  }

  Future<List<Map<String, dynamic>>> getSensors(String deviceId) async {
    final raw = await _invoke('getSensors', {'deviceId': deviceId});
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>?> getCapacity(String deviceId) async {
    final raw = await _invoke('getCapacity', {'deviceId': deviceId});
    return _asMap(raw);
  }

  Future<List<Map<String, dynamic>>> getVolumes(String deviceId) async {
    final raw = await _invoke('getVolumes', {'deviceId': deviceId});
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Object?> _invoke(String method, Map<String, dynamic>? args) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      rethrow;
    } on PlatformException catch (e) {
      AppLogger.instance.warning(
        _tag,
        '$method failed: ${e.code} ${e.message}',
      );
      switch (e.code) {
        case 'PERMISSION_DENIED':
          throw PermissionDeniedException(
            (args?['deviceId'] as String?) ?? '-',
            e.message,
          );
        case 'UNSUPPORTED':
          return null;
        case 'DEVICE_NOT_FOUND':
          throw DeviceNotFoundException((args?['deviceId'] as String?) ?? '-');
        default:
          throw NativeBackendException(
            e.message ?? 'Native storage channel error (${e.code})',
            deviceId: args?['deviceId'] as String?,
          );
      }
    }
  }

  Map<String, dynamic>? _asMap(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }
}
