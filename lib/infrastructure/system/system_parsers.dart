import 'dart:convert';

import '../../application/protection/thermal_models.dart';

/// Pure parsers for OS command output, kept separate so every platform's
/// format can be unit-tested on any machine.

/// `ps -Ao pid=,user=,pcpu=,rss=,comm=` (macOS and Linux).
List<ProcessSample> parsePsOutput(String output, {int? selfPid}) {
  final re = RegExp(r'^\s*(\d+)\s+(\S+)\s+([\d.,]+)\s+(\d+)\s+(.+?)\s*$');
  final samples = <ProcessSample>[];
  for (final line in output.split('\n')) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    final id = int.parse(m.group(1)!);
    if (id == selfPid) continue;
    final cpu = double.tryParse(m.group(3)!.replaceAll(',', '.'));
    final rssKb = int.tryParse(m.group(4)!);
    if (cpu == null) continue;
    final name = m.group(5)!.split('/').last;
    if (name == 'ps') continue;
    samples.add(
      ProcessSample(
        pid: id,
        name: name,
        cpuPercent: cpu,
        user: m.group(2),
        rssBytes: rssKb == null ? null : rssKb * 1024,
      ),
    );
  }
  return samples;
}

/// Windows `Win32_PerfFormattedData_PerfProc_Process` as CSV with columns
/// IDProcess, PercentProcessorTime, WorkingSet, IOWriteBytesPersec, Name.
List<ProcessSample> parseWindowsProcessCsv(String csv, {int? selfPid}) {
  final lines = const LineSplitter()
      .convert(csv)
      .where((l) => l.trim().isNotEmpty);
  if (lines.isEmpty) return const [];
  List<String> cells(String l) =>
      l.split(',').map((c) => c.trim().replaceAll('"', '')).toList();
  final header = cells(lines.first);
  int col(String n) => header.indexOf(n);
  final iPid = col('IDProcess');
  final iCpu = col('PercentProcessorTime');
  final iMem = col('WorkingSet');
  final iIo = col('IOWriteBytesPersec');
  final iName = col('Name');
  if (iPid < 0 || iCpu < 0 || iName < 0) return const [];
  final out = <ProcessSample>[];
  for (final l in lines.skip(1)) {
    final c = cells(l);
    if (c.length <= iName) continue;
    final id = int.tryParse(c[iPid]);
    final cpu = double.tryParse(c[iCpu]);
    if (id == null || cpu == null || id == selfPid || id == 0) continue;
    // "chrome#3" → "chrome"
    final base = c[iName].replaceAll(RegExp(r'#\d+$'), '');
    out.add(
      ProcessSample(
        pid: id,
        name: '$base.exe',
        cpuPercent: cpu,
        rssBytes: iMem >= 0 ? int.tryParse(c[iMem]) : null,
        writeBytesPerSecond: iIo >= 0 ? double.tryParse(c[iIo]) : null,
      ),
    );
  }
  return out;
}

int? _kb(String? v) => v == null ? null : int.tryParse(v);

/// `/proc/meminfo`.
MemorySnapshot? parseMeminfo(String text) {
  final map = <String, int>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line);
    if (m != null) map[m.group(1)!] = int.parse(m.group(2)!);
  }
  final total = _kb(map['MemTotal']?.toString());
  if (total == null || total == 0) return null;
  final avail =
      map['MemAvailable'] ??
      ((map['MemFree'] ?? 0) + (map['Cached'] ?? 0) + (map['Buffers'] ?? 0));
  final swapTotal = map['SwapTotal'];
  final swapFree = map['SwapFree'];
  return MemorySnapshot(
    totalBytes: total * 1024,
    availableBytes: avail * 1024,
    swapTotalBytes: swapTotal == null ? null : swapTotal * 1024,
    swapUsedBytes: (swapTotal != null && swapFree != null)
        ? (swapTotal - swapFree) * 1024
        : null,
  );
}

/// macOS `vm_stat` + `sysctl hw.memsize` + `sysctl vm.swapusage`.
MemorySnapshot? parseMacMemory({
  required String vmStat,
  required String memsize,
  String? swapUsage,
}) {
  final total = int.tryParse(memsize.trim());
  if (total == null || total == 0) return null;
  final pageSize =
      int.tryParse(
        RegExp(r'page size of (\d+) bytes').firstMatch(vmStat)?.group(1) ?? '',
      ) ??
      4096;
  int pages(String label) {
    final m = RegExp('$label:\\s+(\\d+)').firstMatch(vmStat);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  final available =
      (pages('Pages free') +
          pages('Pages inactive') +
          pages('Pages speculative')) *
      pageSize;

  int? swapUsed;
  int? swapTotal;
  if (swapUsage != null) {
    int? mb(String key) {
      final m = RegExp('$key = ([\\d.]+)([MGK])').firstMatch(swapUsage);
      if (m == null) return null;
      final v = double.parse(m.group(1)!);
      final mult = switch (m.group(2)) {
        'G' => 1024 * 1024 * 1024,
        'M' => 1024 * 1024,
        _ => 1024,
      };
      return (v * mult).round();
    }

    swapUsed = mb('used');
    swapTotal = mb('total');
  }
  return MemorySnapshot(
    totalBytes: total,
    availableBytes: available.clamp(0, total),
    swapUsedBytes: swapUsed,
    swapTotalBytes: swapTotal,
  );
}

/// Windows memory JSON (see [windowsMemoryScript]). "Available" memory
/// includes the standby cache, matching Task Manager — WMI's
/// `FreePhysicalMemory` does not, and would raise false low-memory alarms.
MemorySnapshot? parseWindowsMemory(String json) {
  try {
    final d = jsonDecode(json) as Map<String, dynamic>;
    final totalKb = (d['TotalVisibleMemorySize'] as num?)?.toInt();
    if (totalKb == null || totalKb == 0) return null;
    final totalBytes = totalKb * 1024;
    final availBytes =
        (d['AvailableBytes'] as num?)?.toInt() ??
        (((d['FreePhysicalMemory'] as num?)?.toInt() ?? 0) * 1024);

    int? swapUsed;
    int? swapTotal;
    final pfUsedMb = (d['PageFileUsedMB'] as num?)?.toInt();
    final pfTotalMb = (d['PageFileTotalMB'] as num?)?.toInt();
    if (pfUsedMb != null && pfTotalMb != null) {
      swapUsed = pfUsedMb * 1024 * 1024;
      swapTotal = pfTotalMb * 1024 * 1024;
    }
    return MemorySnapshot(
      totalBytes: totalBytes,
      availableBytes: availBytes.clamp(0, totalBytes),
      swapUsedBytes: swapUsed,
      swapTotalBytes: swapTotal,
    );
  } catch (_) {
    return null;
  }
}

/// PowerShell that emits the JSON [parseWindowsMemory] expects.
const windowsMemoryScript =
    r"$os = Get-CimInstance Win32_OperatingSystem; "
    r"$pm = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory; "
    r"$pf = Get-CimInstance Win32_PageFileUsage; "
    r"[pscustomobject]@{ "
    r"TotalVisibleMemorySize = $os.TotalVisibleMemorySize; "
    r"FreePhysicalMemory = $os.FreePhysicalMemory; "
    r"AvailableBytes = $pm.AvailableBytes; "
    r"PageFileUsedMB = [int](($pf | Measure-Object CurrentUsage -Sum).Sum); "
    r"PageFileTotalMB = [int](($pf | Measure-Object AllocatedBaseSize -Sum).Sum) "
    r"} | ConvertTo-Json";

/// Per-pid cumulative bytes written from `/proc/<pid>/io` text.
int? parseProcIoWriteBytes(String text) {
  final m = RegExp(r'^write_bytes:\s+(\d+)', multiLine: true).firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}
