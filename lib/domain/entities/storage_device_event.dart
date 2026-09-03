enum StorageDeviceEventKind { added, removed }

/// A hot-plug notification pushed over the `driveguard/storage_device_events`
/// EventChannel. `MonitoringService` treats this as a hint to re-run
/// discovery immediately rather than waiting for the next poll; it does not
/// replace polling, since not every platform/driver combination reliably
/// fires these.
class StorageDeviceEvent {
  const StorageDeviceEvent({required this.kind, required this.deviceId});

  final StorageDeviceEventKind kind;
  final String deviceId;
}
