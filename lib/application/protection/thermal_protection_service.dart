import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/storage_activity.dart';
import '../../domain/entities/storage_device.dart';
import '../notifications/notification_service.dart';
import '../prediction/trend_analyzer.dart';
import '../settings/app_settings.dart';
import 'process_controller.dart';
import 'system_actions.dart';
import 'thermal_cause_analyzer.dart';
import 'thermal_guard.dart';
import 'thermal_models.dart';

/// Watches every drive for dangerous heat and reacts in escalating steps:
///
/// 1. **elevated / danger** – work out the cause and attach it to the alerts.
/// 2. **emergency** – tell the user the cause, and if they opted in, start a
///    cancellable shutdown countdown that is re-validated against *fresh*
///    data at the last second.
///
/// Heat is the biggest controllable factor in SSD lifespan, so it acts early,
/// avoids flapping, and never decides on stale data (e.g. after sleep).
class ThermalProtectionService {
  ThermalProtectionService({
    required SystemActions actions,
    required NotificationService notifications,
    ThermalCauseAnalyzer analyzer = const ThermalCauseAnalyzer(),
    DateTime Function()? clock,
    Duration causeRefresh = const Duration(seconds: 30),
    Duration snoozeAfterCancel = const Duration(minutes: 10),
    Duration maxReadingAge = const Duration(seconds: 30),
    Future<void> Function()? beforeShutdown,
  }) : _actions = actions,
       _notifications = notifications,
       _analyzer = analyzer,
       _clock = clock ?? DateTime.now,
       _causeRefresh = causeRefresh,
       _snooze = snoozeAfterCancel,
       _maxReadingAge = maxReadingAge,
       _beforeShutdown = beforeShutdown,
       processes = ProcessController(actions);

  static const _tag = 'ThermalProtection';

  final SystemActions _actions;
  final NotificationService _notifications;
  final ThermalCauseAnalyzer _analyzer;
  final DateTime Function() _clock;
  final Duration _causeRefresh;
  final Duration _snooze;
  final Duration _maxReadingAge;
  final Future<void> Function()? _beforeShutdown;

  /// Shared quit logic (also used by the resource guard).
  final ProcessController processes;

  /// Latest memory picture, fed by the resource guard to improve diagnosis.
  MemorySnapshot? latestMemory;

  final Map<String, ThermalGuard> _guards = {};
  final Map<String, ThermalCause> _causes = {};
  final Map<String, DateTime> _causeAt = {};
  final Set<String> _causeInFlight = {};
  final Map<String, ThermalStage> _lastStage = {};
  final Map<String, ThermalProtectionState> _deviceStates = {};
  final Map<String, DateTime> _snoozedUntil = {};
  final Map<String, DateTime> _lastNotifiedAt = {};
  final Map<String, double> _latestCelsius = {};
  final Map<String, DateTime> _latestAt = {};
  final Map<String, DateTime> _lastSampleAt = {};
  final Map<String, double> _stressSeconds = {};
  final Map<String, int> _stressNotifiedLevel = {};

  final _controller = StreamController<ThermalProtectionState>.broadcast();
  ThermalProtectionState _state = ThermalProtectionState.idle;
  Timer? _countdownTimer;
  String? _countdownDeviceId;
  DateTime? _shutdownAt;
  bool _disposed = false;

  Stream<ThermalProtectionState> get stream => _controller.stream;
  ThermalProtectionState get state => _state;

  /// True while any drive is at/above its warning level, so the monitor can
  /// poll faster than its idle cadence.
  bool get anyElevated =>
      _lastStage.values.any((s) => s.index >= ThermalStage.elevated.index);
  bool get anyEmergency =>
      _lastStage.values.any((s) => s == ThermalStage.emergency);

  String? causeHeadlineFor(String deviceId) => _causes[deviceId]?.headline;
  ThermalCause? causeFor(String deviceId) => _causes[deviceId];

  ThermalStage stageFor(String deviceId) =>
      _lastStage[deviceId] ?? ThermalStage.nominal;

  /// Minutes this drive has spent at/above its warning temperature since the
  /// app started — long cumulative heat exposure shortens NAND retention.
  double stressMinutesFor(String deviceId) =>
      (_stressSeconds[deviceId] ?? 0) / 60;

  Future<void> onReading({
    required StorageDevice device,
    required double celsius,
    required List<TrendPoint> recent,
    required StorageActivity? activity,
    required AppSettings settings,
  }) async {
    final cfg = settings.thermalProtection;
    if (_disposed) return;
    final id = device.id;
    if (!cfg.enabled) {
      if (_lastStage.containsKey(id)) forget(id);
      return;
    }
    final now = _clock();
    _latestCelsius[id] = celsius;
    _latestAt[id] = now;
    final guard = _guards.putIfAbsent(id, ThermalGuard.new);
    final assessment = guard.assess(
      celsius: celsius,
      recent: recent,
      thresholds: settings.thresholdsFor(id),
      settings: cfg,
    );

    final previous = _lastStage[id] ?? ThermalStage.nominal;
    _lastStage[id] = assessment.stage;
    _accumulateStress(device, assessment, now);

    if (assessment.stage == ThermalStage.nominal) {
      _causes.remove(id);
      _causeAt.remove(id);
      if (previous != ThermalStage.nominal) _onCooled(device, celsius);
      return;
    }

    await _refreshCause(device, assessment, activity);

    if (assessment.stage == ThermalStage.emergency) {
      await _handleEmergency(device, assessment, settings);
    } else {
      if (_countdownDeviceId == id) {
        _cancelCountdown(
          'Temperature fell to ${celsius.toStringAsFixed(0)}°C — shutdown cancelled.',
        );
      }
      _publish(device, assessment);
    }
  }

  /// The sensor stopped answering. We never power off on unknown data, and an
  /// active countdown is cancelled with an explicit explanation.
  void onSensorLost(String deviceId) {
    _latestAt.remove(deviceId);
    if (_countdownDeviceId == deviceId) {
      _cancelCountdown(
        'Lost contact with the temperature sensor — shutdown cancelled. '
        'Check the drive.',
      );
    }
  }

  /// The computer just woke up: temperatures read before sleep are meaningless.
  void onSystemResume() {
    for (final g in _guards.values) {
      g.reset();
    }
    _latestAt.clear();
    _lastSampleAt.clear();
    if (_countdownDeviceId != null) {
      _cancelCountdown('Computer resumed from sleep — shutdown cancelled.');
    }
  }

  void _accumulateStress(
    StorageDevice device,
    ThermalAssessment a,
    DateTime now,
  ) {
    final id = device.id;
    final last = _lastSampleAt[id];
    _lastSampleAt[id] = now;
    if (last == null || a.stage.index < ThermalStage.elevated.index) return;
    final dt = now.difference(last).inSeconds;
    // Ignore gaps (sleep, paused monitoring) so they don't count as heat.
    if (dt <= 0 || dt > 120) return;
    final total = (_stressSeconds[id] ?? 0) + dt;
    _stressSeconds[id] = total;
    final minutes = total / 60;
    final level = minutes >= 120 ? 2 : (minutes >= 30 ? 1 : 0);
    if (level > (_stressNotifiedLevel[id] ?? 0)) {
      _stressNotifiedLevel[id] = level;
      unawaited(
        _notifications.showAdvisory(
          id: 'thermal-stress-$id-$level',
          deviceId: id,
          title: 'Long heat exposure on ${device.displayName}',
          body:
              'This drive has spent ${minutes.toStringAsFixed(0)} minutes '
              'above its warning temperature this session. Sustained heat '
              'shortens SSD data-retention life — reduce load or improve '
              'airflow.',
        ),
      );
    }
  }

  Future<void> _refreshCause(
    StorageDevice device,
    ThermalAssessment assessment,
    StorageActivity? activity,
  ) async {
    final id = device.id;
    final now = _clock();
    final last = _causeAt[id];
    final fresh = last != null && now.difference(last) < _causeRefresh;
    if (fresh || _causeInFlight.contains(id)) return;
    _causeInFlight.add(id);
    _causeAt[id] = now;

    Future<void> work() async {
      try {
        final procs = await _actions.topProcesses(
          limit: 40,
          measureWrites: true,
        );
        latestMemory ??= await _actions.memorySnapshot();
        _causes[id] = _analyzer.analyze(
          device: device,
          celsius: assessment.celsius,
          slopePerMinute: assessment.slopePerMinute,
          activity: activity,
          processes: procs,
          memory: latestMemory,
          currentUser: _actions.currentUser,
          ownPid: _actions.ownPid,
        );
      } catch (e) {
        AppLogger.instance.debug(_tag, 'Cause analysis failed: $e');
      } finally {
        _causeInFlight.remove(id);
      }
    }

    // First diagnosis of an episode is awaited briefly so the very first
    // alert already names the cause; refreshes happen in the background so
    // sampling never stalls the polling loop.
    if (_causes.containsKey(id)) {
      unawaited(work());
    } else {
      await work().timeout(const Duration(seconds: 6), onTimeout: () {});
    }
  }

  Future<void> _handleEmergency(
    StorageDevice device,
    ThermalAssessment a,
    AppSettings settings,
  ) async {
    final id = device.id;
    final cfg = settings.thermalProtection;
    final cause = _causes[id];
    final snoozed = _snoozedUntil[id];
    final isSnoozed = snoozed != null && _clock().isBefore(snoozed);

    final alreadyCounting = _countdownDeviceId == id && _shutdownAt != null;
    if (cfg.shutdownEnabled && !isSnoozed && !alreadyCounting) {
      _startCountdown(device, a, cfg.countdownSeconds, settings);
      await _notify(
        device,
        'Overheating — shutting down in ${cfg.countdownSeconds}s',
        _body(
          a,
          cause,
          'Your computer will shut down to protect the drive. '
          'Open DriveGuard to cancel.',
        ),
        force: true,
      );
    } else if (!alreadyCounting) {
      await _notify(
        device,
        'Drive overheating — act now',
        _body(
          a,
          cause,
          cfg.shutdownEnabled
              ? 'Automatic shutdown is paused for now.'
              : 'Automatic shutdown is off. Stop the activity or shut down to '
                    'avoid damage.',
        ),
      );
    }
    _publish(device, a);
  }

  String _body(ThermalAssessment a, ThermalCause? cause, String action) {
    final b = StringBuffer('${a.celsius.toStringAsFixed(0)}°C');
    if (a.reason != null) b.write(' · ${a.reason}');
    if (cause != null) {
      b.write('\nMain cause: ${cause.headline}');
      final c = cause.culprit;
      if (c != null) {
        b.write(
          '\n${cause.culpritMeasured ? 'Confirmed source' : 'Likely source'}: '
          '${c.name}',
        );
      }
    }
    b.write('\n$action');
    return b.toString();
  }

  Future<void> _notify(
    StorageDevice device,
    String title,
    String body, {
    bool force = false,
  }) async {
    final now = _clock();
    final last = _lastNotifiedAt[device.id];
    if (!force && last != null && now.difference(last) < _causeRefresh * 2) {
      return;
    }
    _lastNotifiedAt[device.id] = now;
    try {
      await _notifications.showThermalProtection(
        deviceId: device.id,
        deviceName: device.displayName,
        title: title,
        body: body,
      );
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Notification failed: $e');
    }
  }

  void _startCountdown(
    StorageDevice device,
    ThermalAssessment a,
    int seconds,
    AppSettings settings,
  ) {
    _countdownTimer?.cancel();
    _countdownDeviceId = device.id;
    _shutdownAt = _clock().add(Duration(seconds: seconds));
    AppLogger.instance.warning(
      _tag,
      'Emergency on ${device.id} at ${a.celsius}°C — shutdown in ${seconds}s',
    );
    _deviceStates[device.id] = ThermalProtectionState(
      stage: ThermalStage.emergency,
      deviceId: device.id,
      deviceName: device.displayName,
      celsius: a.celsius,
      cause: _causes[device.id],
      countdown: Duration(seconds: seconds),
      shutdownScheduled: true,
      message: 'Shutting down in ${seconds}s',
    );
    _recompute();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tick(device, settings.thermalProtection));
    });
  }

  Future<void> _tick(
    StorageDevice device,
    ThermalProtectionSettings cfg,
  ) async {
    final at = _shutdownAt;
    if (at == null || _disposed) return;
    final id = device.id;
    final remaining = at.difference(_clock());
    final celsius = _latestCelsius[id];
    if (remaining <= Duration.zero) {
      _countdownTimer?.cancel();
      _shutdownAt = null;
      _countdownDeviceId = null;

      // Decide only on *fresh* data: a reading from before a sleep/stall
      // must never trigger a power-off.
      final seenAt = _latestAt[id];
      final fresh =
          seenAt != null && _clock().difference(seenAt) <= _maxReadingAge;
      final stillHot =
          fresh &&
          celsius != null &&
          celsius >=
              cfg.emergencyCelsius - ThermalGuard.releaseHysteresisCelsius;
      if (!stillHot) {
        _deviceStates.remove(id);
        _setState(
          ThermalProtectionState(
            message: fresh
                ? 'Drive cooled down — shutdown aborted.'
                : 'No fresh temperature reading — shutdown aborted for safety.',
          ),
        );
        return;
      }
      _setState(
        ThermalProtectionState(
          stage: ThermalStage.emergency,
          deviceId: id,
          deviceName: device.displayName,
          celsius: celsius,
          cause: _causes[id],
          message: 'Shutting down now to protect the drive…',
        ),
      );
      await _performShutdown();
      return;
    }
    _deviceStates[id] = ThermalProtectionState(
      stage: ThermalStage.emergency,
      deviceId: id,
      deviceName: device.displayName,
      celsius: celsius,
      cause: _causes[id],
      countdown: remaining,
      shutdownScheduled: true,
      message: 'Shutting down in ${remaining.inSeconds}s',
    );
    _recompute();
  }

  /// Graceful shutdown first; if the OS refuses (unsaved documents, missing
  /// permission) fall back to the administrator prompt with force-close.
  Future<void> _performShutdown() async {
    try {
      await _beforeShutdown?.call();
    } catch (_) {}
    final ok = await _actions.shutdown();
    if (!ok && _actions.canElevate) {
      AppLogger.instance.warning(_tag, 'Normal shutdown failed — elevating');
      await _actions.shutdown(elevated: true);
    }
  }

  void _cancelCountdown(String message) {
    final id = _countdownDeviceId;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownDeviceId = null;
    _shutdownAt = null;
    if (id != null) _deviceStates.remove(id);
    AppLogger.instance.info(_tag, message);
    _setState(ThermalProtectionState(message: message));
  }

  /// User pressed "Cancel shutdown". Automatic shutdown for that drive is
  /// paused for a while so the dialog does not immediately reappear.
  void cancelShutdown() {
    final id = _countdownDeviceId;
    if (id != null) _snoozedUntil[id] = _clock().add(_snooze);
    _cancelCountdown('Shutdown cancelled. Keep an eye on the temperature.');
  }

  /// User pressed "Shut down now".
  Future<void> shutdownNow() async {
    _countdownTimer?.cancel();
    _shutdownAt = null;
    _countdownDeviceId = null;
    await _performShutdown();
  }

  /// Quits the process identified as the cause. Only called from an explicit
  /// user action. Escalation is the caller's choice: graceful → [force] →
  /// [admin].
  Future<QuitResult> quitCulprit(
    String deviceId, {
    bool force = false,
    bool admin = false,
  }) async {
    final culprit = _causes[deviceId]?.culprit;
    if (culprit == null) return QuitResult.notAllowed;
    final r = await processes.quit(culprit, force: force, admin: admin);
    if (r == QuitResult.quit) _causeAt.remove(deviceId);
    return r;
  }

  void _onCooled(StorageDevice device, double celsius) {
    _deviceStates.remove(device.id);
    if (_countdownDeviceId == device.id) {
      _cancelCountdown(
        'Temperature fell to ${celsius.toStringAsFixed(0)}°C — shutdown cancelled.',
      );
    } else {
      _recompute();
    }
  }

  void _publish(StorageDevice device, ThermalAssessment a) {
    if (_countdownDeviceId == device.id) return; // countdown owns the state
    if (a.stage.index < ThermalStage.danger.index) {
      _deviceStates.remove(device.id);
    } else {
      _deviceStates[device.id] = ThermalProtectionState(
        stage: a.stage,
        deviceId: device.id,
        deviceName: device.displayName,
        celsius: a.celsius,
        cause: _causes[device.id],
        message: a.reason,
      );
    }
    _recompute();
  }

  /// Publishes the single most urgent drive (countdown first, then the
  /// highest stage, then the hottest) so several drives never overwrite each
  /// other's status.
  void _recompute() {
    ThermalProtectionState? best;
    int rank(ThermalProtectionState s) =>
        (s.shutdownScheduled ? 100 : 0) + s.stage.index * 10;
    for (final s in _deviceStates.values) {
      if (best == null ||
          rank(s) > rank(best) ||
          (rank(s) == rank(best) && (s.celsius ?? 0) > (best.celsius ?? 0))) {
        best = s;
      }
    }
    _setState(best ?? ThermalProtectionState.idle);
  }

  void _setState(ThermalProtectionState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void forget(String deviceId) {
    _guards.remove(deviceId);
    _causes.remove(deviceId);
    _causeAt.remove(deviceId);
    _lastStage.remove(deviceId);
    _latestCelsius.remove(deviceId);
    _latestAt.remove(deviceId);
    _deviceStates.remove(deviceId);
    if (_countdownDeviceId == deviceId) {
      _cancelCountdown('Drive removed.');
    } else {
      _recompute();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _countdownTimer?.cancel();
    await _controller.close();
  }
}
