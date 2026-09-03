/// Explicit, typed failure modes for the storage-monitoring stack.
///
/// Every layer (native tool invocation, parsing, monitoring service) should
/// throw one of these rather than a bare [Exception] so the UI and logs can
/// react to *why* a read failed instead of guessing from a message string.
sealed class StorageMonitorException implements Exception {
  const StorageMonitorException(this.message, {this.deviceId});

  final String message;
  final String? deviceId;

  @override
  String toString() => '$runtimeType(${deviceId ?? '-'}): $message';
}

/// The device referenced by an operation no longer exists (removed,
/// unplugged, or an ID from a stale snapshot).
final class DeviceNotFoundException extends StorageMonitorException {
  const DeviceNotFoundException(String deviceId)
      : super('Device not found', deviceId: deviceId);
}

/// The current OS user lacks the rights needed to read telemetry for this
/// device (e.g. SMART access requires elevation on this backend).
final class PermissionDeniedException extends StorageMonitorException {
  const PermissionDeniedException(String deviceId, [String? detail])
      : super(detail ?? 'Permission denied reading device telemetry',
            deviceId: deviceId);
}

/// The device exists but exposes no temperature sensor through any
/// mechanism available to this backend.
final class SensorUnavailableException extends StorageMonitorException {
  const SensorUnavailableException(String deviceId, [String? detail])
      : super(detail ?? 'Temperature sensor unavailable', deviceId: deviceId);
}

/// The device/controller is not one this backend knows how to query
/// (e.g. an unsupported USB bridge chipset, or a virtual disk).
final class UnsupportedDeviceException extends StorageMonitorException {
  const UnsupportedDeviceException(String deviceId, [String? detail])
      : super(detail ?? 'Device type is not supported for telemetry',
            deviceId: deviceId);
}

/// A platform-native backend (FFI/system API) failed unexpectedly.
final class NativeBackendException extends StorageMonitorException {
  const NativeBackendException(String message, {String? deviceId})
      : super(message, deviceId: deviceId);
}

/// Invoking an external CLI tool (smartctl, nvme, PowerShell, diskutil...)
/// failed: missing binary, non-zero exit, timeout, or unparseable output.
final class CommandExecutionException extends StorageMonitorException {
  const CommandExecutionException(String message, {String? deviceId})
      : super(message, deviceId: deviceId);
}

/// A reading was structurally present but failed validation (out of
/// physically plausible range, malformed, or an impossible jump from the
/// previous reading). Never silently coerced to 0 or the last-known value.
final class InvalidReadingException extends StorageMonitorException {
  const InvalidReadingException(String message, {String? deviceId})
      : super(message, deviceId: deviceId);
}
