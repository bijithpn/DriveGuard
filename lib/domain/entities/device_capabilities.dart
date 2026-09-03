import '../enums/storage_enums.dart';
import 'storage_device.dart';

/// Per-device telemetry capability breakdown (spec section 10) - distinct
/// from [BackendCapabilities] in storage_monitor.dart, which describes what
/// the OS *backend as a whole* can do. This describes what has actually
/// been observed for *this one device*: a NVMe drive behind an
/// unsupported RAID HBA and a well-supported one both report
/// `canEnumerateDevices: true` at the backend level, but only one of them
/// will show `temperature: true` here.
///
/// Every field is derived from data the device already carries - nothing
/// here is a fresh native call, and nothing is guessed from device type
/// alone. A field is `true` only because a real reading populated it,
/// matching spec section 42 ("do not show fake values").
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.temperature,
    required this.multipleSensors,
    required this.smart,
    required this.health,
    required this.nvmeHealth,
    required this.powerCycles,
    required this.powerOnHours,
    required this.percentageUsed,
  });

  final bool temperature;
  final bool multipleSensors;
  final bool smart;
  final bool health;
  final bool nvmeHealth;
  final bool powerCycles;
  final bool powerOnHours;
  final bool percentageUsed;

  factory DeviceCapabilities.derive(StorageDevice device) {
    final health = device.health;
    final hasHealth = health.status != DeviceHealthStatus.unavailable;
    return DeviceCapabilities(
      temperature: device.primaryTemperature?.isValid ?? false,
      multipleSensors: device.sensors.length > 1,
      smart: hasHealth,
      health: hasHealth,
      nvmeHealth: device.interfaceType == StorageInterfaceType.nvme &&
          (health.availableSparePercent != null || health.criticalWarning != null),
      powerCycles: health.powerCycles != null,
      powerOnHours: health.powerOnHours != null,
      percentageUsed: health.percentageUsed != null,
    );
  }

  /// Ordered (label, available) pairs for display - spec section 10's
  /// "Temperature ✓ / Health — " list format.
  List<(String, bool)> get entries => [
        ('Temperature', temperature),
        ('Multiple sensors', multipleSensors),
        ('SMART', smart),
        ('Health', health),
        ('NVMe data', nvmeHealth),
        ('Power cycles', powerCycles),
        ('Power-on hours', powerOnHours),
        ('Percentage used', percentageUsed),
      ];
}
