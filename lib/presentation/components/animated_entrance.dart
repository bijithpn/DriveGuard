import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fade + upward-slide entrance for one item in a list/grid, staggered by
/// [index] so a screen full of static rows/tiles animates in as a cascade
/// instead of appearing all at once. Mirrors the stagger already used for
/// the dashboard's drive-card grid (see dashboard_screen.dart) so the same
/// motion language reads consistently everywhere a collection of cards or
/// rows is built from a list.
///
/// Keep [index] small and local to the list being built (reset per screen/
/// tab) - it only controls stagger delay, not identity.
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: durationMs + index * baseDelayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * offsetY), child: child),
      ),
      child: child,
    );
  }
}

/// A small colored icon badge - the same rounded-square, tinted-background
/// treatment used for drive-card type badges (see drive_card.dart's
/// `_TypeBadge`), reused here so every icon+label row in the app (health
/// tiles, diagnostics rows, settings tiles) reads as one deliberate icon
/// system instead of ad hoc bare `Icon` widgets.
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
