import 'package:driveguard/domain/entities/storage_capacity.dart';
import 'package:driveguard/domain/entities/storage_volume.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageCapacity', () {
    test('unavailable constant reports unavailable, not zero', () {
      const capacity = StorageCapacity.unavailable;
      expect(capacity.availability, SensorAvailability.unavailable);
      expect(capacity.totalBytes, isNull);
      expect(capacity.usagePercent, isNull);
      expect(capacity.isValid, isFalse);
    });

    test('usagePercent computes from used/total', () {
      const capacity = StorageCapacity(
        availability: SensorAvailability.available,
        totalBytes: 1000,
        usedBytes: 250,
      );
      expect(capacity.usagePercent, 25.0);
      expect(capacity.isValid, isTrue);
    });

    test('usagePercent is null rather than dividing by zero total', () {
      const capacity = StorageCapacity(
        availability: SensorAvailability.available,
        totalBytes: 0,
        usedBytes: 0,
      );
      expect(capacity.usagePercent, isNull);
    });

    test(
      'isValid is false when availability is not available even with a total',
      () {
        const capacity = StorageCapacity(
          availability: SensorAvailability.permissionDenied,
          totalBytes: 1000,
        );
        expect(capacity.isValid, isFalse);
      },
    );
  });

  group('StorageVolume', () {
    test('usagePercent computes from used/total', () {
      const volume = StorageVolume(
        id: 'vol-1',
        totalBytes: 2000,
        usedBytes: 500,
      );
      expect(volume.usagePercent, 25.0);
    });

    test('an unmounted volume reports null capacity fields, not zero', () {
      const volume = StorageVolume(id: 'vol-2');
      expect(volume.mountPoint, isNull);
      expect(volume.totalBytes, isNull);
      expect(volume.usagePercent, isNull);
    });

    test('isEncrypted defaults to null (unknown), never false', () {
      const volume = StorageVolume(id: 'vol-3');
      expect(volume.isEncrypted, isNull);
    });
  });
}
