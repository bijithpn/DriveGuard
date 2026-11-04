import 'package:driveguard/application/settings/app_settings.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:driveguard/domain/enums/ui_enums.dart';
import 'package:driveguard/infrastructure/tray/tray_icon_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading is split into number and unit letter', () {
    expect(trayNumberText('42°C'), '42');
    expect(trayUnitText('42°C'), 'C');
    expect(trayNumberText('108°F'), '108');
    expect(trayUnitText('108°F'), 'F');
    expect(trayNumberText('-5°C'), '-5');
    expect(trayNumberText('N/A'), isNull);
    expect(trayUnitText('N/A'), isNull);
    expect(trayNumberText(null), isNull);
  });

  test('every style × severity renders a real PNG', () async {
    for (final style in TrayIconStyle.values) {
      for (final sev in TemperatureSeverity.values) {
        final png = await renderTrayIconPng(
          TrayIconSpec(
            style: style,
            severity: sev,
            numberText: sev == TemperatureSeverity.unavailable ? null : '57',
            unit: 'C',
            fraction: 0.6,
          ),
        );
        expect(png.length, greaterThan(100), reason: '$style/$sev');
        expect(png.sublist(0, 4), [
          0x89,
          0x50,
          0x4E,
          0x47,
        ], reason: '$style/$sev');
      }
    }
  });

  test('templates are only used when no colour is needed', () {
    TrayIconSpec s(TrayIconStyle st, TemperatureSeverity sev) =>
        TrayIconSpec(style: st, severity: sev);
    // Calm states are monochrome → macOS can tint them.
    expect(
      s(TrayIconStyle.glyph, TemperatureSeverity.normal).needsColor,
      isFalse,
    );
    expect(
      s(TrayIconStyle.temperature, TemperatureSeverity.normal).needsColor,
      isFalse,
    );
    // Alerts and the status dot need real colour.
    expect(
      s(TrayIconStyle.glyph, TemperatureSeverity.critical).needsColor,
      isTrue,
    );
    expect(
      s(TrayIconStyle.ring, TemperatureSeverity.warning).needsColor,
      isTrue,
    );
    expect(s(TrayIconStyle.dot, TemperatureSeverity.normal).needsColor, isTrue);
    expect(
      s(TrayIconStyle.bars, TemperatureSeverity.normal).needsColor,
      isFalse,
    );
    expect(
      s(TrayIconStyle.bars, TemperatureSeverity.critical).needsColor,
      isTrue,
    );
  });

  test('cache keys differ when anything visible differs', () {
    const a = TrayIconSpec(
      style: TrayIconStyle.ring,
      severity: TemperatureSeverity.normal,
      numberText: '42',
      fraction: 0.4,
    );
    const b = TrayIconSpec(
      style: TrayIconStyle.ring,
      severity: TemperatureSeverity.normal,
      numberText: '43',
      fraction: 0.4,
    );
    const c = TrayIconSpec(
      style: TrayIconStyle.ring,
      severity: TemperatureSeverity.normal,
      numberText: '42',
      fraction: 0.4,
      darkBackground: false,
    );
    expect({a.cacheKey, b.cacheKey, c.cacheKey}, hasLength(3));
  });

  group('TraySettings', () {
    test('defaults are minimal: drive glyph, hottest, no extra text', () {
      const t = TraySettings();
      expect(t.style, TrayIconStyle.glyph);
      expect(t.metric, TrayMetric.hottest);
      expect(t.showText, isFalse);
      expect(t.menuDetail, TrayMenuDetail.compact);
    });

    test('round-trips through AppSettings JSON', () {
      const s = AppSettings(
        tray: TraySettings(
          style: TrayIconStyle.ring,
          metric: TrayMetric.average,
          showText: true,
          menuDetail: TrayMenuDetail.detailed,
        ),
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.tray, s.tray);
    });

    test('old settings files and unknown values fall back safely', () {
      expect(AppSettings.fromJson(const {}).tray, const TraySettings());
      final t = TraySettings.fromJson(const {'style': 'nope', 'metric': 'x'});
      expect(t.style, TrayIconStyle.glyph);
      expect(t.metric, TrayMetric.hottest);
    });
  });
}
