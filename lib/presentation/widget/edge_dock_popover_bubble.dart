import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/enums/ui_enums.dart';

/// High-performance speech-bubble popover container with a dynamic arrow beak
/// pointing toward the targeted dock item.
class EdgeDockPopoverBubble extends StatelessWidget {
  const EdgeDockPopoverBubble({
    super.key,
    required this.child,
    this.edge = ScreenEdge.left,
    this.targetArrowPosition = 60.0,
    this.backgroundColor = const Color(0xFF0A0A0C),
    this.borderColor = const Color(0xFF1E1E26),
    this.borderRadius = 16.0,
    this.arrowWidth = 8.0,
    this.arrowHeight = 14.0,
    this.borderWidth = 1.0,
    this.padding = const EdgeInsets.all(12.0),
    this.shadows = const [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 24.0,
        offset: Offset(0, 8),
      ),
    ],
  });

  final Widget child;
  final ScreenEdge edge;
  final double targetArrowPosition;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final double arrowWidth;
  final double arrowHeight;
  final double borderWidth;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadows;

  EdgeInsetsGeometry _effectivePadding() {
    EdgeInsets arrowOffset;
    switch (edge) {
      case ScreenEdge.left:
        arrowOffset = EdgeInsets.only(left: arrowWidth);
        break;
      case ScreenEdge.right:
        arrowOffset = EdgeInsets.only(right: arrowWidth);
        break;
      case ScreenEdge.top:
        arrowOffset = EdgeInsets.only(top: arrowWidth);
        break;
      case ScreenEdge.bottom:
        arrowOffset = EdgeInsets.only(bottom: arrowWidth);
        break;
    }
    return arrowOffset.add(padding);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: EdgeDockSpeechBubblePainter(
        edge: edge,
        targetArrowPosition: targetArrowPosition,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        borderRadius: borderRadius,
        arrowWidth: arrowWidth,
        arrowHeight: arrowHeight,
        borderWidth: borderWidth,
        shadows: shadows,
      ),
      child: Padding(
        padding: _effectivePadding(),
        child: child,
      ),
    );
  }
}

/// Vector canvas painter for rendering speech-bubble card geometry with
/// integrated arrow beak, shadows, background, and borders.
class EdgeDockSpeechBubblePainter extends CustomPainter {
  const EdgeDockSpeechBubblePainter({
    this.edge = ScreenEdge.left,
    this.targetArrowPosition = 60.0,
    this.backgroundColor = const Color(0xFF0A0A0C),
    this.borderColor = const Color(0xFF1E1E26),
    this.borderRadius = 16.0,
    this.arrowWidth = 8.0,
    this.arrowHeight = 14.0,
    this.borderWidth = 1.0,
    this.shadows = const [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 24.0,
        offset: Offset(0, 8),
      ),
    ],
  });

  final ScreenEdge edge;
  final double targetArrowPosition;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final double arrowWidth;
  final double arrowHeight;
  final double borderWidth;
  final List<BoxShadow>? shadows;

  /// Builds and returns the calculated [Path] for the given [size].
  Path computePath(Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return Path();

    final r = math.min(borderRadius, math.min(w, h) / 2);
    final halfArrow = arrowHeight / 2;
    final path = Path();

    switch (edge) {
      case ScreenEdge.left:
        // Dock is on left -> Bubble is on right -> Arrow points LEFT at x = 0
        final minCenter = r + halfArrow;
        final maxCenter = math.max(minCenter, h - r - halfArrow);
        final cy = targetArrowPosition.clamp(minCenter, maxCenter);

        path.moveTo(arrowWidth + r, 0);
        path.lineTo(w - r, 0);
        path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
        path.lineTo(w, h - r);
        path.arcToPoint(Offset(w - r, h), radius: Radius.circular(r));
        path.lineTo(arrowWidth + r, h);
        path.arcToPoint(Offset(arrowWidth, h - r), radius: Radius.circular(r));
        path.lineTo(arrowWidth, cy + halfArrow);
        path.lineTo(0, cy); // Beak tip pointing left
        path.lineTo(arrowWidth, cy - halfArrow);
        path.lineTo(arrowWidth, r);
        path.arcToPoint(Offset(arrowWidth + r, 0), radius: Radius.circular(r));
        path.close();
        break;

      case ScreenEdge.right:
        // Dock is on right -> Bubble is on left -> Arrow points RIGHT at x = w
        final minCenter = r + halfArrow;
        final maxCenter = math.max(minCenter, h - r - halfArrow);
        final cy = targetArrowPosition.clamp(minCenter, maxCenter);
        final bodyRight = w - arrowWidth;

        path.moveTo(r, 0);
        path.lineTo(bodyRight - r, 0);
        path.arcToPoint(Offset(bodyRight, r), radius: Radius.circular(r));
        path.lineTo(bodyRight, cy - halfArrow);
        path.lineTo(w, cy); // Beak tip pointing right
        path.lineTo(bodyRight, cy + halfArrow);
        path.lineTo(bodyRight, h - r);
        path.arcToPoint(Offset(bodyRight - r, h), radius: Radius.circular(r));
        path.lineTo(r, h);
        path.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));
        path.lineTo(0, r);
        path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
        path.close();
        break;

      case ScreenEdge.top:
        // Dock is on top -> Bubble is below -> Arrow points UP at y = 0
        final minCenter = r + halfArrow;
        final maxCenter = math.max(minCenter, w - r - halfArrow);
        final cx = targetArrowPosition.clamp(minCenter, maxCenter);

        path.moveTo(r, arrowWidth);
        path.lineTo(cx - halfArrow, arrowWidth);
        path.lineTo(cx, 0); // Beak tip pointing up
        path.lineTo(cx + halfArrow, arrowWidth);
        path.lineTo(w - r, arrowWidth);
        path.arcToPoint(Offset(w, arrowWidth + r), radius: Radius.circular(r));
        path.lineTo(w, h - r);
        path.arcToPoint(Offset(w - r, h), radius: Radius.circular(r));
        path.lineTo(r, h);
        path.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));
        path.lineTo(0, arrowWidth + r);
        path.arcToPoint(Offset(r, arrowWidth), radius: Radius.circular(r));
        path.close();
        break;

      case ScreenEdge.bottom:
        // Dock is on bottom -> Bubble is above -> Arrow points DOWN at y = h
        final minCenter = r + halfArrow;
        final maxCenter = math.max(minCenter, w - r - halfArrow);
        final cx = targetArrowPosition.clamp(minCenter, maxCenter);
        final bodyBottom = h - arrowWidth;

        path.moveTo(r, 0);
        path.lineTo(w - r, 0);
        path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
        path.lineTo(w, bodyBottom - r);
        path.arcToPoint(Offset(w - r, bodyBottom), radius: Radius.circular(r));
        path.lineTo(cx + halfArrow, bodyBottom);
        path.lineTo(cx, h); // Beak tip pointing down
        path.lineTo(cx - halfArrow, bodyBottom);
        path.lineTo(r, bodyBottom);
        path.arcToPoint(Offset(0, bodyBottom - r), radius: Radius.circular(r));
        path.lineTo(0, r);
        path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
        path.close();
        break;
    }

    return path;
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
  bool shouldRepaint(covariant EdgeDockSpeechBubblePainter oldDelegate) {
    return oldDelegate.edge != edge ||
        oldDelegate.targetArrowPosition != targetArrowPosition ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.arrowWidth != arrowWidth ||
        oldDelegate.arrowHeight != arrowHeight ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.shadows != shadows;
  }
}
