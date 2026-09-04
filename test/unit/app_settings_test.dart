import 'package:driveguard/application/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings', () {
    test('defaults showTrayIcon to true', () {
      const settings = AppSettings();
      expect(settings.showTrayIcon, isTrue);
    });

    test('copyWith updates showTrayIcon', () {
      const settings = AppSettings();
      final updated = settings.copyWith(showTrayIcon: false);
      expect(updated.showTrayIcon, isFalse);
    });

    test('round-trips showTrayIcon through JSON', () {
      const settings = AppSettings(showTrayIcon: false);
      final json = settings.toJson();
      expect(json['showTrayIcon'], isFalse);

      final restored = AppSettings.fromJson(json);
      expect(restored.showTrayIcon, isFalse);
    });
  });
}
