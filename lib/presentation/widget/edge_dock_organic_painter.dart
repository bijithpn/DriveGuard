import 'dart:math' as math;
import 'dart:ui' as ui;
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
    this.glass = false,
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

  /// Adds a soft diagonal light sheen over the fill (frosted-glass look).
  final bool glass;

  /// Builds and returns the calculated [Path] for the given [size].
  Path computePath(Size size) {
    return _transformPathForEdge(_computeCanonicalFillPath(), size);
  }

  /// A clean pill flush to the screen edge (canonical orientation: docked to
  /// the left, growing to the right): square where it meets the screen edge,
  /// fully rounded on the free side. Same overall length as before, so all
  /// window geometry stays valid; the old concave "ears" and pinched neck
  /// toward the settings pod are gone.
  Path _computeCanonicalStrokePath() {
    final clamped = expansionProgress.clamp(0.0, 1.0);
    final d = collapsedDepth + (dockDepth - collapsedDepth) * clamped;
    final r = math.min(filletRadius, d / 2);
    final yTotal =
        filletRadius +
        mainRailLength +
        (showPod ? podSpacing + podDiameter : 0) +
        filletRadius;

    return Path()
      ..moveTo(0, 0)
      ..lineTo(d - r, 0)
      ..arcToPoint(Offset(d, r), radius: Radius.circular(r))
      ..lineTo(d, yTotal - r)
      ..arcToPoint(Offset(d - r, yTotal), radius: Radius.circular(r))
      ..lineTo(0, yTotal);
  }

  Path _computeCanonicalFillPath() {
    final path = _computeCanonicalStrokePath();
    path.lineTo(0, 0);
    path.close();
    return path;
  }

  Path _transformPathForEdge(Path canonicalPath, Size size) {
    switch (edge) {
      case ScreenEdge.left:
        return canonicalPath;
      case ScreenEdge.right:
        final matrix = Matrix4(
          -1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          size.width,
          0,
          0,
          1,
        );
        return canonicalPath.transform(matrix.storage);
      case ScreenEdge.top:
        final matrix = Matrix4(0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        return canonicalPath.transform(matrix.storage);
      case ScreenEdge.bottom:
        final matrix = Matrix4(
          0,
          -1,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          size.height,
          0,
          1,
        );
        return canonicalPath.transform(matrix.storage);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final fillPath = _transformPathForEdge(_computeCanonicalFillPath(), size);
    final strokePath = _transformPathForEdge(
      _computeCanonicalStrokePath(),
      size,
    );

    // 1. Drop shadows
    if (shadows != null && shadows!.isNotEmpty) {
      for (final shadow in shadows!) {
        final shadowPaint = shadow.toPaint();
        final shadowPath = fillPath.shift(shadow.offset);
        canvas.drawPath(shadowPath, shadowPaint);
      }
    }

    // 2. Solid / translucent background fill
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, bgPaint);

    if (glass) {
      canvas.save();
      canvas.clipPath(fillPath);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width, size.height),
            const [Color(0x2EFFFFFF), Color(0x08FFFFFF), Color(0x12FFFFFF)],
            const [0.0, 0.55, 1.0],
          ),
      );
      canvas.restore();
    }

    // 3. Crisp outline border on curved screen-facing contours only
    if (borderWidth > 0 && borderColor.a > 0) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(strokePath, borderPaint);
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
        oldDelegate.glass != glass ||
        oldDelegate.shadows != shadows;
  }
}
