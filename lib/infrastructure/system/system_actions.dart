import 'dart:async';
import 'dart:io';

import '../../application/protection/privileged_runner.dart';
import '../../application/protection/system_actions.dart';
import '../../application/protection/thermal_models.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/safe_process_runner.dart';
import 'os_privileged_runner.dart';
import 'system_parsers.dart';

export 'system_parsers.dart' show parsePsOutput;

/// Real [SystemActions] for macOS, Linux and Windows.
class OsSystemActions implements SystemActions {
  OsSystemActions({
    SafeProcessRunner? runner,
    PrivilegedRunner? privileged,
    String? operatingSystem,
  }) : _runner = runner ?? SafeProcessRunner.instance,
       _priv = privileged ?? OsPrivilegedRunner(),
       _os = operatingSystem ?? Platform.operatingSystem;

  static const _tag = 'OsSystemActions';
  final SafeProcessRunner _runner;
  final PrivilegedRunner _priv;
  final String _os;
  bool? _canElevate;

  @override
  String? get currentUser =>
      Platform.environment['USER'] ?? Platform.environment['USERNAME'];

  @override
  int get ownPid => pid;

  @override
  bool get canElevate => _canElevate ?? true;

  Future<void> _probeElevation() async =>
      _canElevate ??= await _priv.isAvailable;

  // --- Processes -----------------------------------------------------------

  @override
  Future<List<ProcessSample>> topProcesses({
    int limit = 5,
    ProcessSort sort = ProcessSort.cpu,
    bool measureWrites = false,
  }) async {
    try {
      var all = _os == 'windows'
          ? await _windowsProcesses()
          : await _unixProcesses();
      if (measureWrites && _os == 'linux') {
        all = await _withLinuxWriteRates(all);
      }
      int Function(ProcessSample, ProcessSample) cmp = switch (sort) {
        ProcessSort.cpu => (a, b) => b.cpuPercent.compareTo(a.cpuPercent),
        ProcessSort.memory => (a, b) => (b.rssBytes ?? 0).compareTo(
          a.rssBytes ?? 0,
        ),
        ProcessSort.write => (a, b) => (b.writeBytesPerSecond ?? 0).compareTo(
          a.writeBytesPerSecond ?? 0,
        ),
      };
      all.sort(cmp);
      return all.take(limit).toList();
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Process sampling failed: $e');
      return const [];
    }
  }

  Future<List<ProcessSample>> _unixProcesses() async {
    final r = await _runner.run('ps', const [
      '-Ao',
      'pid=,user=,pcpu=,rss=,comm=',
    ], timeout: const Duration(seconds: 4));
    return parsePsOutput(r.stdout, selfPid: pid);
  }

  Future<List<ProcessSample>> _windowsProcesses() async {
    final r = await _runner.run('powershell', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | "
          r"Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } | "
          r"Select-Object IDProcess,PercentProcessorTime,WorkingSet,"
          r"IOWriteBytesPersec,Name | ConvertTo-Csv -NoTypeInformation",
    ], timeout: const Duration(seconds: 8));
    return parseWindowsProcessCsv(r.stdout, selfPid: pid);
  }

  /// Two `/proc/<pid>/io` snapshots one second apart → bytes/s actually sent
  /// to storage. Only readable for our own processes unless run as root.
  Future<List<ProcessSample>> _withLinuxWriteRates(
    List<ProcessSample> procs,
  ) async {
    Map<int, int> snapshot() {
      final out = <int, int>{};
      for (final p in procs) {
        try {
          final v = parseProcIoWriteBytes(
            File('/proc/${p.pid}/io').readAsStringSync(),
          );
          if (v != null) out[p.pid] = v;
        } catch (_) {}
      }
      return out;
    }

    final a = snapshot();
    await Future<void>.delayed(const Duration(seconds: 1));
    final b = snapshot();
    return [
      for (final p in procs)
        (a[p.pid] != null && b[p.pid] != null)
            ? ProcessSample(
                pid: p.pid,
                name: p.name,
                cpuPercent: p.cpuPercent,
                user: p.user,
                rssBytes: p.rssBytes,
                writeBytesPerSecond: (b[p.pid]! - a[p.pid]!).toDouble().clamp(
                  0,
                  double.infinity,
                ),
              )
            : p,
    ];
  }

  @override
  Future<bool> isProcessAlive(int targetPid) async {
    try {
      if (_os == 'windows') {
        final r = await _runner.run('tasklist', [
          '/FI',
          'PID eq $targetPid',
          '/NH',
        ]);
        return r.stdout.contains('$targetPid');
      }
      final r = await _runner.run('kill', [
        '-0',
        '$targetPid',
      ], requireZeroExit: false);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> processName(int targetPid) async {
    try {
      if (_os == 'windows') {
        final r = await _runner.run('tasklist', [
          '/FI',
          'PID eq $targetPid',
          '/FO',
          'CSV',
          '/NH',
        ]);
        final m = RegExp(r'^"([^"]+)"').firstMatch(r.stdout.trim());
        return m?.group(1);
      }
      final r = await _runner.run('ps', [
        '-p',
        '$targetPid',
        '-o',
        'comm=',
      ], requireZeroExit: false);
      final name = r.stdout.trim();
      return name.isEmpty ? null : name.split('/').last;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> terminateProcess(
    int targetPid, {
    bool force = false,
    bool elevated = false,
  }) async {
    if (targetPid <= 1 || targetPid == pid) return false;
    final (exe, args) = _os == 'windows'
        ? ('taskkill', ['/PID', '$targetPid', if (force) '/F'])
        : ('kill', [force ? '-KILL' : '-TERM', '$targetPid']);
    try {
      if (elevated) {
        await _probeElevation();
        return await _priv.run(
          exe,
          args,
          reason:
              'DriveGuard needs administrator permission to stop a process '
              'that is overloading your drive.',
        );
      }
      await _runner.run(exe, args);
      return true;
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Could not stop pid $targetPid: $e');
      return false;
    }
  }

  // --- Memory --------------------------------------------------------------

  @override
  Future<MemorySnapshot?> memorySnapshot() async {
    try {
      switch (_os) {
        case 'linux':
          return parseMeminfo(File('/proc/meminfo').readAsStringSync());
        case 'macos':
          final vm = await _runner.run('vm_stat', const []);
          final mem = await _runner.run('sysctl', const ['-n', 'hw.memsize']);
          String? swap;
          try {
            swap = (await _runner.run('sysctl', const [
              '-n',
              'vm.swapusage',
            ])).stdout;
          } catch (_) {}
          return parseMacMemory(
            vmStat: vm.stdout,
            memsize: mem.stdout,
            swapUsage: swap,
          );
        case 'windows':
          final r = await _runner.run('powershell', const [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            windowsMemoryScript,
          ], timeout: const Duration(seconds: 8));
          return parseWindowsMemory(r.stdout);
      }
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Memory sampling failed: $e');
    }
    return null;
  }

  // --- Shutdown ------------------------------------------------------------

  @override
  Future<bool> shutdown({bool elevated = false}) async {
    AppLogger.instance.warning(_tag, 'Requesting system shutdown');
    try {
      if (elevated) {
        return switch (_os) {
          'windows' => await _priv.run(
            'shutdown',
            const ['/s', '/f', '/t', '5'],
            reason: 'DriveGuard is shutting down to protect your drive.',
          ),
          _ => await _priv.run(
            'shutdown',
            const ['-h', 'now'],
            reason: 'DriveGuard is shutting down to protect your drive.',
          ),
        };
      }
      switch (_os) {
        case 'macos':
          await _runner.run('osascript', const [
            '-e',
            'tell application "System Events" to shut down',
          ], timeout: const Duration(seconds: 20));
        case 'linux':
          try {
            await _runner.run('systemctl', const ['poweroff']);
          } catch (_) {
            await _runner.run('shutdown', const ['-h', 'now']);
          }
        case 'windows':
          await _runner.run('shutdown', const [
            '/s',
            '/f',
            '/t',
            '5',
            '/c',
            'DriveGuard: shutting down to protect the drive from overheating',
          ]);
        default:
          return false;
      }
      return true;
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Shutdown request failed: $e');
      return false;
    }
  }
}
