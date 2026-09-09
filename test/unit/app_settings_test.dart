import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgeDockSettings', () {
    test('defaults to disabled, docked right', () {
      const settings = EdgeDockSettings();
      expect(settings.enabled, isFalse);
      expect(settings.edge, ScreenEdge.right);
    });

    test('copyWith updates only the given fields', () {
      const settings = EdgeDockSettings();
      final updated = settings.copyWith(enabled: true, edge: ScreenEdge.left);
      expect(updated.enabled, isTrue);
      expect(updated.edge, ScreenEdge.left);
    });

    test('round-trips through JSON', () {
      const settings = EdgeDockSettings(enabled: true, edge: ScreenEdge.top);
      final restored = EdgeDockSettings.fromJson(settings.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.edge, ScreenEdge.top);
    });

    test('falls back to defaults on malformed JSON', () {
      final restored = EdgeDockSettings.fromJson({'edge': 'not-a-real-edge'});
      expect(restored.enabled, isFalse);
      expect(restored.edge, ScreenEdge.right);
    });
  });

  group('AppSettings', () {
    test('defaults edgeDock to disabled', () {
      const settings = AppSettings();
      expect(settings.edgeDock.enabled, isFalse);
    });

    test('round-trips edgeDock through JSON', () {
      const settings = AppSettings(
        edgeDock: EdgeDockSettings(enabled: true, edge: ScreenEdge.bottom),
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.edgeDock.enabled, isTrue);
      expect(restored.edgeDock.edge, ScreenEdge.bottom);
    });

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
