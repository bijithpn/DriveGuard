import 'dart:convert';
import 'dart:io';

import '../../application/protection/privileged_runner.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';

/// Elevation via the platform's native prompt.
class OsPrivilegedRunner implements PrivilegedRunner {
  OsPrivilegedRunner({SafeProcessRunner? runner, String? operatingSystem})
    : _runner = runner ?? SafeProcessRunner.instance,
      _os = operatingSystem ?? Platform.operatingSystem;

  static const _tag = 'PrivilegedRunner';
  static const _promptTimeout = Duration(minutes: 2);
  final SafeProcessRunner _runner;
  final String _os;

  @override
  Future<bool> get isAvailable async {
    switch (_os) {
      case 'macos':
        return _runner.exists('osascript');
      case 'linux':
        return _runner.exists('pkexec');
      case 'windows':
        return _runner.exists('powershell');
    }
    return false;
  }

  @override
  Future<bool> run(
    String executable,
    List<String> args, {
    required String reason,
  }) async {
    if (!await isAvailable) return false;
    for (final a in [executable, ...args]) {
      if (a.contains('\u0000') || a.contains('\n') || a.contains('\r')) {
        AppLogger.instance.warning(_tag, 'Rejected unsafe argument');
        return false;
      }
    }
    try {
      switch (_os) {
        case 'macos':
          final r = await _runner.run('osascript', [
            '-e',
            buildMacScript(executable, args, reason),
          ], timeout: _promptTimeout);
          return r.exitCode == 0;
        case 'linux':
          final r = await _runner.run('pkexec', [
            executable,
            ...args,
          ], timeout: _promptTimeout);
          return r.exitCode == 0;
        case 'windows':
          final r = await _runner.run('powershell', [
            '-NoProfile',
            '-NonInteractive',
            '-EncodedCommand',
            encodePowerShell(buildWindowsScript(executable, args)),
          ], timeout: _promptTimeout);
          return r.exitCode == 0;
      }
    } catch (e) {
      // Declined prompt, timeout or command failure.
      AppLogger.instance.info(_tag, 'Elevated command did not complete: $e');
    }
    return false;
  }

  /// AppleScript that runs the shell-quoted command with an admin prompt.
  static String buildMacScript(
    String executable,
    List<String> args,
    String reason,
  ) {
    String shq(String s) => "'${s.replaceAll("'", r"'\''")}'";
    String asq(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final cmd = [executable, ...args].map(shq).join(' ');
    return 'do shell script "${asq(cmd)}" with prompt "${asq(reason)}" '
        'with administrator privileges';
  }

  /// PowerShell that starts [executable] elevated (UAC) and propagates its
  /// exit code.
  static String buildWindowsScript(String executable, List<String> args) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final argList = args.isEmpty
        ? ''
        : ' -ArgumentList ${args.map(q).join(',')}';
    return r'$p = Start-Process -FilePath '
        '${q(executable)}$argList -Verb RunAs -Wait -PassThru '
        r'-WindowStyle Hidden; exit $p.ExitCode';
  }

  /// `-EncodedCommand` takes base64 of UTF-16LE, which sidesteps every
  /// quoting problem for scripts and paths containing spaces or quotes.
  static String encodePowerShell(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return base64.encode(bytes);
  }
}
