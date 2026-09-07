import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';




















class NativeWidgetBridge {
  NativeWidgetBridge._();

  static const _channel = MethodChannel('driveguard/native_widget');
  static const _tag = 'NativeWidgetBridge';
  static const _snapshotFileName = 'widget_snapshot.json';

  static bool get _isMacOS => Platform.isMacOS;
  static bool get _writesSnapshotFile => Platform.isWindows || Platform.isLinux;

  static bool get isSupported => _isMacOS || _writesSnapshotFile;

  static Future<void> pushSnapshot(MiniWidgetSnapshot snapshot) async {
    if (!isSupported) return;
    final json = jsonEncode({
      'devices': snapshot.devices
          .map(
            (d) => {
              'id': d.id,
              'name': d.name,
              'valueText': d.valueText,
              'fraction': d.fraction,
              'severity': d.severity.name,
            },
          )
          .toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    if (_isMacOS) {
      try {
        await _channel.invokeMethod('updateSnapshot', json);
      } catch (e) {
        
        
        AppLogger.instance.warning(
          _tag,
          'Failed pushing native widget snapshot: $e',
        );
      }
      return;
    }

    if (_writesSnapshotFile) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        final dir = Directory(p.join(supportDir.path, 'driveguard'));
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        final file = File(p.join(dir.path, _snapshotFileName));
        
        
        
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(file.path);
      } catch (e) {
        AppLogger.instance.warning(
          _tag,
          'Failed writing native widget snapshot file: $e',
        );
      }
    }
  }
}
