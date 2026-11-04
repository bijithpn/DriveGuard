import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'cleanup_scanner.dart' show SizeResult, measurePath;

/// Measures how much disk space a path uses.
abstract class SizeMeasurer {
  Future<SizeResult> measure(String path, {Duration budget});

  /// How many measurements can usefully run at once.
  int get concurrency;
}

/// Native `du` (macOS / Linux): one optimised C process per folder, run
/// concurrently, never blocking the UI isolate. Reports *allocated* space,
/// which is what deleting actually frees.
class DuMeasurer implements SizeMeasurer {
  DuMeasurer({int? concurrency})
    : concurrency = concurrency ?? Platform.numberOfProcessors.clamp(4, 8);

  @override
  final int concurrency;

  /// True when a usable `du` exists on this machine.
  static Future<bool> available() async {
    if (Platform.isWindows) return false;
    try {
      final r = await Process.run('du', const ['-sk', '.']);
      return r.exitCode == 0 || (r.stdout as String).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SizeResult> measure(
    String path, {
    Duration budget = const Duration(seconds: 30),
  }) async {
    DateTime? modified;
    try {
      modified = (await FileStat.stat(path)).modified;
    } catch (_) {}

    Process? proc;
    try {
      proc = await Process.start('du', ['-sk', '--', path]);
    } catch (_) {
      // Some BSD `du` builds reject `--`; retry without it.
      try {
        proc = await Process.start('du', ['-sk', path]);
      } catch (_) {
        return _dartMeasure(path, budget);
      }
    }
    final out = proc.stdout.transform(utf8.decoder).join();
    unawaited(proc.stderr.drain<void>());
    var timedOut = false;
    final timer = Timer(budget, () {
      timedOut = true;
      proc!.kill();
    });
    await proc.exitCode;
    timer.cancel();
    final text = await out;

    // `du` exits non-zero when some sub-folders are unreadable but still
    // prints the total of what it could read — use it.
    final m = RegExp(r'^(\d+)\s', multiLine: true).firstMatch(text);
    if (m == null) {
      return _dartMeasure(path, budget);
    }
    return SizeResult(int.parse(m.group(1)!) * 1024, 0, modified, timedOut);
  }
}

/// Runs the Dart walk in an isolate. Kept as a standalone function so the
/// isolate closure captures only `path`/`budget` — never a `Process`.
Future<SizeResult> _dartMeasure(String path, Duration budget) =>
    Isolate.run(() => measurePath(path, budget));

/// Pure-Dart fallback (Windows, or no `du`): the directory walk runs in a
/// short-lived isolate so the UI thread never touches the filesystem.
class IsolateMeasurer implements SizeMeasurer {
  IsolateMeasurer({int? concurrency})
    : concurrency = concurrency ?? Platform.numberOfProcessors.clamp(2, 8);

  @override
  final int concurrency;

  @override
  Future<SizeResult> measure(
    String path, {
    Duration budget = const Duration(seconds: 25),
  }) => _dartMeasure(path, budget);
}

SizeMeasurer? _cached;

/// Best measurer for this platform (decided once).
Future<SizeMeasurer> defaultMeasurer() async {
  return _cached ??= await DuMeasurer.available()
      ? DuMeasurer()
      : IsolateMeasurer();
}
