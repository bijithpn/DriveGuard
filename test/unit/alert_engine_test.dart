import 'package:driveguard/application/alerts/alert_engine.dart';
import 'package:driveguard/domain/entities/temperature_thresholds.dart';
import 'package:driveguard/domain/enums/storage_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const thresholds = TemperatureThresholds(
    warningCelsius: 60,
    criticalCelsius: 70,
    recoveryHysteresisCelsius: 5,
  );
  const cooldown = Duration(minutes: 5);
  var now = DateTime(2026, 1, 1, 12, 0, 0);

  AlertEvaluation eval(DeviceAlertState state, double celsius) {
    return state.evaluate(
      celsius: celsius,
      thresholds: thresholds,
      cooldown: cooldown,
      recoveryNotificationsEnabled: true,
      now: now,
    );
  }

  test('normal temperature never notifies', () {
    final state = DeviceAlertState();
    final result = eval(state, 40);
    expect(result.severity, TemperatureSeverity.normal);
    expect(result.shouldNotify, isFalse);
  });

  test('first breach of critical notifies immediately', () {
    final state = DeviceAlertState();
    eval(state, 40); // establish normal baseline
    final result = eval(state, 78);
    expect(result.severity, TemperatureSeverity.critical);
    expect(result.shouldNotify, isTrue);
    expect(result.isRecoveryNotification, isFalse);
  });

  test(
    'does not re-notify every poll while sustained just above critical (within cooldown)',
    () {
      final state = DeviceAlertState();
      eval(state, 40);
      expect(eval(state, 78).shouldNotify, isTrue);
      // Still critical seconds later, well within the 5-minute cooldown.
      now = now.add(const Duration(seconds: 5));
      final second = eval(state, 79);
      expect(second.shouldNotify, isFalse);
      expect(second.severity, TemperatureSeverity.critical);
    },
  );

  test('re-notifies once the cooldown elapses while still critical', () {
    final state = DeviceAlertState();
    eval(state, 40);
    eval(state, 78);
    now = now.add(const Duration(minutes: 6));
    final result = eval(state, 79);
    expect(result.shouldNotify, isTrue);
  });

  test(
    'recovering below the hysteresis band then re-breaching notifies again immediately',
    () {
      final state = DeviceAlertState();
      eval(state, 40);
      eval(state, 78); // critical notification #1

      now = now.add(const Duration(seconds: 5));
      eval(
        state,
        63,
      ); // still above criticalRecoveryCelsius(65)? no: 63 < 65, recovers
      // temperature must pass through "normal" to fire a recovery notification below,
      // so drop further first.
      final recovered = eval(state, 40);
      expect(recovered.isRecoveryNotification, isTrue);
      expect(recovered.shouldNotify, isTrue);

      now = now.add(const Duration(seconds: 5));
      final rebreach = eval(state, 78);
      expect(rebreach.shouldNotify, isTrue);
      expect(rebreach.severity, TemperatureSeverity.critical);
    },
  );

  test(
    'escalation from warning to critical notifies immediately, ignoring cooldown',
    () {
      final state = DeviceAlertState();
      eval(state, 40);
      eval(state, 62); // warning notification
      now = now.add(const Duration(seconds: 1));
      final escalated = eval(state, 78);
      expect(escalated.shouldNotify, isTrue);
      expect(escalated.severity, TemperatureSeverity.critical);
    },
  );

  test(
    'cooling from critical to warning (without full recovery) does not immediately notify',
    () {
      final state = DeviceAlertState();
      eval(state, 40);
      eval(state, 78); // critical notification #1
      now = now.add(const Duration(seconds: 5));
      final cooling = eval(
        state,
        62,
      ); // still warning-band, not below recovery threshold
      expect(cooling.severity, TemperatureSeverity.warning);
      // This used to fire an immediate "Warning" notification on the way
      // down from critical - it must not, since nothing has escalated.
      expect(cooling.shouldNotify, isFalse);
    },
  );

  test(
    're-escalating to critical after dipping to warning notifies again immediately',
    () {
      final state = DeviceAlertState();
      eval(state, 40);
      eval(state, 78); // critical #1
      now = now.add(const Duration(seconds: 5));
      eval(state, 62); // dips to warning, no notify (see test above)
      now = now.add(const Duration(seconds: 5));
      final reescalated = eval(state, 78); // back up to critical
      expect(reescalated.severity, TemperatureSeverity.critical);
      expect(reescalated.shouldNotify, isTrue);
    },
  );

  test(
    'unavailable temperature reports unavailable severity without notifying',
    () {
      final state = DeviceAlertState();
      final result = eval(state, double.nan.isNaN ? 40 : 40); // sanity no-op
      expect(result.shouldNotify, isFalse);
      final unavailable = state.evaluate(
        celsius: null,
        thresholds: thresholds,
        cooldown: cooldown,
        recoveryNotificationsEnabled: true,
      );
      expect(unavailable.severity, TemperatureSeverity.unavailable);
      expect(unavailable.shouldNotify, isFalse);
    },
  );
}
