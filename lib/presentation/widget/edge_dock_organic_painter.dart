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
    this.endMargin,
    this.sweepLength,
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

  /// Reserved length at each end of the rail that the body does not cover.
  /// Defaults to [filletRadius].
  final double? endMargin;

  /// Length of the concave end sweep along the edge (defaults to
  /// [filletRadius], i.e. a circular quarter). Longer = more gradual.
  final double? sweepLength;
  final double dockDepth;
  final double collapsedDepth;
  final List<BoxShadow>? shadows;

  /// Adds a soft diagonal light sheen over the fill (frosted-glass look).
  final bool glass;

  /// Builds and returns the calculated [Path] for the given [size].
  Path computePath(Size size) {
    return _transformPathForEdge(
      _computeCanonicalFillPath(_alongLength(size)),
      size,
    );
  }

  /// The rail silhouette in canonical orientation (docked to the left edge,
  /// growing to the right): the screen edge sweeps into the body through a
  /// smooth concave quarter-circle at both ends, and the free side is a
  /// wide, fully rounded face. Everything is built from circular arcs that
  /// meet tangentially, so there are no kinks or pinched "necks".
  ///
  /// The body occupies y in [filletRadius, total - filletRadius]; the
  /// concave sweeps live in the reserved filletRadius margins above/below
  /// it, so ring positions never depend on the animation state.
  double _alongLength(Size size) =>
      (edge == ScreenEdge.left || edge == ScreenEdge.right)
      ? size.height
      : size.width;

  Path _computeCanonicalStrokePath(double length) {
    final clamped = expansionProgress.clamp(0.0, 1.0);
    final d = collapsedDepth + (dockDepth - collapsedDepth) * clamped;
    final f = math.min(filletRadius, d * 0.45); // concave sweep radius
    final rc = math.max(0.0, math.min(26.0, d - f)); // convex face radius
    final margin = endMargin ?? filletRadius;
    final yTop = margin;
    final yb = length - margin; // body bottom
    // The sweep shrinks in proportion while the rail is collapsed.
    final sweepScale = filletRadius == 0 ? 1.0 : f / filletRadius;
    final l = math.min((sweepLength ?? filletRadius) * sweepScale, margin);
    // Cubic "continuous curvature" blend: handles 64% of the leg length
    // (a circle would use ~45%), which flattens the ends of the curve into
    // the edge and the body for a softer, more gradual transition.
    const k = 0.64;

    return Path()
      ..moveTo(0, yTop - l)
      ..cubicTo(0, yTop - l * (1 - k), f * (1 - k), yTop, f, yTop)
      ..lineTo(d - rc, yTop)
      ..arcToPoint(Offset(d, yTop + rc), radius: Radius.circular(rc))
      ..lineTo(d, yb - rc)
      ..arcToPoint(Offset(d - rc, yb), radius: Radius.circular(rc))
      ..lineTo(f, yb)
      ..cubicTo(f * (1 - k), yb, 0, yb + l * (1 - k), 0, yb + l);
  }

  Path _computeCanonicalFillPath(double length) {
    final path = _computeCanonicalStrokePath(length);
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
    final length = _alongLength(size);
    final fillPath = _transformPathForEdge(
      _computeCanonicalFillPath(length),
      size,
    );
    final strokePath = _transformPathForEdge(
      _computeCanonicalStrokePath(length),
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
        oldDelegate.endMargin != endMargin ||
        oldDelegate.sweepLength != sweepLength ||
        oldDelegate.dockDepth != dockDepth ||
        oldDelegate.collapsedDepth != collapsedDepth ||
        oldDelegate.glass != glass ||
        oldDelegate.shadows != shadows;
  }
}
