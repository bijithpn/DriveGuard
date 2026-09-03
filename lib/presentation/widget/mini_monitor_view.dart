import 'dart:math';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

/// Premium compact always-on-top mini-monitor widget.
/// Borderless, draggable, low-chrome, fully themed.
///
/// Pure data-in, no Riverpod: this runs inside the mini-widget's own
/// separate window/isolate (see `MiniWidgetApp`), which has no access to
/// the main window's provider container. [snapshot] arrives over
/// `desktop_multi_window`'s method channel instead.
class MiniMonitorView extends StatelessWidget {
  const MiniMonitorView({super.key, required this.snapshot, required this.onExpand});
  final MiniWidgetSnapshot snapshot;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;

    // Derive overall health
    bool anyWarning = false;
    bool anyCritical = false;
    for (final d in devices) {
      if (d.severity == TemperatureSeverity.critical) {
        anyCritical = true;
        break;
      }
      if (d.severity == TemperatureSeverity.warning) anyWarning = true;
    }

    final statusColor = anyCritical
        ? AppColors.critical
        : anyWarning
            ? AppColors.warning
            : AppColors.normal;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1640), Color(0xFF0D0B1A)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 20, spreadRadius: 0),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text(
                        'Storage',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      _MiniIconButton(
                        icon: Icons.open_in_full_rounded,
                        tooltip: 'Expand',
                        onPressed: onExpand,
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, AppColors.divider, Colors.transparent],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Device list
                  if (devices.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Scanning…',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          final style = SeverityStyle.of(device.severity, context);
                          final compact = snapshot.compact;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                _MiniTempMeter(
                                  fraction: device.fraction,
                                  color: style.color,
                                  size: compact ? 14 : 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    device.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: compact ? 11 : 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  device.valueText,
                                  style: TextStyle(
                                    color: style.color,
                                    fontSize: compact ? 11 : 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                  // Footer status
                  if (devices.isNotEmpty) ...[
                    Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, AppColors.divider, Colors.transparent],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      anyCritical
                          ? '⚠ Critical temperature'
                          : anyWarning
                              ? '⚠ Temperature warning'
                              : '✓ All systems normal',
                      style: TextStyle(
                        color: statusColor.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny animated ring gauge used in place of a plain status dot, so the
/// mini widget shows temperature as a moving meter rather than a static
/// on/off indicator. The fill sweeps and tweens smoothly toward each new
/// reading via [TweenAnimationBuilder].
class _MiniTempMeter extends StatelessWidget {
  const _MiniTempMeter({
    required this.fraction,
    required this.color,
    required this.size,
  });

  final double fraction;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
      duration: AppDurations.slow,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _MiniRingPainter(fraction: value, color: color),
          ),
        );
      },
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  static const _startAngle = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1.5;
    final strokeWidth = size.width * 0.22;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (fraction <= 0) return;
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      2 * pi * fraction,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.bg3,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 12, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
