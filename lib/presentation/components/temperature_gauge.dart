import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

/// Premium animated circular temperature gauge with gradient arc,
/// glow effects, pulse on warning/critical, and smooth value tweening.
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

  /// Pre-formatted value, e.g. "48°C" or "Unavailable".
  final String valueText;

  /// 0..1 fill fraction.
  final double fraction;
  final TemperatureSeverity severity;
  final double size;
  final bool showLabel;
  final String? labelText;

  @override
  State<TemperatureGauge> createState() => _TemperatureGaugeState();
}

class _TemperatureGaugeState extends State<TemperatureGauge> with TickerProviderStateMixin {
  late final AnimationController _valueController;
  late final AnimationController _pulseController;
  late final AnimationController _glowController;
  late Animation<double> _valueAnimation;
  double _previousFraction = 0;

  @override
  void initState() {
    super.initState();
    _valueController = AnimationController(vsync: this, duration: AppDurations.slow);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _valueAnimation = AlwaysStoppedAnimation(widget.fraction);
    _previousFraction = widget.fraction;
  }

  @override
  void didUpdateWidget(covariant TemperatureGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fraction != widget.fraction) {
      _valueAnimation = Tween<double>(begin: _previousFraction, end: widget.fraction)
          .animate(CurvedAnimation(parent: _valueController, curve: Curves.easeOutCubic));
      _previousFraction = widget.fraction;
      _valueController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(widget.severity, context);
    final animatePulse = widget.severity == TemperatureSeverity.warning ||
        widget.severity == TemperatureSeverity.critical;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([_valueAnimation, _pulseController, _glowController]),
      builder: (context, _) {
        final pulseScale = animatePulse
            ? 1.0 +
                (widget.severity == TemperatureSeverity.critical ? 0.04 : 0.02) *
                    _pulseController.value
            : 1.0;
        final glowOpacity = animatePulse
            ? 0.4 + 0.35 * _glowController.value
            : 0.2 + 0.15 * _glowController.value;

        return Transform.scale(
          scale: pulseScale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _GaugePainter(
                fraction: _valueAnimation.value,
                color: style.color,
                glowColor: style.glowColor,
                trackColor: isDark ? AppColors.bg3 : const Color(0xFFE8E3FF),
                glow: animatePulse,
                glowOpacity: glowOpacity,
                isDark: isDark,
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
                        color: style.color,
                        fontSize: widget.size * 0.16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (widget.showLabel) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.labelText ?? style.label,
                        style: TextStyle(
                          color: style.color.withValues(alpha: 0.7),
                          fontSize: widget.size * 0.1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
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
    required this.glowColor,
    required this.trackColor,
    required this.glow,
    required this.glowOpacity,
    required this.isDark,
  });

  final double fraction;
  final Color color;
  final Color glowColor;
  final Color trackColor;
  final bool glow;
  final double glowOpacity;
  final bool isDark;

  static const _startAngle = -pi / 2 - pi * 0.75;
  static const _sweepTotal = pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final strokeWidth = size.width * 0.075;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), _startAngle, _sweepTotal,
        false, trackPaint);

    final clampedFraction = fraction.clamp(0.0, 1.0);
    if (clampedFraction <= 0) return;

    // Glow layer
    if (glow || isDark) {
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: glowOpacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), _startAngle,
          _sweepTotal * clampedFraction, false, glowPaint);
    }

    // Main arc — gradient via shader
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final shader = SweepGradient(
      center: Alignment.center,
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepTotal * clampedFraction,
      colors: [
        color.withValues(alpha: 0.6),
        color,
      ],
    ).createShader(arcRect);

    final valuePaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, _startAngle, _sweepTotal * clampedFraction, false, valuePaint);

    // Bright tip dot
    final tipAngle = _startAngle + _sweepTotal * clampedFraction;
    final tipX = center.dx + radius * cos(tipAngle);
    final tipY = center.dy + radius * sin(tipAngle);
    final tipPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(tipX, tipY), strokeWidth * 0.4, tipPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.glowOpacity != glowOpacity;
}
