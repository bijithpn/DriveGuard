import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/widget/mini_widget_snapshot.dart';
import '../../core/logging/app_logger.dart';

/// Pushes drive data into an OS-native widget surface, independently of the
/// in-app "mini monitor" floating window (`DesktopWindowController`/
/// `MiniWidgetApp`): a native widget is hosted entirely by the OS or desktop
/// shell, keeps showing the last pushed snapshot even if DriveGuard isn't
/// running at all, and has no window of its own to open, close, or crash
/// alongside the app.
///
/// Two delivery mechanisms, chosen per-platform by what the OS widget host
/// can actually read:
///
/// - **macOS**: pushed over a `MethodChannel` into a shared App Group
///   container, because the WidgetKit extension is sandboxed and can't see
///   arbitrary files. See `macos/Runner/StorageMonitor/NativeWidgetChannel.swift`.
/// - **Windows / Linux**: written straight to a JSON file in the same
///   per-user data directory `AppDatabase` already uses
///   (`<applicationSupportDir>/driveguard/widget_snapshot.json`). No native
///   plugin code needed to *write* it - a widget host reads that file
///   directly. See `NATIVE_WIDGETS.md` for the Windows Widgets Board / GNOME
///   Shell extension that reads it.
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
        // Fire-and-forget: the widget just keeps its last snapshot if this
        // fails (e.g. App Group not provisioned yet in a dev build).
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
        // Write to a temp file then rename: readers (a GNOME Shell
        // extension's file monitor, a Windows widget provider) never see a
        // half-written file this way.
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
