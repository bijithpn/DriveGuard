enum StorageDeviceType { nvme, ssd, hdd, unknown }

enum StorageInterfaceType { nvme, sata, usb, scsi, unknown }

enum SensorAvailability {
  available,
  unavailable,
  permissionDenied,
  unsupported,
  error,
}

enum TemperatureUnit { celsius, fahrenheit }

enum TemperatureSensorType { composite, controller, namespace, drive, unknown }

enum DeviceHealthStatus { healthy, warning, critical, unknown, unavailable }

enum TemperatureSeverity { normal, warm, warning, critical, unavailable }

enum MonitoringStatus {
  initializing,
  active,
  paused,
  staleData,
  sensorUnavailable,
  permissionDenied,
  error,
  disconnected,
}
