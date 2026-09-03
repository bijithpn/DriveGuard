import 'dart:math';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../domain/enums/storage_enums.dart';
import '../theme/app_theme.dart';

class MiniMonitorView extends StatefulWidget {
  const MiniMonitorView({
    super.key,
    required this.snapshot,
    required this.onExpand,
    this.onClose,
  });

  final MiniWidgetSnapshot snapshot;
  final VoidCallback onExpand;
  final VoidCallback? onClose;

  @override
  State<MiniMonitorView> createState() => _MiniMonitorViewState();
}

class _MiniMonitorViewState extends State<MiniMonitorView> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.snapshot.devices.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.snapshot.devices;
    final compact = widget.snapshot.compact;

    if (_currentIndex >= devices.length && devices.isNotEmpty) {
      _currentIndex = devices.length - 1;
    }

    final currentDevice = devices.isNotEmpty ? devices[_currentIndex] : null;

    final statusColor = currentDevice == null
        ? AppColors.textMuted
        : currentDevice.severity == TemperatureSeverity.critical
            ? AppColors.critical
            : currentDevice.severity == TemperatureSeverity.warning
                ? AppColors.warning
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
                currentIndex: _currentIndex,
                onExpand: widget.onExpand,
                compact: compact,
                onClose: widget.onClose,
                onPrev: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                onNext: _currentIndex < devices.length - 1 ? () => _goTo(_currentIndex + 1) : null,
              ),
            ),
            if (devices.isEmpty)
              _EmptyBody(compact: compact)
            else
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    return _SingleDeviceCard(
                      device: devices[index],
                      compact: compact,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _SingleDeviceCard extends StatelessWidget {
  const _SingleDeviceCard({
    required this.device,
    required this.compact,
  });

  final MiniWidgetDeviceSnapshot device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = SeverityStyle.of(device.severity, context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Column(
        children: [
          // Device Model Header with Type Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                device.type == StorageDeviceType.nvme
                    ? Icons.memory_rounded
                    : device.type == StorageDeviceType.ssd
                        ? Icons.storage_rounded
                        : Icons.album_rounded,
                size: 13,
                color: const Color(0xFF98989D),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEEEEF0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Central Radial Gauge
          Expanded(
            child: Center(
              child: SizedBox(
                width: compact ? 92 : 110,
                height: compact ? 92 : 110,
                child: CustomPaint(
                  painter: _MiniGaugePainter(
                    fraction: device.fraction,
                    color: style.color,
                    trackColor: const Color(0xFF2C2C2E),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          device.valueText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFFEEEEF0),
                            fontSize: compact ? 18 : 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          style.label.toUpperCase(),
                          style: TextStyle(
                            color: style.color,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Enriched Drive Metrics Chips (Health, TBW/Hours, Live I/O)
          Row(
            children: [
              _MiniStatChip(
                label: 'Health',
                value: device.lifePercent != null
                    ? '${device.lifePercent}%'
                    : device.healthStatus,
                icon: Icons.favorite_rounded,
                color: device.healthStatus == 'HEALTHY' || device.healthStatus == 'OK'
                    ? AppColors.normal
                    : AppColors.warning,
              ),
              const SizedBox(width: 5),
              _MiniStatChip(
                label: device.tbwText != null ? 'Written' : 'Power',
                value: device.tbwText ?? device.powerOnHoursText ?? 'Active',
                icon: device.tbwText != null
                    ? Icons.save_as_rounded
                    : Icons.power_rounded,
                color: const Color(0xFF64D2FF),
              ),
              const SizedBox(width: 5),
              _MiniStatChip(
                label: 'Live I/O',
                value: device.readSpeedText ?? device.writeSpeedText ?? '0.0 MB/s',
                icon: Icons.speed_rounded,
                color: AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF242426),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF38383A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 9, color: color),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFF2F2F7),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniGaugePainter extends CustomPainter {
  _MiniGaugePainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  static const double _startAngle = -pi * 1.25;
  static const double _sweepTotal = pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;
    const strokeWidth = 5.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal,
      false,
      trackPaint,
    );

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal * clamped,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
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
    required this.currentIndex,
    required this.onExpand,
    required this.compact,
    this.onClose,
    this.onPrev,
    this.onNext,
  });

  final Color statusColor;
  final int deviceCount;
  final int currentIndex;
  final VoidCallback onExpand;
  final bool compact;
  final VoidCallback? onClose;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

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
          if (deviceCount > 1) ...[
            const SizedBox(width: 8),
            _NavArrowButton(
              icon: Icons.chevron_left_rounded,
              onPressed: onPrev,
              compact: compact,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${currentIndex + 1}/$deviceCount',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _NavArrowButton(
              icon: Icons.chevron_right_rounded,
              onPressed: onNext,
              compact: compact,
            ),
          ],
          const Spacer(),

          _ExpandButton(onPressed: onExpand, compact: compact),
          if (onClose != null) ...[
            const SizedBox(width: 4),
            _CloseWidgetButton(onPressed: onClose!, compact: compact),
          ],
        ],
      ),
    );
  }
}

class _NavArrowButton extends StatefulWidget {
  const _NavArrowButton({
    required this.icon,
    required this.onPressed,
    required this.compact,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  State<_NavArrowButton> createState() => _NavArrowButtonState();
}

class _NavArrowButtonState extends State<_NavArrowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: widget.compact ? 22 : 24,
          height: widget.compact ? 22 : 24,
          decoration: BoxDecoration(
            color: enabled && _hovered
                ? const Color(0xFF48484A)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            widget.icon,
            size: widget.compact ? 16 : 18,
            color: enabled
                ? (_hovered ? const Color(0xFFEEEEF0) : const Color(0xFFB0B0B5))
                : const Color(0xFF38383A),
          ),
        ),
      ),
    );
  }
}

class _CloseWidgetButton extends StatefulWidget {
  const _CloseWidgetButton({required this.onPressed, required this.compact});
  final VoidCallback onPressed;
  final bool compact;

  @override
  State<_CloseWidgetButton> createState() => _CloseWidgetButtonState();
}

class _CloseWidgetButtonState extends State<_CloseWidgetButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Tooltip(
          message: 'Close widget',
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: widget.compact ? 22 : 24,
            height: widget.compact ? 22 : 24,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF5A2A2A)
                  : const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _hovered ? const Color(0xFFFF453A) : const Color(0xFF48484A),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.close_rounded,
              size: widget.compact ? 13 : 15,
              color: _hovered
                  ? const Color(0xFFFF6961)
                  : const Color(0xFFA0A0A5),
            ),
          ),
        ),
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
            width: widget.compact ? 22 : 24,
            height: widget.compact ? 22 : 24,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF48484A)
                  : const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF48484A), width: 1),
            ),
            child: Icon(
              Icons.open_in_full_rounded,
              size: widget.compact ? 12 : 14,
              color: _hovered
                  ? const Color(0xFFEEEEF0)
                  : const Color(0xFFA0A0A5),
            ),
          ),
        ),
      ),
    );
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


