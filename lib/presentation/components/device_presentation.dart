import '../../domain/entities/storage_device.dart';
import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';
import '../../core/utils/temperature_utils.dart';

class DevicePresentation {
  DevicePresentation._({
    required this.severity,
    required this.valueText,
    required this.fraction,
    required this.statusText,
    required this.isStaleLike,
    required this.tempCelsius,
  });

  final TemperatureSeverity severity;
  final String valueText;
  final double fraction;
  final String statusText;
  final bool isStaleLike;
  final double? tempCelsius;

  factory DevicePresentation.of(
    StorageDevice device,
    TemperatureThresholds thresholds,
    TemperatureUnit unit,
  ) {
    final reading = device.primaryTemperature;
    final isUnavailableStatus =
        device.sensorAvailability == SensorAvailability.unsupported ||
        device.sensorAvailability == SensorAvailability.permissionDenied ||
        reading == null;

    if (device.monitoringStatus == MonitoringStatus.disconnected) {
      return DevicePresentation._(
        severity: TemperatureSeverity.unavailable,
        valueText: 'Disconnected',
        fraction: 0,
        statusText: 'Device disconnected',
        isStaleLike: true,
        tempCelsius: null,
      );
    }

    if (device.sensorAvailability == SensorAvailability.permissionDenied) {
      return DevicePresentation._(
        severity: TemperatureSeverity.unavailable,
        valueText: 'Permission required',
        fraction: 0,
        statusText:
            device.lastError ??
            'This device does not expose temperature data to the application without additional permissions.',
        isStaleLike: false,
        tempCelsius: null,
      );
    }

    if (isUnavailableStatus) {
      return DevicePresentation._(
        severity: TemperatureSeverity.unavailable,
        valueText: 'N/A',
        fraction: 0,
        statusText:
            device.lastError ??
            'This device does not expose SMART temperature data to the application.',
        isStaleLike: false,
        tempCelsius: null,
      );
    }

    final severity = thresholds.classify(reading.celsius);
    final isStale = device.monitoringStatus == MonitoringStatus.staleData;
    final valueText = TemperatureUtils.format(reading.celsius, unit);
    final safeCritical = thresholds.criticalCelsius > 0
        ? thresholds.criticalCelsius
        : 1.0;
    final rawFraction = reading.celsius / (safeCritical * 1.15);
    final fraction = rawFraction.isFinite ? rawFraction.clamp(0.0, 1.0) : 1.0;

    return DevicePresentation._(
      severity: severity,
      valueText: valueText,
      fraction: fraction,
      statusText: isStale
          ? 'Sensor data is currently stale'
          : (device.monitoringStatus == MonitoringStatus.error
                ? (device.lastError ?? 'Monitoring error')
                : _severityStatusText(severity)),
      isStaleLike: isStale,
      tempCelsius: reading.celsius,
    );
  }

  static String _severityStatusText(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return 'Normal';
      case TemperatureSeverity.warning:
        return 'Approaching configured limit';
      case TemperatureSeverity.critical:
        return 'Exceeded configured critical limit';
      case TemperatureSeverity.unavailable:
        return 'N/A';
    }
  }
}
