import '../enums/storage_enums.dart';

/// Capacity/usage for a physical disk, as reported by the native layer.
///
/// `availability` follows the same [SensorAvailability] states used for
/// temperature/health — a disk whose capacity couldn't be read is
/// `unavailable`/`error`, never a fabricated zero.
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

  /// Bytes allocated to partitions/volumes (may be less than [totalBytes]).
  final int? allocatedBytes;

  /// Bytes on the physical disk not allocated to any partition.
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
