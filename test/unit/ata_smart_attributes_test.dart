import 'package:driveguard/infrastructure/storage/ata_smart_attributes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtaSmartExtras.fromSmartctlJson', () {
    test('extracts sector/error counts and life-left by id', () {
      final json = {
        'ata_smart_attributes': {
          'table': [
            {
              'id': 5,
              'name': 'Reallocated_Sector_Ct',
              'value': 100,
              'raw': {'value': 3, 'string': '3'},
            },
            {
              'id': 196,
              'name': 'Reallocated_Event_Count',
              'value': 100,
              'raw': {'value': 2, 'string': '2'},
            },
            {
              'id': 197,
              'name': 'Current_Pending_Sector',
              'value': 100,
              'raw': {'value': 1, 'string': '1'},
            },
            {
              'id': 198,
              'name': 'Offline_Uncorrectable',
              'value': 100,
              'raw': {'value': 0, 'string': '0'},
            },
            {
              'id': 231,
              'name': 'SSD_Life_Left',
              'value': 87,
              'raw': {'value': 87, 'string': '87'},
            },
          ],
        },
      };

      final extras = AtaSmartExtras.fromSmartctlJson(json);

      expect(extras.reallocatedSectorCount, 3);
      expect(extras.reallocatedEventCount, 2);
      expect(extras.currentPendingSectorCount, 1);
      expect(extras.offlineUncorrectableCount, 0);
      expect(extras.ssdLifeLeftPercent, 87);
    });

    test('falls back to name matching for vendor-specific wear attributes', () {
      final json = {
        'ata_smart_attributes': {
          'table': [
            {
              'id': 233,
              'name': 'Media_Wearout_Indicator',
              'value': 62,
              'raw': {'value': 62, 'string': '62'},
            },
          ],
        },
      };

      final extras = AtaSmartExtras.fromSmartctlJson(json);

      expect(extras.ssdLifeLeftPercent, 62);
    });

    test(
      'returns empty when ata_smart_attributes is absent (NVMe-only device)',
      () {
        final extras = AtaSmartExtras.fromSmartctlJson({
          'nvme_smart_health_information_log': {'percentage_used': 4},
        });

        expect(extras.reallocatedSectorCount, isNull);
        expect(extras.currentPendingSectorCount, isNull);
        expect(extras.ssdLifeLeftPercent, isNull);
      },
    );

    test('returns empty on malformed input rather than throwing', () {
      final extras = AtaSmartExtras.fromSmartctlJson({
        'ata_smart_attributes': {'table': 'not-a-list'},
      });

      expect(extras.reallocatedSectorCount, isNull);
    });
  });

  group('AtaSmartExtras.fromRawAttributeBlock', () {
    List<int> attributeRecord(int id, {int current = 100, int raw = 0}) {
      final bytes = List<int>.filled(12, 0);
      bytes[0] = id;
      bytes[3] = current;
      for (var i = 0; i < 6; i++) {
        bytes[5 + i] = (raw >> (8 * i)) & 0xFF;
      }
      return bytes;
    }

    List<int> block(List<List<int>> records) => [
      0, 0, // 2-byte header
      ...records.expand((r) => r),
    ];

    test('parses a well-formed block with a few attributes', () {
      final bytes = block([
        attributeRecord(5, raw: 3), // reallocated sectors
        attributeRecord(197, raw: 1), // pending sectors
        attributeRecord(231, current: 74), // life left
        attributeRecord(0), // end marker
      ]);

      final extras = AtaSmartExtras.fromRawAttributeBlock(bytes);

      expect(extras.reallocatedSectorCount, 3);
      expect(extras.currentPendingSectorCount, 1);
      expect(extras.ssdLifeLeftPercent, 74);
      expect(extras.offlineUncorrectableCount, isNull);
    });

    test('an all-zero block yields an empty result', () {
      final bytes = List<int>.filled(200, 0);

      final extras = AtaSmartExtras.fromRawAttributeBlock(bytes);

      expect(extras.reallocatedSectorCount, isNull);
      expect(extras.currentPendingSectorCount, isNull);
      expect(extras.ssdLifeLeftPercent, isNull);
    });

    test('a truncated block does not throw', () {
      final extras = AtaSmartExtras.fromRawAttributeBlock([1, 2, 3]);

      expect(extras.reallocatedSectorCount, isNull);
    });
  });
}
