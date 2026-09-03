import '../enums/storage_enums.dart';

/// A single temperature sample. Always canonically Celsius; convert only
/// at presentation time via [TemperatureUtils.convert].
///
/// [isValid] distinguishes "we got a number but it failed validation"
/// (kept for diagnostics) from a normal reading - callers should never
/// treat an invalid reading as current temperature.
class TemperatureReading {
  const TemperatureReading({
    required this.celsius,
    required this.timestamp,
    required this.source,
    this.isValid = true,
    this.invalidReason,
  });

  final double celsius;
  final DateTime timestamp;
  final TemperatureSource source;
  final bool isValid;
  final String? invalidReason;

  TemperatureReading copyWith({
    double? celsius,
    DateTime? timestamp,
    TemperatureSource? source,
    bool? isValid,
    String? invalidReason,
  }) {
    return TemperatureReading(
      celsius: celsius ?? this.celsius,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      isValid: isValid ?? this.isValid,
      invalidReason: invalidReason ?? this.invalidReason,
    );
  }
}

/// Where a temperature number came from - shown in the details screen so
/// users can tell "smartctl" from "nvme-cli" from the mock backend, rather
/// than presenting all numbers as equally authoritative.
class TemperatureSource {
  const TemperatureSource({required this.backendName, required this.sensorId});

  final String backendName;
  final String sensorId;

  @override
  String toString() => '$backendName:$sensorId';
}

/// One physical sensor exposed by a device. NVMe controllers commonly
/// expose several (composite + per-namespace); [isPrimary] marks the one
/// the dashboard uses by default.
class StorageSensor {
  const StorageSensor({
    required this.id,
    required this.name,
    required this.reading,
    required this.type,
    this.isPrimary = false,
  });

  final String id;
  final String name;
  final TemperatureReading? reading;
  final TemperatureSensorType type;
  final bool isPrimary;
}
