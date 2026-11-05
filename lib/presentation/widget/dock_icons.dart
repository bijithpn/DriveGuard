import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/enums/storage_enums.dart';

/// SVG artwork used by the floating dock and the mini monitor.
///
/// The SVGs are single-colour line/fill art, so they are tinted at paint time
/// (`srcIn`) to follow the severity / theme colour instead of shipping a
/// variant per colour.
class DockAssets {
  const DockAssets._();

  static const hand = 'assets/svgs/hand_cursor.svg';
  static const generic = 'assets/svgs/drive_generic.svg';

  static String driveFor(StorageDeviceType type) => switch (type) {
    StorageDeviceType.nvme => 'assets/svgs/drive_nvme.svg',
    StorageDeviceType.ssd => 'assets/svgs/drive_ssd.svg',
    StorageDeviceType.hdd => 'assets/svgs/drive_hdd.svg',
    StorageDeviceType.unknown => generic,
  };
}

class DockIcon extends StatelessWidget {
  const DockIcon(this.asset, {super.key, required this.size, this.color});

  /// The drive glyph for [type].
  DockIcon.drive(
    StorageDeviceType type, {
    super.key,
    required this.size,
    this.color,
  }) : asset = DockAssets.driveFor(type);

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? Colors.white;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
