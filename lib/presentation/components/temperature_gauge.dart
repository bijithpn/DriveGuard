import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

class TemperatureGauge extends StatefulWidget {
  const TemperatureGauge({
    super.key,
    required this.valueText,
    required this.fraction,
    required this.severity,
    this.size = 140,
    this.showLabel = true,
    this.labelText,
  });

  final String valueText;

  final double fraction;
  final TemperatureSeverity severity;
  final double size;
  final bool showLabel;
  final String? labelText;

  @override
  State<TemperatureGauge> createState() => _TemperatureGaugeState();
}

class _TemperatureGaugeState extends State<TemperatureGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _valueController;
  late Animation<double> _valueAnimation;
  double _previousFraction = 0;

  @override
  void initState() {
    super.initState();
    _valueController = AnimationController(
      vsync: this,
      duration: AppDurations.slow,
    );
    _valueAnimation = AlwaysStoppedAnimation(widget.fraction);
    _previousFraction = widget.fraction;
  }

  @override
  void didUpdateWidget(covariant TemperatureGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fraction != widget.fraction) {
      _valueAnimation =
          Tween<double>(begin: _previousFraction, end: widget.fraction).animate(
            CurvedAnimation(
              parent: _valueController,
              curve: Curves.easeOutCubic,
            ),
          );
      _previousFraction = widget.fraction;
      _valueController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(widget.severity, context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _valueAnimation,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: _valueAnimation.value,
              color: style.color,
              trackColor: isDark ? AppColors.bg3 : AppColors.lightSurfaceMuted,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.valueText,
                    textAlign: TextAlign.center,
                    semanticsLabel: '${style.label}: ${widget.valueText}',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightText,
                      fontSize: widget.size * 0.155,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(height: 1),
                    Text(
                      widget.labelText ?? style.label,
                      style: TextStyle(
                        color: style.color,
                        fontSize: widget.size * 0.09,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  static const _startAngle = -pi / 2 - pi * 0.75;
  static const _sweepTotal = pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final strokeWidth = size.width * 0.06;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal,
      false,
      trackPaint,
    );

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal * clamped,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
