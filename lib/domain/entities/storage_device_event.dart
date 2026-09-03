enum StorageDeviceEventKind { added, removed }






class StorageDeviceEvent {
  const StorageDeviceEvent({required this.kind, required this.deviceId});

  final StorageDeviceEventKind kind;
  final String deviceId;
}
