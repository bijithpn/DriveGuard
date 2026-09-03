import '../enums/storage_enums.dart';
import 'storage_device.dart';

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
      nvmeHealth:
          device.interfaceType == StorageInterfaceType.nvme &&
          (health.availableSparePercent != null ||
              health.criticalWarning != null),
      powerCycles: health.powerCycles != null,
      powerOnHours: health.powerOnHours != null,
      percentageUsed: health.percentageUsed != null,
    );
  }

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
