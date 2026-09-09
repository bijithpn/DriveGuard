import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/enums/ui_enums.dart';

/// High-performance vector canvas painter for rendering the continuous organic
/// Bezier curve dock shape anchored flush to the screen edge.
///
/// Features:
/// - Smooth concave top fillet blending from the screen edge into the rail body.
/// - Straight/convex rail body housing the metric circular gauges.
/// - Fluid concave bridge narrowing down into the bottom circular action pod.
/// - Smooth concave bottom fillet returning flush to the screen edge.
/// - Symmetrical matrix transformations for Left, Right, Top, and Bottom screen edges.
/// - Multi-layer shadow, background fill, and outline stroke rendering.
class EdgeDockOrganicPainter extends CustomPainter {
  const EdgeDockOrganicPainter({
    this.edge = ScreenEdge.left,
    this.backgroundColor = const Color(0xFF0A0A0C),
    this.borderColor = const Color(0xFF1E1E26),
    this.borderWidth = 1.0,
    this.mainRailLength = 200.0,
    this.podDiameter = 36.0,
    this.podSpacing = 12.0,
    this.expansionProgress = 1.0,
    this.showPod = true,
    this.filletRadius = 18.0,
    this.dockDepth = 52.0,
    this.collapsedDepth = 8.0,
    this.shadows = const [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 16.0,
        offset: Offset(0, 4),
      ),
    ],
  });

  final ScreenEdge edge;
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double mainRailLength;
  final double podDiameter;
  final double podSpacing;
  final double expansionProgress;
  final bool showPod;
  final double filletRadius;
  final double dockDepth;
  final double collapsedDepth;
  final List<BoxShadow>? shadows;

  /// Builds and returns the calculated [Path] for the given [size].
  Path computePath(Size size) {
    final clamped = expansionProgress.clamp(0.0, 1.0);
    final d = collapsedDepth + (dockDepth - collapsedDepth) * clamped;
    final rTop = math.min(filletRadius, 24.0);
    final rBottom = math.min(filletRadius, 24.0);

    final path = Path();
    // Start at top anchor on screen edge
    path.moveTo(0, 0);

    // 1. Top concave fillet S-curve from (0,0) to (d, rTop)
    path.cubicTo(
      0,
      rTop * 0.55,
      d * 0.45,
      rTop,
      d,
      rTop,
    );

    // 2. Main rail body
    final yRailEnd = rTop + mainRailLength;
    path.lineTo(d, yRailEnd);

    double yBottomStart;
    double dLast;

    if (showPod) {
      final yPodTop = yRailEnd + podSpacing;
      final yNeck = yRailEnd + podSpacing / 2;
      final dNeck = math.max(collapsedDepth, d * 0.78);
      final dPod = math.min(d, podDiameter > 0 ? podDiameter : d);

      // Concave bridge from rail to pod neck
      path.cubicTo(
        d,
        yRailEnd + podSpacing * 0.25,
        dNeck,
        yNeck - podSpacing * 0.25,
        dNeck,
        yNeck,
      );

      // Concave bridge expanding to pod top
      final podCurveOffset = podDiameter * 0.15;
      path.cubicTo(
        dNeck,
        yNeck + podSpacing * 0.25,
        dPod,
        yPodTop,
        dPod,
        yPodTop + podCurveOffset,
      );

      // Pod outer curve apex
      final yPodCenter = yPodTop + podDiameter / 2;
      final yPodBottom = yPodTop + podDiameter;
      path.cubicTo(
        dPod,
        yPodCenter - podDiameter * 0.2,
        dPod,
        yPodCenter + podDiameter * 0.2,
        dPod,
        yPodBottom - podCurveOffset,
      );

      path.cubicTo(
        dPod,
        yPodBottom - podCurveOffset * 0.5,
        dPod,
        yPodBottom,
        dPod,
        yPodBottom,
      );

      yBottomStart = yPodBottom;
      dLast = dPod;
    } else {
      yBottomStart = yRailEnd;
      dLast = d;
    }

    // 3. Bottom concave fillet S-curve from (dLast, yBottomStart) to (0, yTotal)
    final yTotal = yBottomStart + rBottom;
    path.cubicTo(
      dLast * 0.45,
      yBottomStart,
      0,
      yTotal - rBottom * 0.55,
      0,
      yTotal,
    );

    // 4. Close path flush along the screen edge
    path.lineTo(0, 0);
    path.close();

    return _transformPathForEdge(path, size);
  }

  Path _transformPathForEdge(Path canonicalPath, Size size) {
    switch (edge) {
      case ScreenEdge.left:
        return canonicalPath;
      case ScreenEdge.right:
        final matrix = Matrix4(
          -1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          size.width, 0, 0, 1,
        );
        return canonicalPath.transform(matrix.storage);
      case ScreenEdge.top:
        final matrix = Matrix4(
          0, 1, 0, 0,
          1, 0, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        );
        return canonicalPath.transform(matrix.storage);
      case ScreenEdge.bottom:
        final matrix = Matrix4(
          0, -1, 0, 0,
          1, 0, 0, 0,
          0, 0, 1, 0,
          0, size.height, 0, 1,
        );
        return canonicalPath.transform(matrix.storage);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final path = computePath(size);

    // 1. Drop shadows
    if (shadows != null && shadows!.isNotEmpty) {
      for (final shadow in shadows!) {
        final shadowPaint = shadow.toPaint();
        final shadowPath = path.shift(shadow.offset);
        canvas.drawPath(shadowPath, shadowPaint);
      }
    }

    // 2. Solid / translucent background fill
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bgPaint);

    // 3. Crisp outline border
    if (borderWidth > 0 && borderColor.a > 0) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EdgeDockOrganicPainter oldDelegate) {
    return oldDelegate.edge != edge ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.mainRailLength != mainRailLength ||
        oldDelegate.podDiameter != podDiameter ||
        oldDelegate.podSpacing != podSpacing ||
        oldDelegate.expansionProgress != expansionProgress ||
        oldDelegate.showPod != showPod ||
        oldDelegate.filletRadius != filletRadius ||
        oldDelegate.dockDepth != dockDepth ||
        oldDelegate.collapsedDepth != collapsedDepth ||
        oldDelegate.shadows != shadows;
  }
}
