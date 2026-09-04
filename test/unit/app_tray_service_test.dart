import 'dart:typed_data';

import 'package:driveguard/infrastructure/tray/app_tray_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTrayService.wrapPngInIco', () {
    test('wraps PNG payload in valid 22-byte ICO container header', () {
      final fakePng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk header
      ]);

      final ico = AppTrayService.wrapPngInIco(fakePng, 64, 64);

      // Header is 22 bytes + png length
      expect(ico.length, equals(22 + fakePng.length));

      final bd = ByteData.sublistView(ico);

      // ICONDIR (6 bytes)
      expect(bd.getUint16(0, Endian.little), equals(0)); // Reserved = 0
      expect(bd.getUint16(2, Endian.little), equals(1)); // Type = 1 (ICO)
      expect(bd.getUint16(4, Endian.little), equals(1)); // Count = 1

      // ICONDIRENTRY (16 bytes)
      expect(bd.getUint8(6), equals(64)); // Width = 64
      expect(bd.getUint8(7), equals(64)); // Height = 64
      expect(bd.getUint8(8), equals(0));  // ColorCount = 0
      expect(bd.getUint8(9), equals(0));  // Reserved = 0
      expect(bd.getUint16(10, Endian.little), equals(1));  // Planes = 1
      expect(bd.getUint16(12, Endian.little), equals(32)); // BitCount = 32
      expect(bd.getUint32(14, Endian.little), equals(fakePng.length)); // BytesInRes
      expect(bd.getUint32(18, Endian.little), equals(22)); // ImageOffset = 22

      // Payload verification
      expect(ico.sublist(22), equals(fakePng));
    });

    test('handles 256px dimensions encoded as 0 per ICO spec', () {
      final fakePng = Uint8List.fromList([1, 2, 3, 4]);
      final ico = AppTrayService.wrapPngInIco(fakePng, 256, 256);
      final bd = ByteData.sublistView(ico);

      expect(bd.getUint8(6), equals(0)); // 256 encoded as 0
      expect(bd.getUint8(7), equals(0)); // 256 encoded as 0
    });
  });
}
