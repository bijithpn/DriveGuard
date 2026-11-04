import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Small shared building blocks so every screen uses the same spacing, type
/// and surfaces instead of re-inventing them.

bool isDarkOf(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Color mutedOf(BuildContext c) =>
    isDarkOf(c) ? AppColors.textSecondary : AppColors.lightTextSecondary;

Color faintOf(BuildContext c) =>
    isDarkOf(c) ? AppColors.textMuted : const Color(0xFF8A94A1);

Color primaryTextOf(BuildContext c) =>
    isDarkOf(c) ? AppColors.textPrimary : AppColors.lightText;

Color hairlineOf(BuildContext c) =>
    isDarkOf(c) ? AppColors.divider : AppColors.lightBorder;

/// Type scale. Weights stay between 500 and 700; sizes step 11 / 12 / 13 /
/// 14 / 16 / 20 / 32 so nothing feels arbitrarily sized.
class AppText {
  const AppText._();

  static TextStyle title(BuildContext c) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: primaryTextOf(c),
    height: 1.2,
  );

  static TextStyle heading(BuildContext c) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: primaryTextOf(c),
    height: 1.3,
  );

  static TextStyle body(BuildContext c) =>
      TextStyle(fontSize: 13, color: primaryTextOf(c), height: 1.4);

  static TextStyle secondary(BuildContext c) =>
      TextStyle(fontSize: 12.5, color: mutedOf(c), height: 1.4);

  static TextStyle caption(BuildContext c) =>
      TextStyle(fontSize: 11.5, color: faintOf(c), height: 1.3);

  static TextStyle label(BuildContext c) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: faintOf(c),
  );

  static TextStyle metric(BuildContext c, {double size = 32}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
    color: primaryTextOf(c),
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Flat surface: hairline border, no shadow, consistent padding.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.radius = AppRadius.lg,
    this.color,
    this.borderColor,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? (dark ? AppColors.bg1 : AppColors.lightCard),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              borderColor ?? (dark ? AppColors.border : AppColors.lightBorder),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// "Label ........ value" row used for detail lists.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppText.secondary(context))),
        Text(
          value,
          style: AppText.body(context).copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Page header: title + optional one-line subtitle on the left, actions on
/// the right. Same height everywhere.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.backLabel,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// Optional "‹ Back" link above the title. It sits on the same left edge as
  /// the title and the content below, so nothing is indented.
  final String? backLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (backLabel != null) ...[
                  InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 18,
                            color: mutedOf(context),
                          ),
                          const SizedBox(width: 2),
                          Text(backLabel!, style: AppText.secondary(context)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(title, style: AppText.title(context)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary(context),
                  ),
                ],
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Two-option segmented switch with the app's flat styling.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkOf(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? AppColors.bg1 : AppColors.lightSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: dark ? AppColors.border : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o.$1),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: o.$1 == value
                      ? (dark ? AppColors.bg3 : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (o.$3 != null) ...[
                      Icon(
                        o.$3,
                        size: 15,
                        color: o.$1 == value
                            ? primaryTextOf(context)
                            : mutedOf(context),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      o.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: o.$1 == value
                            ? primaryTextOf(context)
                            : mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Heading + content block used to structure every detail page the same way.
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.caption,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? caption;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: AppText.heading(context))),
          ?trailing,
        ],
      ),
      if (caption != null) ...[
        const SizedBox(height: 2),
        Text(caption!, style: AppText.caption(context)),
      ],
      const SizedBox(height: 12),
      child,
    ],
  );
}

class DetailRowData {
  const DetailRowData(
    this.label,
    this.value, {
    this.dot,
    this.copyable = false,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Small status dot before the value (severity only).
  final Color? dot;
  final bool copyable;
  final Color? valueColor;
}

/// One surface, hairline-separated rows: label left, value right.
class DetailTable extends StatelessWidget {
  const DetailTable(this.rows, {super.key});
  final List<DetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _DetailRow(rows[i], first: i == 0),
        ],
      ),
    );
  }
}

class _DetailRow extends StatefulWidget {
  const _DetailRow(this.data, {required this.first});
  final DetailRowData data;
  final bool first;

  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: widget.first
              ? null
              : Border(top: BorderSide(color: hairlineOf(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 168,
              child: Text(d.label, style: AppText.secondary(context)),
            ),
            if (d.dot != null)
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 8),
                child: StatusDot(d.dot!, size: 7),
              ),
            Expanded(
              child: Text(
                d.value,
                style: AppText.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w600, color: d.valueColor),
              ),
            ),
            if (d.copyable)
              AnimatedOpacity(
                duration: AppDurations.fast,
                opacity: _hover ? 1 : 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: d.value));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text('${d.label} copied'),
                        behavior: SnackBarBehavior.floating,
                        width: 240,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: faintOf(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
