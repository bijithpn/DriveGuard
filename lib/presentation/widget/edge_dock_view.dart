import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../../application/settings/app_settings.dart' show kAllEdgeDockMetrics;
import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../../infrastructure/tray/edge_dock_geometry.dart'
    show EdgeDockGeometry;
import '../theme/app_theme.dart';
import 'edge_dock_organic_painter.dart';
import 'edge_dock_popover_bubble.dart';

/// Resolved colors for the edge dock's own surfaces (panel background, body
/// text) plus severity overrides, kept in one place instead of scattering
/// `AppColors.*`/user-color decisions across widgets. `null` fields on
/// [EdgeDockSettings] fall back to the app's normal design-system colors.
class EdgeDockTheme {
  const EdgeDockTheme({
    required this.background,
    required this.text,
    required this.mutedText,
    required this.warning,
    required this.critical,
  });

  final Color background;
  final Color text;
  final Color mutedText;
  final Color warning;
  final Color critical;

  static const EdgeDockTheme defaults = EdgeDockTheme(
    background: AppColors.bg1,
    text: AppColors.textPrimary,
    mutedText: AppColors.textMuted,
    warning: AppColors.warning,
    critical: AppColors.critical,
  );

  factory EdgeDockTheme.resolve({
    int? backgroundColor,
    int? textColor,
    int? warningColor,
    int? criticalColor,
  }) {
    final text = textColor != null ? Color(textColor) : AppColors.textPrimary;
    return EdgeDockTheme(
      background: backgroundColor != null
          ? Color(backgroundColor)
          : AppColors.bg1,
      text: text,
      mutedText: textColor != null
          ? text.withValues(alpha: 0.6)
          : AppColors.textMuted,
      warning: warningColor != null ? Color(warningColor) : AppColors.warning,
      critical: criticalColor != null
          ? Color(criticalColor)
          : AppColors.critical,
    );
  }
}

Color severityColor(TemperatureSeverity severity, [EdgeDockTheme? theme]) {
  final t = theme ?? EdgeDockTheme.defaults;
  switch (severity) {
    case TemperatureSeverity.critical:
      return t.critical;
    case TemperatureSeverity.warning:
      return t.warning;
    case TemperatureSeverity.warm:
    case TemperatureSeverity.normal:
      return AppColors.normal;
    case TemperatureSeverity.unavailable:
      return t.mutedText;
  }
}

/// Resolves a user-chosen accent to a concrete color, or `null` for
/// [EdgeDockAccent.auto] (caller falls back to per-device severity color).
Color? resolveAccent(EdgeDockAccent accent) {
  switch (accent) {
    case EdgeDockAccent.auto:
      return null;
    case EdgeDockAccent.blue:
      return AppColors.accent;
    case EdgeDockAccent.teal:
      return const Color(0xFF2DD4BF);
    case EdgeDockAccent.purple:
      return const Color(0xFF9B7BFF);
    case EdgeDockAccent.pink:
      return const Color(0xFFEC6BAE);
    case EdgeDockAccent.orange:
      return const Color(0xFFFF9F45);
    case EdgeDockAccent.red:
      return AppColors.critical;
  }
}

bool isVerticalEdge(ScreenEdge edge) =>
    edge == ScreenEdge.left || edge == ScreenEdge.right;

/// The full edge-dock surface: a rail of per-device ring indicators
/// docked to a screen edge, plus a detail card that appears beside
/// whichever ring is hovered or pinned. Hover is driven entirely by native
/// [MouseRegion] events (no cursor polling) - the rail and the open detail
/// card are one interactive zone, so moving from a ring toward its card
/// never flickers.
///
/// [onHover] is called with the newly hovered device index, or `null` when
/// the pointer leaves the whole surface. [onTapRing] pins/unpins a ring's
/// panel open independent of the pointer - the click-to-pin interaction
/// this doubles as the non-hover accessibility fallback for: the panel
/// doesn't require the pointer to keep hovering once pinned, and the same
/// mechanism is reachable from the keyboard via [onArrowKey] (move which
/// ring is targeted) plus Enter/Space (pin it) once the dock has keyboard
/// focus - never grabbed automatically, only by a deliberate click, so this
/// doesn't count as stealing focus from the main app window. The caller
/// (EdgeDockApp) owns the actual OS window resize this implies - this
/// widget only lays out content within whatever bounds it's given.
class EdgeDockContent extends StatelessWidget {
  const EdgeDockContent({
    super.key,
    required this.snapshot,
    required this.edge,
    required this.accentOverride,
    required this.hoveredIndex,
    required this.onHover,
    required this.railLocalRect,
    required this.panelLocalRect,
    this.pinnedIndex,
    this.onTapRing,
    this.onTapActionPod,
    this.onArrowKey,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.theme = EdgeDockTheme.defaults,
    this.visibleMetrics = kAllEdgeDockMetrics,
    this.isExpanded = true,
    this.expansionProgress = 1.0,
    this.onMouseEnterDock,
    this.onMouseExitDock,
  });

  final MiniWidgetSnapshot snapshot;
  final ScreenEdge edge;
  final Color? accentOverride;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final VoidCallback? onTapActionPod;
  final void Function({required bool forward})? onArrowKey;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Rect railLocalRect;
  final Rect? panelLocalRect;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;
  final bool isExpanded;
  final double expansionProgress;
  final VoidCallback? onMouseEnterDock;
  final VoidCallback? onMouseExitDock;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final onArrow = onArrowKey;
    final key = event.logicalKey;
    final vertical = isVerticalEdge(edge);
    final forwardKey = vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    final backwardKey = vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    if (onArrow != null && key == forwardKey) {
      onArrow(forward: true);
      return KeyEventResult.handled;
    }
    if (onArrow != null && key == backwardKey) {
      onArrow(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      onTapRing?.call(hoveredIndex ?? pinnedIndex ?? 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      onTapRing?.call(null);
      onHover(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;
    final panelRect = panelLocalRect;
    final displayed = pinnedIndex ?? hoveredIndex;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Focus(
      canRequestFocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onEnter: (_) => onMouseEnterDock?.call(),
        onExit: (_) {
          onMouseExitDock?.call();
          onHover(null);
        },
        child: Stack(
          children: [
            const Positioned.fill(child: SizedBox.expand()),
            Positioned.fromRect(
              rect: railLocalRect,
              child: _Rail(
                devices: devices,
                edge: edge,
                hoveredIndex: displayed,
                pinnedIndex: pinnedIndex,
                onHover: onHover,
                onTapRing: onTapRing,
                onTapActionPod: onTapActionPod,
                onDragStart: onDragStart,
                onDragUpdate: onDragUpdate,
                onDragEnd: onDragEnd,
                accentOverride: accentOverride,
                theme: theme,
                reducedMotion: reducedMotion,
                isExpanded: isExpanded,
                expansionProgress: expansionProgress,
              ),
            ),
            if (displayed != null &&
                panelRect != null &&
                displayed < devices.length &&
                expansionProgress > 0.3)
              Positioned.fromRect(
                rect: panelRect,
                child: _DetailCard(
                  device: devices[displayed],
                  edge: edge,
                  targetArrowPosition: isVerticalEdge(edge)
                      ? (EdgeDockGeometry.ringCenter(
                              railLocalRect,
                              edge,
                              displayed,
                            ).dy -
                            panelRect.top)
                      : (EdgeDockGeometry.ringCenter(
                              railLocalRect,
                              edge,
                              displayed,
                            ).dx -
                            panelRect.left),
                  accentOverride: accentOverride,
                  theme: theme,
                  visibleMetrics: visibleMetrics,
                  reducedMotion: reducedMotion,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.devices,
    required this.edge,
    required this.hoveredIndex,
    required this.onHover,
    required this.accentOverride,
    required this.theme,
    required this.reducedMotion,
    this.pinnedIndex,
    this.onTapRing,
    this.onTapActionPod,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.isExpanded = true,
    this.expansionProgress = 1.0,
  });

  final List<MiniWidgetDeviceSnapshot> devices;
  final ScreenEdge edge;
  final int? hoveredIndex;
  final int? pinnedIndex;
  final ValueChanged<int?> onHover;
  final ValueChanged<int?>? onTapRing;
  final VoidCallback? onTapActionPod;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final bool reducedMotion;
  final bool isExpanded;
  final double expansionProgress;

  @override
  Widget build(BuildContext context) {
    final vertical = isVerticalEdge(edge);
    final items = devices.isEmpty
        ? [_EmptyRingItem(theme: theme)]
        : List.generate(
            devices.length,
            (i) => _RingItem(
              device: devices[i],
              selected: hoveredIndex == i,
              pinned: pinnedIndex == i,
              accentOverride: accentOverride,
              theme: theme,
              reducedMotion: reducedMotion,
              onEnter: () => onHover(i),
              onTap: onTapRing == null ? null : () => onTapRing!(i),
            ),
          );

    final count = devices.isEmpty ? 1 : devices.length;
    final mainRailLength =
        count * EdgeDockGeometry.itemBlockLength +
        (count - 1) * EdgeDockGeometry.itemSpacing;

    final pod = _BottomActionPod(
      theme: theme,
      reducedMotion: reducedMotion,
      onTap: onTapActionPod,
    );

    final animatedItems = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (expansionProgress >= 1.0) {
        animatedItems.add(item);
        continue;
      }
      final staggerDelay = (i * 0.05).clamp(0.0, 0.3);
      final itemProgress = reducedMotion
          ? (expansionProgress > 0.0 ? 1.0 : 0.0)
          : ((expansionProgress - staggerDelay) / (1.0 - staggerDelay)).clamp(0.0, 1.0);
      final curvedItemProgress = Curves.easeOutCubic.transform(itemProgress);

      final slideDistance = 14.0 * (1.0 - curvedItemProgress);
      Offset slideOffset;
      switch (edge) {
        case ScreenEdge.left:
          slideOffset = Offset(-slideDistance, 0);
        case ScreenEdge.right:
          slideOffset = Offset(slideDistance, 0);
        case ScreenEdge.top:
          slideOffset = Offset(0, -slideDistance);
        case ScreenEdge.bottom:
          slideOffset = Offset(0, slideDistance);
      }

      animatedItems.add(
        Transform.translate(
          offset: slideOffset,
          child: Opacity(
            opacity: curvedItemProgress,
            child: IgnorePointer(
              ignoring: curvedItemProgress < 0.5,
              child: item,
            ),
          ),
        ),
      );
    }

    Widget animatedPod = pod;
    if (expansionProgress < 1.0) {
      final podProgress = reducedMotion
          ? (expansionProgress > 0.0 ? 1.0 : 0.0)
          : ((expansionProgress - 0.15) / 0.85).clamp(0.0, 1.0);
      final curvedPodProgress = Curves.easeOutCubic.transform(podProgress);
      final podSlideDistance = 14.0 * (1.0 - curvedPodProgress);
      Offset podSlideOffset;
      switch (edge) {
        case ScreenEdge.left:
          podSlideOffset = Offset(-podSlideDistance, 0);
        case ScreenEdge.right:
          podSlideOffset = Offset(podSlideDistance, 0);
        case ScreenEdge.top:
          podSlideOffset = Offset(0, -podSlideDistance);
        case ScreenEdge.bottom:
          podSlideOffset = Offset(0, podSlideDistance);
      }
      animatedPod = Transform.translate(
        offset: podSlideOffset,
        child: Opacity(
          opacity: curvedPodProgress,
          child: IgnorePointer(
            ignoring: curvedPodProgress < 0.5,
            child: pod,
          ),
        ),
      );
    }

    final content = CustomPaint(
      painter: EdgeDockOrganicPainter(
        edge: edge,
        backgroundColor: theme.background,
        borderColor: Colors.transparent,
        borderWidth: 0.0,
        mainRailLength: mainRailLength,
        podDiameter: EdgeDockGeometry.podDiameter,
        podSpacing: EdgeDockGeometry.podSpacing,
        filletRadius: EdgeDockGeometry.filletRadius,
        showPod: true,
        dockDepth: EdgeDockGeometry.railThickness,
        collapsedDepth: EdgeDockGeometry.collapsedThickness,
        expansionProgress: expansionProgress,
      ),
      child: ClipRect(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isVerticalEdge(edge) ? 12 : EdgeDockGeometry.filletRadius,
            vertical: isVerticalEdge(edge) ? EdgeDockGeometry.filletRadius : 12,
          ),
          child: vertical
              ? SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _withSpacing(animatedItems, vertical: true),
                      ),
                      const SizedBox(height: EdgeDockGeometry.podSpacing),
                      animatedPod,
                    ],
                  ),
                )
              : SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _withSpacing(animatedItems, vertical: false),
                      ),
                      const SizedBox(width: EdgeDockGeometry.podSpacing),
                      animatedPod,
                    ],
                  ),
                ),
        ),
      ),
    );

    if (onDragUpdate == null) return content;
    // The grip is drawn *over* the rail rather than taking its own layout
    // space in the Column/Row above - the rail's measured size (and every
    // EdgeDockGeometry calculation) stays exactly what it was without
    // drag-to-reposition, so there's no risk of it silently drifting out
    // of sync with the geometry math the way the fixed-height detail panel
    // once did. Dragging starts from the rail's own background/padding,
    // not from a ring, so it never competes with a ring's tap-to-pin.
    return Stack(
      children: [
        MouseRegion(
          cursor: vertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart?.call(),
            onPanUpdate: (d) =>
                onDragUpdate!(vertical ? d.delta.dy : d.delta.dx),
            onPanEnd: (_) => onDragEnd?.call(),
            child: content,
          ),
        ),
        Positioned(
          top: vertical ? 4 : null,
          left: vertical ? 0 : 4,
          right: vertical ? 0 : null,
          bottom: vertical ? null : 0,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: Icon(
                vertical
                    ? Icons.drag_indicator_rounded
                    : Icons.drag_handle_rounded,
                size: 12,
                color: theme.mutedText.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _withSpacing(List<Widget> items, {required bool vertical}) {
    final spaced = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        spaced.add(
          vertical ? const SizedBox(height: 10) : const SizedBox(width: 10),
        );
      }
      spaced.add(items[i]);
    }
    return spaced;
  }
}

class _RingItem extends StatelessWidget {
  const _RingItem({
    required this.device,
    required this.selected,
    required this.accentOverride,
    required this.theme,
    required this.reducedMotion,
    required this.onEnter,
    this.pinned = false,
    this.onTap,
  });

  final MiniWidgetDeviceSnapshot device;
  final bool selected;
  final bool pinned;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final bool reducedMotion;
  final VoidCallback onEnter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity, theme);
    final scaleDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final displayValue = device.valueText.isNotEmpty
        ? device.valueText
        : '${(device.fraction * 100).round()}%';

    return MouseRegion(
      onEnter: (_) => onEnter(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                Focus.of(context).requestFocus();
                onTap!();
              },
        child: Semantics(
          button: true,
          label: '${device.name}, $displayValue',
          hint: pinned
              ? 'Details pinned open. Activate to unpin.'
              : 'Activate to pin details open.',
          child: AnimatedScale(
            scale: selected ? 1.08 : 1.0,
            duration: scaleDuration,
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: EdgeDockGeometry.ringDiameter,
                  height: EdgeDockGeometry.ringDiameter,
                  child: CustomPaint(
                    painter: _RingPainter(
                      fraction: device.fraction,
                      color: color,
                      pinned: pinned,
                      selected: selected,
                    ),
                    child: Center(
                      child: Icon(
                        device.type == StorageDeviceType.nvme
                            ? Icons.memory_rounded
                            : device.type == StorageDeviceType.ssd
                            ? Icons.storage_rounded
                            : Icons.album_rounded,
                        size: 15,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRingItem extends StatelessWidget {
  const _EmptyRingItem({required this.theme});

  final EdgeDockTheme theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: EdgeDockGeometry.ringDiameter,
          height: EdgeDockGeometry.ringDiameter,
          child: CustomPaint(
            painter: _RingPainter(fraction: 0, color: theme.mutedText),
            child: Center(
              child: Icon(
                Icons.hourglass_empty_rounded,
                size: 14,
                color: theme.mutedText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '--',
          style: TextStyle(
            color: theme.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _BottomActionPod extends StatefulWidget {
  const _BottomActionPod({
    required this.theme,
    required this.reducedMotion,
    this.onTap,
  });

  final EdgeDockTheme theme;
  final bool reducedMotion;
  final VoidCallback? onTap;

  @override
  State<_BottomActionPod> createState() => _BottomActionPodState();
}

class _BottomActionPodState extends State<_BottomActionPod> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scaleDuration = widget.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                Focus.of(context).requestFocus();
                widget.onTap!();
              },
        child: Semantics(
          button: true,
          label: 'Settings',
          hint: 'Open settings and dock actions',
          child: AnimatedScale(
            scale: _hovered ? 1.12 : 1.0,
            duration: scaleDuration,
            curve: Curves.easeOutCubic,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? widget.theme.text.withValues(alpha: 0.12)
                    : widget.theme.background.withValues(alpha: 0.6),
                border: Border.all(
                  color: _hovered
                      ? widget.theme.text.withValues(alpha: 0.3)
                      : const Color(0xFF1E1E26),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: _hovered ? widget.theme.text : widget.theme.mutedText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// The rows the detail panel renders for [device], given which optional
/// [EdgeDockMetric]s are enabled - temperature is always first and always
/// present. Shared between the widget (to build the rows) and the
/// window-geometry code (`EdgeDockGeometry.panelHeightFor`, via this list's
/// length) so the panel is sized to fit exactly what it renders instead of
/// a fixed height that can overflow once more rows are toggled on.
List<(String, String)> edgeDockDetailRows(
  MiniWidgetDeviceSnapshot device,
  Set<EdgeDockMetric> visibleMetrics,
) {
  return [
    ('Temperature', device.valueText),
    if (visibleMetrics.contains(EdgeDockMetric.health) &&
        device.lifePercent != null)
      ('Health', '${device.lifePercent}%'),
    if (visibleMetrics.contains(EdgeDockMetric.smart))
      ('SMART', device.healthStatus),
    if (visibleMetrics.contains(EdgeDockMetric.powerOnHours) &&
        device.powerOnHoursText != null)
      ('Power on', device.powerOnHoursText!),
    if (visibleMetrics.contains(EdgeDockMetric.transferSpeed) &&
        device.readSpeedText != null)
      ('Read', device.readSpeedText!),
    if (visibleMetrics.contains(EdgeDockMetric.transferSpeed) &&
        device.writeSpeedText != null)
      ('Write', device.writeSpeedText!),
    if (visibleMetrics.contains(EdgeDockMetric.freeCapacity) &&
        device.freeCapacityText != null)
      ('Free', device.freeCapacityText!),
  ];
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.device,
    this.edge = ScreenEdge.left,
    this.targetArrowPosition = 60.0,
    this.accentOverride,
    this.theme = EdgeDockTheme.defaults,
    this.visibleMetrics = kAllEdgeDockMetrics,
    this.reducedMotion = false,
  });

  final MiniWidgetDeviceSnapshot device;
  final ScreenEdge edge;
  final double targetArrowPosition;
  final Color? accentOverride;
  final EdgeDockTheme theme;
  final Set<EdgeDockMetric> visibleMetrics;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity, theme);
    final rows = edgeDockDetailRows(device, visibleMetrics);
    final usedPercent = (device.fraction * 100).round();
    final leftPercent = (100 - usedPercent).clamp(0, 100);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.94 + 0.06 * t,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: EdgeDockPopoverBubble(
          edge: edge,
          targetArrowPosition: targetArrowPosition,
          backgroundColor: theme.background,
          borderColor: Colors.transparent,
          borderRadius: 20.0,
          borderWidth: 0.0,
          arrowWidth: 8.0,
          arrowHeight: 16.0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Section: Device icon + Bold name + Status badge
              Row(
                children: [
                  Icon(
                    device.type == StorageDeviceType.nvme
                        ? Icons.memory_rounded
                        : device.type == StorageDeviceType.ssd
                        ? Icons.storage_rounded
                        : Icons.album_rounded,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: color.withValues(alpha: 0.28),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      device.healthStatus.isNotEmpty
                          ? device.healthStatus
                          : 'OK',
                      style: TextStyle(
                        color: color,
                        fontSize: 10.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Linear Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: device.fraction.clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFF1E1E28),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 4),
              // Breakdown Label
              Text(
                '$usedPercent% Used · $leftPercent% left',
                style: TextStyle(
                  color: theme.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 7),
              Container(
                height: 1,
                color: theme.mutedText.withValues(alpha: 0.14),
              ),
              const SizedBox(height: 4),
              // Metrics List
              for (final (label, value) in rows)
                _DetailRow(label: label, value: value, theme: theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final EdgeDockTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: theme.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    this.pinned = false,
    this.selected = false,
  });

  final double fraction;
  final Color color;
  final bool pinned;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2.5;
    const strokeWidth = 3.2;

    final track = Paint()
      ..color = const Color(0xFF1A1A22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped > 0) {
      final value = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * clamped,
        false,
        value,
      );
    }

    if (pinned || selected) {
      // Outer glow / indicator ring distinct from the progress arc
      final indicator = Paint()
        ..color = color.withValues(alpha: pinned ? 0.85 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = pinned ? 1.5 : 1.0;
      canvas.drawCircle(center, radius + 2.0, indicator);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.pinned != pinned ||
      oldDelegate.selected != selected;
}


/// Debounces the "pointer left the whole dock" event by a short grace
/// period, so a fast cursor movement between the rail and the detail card
/// (both inside the same window, but Flutter can report a same-frame
/// exit+re-enter at the boundary) doesn't cause a visible flicker. Pure
/// timer wrapper - the actual hover-zone containment is handled by
/// [EdgeDockContent]'s own MouseRegion.
class EdgeDockCollapseDebouncer {
  EdgeDockCollapseDebouncer({this.grace = const Duration(milliseconds: 150)});

  final Duration grace;
  Timer? _timer;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void schedule(VoidCallback onCollapse) {
    _timer?.cancel();
    _timer = Timer(grace, onCollapse);
  }

  void dispose() => cancel();
}
