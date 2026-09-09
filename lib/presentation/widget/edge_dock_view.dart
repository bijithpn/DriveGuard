import 'dart:math';

import 'package:flutter/material.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../../domain/enums/ui_enums.dart';
import '../theme/app_theme.dart';

/// The worst-severity device across the snapshot, used both for the
/// collapsed badge's tint/value and as the expanded panel's headline.
MiniWidgetDeviceSnapshot? worstDevice(List<MiniWidgetDeviceSnapshot> devices) {
  if (devices.isEmpty) return null;
  const rank = {
    TemperatureSeverity.critical: 4,
    TemperatureSeverity.warning: 3,
    TemperatureSeverity.warm: 2,
    TemperatureSeverity.normal: 1,
    TemperatureSeverity.unavailable: 0,
  };
  return devices.reduce(
    (a, b) => (rank[a.severity] ?? 0) >= (rank[b.severity] ?? 0) ? a : b,
  );
}

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
/// [EdgeDockAccent.auto] (caller falls back to severity-based tinting).
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

bool _isVertical(ScreenEdge edge) =>
    edge == ScreenEdge.left || edge == ScreenEdge.right;

/// The collapsed badge: a rounded pill docked to the edge, tinted by the
/// worst connected drive's severity (or a user-chosen accent), showing a
/// glanceable icon + value even before it's hovered.
class EdgeDockStrip extends StatelessWidget {
  const EdgeDockStrip({
    super.key,
    required this.snapshot,
    required this.edge,
    this.accentOverride,
  });

  final MiniWidgetSnapshot snapshot;
  final ScreenEdge edge;
  final Color? accentOverride;

  @override
  Widget build(BuildContext context) {
    final worst = worstDevice(snapshot.devices);
    final color =
        accentOverride ??
        (worst == null ? AppColors.textMuted : severityColor(worst.severity));

    final icon = Icon(Icons.thermostat_rounded, size: 16, color: color);
    final valueText = Text(
      worst?.valueText ?? '--',
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg1.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: -2,
          ),
          const BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: _isVertical(edge)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(height: 3), valueText],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(width: 5), valueText],
              ),
      ),
    );
  }
}

/// The expanded panel: a compact live summary, sliding out from the docked
/// edge on hover.
class EdgeDockPanel extends StatelessWidget {
  const EdgeDockPanel({super.key, required this.snapshot, this.accentOverride});

  final MiniWidgetSnapshot snapshot;
  final Color? accentOverride;

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;
    final worst = worstDevice(devices);
    final headerColor =
        accentOverride ??
        (worst == null ? AppColors.textMuted : severityColor(worst.severity));

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg1,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.bg3, width: 1),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowDark,
              blurRadius: 28,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(color: headerColor, deviceCount: devices.length),
              Expanded(
                child: devices.isEmpty
                    ? const Center(
                        child: Text(
                          'Scanning...',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: devices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _EdgeDockDeviceRow(device: devices[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.color, required this.deviceCount});

  final Color color;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          const Text(
            'DriveGuard',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '$deviceCount drive${deviceCount == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeDockDeviceRow extends StatelessWidget {
  const _EdgeDockDeviceRow({required this.device});

  final MiniWidgetDeviceSnapshot device;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(device.severity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: CustomPaint(
            painter: _RingPainter(fraction: device.fraction, color: color),
            child: Center(
              child: Icon(
                device.type == StorageDeviceType.nvme
                    ? Icons.memory_rounded
                    : device.type == StorageDeviceType.ssd
                    ? Icons.storage_rounded
                    : Icons.album_rounded,
                size: 12,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    device.valueText,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: device.fraction.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.bg3,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ],
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
    final radius = size.width / 2 - 2;
    const strokeWidth = 2.5;

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
