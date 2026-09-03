import '../enums/storage_enums.dart';

class StorageCapacity {
  const StorageCapacity({
    required this.availability,
    this.totalBytes,
    this.usedBytes,
    this.freeBytes,
    this.allocatedBytes,
    this.unallocatedBytes,
  });

  final SensorAvailability availability;
  final int? totalBytes;
  final int? usedBytes;
  final int? freeBytes;

  final int? allocatedBytes;

  final int? unallocatedBytes;

  static const unavailable = StorageCapacity(
    availability: SensorAvailability.unavailable,
  );

  double? get usagePercent {
    if (totalBytes == null || usedBytes == null || totalBytes == 0) {
      return null;
    }
    return (usedBytes! / totalBytes!) * 100;
  }

  bool get isValid =>
      availability == SensorAvailability.available && totalBytes != null;

  StorageCapacity copyWith({
    SensorAvailability? availability,
    int? totalBytes,
    int? usedBytes,
    int? freeBytes,
    int? allocatedBytes,
    int? unallocatedBytes,
  }) {
    return StorageCapacity(
      availability: availability ?? this.availability,
      totalBytes: totalBytes ?? this.totalBytes,
      usedBytes: usedBytes ?? this.usedBytes,
      freeBytes: freeBytes ?? this.freeBytes,
      allocatedBytes: allocatedBytes ?? this.allocatedBytes,
      unallocatedBytes: unallocatedBytes ?? this.unallocatedBytes,
    );
  }
}
