import 'dart:math';

import 'package:flutter/material.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

/// The worst-severity device across the snapshot, used both for the
/// collapsed strip's tint and as the expanded panel's headline device.
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

/// The collapsed strip: a slim bar tinted by the worst connected drive's
/// severity, glanceable without reading text.
class EdgeDockStrip extends StatelessWidget {
  const EdgeDockStrip({super.key, required this.snapshot});

  final MiniWidgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final worst = worstDevice(snapshot.devices);
    final color = worst == null
        ? AppColors.textMuted
        : severityColor(worst.severity);

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
            spreadRadius: -1,
          ),
        ],
      ),
    );
  }
}

/// The expanded panel: a compact live summary, sliding out from the docked
/// edge on hover.
class EdgeDockPanel extends StatelessWidget {
  const EdgeDockPanel({super.key, required this.snapshot});

  final MiniWidgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;

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
              blurRadius: 24,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _EdgeDockDeviceRow(device: devices[index]),
                  ),
          ),
        ),
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
      children: [
        SizedBox(
          width: 28,
          height: 28,
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
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
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
