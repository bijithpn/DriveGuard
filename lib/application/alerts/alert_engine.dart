import '../../domain/entities/storage_thresholds.dart';
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

class CapacityAlertEvaluation {
  const CapacityAlertEvaluation({
    required this.severity,
    required this.shouldNotify,
    required this.isRecoveryNotification,
  });

  final CapacitySeverity severity;
  final bool shouldNotify;
  final bool isRecoveryNotification;
}

/// Same escalation/cooldown/hysteresis shape as [DeviceAlertState], for
/// disk-usage percentage instead of temperature. Kept as a separate,
/// smaller class rather than generalizing [DeviceAlertState] - the two
/// units (°C vs %) and severity enums differ enough that a shared abstract
/// base would add more indirection than it would save.
class StorageAlertState {
  StorageAlertState();

  CapacitySeverity _lastSeverity = CapacitySeverity.normal;
  CapacitySeverity? _armedFor;
  DateTime? _lastNotifiedAt;
  bool _wasEverAlerted = false;

  CapacitySeverity get lastSeverity => _lastSeverity;

  CapacityAlertEvaluation evaluate({
    required double? usagePercent,
    required StorageThresholds thresholds,
    required Duration cooldown,
    required bool recoveryNotificationsEnabled,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    if (usagePercent == null) {
      _lastSeverity = CapacitySeverity.unavailable;
      return const CapacityAlertEvaluation(
        severity: CapacitySeverity.unavailable,
        shouldNotify: false,
        isRecoveryNotification: false,
      );
    }

    final severity = thresholds.classify(usagePercent);
    _lastSeverity = severity;
    final isAlertable =
        severity == CapacitySeverity.warning ||
        severity == CapacitySeverity.critical;

    if (_armedFor != null) {
      final recoveryPoint = _armedFor == CapacitySeverity.critical
          ? thresholds.criticalRecoveryPercent
          : thresholds.warningRecoveryPercent;
      if (usagePercent < recoveryPoint) {
        final wasAlerting = _armedFor;
        _armedFor = null;
        if (isAlertable) {
          _armedFor = severity;
          return CapacityAlertEvaluation(
            severity: severity,
            shouldNotify: false,
            isRecoveryNotification: false,
          );
        }

        if (recoveryNotificationsEnabled &&
            wasAlerting != null &&
            _wasEverAlerted) {
          _lastNotifiedAt = currentTime;
          return CapacityAlertEvaluation(
            severity: severity,
            shouldNotify: true,
            isRecoveryNotification: true,
          );
        }
        return CapacityAlertEvaluation(
          severity: severity,
          shouldNotify: false,
          isRecoveryNotification: false,
        );
      }
    }

    if (!isAlertable) {
      return CapacityAlertEvaluation(
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

    return CapacityAlertEvaluation(
      severity: severity,
      shouldNotify: shouldNotify,
      isRecoveryNotification: false,
    );
  }

  int _severityRank(CapacitySeverity severity) {
    switch (severity) {
      case CapacitySeverity.critical:
        return 2;
      case CapacitySeverity.warning:
        return 1;
      case CapacitySeverity.normal:
      case CapacitySeverity.unavailable:
        return 0;
    }
  }
}
