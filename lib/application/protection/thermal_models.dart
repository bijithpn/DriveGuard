/// Escalation ladder used by the thermal protection engine.
enum ThermalStage { nominal, elevated, danger, emergency }

enum ThermalCauseKind {
  heavyWrites,
  memoryPressure,
  heavyReads,
  saturatedDrive,
  nearlyFull,
  cpuLoad,
  rapidRise,
  poorAirflow,
}

/// One running process, as seen by the platform process sampler.
class ProcessSample {
  const ProcessSample({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    this.user,
    this.rssBytes,
    this.writeBytesPerSecond,
  });

  final int pid;
  final String name;
  final double cpuPercent;
  final String? user;

  /// Resident memory in bytes, when the platform reports it.
  final int? rssBytes;

  /// Measured disk write rate. Only available where the OS exposes
  /// per-process I/O (Linux, Windows) — never guessed.
  final double? writeBytesPerSecond;
}

enum ProcessSort { cpu, memory, write }

/// Outcome of asking a process to quit.
enum QuitResult { quit, stillRunning, denied, failed, notAllowed }

/// System memory picture, including swap — heavy swapping means constant
/// SSD writes, which is one of the biggest avoidable sources of SSD wear.
class MemorySnapshot {
  const MemorySnapshot({
    required this.totalBytes,
    required this.availableBytes,
    this.swapUsedBytes,
    this.swapTotalBytes,
  });

  final int totalBytes;
  final int availableBytes;
  final int? swapUsedBytes;
  final int? swapTotalBytes;

  double get availablePercent =>
      totalBytes == 0 ? 100 : availableBytes / totalBytes * 100;
  double get usedPercent => 100 - availablePercent;
}

enum ResourceAlertKind { memoryPressure, heavySwap, heavyWrites }

enum ResourceSeverity { warning, critical }

/// An ongoing, user-actionable system condition that is hurting (or about to
/// hurt) the SSD. Shown in the dashboard until it clears.
class ResourceAlert {
  const ResourceAlert({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    this.culprit,
    this.advice = const [],
  });

  final String id;
  final ResourceAlertKind kind;
  final ResourceSeverity severity;
  final String title;
  final String detail;
  final ProcessSample? culprit;
  final List<String> advice;
}

/// Why a drive is hot, ranked by how likely each factor is the main cause.
class ThermalCause {
  const ThermalCause({
    required this.kind,
    required this.headline,
    required this.detail,
    this.secondary = const [],
    this.culprit,
    this.culpritMeasured = false,
    this.advice = const [],
  });

  final ThermalCauseKind kind;

  /// Short, user-facing sentence: "Sustained heavy writes (412 MB/s)".
  final String headline;
  final String detail;

  /// Other contributing factors, most significant first.
  final List<String> secondary;

  /// Process most likely responsible, when one can be identified.
  final ProcessSample? culprit;

  /// True when the process was *measured* doing the work (per-process write
  /// rate); false when it is only the busiest process by CPU/memory.
  final bool culpritMeasured;
  final List<String> advice;
}

class ThermalAssessment {
  const ThermalAssessment({
    required this.stage,
    required this.celsius,
    this.slopePerMinute,
    this.secondsToEmergency,
    this.reason,
  });

  final ThermalStage stage;
  final double celsius;
  final double? slopePerMinute;
  final int? secondsToEmergency;

  /// Why the stage was chosen (sustained reading, prediction, ...).
  final String? reason;
}

/// Snapshot published to the UI.
class ThermalProtectionState {
  const ThermalProtectionState({
    this.stage = ThermalStage.nominal,
    this.deviceId,
    this.deviceName,
    this.celsius,
    this.cause,
    this.countdown,
    this.shutdownScheduled = false,
    this.message,
  });

  static const idle = ThermalProtectionState();

  final ThermalStage stage;
  final String? deviceId;
  final String? deviceName;
  final double? celsius;
  final ThermalCause? cause;

  /// Time left before the machine shuts down; null when no shutdown pending.
  final Duration? countdown;
  final bool shutdownScheduled;
  final String? message;

  bool get isActive => stage.index >= ThermalStage.danger.index;
}
