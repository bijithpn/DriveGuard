sealed class StorageMonitorException implements Exception {
  const StorageMonitorException(this.message, {this.deviceId});

  final String message;
  final String? deviceId;

  @override
  String toString() => '$runtimeType(${deviceId ?? '-'}): $message';
}

final class DeviceNotFoundException extends StorageMonitorException {
  const DeviceNotFoundException(String deviceId)
    : super('Device not found', deviceId: deviceId);
}

final class PermissionDeniedException extends StorageMonitorException {
  const PermissionDeniedException(String deviceId, [String? detail])
    : super(
        detail ?? 'Permission denied reading device telemetry',
        deviceId: deviceId,
      );
}

final class SensorUnavailableException extends StorageMonitorException {
  const SensorUnavailableException(String deviceId, [String? detail])
    : super(detail ?? 'Temperature sensor unavailable', deviceId: deviceId);
}

final class UnsupportedDeviceException extends StorageMonitorException {
  const UnsupportedDeviceException(String deviceId, [String? detail])
    : super(
        detail ?? 'Device type is not supported for telemetry',
        deviceId: deviceId,
      );
}

final class NativeBackendException extends StorageMonitorException {
  const NativeBackendException(super.message, {super.deviceId});
}

final class CommandExecutionException extends StorageMonitorException {
  const CommandExecutionException(super.message, {super.deviceId});
}

final class InvalidReadingException extends StorageMonitorException {
  const InvalidReadingException(super.message, {super.deviceId});
}
