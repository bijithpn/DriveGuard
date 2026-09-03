import '../enums/storage_enums.dart';









class StorageActivity {
  const StorageActivity({
    required this.deviceId,
    required this.timestamp,
    required this.availability,
    this.readBytesPerSecond,
    this.writeBytesPerSecond,
    this.readOperationsPerSecond,
    this.writeOperationsPerSecond,
    this.utilizationPercent,
  });

  final String deviceId;
  final DateTime timestamp;
  final SensorAvailability availability;

  final double? readBytesPerSecond;
  final double? writeBytesPerSecond;
  final double? readOperationsPerSecond;
  final double? writeOperationsPerSecond;

  
  
  
  final double? utilizationPercent;
}
