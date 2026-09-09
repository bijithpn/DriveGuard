import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../../infrastructure/tray/edge_dock_geometry.dart'
    show EdgeDockGeometry;
import '../theme/app_theme.dart';

Color severityColor(TemperatureSeverity severity) {
  switch (severity) {
    case TemperatureSeverity.critical:
      return AppColors.critical;
    case TemperatureSeverity.warning:
      return AppColors.warning;
    case TemperatureSeverity.warm:
    case TemperatureSeverity.normal:
      return AppColors.normal;
    case TemperatureSeverity.unavailable:
      return AppColors.textMuted;
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
/// whichever ring is hovered. Hover is driven entirely by native
/// [MouseRegion] events (no cursor polling) - the rail and the open detail
/// card are one interactive zone, so moving from a ring toward its card
/// never flickers.
///
/// [onHover] is called with the newly hovered device index, or `null` when
/// the pointer leaves the whole surface. The caller (EdgeDockApp) owns the
/// actual OS window resize this implies - this widget only lays out
/// content within whatever bounds it's given.
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
  });

  final MiniWidgetSnapshot snapshot;
  final ScreenEdge edge;
  final Color? accentOverride;
  final int? hoveredIndex;
  final ValueChanged<int?> onHover;
  final Rect railLocalRect;
  final Rect? panelLocalRect;

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;
    final panelRect = panelLocalRect;
    final hovered = hoveredIndex;

    return MouseRegion(
      onExit: (_) => onHover(null),
      child: Stack(
        children: [
          const Positioned.fill(child: SizedBox.expand()),
          Positioned.fromRect(
            rect: railLocalRect,
            child: _Rail(
              devices: devices,
              edge: edge,
              hoveredIndex: hovered,
              onHover: onHover,
              accentOverride: accentOverride,
            ),
          ),
          if (hovered != null && panelRect != null && hovered < devices.length)
            Positioned.fromRect(
              rect: panelRect,
              child: _DetailCard(
                device: devices[hovered],
                accentOverride: accentOverride,
              ),
            ),
        ],
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
  });

  final List<MiniWidgetDeviceSnapshot> devices;
  final ScreenEdge edge;
  final int? hoveredIndex;
  final ValueChanged<int?> onHover;
  final Color? accentOverride;

  @override
  Widget build(BuildContext context) {
    final vertical = isVerticalEdge(edge);
    final items = devices.isEmpty
        ? [const _EmptyRingItem()]
        : List.generate(
            devices.length,
            (i) => _RingItem(
              device: devices[i],
              selected: hoveredIndex == i,
              accentOverride: accentOverride,
              onEnter: () => onHover(i),
            ),
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg1.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.bg3, width: 1),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: _withSpacing(items, vertical: true),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: _withSpacing(items, vertical: false),
            ),
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
    required this.onEnter,
  });

  final MiniWidgetDeviceSnapshot device;
  final bool selected;
  final Color? accentOverride;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity);

    return MouseRegion(
      onEnter: (_) => onEnter(),
      child: AnimatedScale(
        scale: selected ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: EdgeDockGeometry.ringDiameter,
              height: EdgeDockGeometry.ringDiameter,
              child: CustomPaint(
                painter: _RingPainter(fraction: device.fraction, color: color),
                child: Center(
                  child: Icon(
                    device.type == StorageDeviceType.nvme
                        ? Icons.memory_rounded
                        : device.type == StorageDeviceType.ssd
                        ? Icons.storage_rounded
                        : Icons.album_rounded,
                    size: 14,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              device.valueText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRingItem extends StatelessWidget {
  const _EmptyRingItem();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: EdgeDockGeometry.ringDiameter,
          height: EdgeDockGeometry.ringDiameter,
          child: CustomPaint(
            painter: _RingPainter(fraction: 0, color: AppColors.textMuted),
            child: const Center(
              child: Icon(
                Icons.hourglass_empty_rounded,
                size: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '--',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.device, required this.accentOverride});

  final MiniWidgetDeviceSnapshot device;
  final Color? accentOverride;

  @override
  Widget build(BuildContext context) {
    final color = accentOverride ?? severityColor(device.severity);
    final rows = <(String, String)>[
      ('Temperature', device.valueText),
      if (device.lifePercent != null) ('Health', '${device.lifePercent}%'),
      ('SMART', device.healthStatus),
      if (device.powerOnHoursText != null)
        ('Power on', device.powerOnHoursText!),
      if (device.readSpeedText != null) ('Read', device.readSpeedText!),
      if (device.writeSpeedText != null) ('Write', device.writeSpeedText!),
      if (device.freeCapacityText != null) ('Free', device.freeCapacityText!),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.96 + 0.04 * t,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg1,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.bg3, width: 1),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowDark,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    border: Border(
                      bottom: BorderSide(color: color.withValues(alpha: 0.18)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (label, value) in rows)
                        _DetailRow(label: label, value: value),
                    ],
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2.5;
    const strokeWidth = 3.0;

    final track = Paint()
      ..color = AppColors.bg3
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped <= 0) return;
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

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
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
