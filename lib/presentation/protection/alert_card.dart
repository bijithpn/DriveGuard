import 'package:flutter/material.dart';

import '../components/ui_kit.dart';
import '../theme/app_theme.dart';

/// Flat alert surface: hairline border, a 3px coloured edge, one small icon.
/// Colour carries severity only — no tinted fills or icon tiles.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    this.trailing,
    this.subtitle,
    this.children = const [],
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: EdgeInsets.zero,
      clip: true,
      borderColor: color.withValues(alpha: 0.45),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AppText.heading(context)),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  style: AppText.secondary(context),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                    if (children.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ...children,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdviceList extends StatelessWidget {
  const AdviceList(this.items, {super.key});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final a in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 10),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: faintOf(context),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: Text(a, style: AppText.body(context))),
            ],
          ),
        ),
    ],
  );
}
