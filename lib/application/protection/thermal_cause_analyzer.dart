import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import 'process_controller.dart';
import 'thermal_models.dart';

/// Works out *why* a drive is hot from what the OS tells us: drive I/O
/// throughput, per-process writes (Linux/Windows), memory pressure and
/// swapping, drive fullness, rate of temperature rise and the busiest
/// processes. Pure (no I/O) so it is trivially testable.
///
/// It only reports a culprit it can support: a process that was *measured*
/// writing is "confirmed"; otherwise the busiest process is offered as
/// "likely" and only when it is genuinely busy.
class ThermalCauseAnalyzer {
  const ThermalCauseAnalyzer();

  static const double _heavyWriteNvme = 150 * 1024 * 1024;
  static const double _heavyWriteOther = 50 * 1024 * 1024;
  static const double _saturationPercent = 90;
  static const double _nearlyFullPercent = 90;
  static const double _busyProcessCpu = 60;
  static const double _quietIo = 10 * 1024 * 1024;
  static const double _measuredWriterMin = 5 * 1024 * 1024;

  ThermalCause analyze({
    required StorageDevice device,
    required double celsius,
    required double? slopePerMinute,
    required StorageActivity? activity,
    required List<ProcessSample> processes,
    MemorySnapshot? memory,
    String? currentUser,
    int? ownPid,
  }) {
    final write = activity?.writeBytesPerSecond;
    final read = activity?.readBytesPerSecond;
    final util = activity?.utilizationPercent;
    final usage = device.capacity.usagePercent;

    final writeLimit =
        device.type == StorageDeviceType.nvme ||
            device.interfaceType == StorageInterfaceType.nvme
        ? _heavyWriteNvme
        : _heavyWriteOther;

    bool allowed(ProcessSample p) =>
        killAccess(p, currentUser: currentUser, ownPid: ownPid) !=
        KillAccess.never;

    // Best-supported "who": a measured writer beats a CPU guess.
    ProcessSample? measuredWriter;
    for (final p in processes) {
      final w = p.writeBytesPerSecond;
      if (w != null &&
          w >= _measuredWriterMin &&
          allowed(p) &&
          (measuredWriter == null ||
              w > (measuredWriter.writeBytesPerSecond ?? 0))) {
        measuredWriter = p;
      }
    }
    ProcessSample? busiestCpu;
    for (final p in processes) {
      if (allowed(p) &&
          (busiestCpu == null || p.cpuPercent > busiestCpu.cpuPercent)) {
        busiestCpu = p;
      }
    }
    final cpuGuess = busiestCpu != null && busiestCpu.cpuPercent >= 25
        ? busiestCpu
        : null;
    ProcessSample? biggestMemory;
    for (final p in processes) {
      if (allowed(p) &&
          (biggestMemory == null ||
              (p.rssBytes ?? 0) > (biggestMemory.rssBytes ?? 0))) {
        biggestMemory = p;
      }
    }

    final factors = <_Factor>[];

    if (write != null && write >= writeLimit) {
      factors.add(
        _Factor(
          ThermalCauseKind.heavyWrites,
          100 + write / writeLimit,
          measuredWriter != null
              ? 'Heavy disk writes (${_rate(write)}) from ${measuredWriter.name}'
              : 'Sustained heavy writes (${_rate(write)})',
          'The drive is being written to continuously, which keeps the '
          'controller and NAND under constant load.',
          culprit: measuredWriter ?? cpuGuess,
          measured: measuredWriter != null,
        ),
      );
    }

    final mem = memory;
    if (mem != null) {
      final swapGb = (mem.swapUsedBytes ?? 0) / (1024 * 1024 * 1024);
      if (mem.availablePercent < 10 || swapGb >= 4) {
        factors.add(
          _Factor(
            ThermalCauseKind.memoryPressure,
            90 + (100 - mem.availablePercent) / 10,
            'Low memory — ${swapGb.toStringAsFixed(1)} GB swapped to the SSD',
            'When RAM runs out the system pages memory to the SSD '
                'continuously, adding writes, heat and wear.',
            culprit: biggestMemory,
          ),
        );
      }
    }

    if (read != null && read >= writeLimit * 1.5) {
      factors.add(
        _Factor(
          ThermalCauseKind.heavyReads,
          80 + read / (writeLimit * 1.5),
          'Sustained heavy reads (${_rate(read)})',
          'Large continuous reads (copying, indexing, scanning or '
              'rendering) are keeping the controller busy.',
          culprit: cpuGuess,
        ),
      );
    }
    if (util != null && util >= _saturationPercent) {
      factors.add(
        _Factor(
          ThermalCauseKind.saturatedDrive,
          70 + util / 10,
          'Drive is saturated (${util.toStringAsFixed(0)}% busy)',
          'The drive has no idle time to shed heat.',
          culprit: measuredWriter ?? cpuGuess,
          measured: measuredWriter != null,
        ),
      );
    }
    if (usage != null && usage >= _nearlyFullPercent) {
      factors.add(
        _Factor(
          ThermalCauseKind.nearlyFull,
          50 + usage / 10,
          'Drive is ${usage.toStringAsFixed(0)}% full',
          'A nearly full SSD has little room for garbage collection and '
              'wear levelling, so it works harder (and hotter) for every write.',
        ),
      );
    }
    if (busiestCpu != null && busiestCpu.cpuPercent >= _busyProcessCpu) {
      factors.add(
        _Factor(
          ThermalCauseKind.cpuLoad,
          60 + busiestCpu.cpuPercent / 10,
          'Heavy system load from ${busiestCpu.name} '
              '(${busiestCpu.cpuPercent.toStringAsFixed(0)}% CPU)',
          'High CPU/GPU load heats the whole enclosure, and the drive '
              'soaks up that heat.',
          culprit: busiestCpu,
        ),
      );
    }
    if (slopePerMinute != null && slopePerMinute >= 2) {
      factors.add(
        _Factor(
          ThermalCauseKind.rapidRise,
          40 + slopePerMinute,
          'Temperature rising ${slopePerMinute.toStringAsFixed(1)}°C/min',
          'Heat is building faster than the drive can shed it.',
        ),
      );
    }

    final quiet = (write ?? 0) < _quietIo && (read ?? 0) < _quietIo;
    final onlyRise =
        factors.length == 1 && factors.first.kind == ThermalCauseKind.rapidRise;
    if (factors.isEmpty || (quiet && onlyRise)) {
      factors.add(
        _Factor(
          ThermalCauseKind.poorAirflow,
          30,
          'Poor cooling or high ambient temperature',
          'The drive is hot while barely being used, which points to '
              'airflow, a missing heatsink, or a hot enclosure.',
        ),
      );
    }

    factors.sort((a, b) => b.score.compareTo(a.score));
    final primary = factors.first;

    return ThermalCause(
      kind: primary.kind,
      headline: primary.headline,
      detail: primary.detail,
      secondary: [for (final f in factors.skip(1)) f.headline],
      culprit: primary.culprit,
      culpritMeasured: primary.measured,
      advice: _advice(primary.kind),
    );
  }

  static List<String> _advice(ThermalCauseKind kind) {
    switch (kind) {
      case ThermalCauseKind.heavyWrites:
      case ThermalCauseKind.heavyReads:
      case ThermalCauseKind.saturatedDrive:
        return const [
          'Pause the large copy, download, backup or render that is running.',
          'Resume it later in smaller batches so the drive can cool between them.',
        ];
      case ThermalCauseKind.memoryPressure:
        return const [
          'Quit the biggest memory user or close unused apps and browser tabs.',
          'Adding RAM is the long-term fix — it stops constant swapping to the SSD.',
        ];
      case ThermalCauseKind.nearlyFull:
        return const [
          'Free up space in Storage Sense — keep at least 15–20% free.',
          'More free space lets the SSD spread wear and run cooler.',
        ];
      case ThermalCauseKind.cpuLoad:
        return const [
          'Close or pause the busy application.',
          'Check that the vents are clear and fans are running.',
        ];
      case ThermalCauseKind.rapidRise:
        return const [
          'Stop heavy work now and let the system idle for a few minutes.',
        ];
      case ThermalCauseKind.poorAirflow:
        return const [
          'Improve airflow: clear vents, raise the laptop, add a heatsink.',
          'Move the machine away from direct sun or other heat sources.',
        ];
    }
  }

  static String _rate(double bytesPerSecond) {
    final mb = bytesPerSecond / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB/s';
    return '${mb.toStringAsFixed(0)} MB/s';
  }
}

class _Factor {
  _Factor(
    this.kind,
    this.score,
    this.headline,
    this.detail, {
    this.culprit,
    this.measured = false,
  });
  final ThermalCauseKind kind;
  final double score;
  final String headline;
  final String detail;
  final ProcessSample? culprit;
  final bool measured;
}
