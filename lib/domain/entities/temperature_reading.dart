import '../enums/storage_enums.dart';

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

class TemperatureSource {
  const TemperatureSource({required this.backendName, required this.sensorId});

  final String backendName;
  final String sensorId;

  @override
  String toString() => '$backendName:$sensorId';
}

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
