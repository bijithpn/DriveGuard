import '../../domain/entities/temperature_thresholds.dart';
import '../../domain/enums/storage_enums.dart';

class AlertEvaluation {
  const AlertEvaluation({
    required this.severity,
    required this.shouldNotify,
    required this.isRecoveryNotification,
  });

  final TemperatureSeverity severity;

  final bool shouldNotify;
  final bool isRecoveryNotification;
}

class DeviceAlertState {
  DeviceAlertState();

  TemperatureSeverity _lastSeverity = TemperatureSeverity.normal;
  TemperatureSeverity? _armedFor;
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
        severity == TemperatureSeverity.warning ||
        severity == TemperatureSeverity.critical;

    if (_armedFor != null) {
      final recoveryPoint = _armedFor == TemperatureSeverity.critical
          ? thresholds.criticalRecoveryCelsius
          : thresholds.warningRecoveryCelsius;
      if (celsius < recoveryPoint) {
        final wasAlerting = _armedFor;
        _armedFor = null;
        if (isAlertable) {
          _armedFor = severity;
          return AlertEvaluation(
            severity: severity,
            shouldNotify: false,
            isRecoveryNotification: false,
          );
        }

        if (recoveryNotificationsEnabled &&
            wasAlerting != null &&
            _wasEverAlerted) {
          _lastNotifiedAt = currentTime;
          return AlertEvaluation(
            severity: severity,
            shouldNotify: true,
            isRecoveryNotification: true,
          );
        }
        return AlertEvaluation(
          severity: severity,
          shouldNotify: false,
          isRecoveryNotification: false,
        );
      }
    }

    if (!isAlertable) {
      return AlertEvaluation(
        severity: severity,
        shouldNotify: false,
        isRecoveryNotification: false,
      );
    }

    final currentRank = _severityRank(severity);
    final armedRank = _armedFor == null ? 0 : _severityRank(_armedFor!);
    final justEscalated = _armedFor == null || currentRank > armedRank;

    final cooldownElapsed =
        _lastNotifiedAt == null ||
        currentTime.difference(_lastNotifiedAt!) >= cooldown;

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
