import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';

/// Everything needed to draw one tray icon.
class TrayIconSpec {
  const TrayIconSpec({
    required this.style,
    required this.severity,
    this.numberText,
    this.unit,
    this.fraction = 0,
    this.darkBackground = true,
    this.template = false,
  });

  final TrayIconStyle style;
  final TemperatureSeverity severity;

  /// Digits only, e.g. "42". Null when no reading is available.
  final String? numberText;

  /// "C" or "F" — drawn as "°C" / "°F" next to the number.
  final String? unit;

  /// 0..1 fill for the ring and bars styles.
  final double fraction;

  /// Whether the surface behind the icon is dark (picks white vs near-black
  /// for the neutral colour). Ignored when [template] is true.
  final bool darkBackground;

  /// macOS template image: drawn in black and tinted by the system.
  final bool template;

  /// Template images can't be coloured, so any style/severity that needs
  /// colour is never a template.
  bool get needsColor =>
      style == TrayIconStyle.dot ||
      severity == TemperatureSeverity.warning ||
      severity == TemperatureSeverity.critical;

  String get cacheKey =>
      '${style.name}_${severity.name}_${numberText ?? 'x'}_${unit ?? 'x'}_'
      '${(fraction * 20).round()}_${darkBackground ? 'd' : 'l'}_'
      '${template ? 't' : 'c'}';
}

final _reading = RegExp(r'^(-?\d+(?:\.\d+)?)\s*°\s*([CF])?');

/// "42°C" → "42", "108°F" → "108", anything else → null.
String? trayNumberText(String? valueText) {
  if (valueText == null) return null;
  return _reading.firstMatch(valueText)?.group(1);
}

/// "42°C" → "C", "108°F" → "F".
String? trayUnitText(String? valueText) {
  if (valueText == null) return null;
  return _reading.firstMatch(valueText)?.group(2);
}

const _normal = ui.Color(0xFF34C759);
const _warning = ui.Color(0xFFFFB020);
const _critical = ui.Color(0xFFFF453A);

ui.Color _severityColor(TemperatureSeverity s, ui.Color neutral) {
  switch (s) {
    case TemperatureSeverity.warning:
      return _warning;
    case TemperatureSeverity.critical:
      return _critical;
    case TemperatureSeverity.unavailable:
      return neutral.withValues(alpha: 0.5);
    case TemperatureSeverity.normal:
    case TemperatureSeverity.warm:
      return neutral;
  }
}

/// Draws [spec] into a [size]×[size] square. Shapes are bold and simple so
/// they stay legible at 16–22 px.
void paintTrayIcon(ui.Canvas canvas, double size, TrayIconSpec spec) {
  final u = size / 64.0; // design grid is 64
  final neutral = spec.template
      ? const ui.Color(0xFF000000)
      : (spec.darkBackground
            ? const ui.Color(0xFFFFFFFF)
            : const ui.Color(0xFF1B1F24));
  final accent = _severityColor(spec.severity, neutral);

  switch (spec.style) {
    case TrayIconStyle.glyph:
      _drawDrive(canvas, u, accent);
    case TrayIconStyle.dot:
      _drawDot(canvas, size, spec);
    case TrayIconStyle.temperature:
      _drawReading(
        canvas,
        size,
        spec.numberText,
        spec.unit == null ? null : '°${spec.unit}',
        accent,
      );
    case TrayIconStyle.ring:
      _drawRing(canvas, size, u, spec, neutral, accent);
    case TrayIconStyle.bars:
      _drawBars(canvas, u, spec, neutral, accent);
  }
}

void _drawDrive(ui.Canvas canvas, double u, ui.Color color) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(7 * u, 15 * u, 50 * u, 34 * u),
      ui.Radius.circular(10 * u),
    ),
    ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 6 * u
      ..isAntiAlias = true,
  );
  final fill = ui.Paint()
    ..color = color
    ..isAntiAlias = true;
  canvas.drawCircle(ui.Offset(45 * u, 38 * u), 4.2 * u, fill);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(17 * u, 35 * u, 16 * u, 6 * u),
      ui.Radius.circular(3 * u),
    ),
    fill,
  );
}

void _drawDot(ui.Canvas canvas, double size, TrayIconSpec spec) {
  final color = switch (spec.severity) {
    TemperatureSeverity.warning => _warning,
    TemperatureSeverity.critical => _critical,
    TemperatureSeverity.unavailable => const ui.Color(0xFF8E8E93),
    _ => _normal,
  };
  final c = ui.Offset(size / 2, size / 2);
  // Soft halo + solid core: reads as a status light on any background.
  canvas.drawCircle(
    c,
    size * 0.42,
    ui.Paint()..color = color.withValues(alpha: 0.28),
  );
  canvas.drawCircle(
    c,
    size * 0.27,
    ui.Paint()
      ..color = color
      ..isAntiAlias = true,
  );
}

void _drawBars(
  ui.Canvas canvas,
  double u,
  TrayIconSpec spec,
  ui.Color neutral,
  ui.Color accent,
) {
  final f = spec.fraction;
  final lit = spec.severity == TemperatureSeverity.unavailable
      ? 0
      : (f < 0.45 ? 1 : (f < 0.8 ? 2 : 3));
  const heights = [22.0, 36.0, 50.0];
  for (var i = 0; i < 3; i++) {
    final h = heights[i] * u;
    final x = (10 + i * 18) * u;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, 57 * u - h, 12 * u, h),
        ui.Radius.circular(4 * u),
      ),
      ui.Paint()
        ..color = i < lit ? accent : neutral.withValues(alpha: 0.28)
        ..isAntiAlias = true,
    );
  }
}

ui.Paragraph _para(
  String text,
  double fontSize,
  ui.Color color,
  ui.FontWeight w,
) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
    ..pushStyle(
      ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: w,
        fontFamily: 'Manrope',
        letterSpacing: -fontSize * 0.03,
      ),
    )
    ..addText(text);
  return b.build()..layout(const ui.ParagraphConstraints(width: 400));
}

/// Number plus a small unit ("42" + "°C") centred as one unit. The unit is
/// part of the picture, so the OS never needs to draw any text.
void _drawReading(
  ui.Canvas canvas,
  double size,
  String? number,
  String? unit,
  ui.Color color,
) {
  final text = (number == null || number.isEmpty) ? '–' : number;
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length.clamp(1, 4);
  // Leave room for the unit on the right.
  final hasUnit = unit != null && unit.isNotEmpty;
  var numSize = size * (digits <= 2 ? 0.52 : (digits == 3 ? 0.42 : 0.34));
  if (!hasUnit) numSize *= 1.1;
  final unitSize = numSize * 0.62;

  final num = _para(text, numSize, color, ui.FontWeight.w800);
  final un = hasUnit ? _para(unit, unitSize, color, ui.FontWeight.w700) : null;

  final gap = size * 0.015;
  var total = num.longestLine + (un == null ? 0 : un.longestLine + gap);
  // Shrink to fit if the combined width is too wide.
  var k = 1.0;
  if (total > size * 0.98) k = size * 0.98 / total;
  total *= k;

  canvas.save();
  canvas.translate((size - total) / 2, size / 2);
  canvas.scale(k);
  canvas.drawParagraph(num, ui.Offset(0, -num.height / 2));
  if (un != null) {
    // Unit sits at the top of the number like a superscript.
    canvas.drawParagraph(
      un,
      ui.Offset(num.longestLine + gap, -num.height / 2 + numSize * 0.12),
    );
  }
  canvas.restore();
}

void _drawRing(
  ui.Canvas canvas,
  double size,
  double u,
  TrayIconSpec spec,
  ui.Color neutral,
  ui.Color accent,
) {
  final stroke = 7 * u;
  final rect = ui.Rect.fromLTWH(
    stroke / 2 + 3 * u,
    stroke / 2 + 3 * u,
    size - stroke - 6 * u,
    size - stroke - 6 * u,
  );
  canvas.drawArc(
    rect,
    0,
    math.pi * 2,
    false,
    ui.Paint()
      ..color = neutral.withValues(alpha: 0.28)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true,
  );
  final f = spec.fraction.clamp(0.04, 1.0);
  canvas.drawArc(
    rect,
    -math.pi / 2,
    math.pi * 2 * f,
    false,
    ui.Paint()
      ..color = accent
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = ui.StrokeCap.round
      ..isAntiAlias = true,
  );
  // Number inside, with a degree mark (no room for the letter in a ring).
  canvas.save();
  canvas.scale(0.58);
  canvas.translate(size * 0.36, size * 0.36);
  _drawReading(canvas, size, spec.numberText, '°', neutral);
  canvas.restore();
}

/// Renders [spec] to PNG bytes.
Future<List<int>> renderTrayIconPng(TrayIconSpec spec, {int size = 64}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintTrayIcon(canvas, size.toDouble(), spec);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
