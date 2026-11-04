import 'dart:io';

import 'safe_process_runner.dart';

/// When the operating system last booted, or null if it can't be determined.
///
/// Used to tell "the whole machine restarted" apart from "only DriveGuard
/// stopped" (crash, forced quit, `flutter run` restart).
class BootTime {
  const BootTime._();

  static Future<DateTime?> current() async {
    try {
      if (Platform.isMacOS) {
        final r = await SafeProcessRunner.instance.run('sysctl', [
          '-n',
          'kern.boottime',
        ], timeout: const Duration(seconds: 3));
        final sec = RegExp(r'sec\s*=\s*(\d+)').firstMatch(r.stdout)?.group(1);
        return sec == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(int.parse(sec) * 1000);
      }
      if (Platform.isLinux) {
        final up = double.tryParse(
          (await File('/proc/uptime').readAsString()).split(' ').first,
        );
        return up == null
            ? null
            : DateTime.now().subtract(Duration(seconds: up.round()));
      }
      if (Platform.isWindows) {
        final r = await SafeProcessRunner.instance.run('powershell', [
          '-NoProfile',
          '-Command',
          '[DateTimeOffset]::new((Get-CimInstance Win32_OperatingSystem)'
              '.LastBootUpTime).ToUnixTimeSeconds()',
        ], timeout: const Duration(seconds: 8));
        final sec = int.tryParse(r.stdout.trim());
        return sec == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      }
    } catch (_) {}
    return null;
  }
}
