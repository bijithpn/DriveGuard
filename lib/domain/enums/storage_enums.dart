/// Physical category of a storage device.
enum StorageDeviceType { nvme, ssd, hdd, unknown }

/// Bus/interface a device is attached through.
enum StorageInterfaceType { nvme, sata, usb, scsi, unknown }

/// Whether/why a temperature sensor is available for a device.
///
/// This is distinct from the reading itself: a device can be
/// [available] but still momentarily fail a single read (see
/// [SensorAvailability.error]), which is different from a device that
/// structurally has [unsupported] telemetry.
enum SensorAvailability {
  available,
  unavailable,
  permissionDenied,
  unsupported,
  error,
}

/// Canonical unit for presentation. Storage internally is always Celsius.
enum TemperatureUnit { celsius, fahrenheit }

/// Which physical sensor a reading came from, for devices exposing more
/// than one (e.g. NVMe composite + per-namespace sensors).
enum TemperatureSensorType { composite, controller, namespace, drive, unknown }

/// SMART/NVMe health assessment. Deliberately independent of temperature
/// severity - see docs/temperature-monitoring.md.
enum DeviceHealthStatus { healthy, warning, critical, unknown, unavailable }

/// Combined severity used by the alert engine and UI badges.
enum TemperatureSeverity { normal, warm, warning, critical, unavailable }

/// Live monitoring status of a device as tracked by the monitoring service.
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
