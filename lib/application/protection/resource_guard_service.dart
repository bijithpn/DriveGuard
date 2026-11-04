import 'dart:async';
import 'dart:collection';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import '../notifications/notification_service.dart';
import '../settings/app_settings.dart';
import 'process_controller.dart';
import 'system_actions.dart';
import 'thermal_models.dart';

const _gb = 1024 * 1024 * 1024;
const _mb = 1024 * 1024;

/// Pure memory/swap classification so the thresholds are easy to test.
class MemoryAssessment {
  const MemoryAssessment(this.severity, this.kind, this.summary);
  final ResourceSeverity? severity;
  final ResourceAlertKind? kind;
  final String summary;
}

/// [swapGrowthBytesPerMin] is how fast swap usage is rising right now.
/// [active] applies hysteresis: an existing alert needs a clear recovery
/// before it is withdrawn, so it doesn't flicker.
MemoryAssessment assessMemory(
  MemorySnapshot m, {
  double swapGrowthBytesPerMin = 0,
  bool active = false,
}) {
  final avail = m.availablePercent;
  final swap = m.swapUsedBytes ?? 0;
  final growing = swapGrowthBytesPerMin >= 200 * _mb;
  final bigSwap = swap >= 4 * _gb || swap >= m.totalBytes * 0.5;

  final critical = avail < 5 || (swap >= 8 * _gb && (growing || avail < 10));
  final warning =
      avail < 10 || growing && swap >= 1 * _gb || (bigSwap && avail < 20);
  final holdOn = active && (avail < 15 || growing || (bigSwap && avail < 25));

  String summary() {
    final swapText = m.swapUsedBytes == null
        ? ''
        : ' ${(swap / _gb).toStringAsFixed(1)} GB is swapped to the SSD.';
    return '${avail.toStringAsFixed(0)}% of memory is available.$swapText';
  }

  if (critical) {
    return MemoryAssessment(
      ResourceSeverity.critical,
      avail < 5
          ? ResourceAlertKind.memoryPressure
          : ResourceAlertKind.heavySwap,
      summary(),
    );
  }
  if (warning || holdOn) {
    return MemoryAssessment(
      ResourceSeverity.warning,
      avail < 15
          ? ResourceAlertKind.memoryPressure
          : ResourceAlertKind.heavySwap,
      summary(),
    );
  }
  return MemoryAssessment(null, null, summary());
}

/// Watches the conditions that quietly wear an SSD out — running out of RAM
/// (constant swapping) and heavy sustained writing — and tells the user which
/// app is responsible, with one-tap quit actions.
///
/// It is deliberately cheap: one small sample per minute (slower when the
/// window is hidden, faster only while an alert is active), no sampling at all
/// when the user turns it off.
class ResourceGuardService {
  ResourceGuardService({
    required SystemActions actions,
    required NotificationService notifications,
    required List<StorageDevice> Function() devices,
    required AppSettings Function() settings,
    ProcessController? processes,
    DateTime Function()? clock,
    this.baseInterval = const Duration(seconds: 60),
    this.onMemory,
  }) : _actions = actions,
       _notifications = notifications,
       _devices = devices,
       _settings = settings,
       _clock = clock ?? DateTime.now,
       processes = processes ?? ProcessController(actions);

  static const _tag = 'ResourceGuard';

  /// Sustained average write rate that we treat as "heavy" for an SSD.
  static const double heavyWriteBytesPerSec = 25.0 * _mb;
  static const double heavyWriteClearBytesPerSec = 12.0 * _mb;
  static const Duration writeWindow = Duration(minutes: 10);
  static const Duration minWriteCoverage = Duration(minutes: 5);

  final SystemActions _actions;
  final NotificationService _notifications;
  final List<StorageDevice> Function() _devices;
  final AppSettings Function() _settings;
  final DateTime Function() _clock;
  final ProcessController processes;
  final Duration baseInterval;
  final void Function(MemorySnapshot)? onMemory;

  Timer? _timer;
  bool _started = false;
  bool _uiActive = true;
  bool _ticking = false;
  bool _disposed = false;

  final Queue<(DateTime, int)> _swapHistory = Queue();
  final Map<String, Queue<_Bucket>> _writes = {};
  final Map<String, DateTime> _lastActivityAt = {};
  final Map<String, ResourceAlert> _active = {};
  final Map<String, DateTime> _notifiedAt = {};
  final Map<String, ResourceSeverity> _notifiedSeverity = {};

  final _controller = StreamController<List<ResourceAlert>>.broadcast();
  Stream<List<ResourceAlert>> get stream => _controller.stream;
  List<ResourceAlert> get current => _active.values.toList(growable: false);
  MemorySnapshot? latestMemory;

  void start() {
    if (_started) return;
    _started = true;
    _schedule();
  }

  void setUiActive(bool active) {
    if (_uiActive == active) return;
    _uiActive = active;
    if (_started) _schedule();
  }

  Duration get _interval {
    var d = baseInterval;
    if (!_uiActive) d *= 2;
    if (_active.isNotEmpty) d = Duration(seconds: (d.inSeconds / 2).round());
    return d;
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(_interval, () async {
      await tick();
      _schedule();
    });
  }

  /// Integrates drive write throughput into per-minute buckets. Called for
  /// every activity sample; O(1) and allocation-light.
  void recordActivity(StorageActivity a) {
    final rate = a.writeBytesPerSecond;
    if (rate == null || rate < 0) return;
    final last = _lastActivityAt[a.deviceId];
    _lastActivityAt[a.deviceId] = a.timestamp;
    if (last == null) return;
    final dt = a.timestamp.difference(last).inMilliseconds / 1000.0;
    if (dt <= 0 || dt > 15) return; // ignore gaps (sleep, paused)
    final q = _writes.putIfAbsent(a.deviceId, Queue.new);
    final minute = DateTime(
      a.timestamp.year,
      a.timestamp.month,
      a.timestamp.day,
      a.timestamp.hour,
      a.timestamp.minute,
    );
    if (q.isNotEmpty && q.last.minute == minute) {
      q.last
        ..bytes += rate * dt
        ..seconds += dt;
    } else {
      q.add(
        _Bucket(minute)
          ..bytes = rate * dt
          ..seconds = dt,
      );
    }
    final cutoff = a.timestamp.subtract(
      writeWindow + const Duration(minutes: 1),
    );
    while (q.isNotEmpty && q.first.minute.isBefore(cutoff)) {
      q.removeFirst();
    }
  }

  /// Average write rate over the window, or null without enough coverage.
  double? averageWriteRate(String deviceId, {DateTime? now}) {
    final q = _writes[deviceId];
    if (q == null || q.isEmpty) return null;
    final cutoff = (now ?? _clock()).subtract(writeWindow);
    var bytes = 0.0;
    var seconds = 0.0;
    for (final b in q) {
      if (b.minute.isBefore(cutoff)) continue;
      bytes += b.bytes;
      seconds += b.seconds;
    }
    if (seconds < minWriteCoverage.inSeconds) return null;
    return bytes / seconds;
  }

  Future<void> tick() async {
    if (_ticking || _disposed) return;
    final settings = _settings();
    if (!settings.resourceGuardEnabled || !settings.monitoringEnabled) {
      if (_active.isNotEmpty) {
        _active.clear();
        _emit();
      }
      return;
    }
    _ticking = true;
    try {
      await _checkMemory(settings);
      await _checkWrites(settings);
      _emit();
    } catch (e) {
      AppLogger.instance.debug(_tag, 'Tick failed: $e');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _checkMemory(AppSettings settings) async {
    final mem = await _actions.memorySnapshot();
    if (mem == null) return;
    latestMemory = mem;
    onMemory?.call(mem);

    final now = _clock();
    if (mem.swapUsedBytes != null) {
      _swapHistory.addLast((now, mem.swapUsedBytes!));
      while (_swapHistory.isNotEmpty &&
          now.difference(_swapHistory.first.$1) > const Duration(minutes: 6)) {
        _swapHistory.removeFirst();
      }
    }
    var growth = 0.0;
    if (_swapHistory.length >= 3) {
      final first = _swapHistory.first;
      final last = _swapHistory.last;
      final mins = last.$1.difference(first.$1).inSeconds / 60;
      if (mins >= 2) growth = (last.$2 - first.$2) / mins;
    }

    final a = assessMemory(
      mem,
      swapGrowthBytesPerMin: growth,
      active: _active.containsKey('memory'),
    );
    if (a.severity == null) {
      if (_active.remove('memory') != null) {
        _notifiedAt.remove('memory');
        _notifiedSeverity.remove('memory');
      }
      return;
    }

    final top = await _actions.topProcesses(limit: 8, sort: ProcessSort.memory);
    ProcessSample? culprit;
    for (final p in top) {
      if (processes.accessFor(p) != KillAccess.never) {
        culprit = p;
        break;
      }
    }
    final culpritText = culprit?.rssBytes == null
        ? ''
        : ' Biggest memory user: ${culprit!.name} '
              '(${(culprit.rssBytes! / _gb).toStringAsFixed(1)} GB).';

    final critical = a.severity == ResourceSeverity.critical;
    final alert = ResourceAlert(
      id: 'memory',
      kind: a.kind!,
      severity: a.severity!,
      title: critical ? 'Memory is almost full' : 'Memory is running low',
      detail:
          '${a.summary} When RAM runs out the system keeps writing memory '
          'pages to your SSD, which slows everything down and wears the '
          'drive.$culpritText',
      culprit: culprit,
      advice: const [
        'Quit the biggest memory user or close unused apps and browser tabs.',
        'Restart apps that have been running for days — they leak memory.',
        'If this is routine, more RAM is the best way to protect the SSD.',
      ],
    );
    _active['memory'] = alert;
    await _notifyOnce('memory', alert);
  }

  Future<void> _checkWrites(AppSettings settings) async {
    final seen = <String>{};
    for (final d in _devices()) {
      if (d.type != StorageDeviceType.ssd && d.type != StorageDeviceType.nvme) {
        continue;
      }
      final id = 'writes:${d.id}';
      seen.add(id);
      final avg = averageWriteRate(d.id);
      final wasActive = _active.containsKey(id);
      final limit = wasActive
          ? heavyWriteClearBytesPerSec
          : heavyWriteBytesPerSec;
      if (avg == null || avg < limit) {
        if (_active.remove(id) != null) {
          _notifiedAt.remove(id);
          _notifiedSeverity.remove(id);
        }
        continue;
      }
      final procs = await _actions.topProcesses(
        limit: 40,
        sort: ProcessSort.write,
        measureWrites: true,
      );
      ProcessSample? writer;
      for (final p in procs) {
        if ((p.writeBytesPerSecond ?? 0) >= 5 * _mb &&
            processes.accessFor(p) != KillAccess.never) {
          writer = p;
          break;
        }
      }
      final tenMinGb = avg * writeWindow.inSeconds / _gb;
      final measurable = procs.any((p) => p.writeBytesPerSecond != null);
      final alert = ResourceAlert(
        id: id,
        kind: ResourceAlertKind.heavyWrites,
        severity: avg >= heavyWriteBytesPerSec * 3
            ? ResourceSeverity.critical
            : ResourceSeverity.warning,
        title: 'Heavy sustained writing to ${d.displayName}',
        detail:
            'About ${tenMinGb.toStringAsFixed(1)} GB written in the last '
            '10 minutes (${(avg / _mb).toStringAsFixed(0)} MB/s average). '
            'Constant heavy writing uses up SSD lifespan and raises its '
            'temperature.'
            '${writer != null ? ' Confirmed source: ${writer.name}.' : ''}'
            '${writer == null && !measurable ? ' This OS does not report per-app disk writes — check Activity Monitor → Disk (macOS) to find the app.' : ''}',
        culprit: writer,
        advice: const [
          'Pause the backup, download, render, VM or database job that is running.',
          'Move scratch/cache folders and downloads to a secondary drive or RAM disk.',
          'Schedule big jobs in batches so the drive can rest and cool.',
        ],
      );
      _active[id] = alert;
      await _notifyOnce(id, alert);
    }
    // Drive disappeared: drop its alert.
    _active.removeWhere((k, _) => k.startsWith('writes:') && !seen.contains(k));
  }

  Future<void> _notifyOnce(String id, ResourceAlert alert) async {
    final now = _clock();
    final lastAt = _notifiedAt[id];
    final lastSev = _notifiedSeverity[id];
    final escalated = lastSev != null && alert.severity.index > lastSev.index;
    final reminder =
        lastAt != null && now.difference(lastAt) >= const Duration(minutes: 30);
    if (lastAt != null && !escalated && !reminder) return;
    _notifiedAt[id] = now;
    _notifiedSeverity[id] = alert.severity;
    if (!_settings().notificationsEnabled) return;
    final body = StringBuffer(alert.detail);
    final c = alert.culprit;
    if (c != null) body.write('\nOpen DriveGuard to quit ${c.name}.');
    try {
      await _notifications.showAdvisory(
        id: id,
        title: alert.title,
        body: body.toString(),
        urgent: alert.severity == ResourceSeverity.critical,
      );
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Notification failed: $e');
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  /// Called after a quit action so the banner refreshes promptly.
  Future<void> refreshSoon() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!_disposed) await tick();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _controller.close();
  }
}

class _Bucket {
  _Bucket(this.minute);
  final DateTime minute;
  double bytes = 0;
  double seconds = 0;
}
