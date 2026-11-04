import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../application/monitoring/metric_history_store.dart';
import '../../theme/app_theme.dart';

/// Minimal area sparkline of drive usage over time.
class TrendSparkline extends StatelessWidget {
  const TrendSparkline({
    super.key,
    required this.points,
    this.color = AppColors.accent,
    this.height = 56,
  });

  final List<MetricPoint> points;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SparkPainter(points, color)),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color);
  final List<MetricPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final t0 = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final span = points.last.timestamp.millisecondsSinceEpoch - t0;
    if (span <= 0) return;
    var lo = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    var hi = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.5) {
      final mid = (hi + lo) / 2;
      lo = mid - 0.5;
      hi = mid + 0.5;
    }
    const pad = 4.0;
    Offset at(MetricPoint p) => Offset(
      (p.timestamp.millisecondsSinceEpoch - t0) / span * size.width,
      pad + (1 - (p.value - lo) / (hi - lo)) * (size.height - pad * 2),
    );

    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(points[i - 1]);
      final b = at(points[i]);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(at(points.last), 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points.length != points.length || old.color != color;
}
