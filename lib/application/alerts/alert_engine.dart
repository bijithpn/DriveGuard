import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';

/// One evaluated alert state transition for a device, independent of the
/// UI (section 8) - the UI/notification layer reacts to this, it never
/// re-derives severity itself.
class AlertEvaluation {
  const AlertEvaluation({
    required this.severity,
    required this.shouldNotify,
    required this.isRecoveryNotification,
  });

  final TemperatureSeverity severity;

  /// True exactly when a new notification should be raised right now,
  /// after cooldown/hysteresis has been applied.
  final bool shouldNotify;
  final bool isRecoveryNotification;
}

/// Per-device alert state machine: hysteresis (a breach must recover past
/// a lower threshold before it can re-fire) + a notification cooldown, so
/// a device sitting at 71°C does not spam a notification every poll.
class DeviceAlertState {
  DeviceAlertState();

  TemperatureSeverity _lastSeverity = TemperatureSeverity.normal;
  TemperatureSeverity? _armedFor; // severity we're waiting to notify again for
  DateTime? _lastNotifiedAt;
  bool _wasEverAlerted = false;

  TemperatureSeverity get lastSeverity => _lastSeverity;

  AlertEvaluation evaluate({
    required double? celsius,
    required TemperatureThresholds thresholds,
    required Duration cooldown,
    required bool recoveryNotificationsEnabled,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    if (celsius == null) {
      _lastSeverity = TemperatureSeverity.unavailable;
      return const AlertEvaluation(
        severity: TemperatureSeverity.unavailable,
        shouldNotify: false,
        isRecoveryNotification: false,
      );
    }

    final severity = thresholds.classify(celsius);
    _lastSeverity = severity;
    final isAlertable =
        severity == TemperatureSeverity.warning || severity == TemperatureSeverity.critical;

    // Step 1: has temperature dropped back under the recovery band for
    // whichever alertable severity we're currently armed at? Two distinct
    // outcomes follow, and conflating them was the source of a real bug:
    //   (a) it dropped enough to leave the alertable range entirely
    //       (e.g. critical -> normal) -> potential recovery notification.
    //   (b) it only dropped into a *lower* alertable band (e.g. critical's
    //       recovery point is passed but we're still in the warning band)
    //       -> silently re-baseline to that lower band, no notification.
    //       Treating this as "armed cleared, then a fresh warning breach"
    //       used to fire an incorrect immediate "Warning" alert on the way
    //       down from critical.
    if (_armedFor != null) {
      final recoveryPoint = _armedFor == TemperatureSeverity.critical
          ? thresholds.criticalRecoveryCelsius
          : thresholds.warningRecoveryCelsius;
      if (celsius < recoveryPoint) {
        final wasAlerting = _armedFor;
        _armedFor = null;
        if (isAlertable) {
          // (b) stepped down a band, not fully recovered - re-baseline
          // silently so a later re-escalation is measured from here.
          _armedFor = severity;
          return AlertEvaluation(
            severity: severity,
            shouldNotify: false,
            isRecoveryNotification: false,
          );
        }
        // (a) fully recovered out of any alertable band.
        if (recoveryNotificationsEnabled && wasAlerting != null && _wasEverAlerted) {
          _lastNotifiedAt = currentTime;
          return AlertEvaluation(
            severity: severity,
            shouldNotify: true,
            isRecoveryNotification: true,
          );
        }
        return AlertEvaluation(severity: severity, shouldNotify: false, isRecoveryNotification: false);
      }
    }

    if (!isAlertable) {
      return AlertEvaluation(
        severity: severity,
        shouldNotify: false,
        isRecoveryNotification: false,
      );
    }

    // Step 2: still alertable and not this tick's first drop below a
    // recovery point. A rank *increase* (warning -> critical, or armed
    // cleared -> anything) notifies immediately regardless of cooldown; a
    // sustained/rank-steady state paces reminders via cooldown instead of
    // firing on every poll (section 8).
    final currentRank = _severityRank(severity);
    final armedRank = _armedFor == null ? 0 : _severityRank(_armedFor!);
    final justEscalated = _armedFor == null || currentRank > armedRank;

    final cooldownElapsed =
        _lastNotifiedAt == null || currentTime.difference(_lastNotifiedAt!) >= cooldown;

    final shouldNotify = justEscalated || cooldownElapsed;

    _armedFor = severity;
    if (shouldNotify) {
      _lastNotifiedAt = currentTime;
      _wasEverAlerted = true;
    }

    return AlertEvaluation(
      severity: severity,
      shouldNotify: shouldNotify,
      isRecoveryNotification: false,
    );
  }

  int _severityRank(TemperatureSeverity severity) {
    switch (severity) {
      case TemperatureSeverity.critical:
        return 2;
      case TemperatureSeverity.warning:
        return 1;
      case TemperatureSeverity.normal:
      case TemperatureSeverity.warm:
      case TemperatureSeverity.unavailable:
        return 0;
    }
  }
}
