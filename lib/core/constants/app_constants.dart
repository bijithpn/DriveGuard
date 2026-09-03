/// App-wide defaults. All of these are user-overridable via Settings and
/// persisted through [SettingsService] - values here are only the
/// out-of-the-box defaults, never hard-coded "safe" hardware limits.
class AppConstants {
  const AppConstants._();

  static const Duration defaultPollingInterval = Duration(seconds: 5);
  static const List<Duration> allowedPollingIntervals = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static const Duration deviceDiscoveryInterval = Duration(seconds: 15);

  /// A reading older than (pollingInterval * this) is considered stale.
  static const int staleThresholdMultiplier = 4;

  /// Default application-level severity bands (section 7). These are a
  /// *starting point* the user configures per device - not a claim about
  /// what is safe for any specific drive.
  static const double defaultWarningCelsius = 60.0;
  static const double defaultCriticalCelsius = 70.0;

  /// Once critical, temperature must drop back below
  /// (criticalThreshold - recoveryHysteresisCelsius) before the alert
  /// engine will re-arm and allow another critical notification.
  static const double recoveryHysteresisCelsius = 5.0;

  static const Duration defaultNotificationCooldown = Duration(minutes: 5);
  static const List<Duration> allowedNotificationCooldowns = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  static const Duration externalCommandTimeout = Duration(seconds: 6);

  /// Raw per-reading history is kept at full resolution for this long;
  /// older data is aggregated (see HistoryStore) rather than dropped or
  /// kept unbounded in memory.
  static const Duration rawHistoryRetention = Duration(hours: 1);
  static const Duration maxHistoryRetention = Duration(hours: 24);
}
