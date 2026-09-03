import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EntranceFade extends StatelessWidget {
  const EntranceFade({
    super.key,
    required this.index,
    required this.child,
    this.baseDelayMs = 40,
    this.durationMs = 280,
    this.offsetY = 12,
  });

  final int index;
  final Widget child;
  final int baseDelayMs;
  final int durationMs;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: durationMs + index * baseDelayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * offsetY),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
    this.iconSize = 15,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
