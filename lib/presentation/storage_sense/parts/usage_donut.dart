import 'dart:math' as math;

import 'package:flutter/material.dart';

class DonutSegment {
  const DonutSegment(this.value, this.color);
  final double value;
  final Color color;
}

/// Ring chart with rounded, gapped segments that animates when values change.
class UsageDonut extends StatelessWidget {
  const UsageDonut({
    super.key,
    required this.segments,
    required this.trackColor,
    required this.child,
    this.size = 190,
    this.thickness = 18,
  });

  final List<DonutSegment> segments;
  final Color trackColor;
  final Widget child;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      key: ValueKey(segments.map((s) => s.value.round()).join(',')),
      builder: (context, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(segments, trackColor, thickness, t),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.track, this.thickness, this.t);

  final List<DonutSegment> segments;
  final Color track;
  final double thickness;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(thickness / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    final gap = segments.where((s) => s.value > 0).length > 1 ? 0.045 : 0.0;
    var start = -math.pi / 2;
    for (final s in segments) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * math.pi * 2 * t;
      final drawn = math.max(0.0, sweep - gap);
      if (drawn > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..color = s.color;
        // Shrink by the cap radius so rounded ends don't overlap neighbours.
        final capAngle = (thickness / 2) / (arcRect.width / 2);
        final a = math.max(0.0, drawn - capAngle * 2);
        canvas.drawArc(
          arcRect,
          start + gap / 2 + capAngle,
          a < 0.001 ? 0.001 : a,
          false,
          paint,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.t != t || old.segments != segments || old.track != track;
}
