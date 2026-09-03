import 'dart:math';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

class MiniMonitorView extends StatelessWidget {
  const MiniMonitorView({
    super.key,
    required this.snapshot,
    required this.onExpand,
  });

  final MiniWidgetSnapshot snapshot;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final devices = snapshot.devices;
    final compact = snapshot.compact;

    TemperatureSeverity worstSeverity = TemperatureSeverity.normal;
    for (final d in devices) {
      if (d.severity == TemperatureSeverity.critical) {
        worstSeverity = TemperatureSeverity.critical;
        break;
      }
      if (d.severity == TemperatureSeverity.warning) {
        worstSeverity = TemperatureSeverity.warning;
      }
    }

    final statusColor = worstSeverity == TemperatureSeverity.critical
        ? AppColors.critical
        : worstSeverity == TemperatureSeverity.warning
        ? AppColors.warning
        : devices.isEmpty
        ? AppColors.textMuted
        : AppColors.normal;

    return Material(
      color: Colors.transparent,
      child: _WidgetShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DragToMoveArea(
              child: _Header(
                statusColor: statusColor,
                deviceCount: devices.length,
                onExpand: onExpand,
                compact: compact,
              ),
            ),
            if (devices.isEmpty)
              _EmptyBody(compact: compact)
            else
              Flexible(
                child: SingleChildScrollView(
                  child: _DeviceList(devices: devices, compact: compact),
                ),
              ),
            if (devices.isNotEmpty)
              _Footer(
                worstSeverity: worstSeverity,
                statusColor: statusColor,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _WidgetShell extends StatelessWidget {
  const _WidgetShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEA1C1C1E),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFF3A3A3C), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x50000000),
            blurRadius: 24,
            spreadRadius: 0,
            offset: Offset(0, 6),
          ),

          BoxShadow(
            color: Color(0x0CFFFFFF),
            blurRadius: 0,
            spreadRadius: -1,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.statusColor,
    required this.deviceCount,
    required this.onExpand,
    required this.compact,
  });

  final Color statusColor;
  final int deviceCount;
  final VoidCallback onExpand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final topPad = compact ? 8.0 : 10.0;
    final sidePad = compact ? 10.0 : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePad,
        topPad,
        sidePad - 2,
        compact ? 6 : 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: compact ? 5 : 6),

          Text(
            'Drives',
            style: TextStyle(
              color: const Color(0xFF98989D),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          if (deviceCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3C),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '$deviceCount',
                style: TextStyle(
                  color: const Color(0xFF636366),
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),

          _ExpandButton(onPressed: onExpand, compact: compact),
        ],
      ),
    );
  }
}

class _ExpandButton extends StatefulWidget {
  const _ExpandButton({required this.onPressed, required this.compact});
  final VoidCallback onPressed;
  final bool compact;

  @override
  State<_ExpandButton> createState() => _ExpandButtonState();
}

class _ExpandButtonState extends State<_ExpandButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Tooltip(
          message: 'Open dashboard',
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: widget.compact ? 18 : 20,
            height: widget.compact ? 18 : 20,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF48484A)
                  : const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF48484A), width: 1),
            ),
            child: Icon(
              Icons.open_in_full_rounded,
              size: widget.compact ? 9 : 10,
              color: _hovered
                  ? const Color(0xFF98989D)
                  : const Color(0xFF636366),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetDivider extends StatelessWidget {
  const _WidgetDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFF38383A));
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 14,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            size: 11,
            color: Color(0xFF636366),
          ),
          const SizedBox(width: 5),
          Text(
            'Scanning...',
            style: TextStyle(
              color: const Color(0xFF636366),
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.compact});

  final List<MiniWidgetDeviceSnapshot> devices;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _WidgetDivider(),
        for (int i = 0; i < devices.length; i++) ...[
          _DeviceRow(device: devices[i], compact: compact),
          if (i < devices.length - 1)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
              child: const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFF2C2C2E),
              ),
            ),
        ],
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.compact});

  final MiniWidgetDeviceSnapshot device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(device.severity, context);
    final vPad = compact ? 6.0 : 8.0;
    final hPad = compact ? 10.0 : 12.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _TempRing(
            fraction: device.fraction,
            color: style.color,
            size: compact ? 22 : 26,
          ),
          SizedBox(width: compact ? 7 : 8),

          Expanded(
            child: Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFEEEEF0),
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),

          Text(
            device.valueText,
            style: TextStyle(
              color: style.color,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.worstSeverity,
    required this.statusColor,
    required this.compact,
  });

  final TemperatureSeverity worstSeverity;
  final Color statusColor;
  final bool compact;

  String _label() {
    switch (worstSeverity) {
      case TemperatureSeverity.critical:
        return 'Critical';
      case TemperatureSeverity.warning:
        return 'Warning';
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
        return 'Normal';
      case TemperatureSeverity.unavailable:
        return 'Unavailable';
    }
  }

  IconData _icon() {
    switch (worstSeverity) {
      case TemperatureSeverity.critical:
        return Icons.error_outline_rounded;
      case TemperatureSeverity.warning:
        return Icons.warning_amber_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = compact ? 10.0 : 12.0;
    final vPad = compact ? 5.0 : 6.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _WidgetDivider(),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad + 1),
          child: Row(
            children: [
              Icon(_icon(), size: compact ? 9 : 10, color: statusColor),
              SizedBox(width: compact ? 3 : 4),
              Text(
                _label(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TempRing extends StatelessWidget {
  const _TempRing({
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
      builder: (context, value, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(fraction: value, color: color),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  static const _start = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final strokeWidth = size.width * 0.18;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (fraction <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _start,
      2 * pi * fraction,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
