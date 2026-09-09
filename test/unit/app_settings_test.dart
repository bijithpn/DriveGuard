import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgeDockSettings', () {
    test('defaults to disabled, docked right, auto accent, full opacity', () {
      const settings = EdgeDockSettings();
      expect(settings.enabled, isFalse);
      expect(settings.edge, ScreenEdge.right);
      expect(settings.accent, EdgeDockAccent.auto);
      expect(settings.opacity, 1.0);
    });

    test('copyWith updates only the given fields', () {
      const settings = EdgeDockSettings();
      final updated = settings.copyWith(
        enabled: true,
        edge: ScreenEdge.left,
        accent: EdgeDockAccent.purple,
        opacity: 0.8,
      );
      expect(updated.enabled, isTrue);
      expect(updated.edge, ScreenEdge.left);
      expect(updated.accent, EdgeDockAccent.purple);
      expect(updated.opacity, 0.8);
    });

    test('round-trips through JSON', () {
      const settings = EdgeDockSettings(
        enabled: true,
        edge: ScreenEdge.top,
        accent: EdgeDockAccent.teal,
        opacity: 0.75,
      );
      final restored = EdgeDockSettings.fromJson(settings.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.edge, ScreenEdge.top);
      expect(restored.accent, EdgeDockAccent.teal);
      expect(restored.opacity, 0.75);
    });

    test('falls back to defaults on malformed JSON', () {
      final restored = EdgeDockSettings.fromJson({
        'edge': 'not-a-real-edge',
        'accent': 'not-a-real-accent',
      });
      expect(restored.enabled, isFalse);
      expect(restored.edge, ScreenEdge.right);
      expect(restored.accent, EdgeDockAccent.auto);
    });

    test('defaults to primary display and default colors, all metrics on', () {
      const settings = EdgeDockSettings();
      expect(settings.displayId, isNull);
      expect(settings.backgroundColor, isNull);
      expect(settings.textColor, isNull);
      expect(settings.warningColor, isNull);
      expect(settings.criticalColor, isNull);
      expect(settings.visibleMetrics, kAllEdgeDockMetrics);
    });

    test('copyWith sets displayId and colors', () {
      const settings = EdgeDockSettings();
      final updated = settings.copyWith(
        displayId: 'DISPLAY-2',
        backgroundColor: 0xFF000000,
        textColor: 0xFFFFFFFF,
        warningColor: 0xFFFFC107,
        criticalColor: 0xFFE53935,
        visibleMetrics: {EdgeDockMetric.health},
      );
      expect(updated.displayId, 'DISPLAY-2');
      expect(updated.backgroundColor, 0xFF000000);
      expect(updated.textColor, 0xFFFFFFFF);
      expect(updated.warningColor, 0xFFFFC107);
      expect(updated.criticalColor, 0xFFE53935);
      expect(updated.visibleMetrics, {EdgeDockMetric.health});
    });

    test('copyWith clear* flags reset a field back to null', () {
      const settings = EdgeDockSettings(
        displayId: 'DISPLAY-2',
        backgroundColor: 0xFF000000,
      );
      final cleared = settings.copyWith(
        clearDisplayId: true,
        clearBackgroundColor: true,
      );
      expect(cleared.displayId, isNull);
      expect(cleared.backgroundColor, isNull);
    });

    test('round-trips displayId/colors/visibleMetrics through JSON', () {
      const settings = EdgeDockSettings(
        displayId: 'DISPLAY-2',
        backgroundColor: 0xFF000000,
        textColor: 0xFFFFFFFF,
        warningColor: 0xFFFFC107,
        criticalColor: 0xFFE53935,
        visibleMetrics: {EdgeDockMetric.health, EdgeDockMetric.smart},
      );
      final restored = EdgeDockSettings.fromJson(settings.toJson());
      expect(restored.displayId, 'DISPLAY-2');
      expect(restored.backgroundColor, 0xFF000000);
      expect(restored.textColor, 0xFFFFFFFF);
      expect(restored.warningColor, 0xFFFFC107);
      expect(restored.criticalColor, 0xFFE53935);
      expect(restored.visibleMetrics, {
        EdgeDockMetric.health,
        EdgeDockMetric.smart,
      });
    });

    test('malformed visibleMetrics JSON falls back to all metrics', () {
      final restored = EdgeDockSettings.fromJson({'visibleMetrics': null});
      expect(restored.visibleMetrics, kAllEdgeDockMetrics);
    });

    test('positionOffset defaults to 0 (centered)', () {
      const settings = EdgeDockSettings();
      expect(settings.positionOffset, 0);
    });

    test('copyWith updates positionOffset', () {
      const settings = EdgeDockSettings();
      final updated = settings.copyWith(positionOffset: 42.5);
      expect(updated.positionOffset, 42.5);
    });

    test('positionOffset round-trips through JSON', () {
      const settings = EdgeDockSettings(positionOffset: -75);
      final restored = EdgeDockSettings.fromJson(settings.toJson());
      expect(restored.positionOffset, -75);
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
