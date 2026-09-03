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

  static const int staleThresholdMultiplier = 4;

  static const double defaultWarningCelsius = 60.0;
  static const double defaultCriticalCelsius = 70.0;

  static const double recoveryHysteresisCelsius = 5.0;

  static const Duration defaultNotificationCooldown = Duration(minutes: 5);
  static const List<Duration> allowedNotificationCooldowns = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  static const Duration externalCommandTimeout = Duration(seconds: 6);

  static const Duration rawHistoryRetention = Duration(hours: 1);
  static const Duration maxHistoryRetention = Duration(hours: 24);

  // Rapid-rise ("hike") detection - a UI default, not a hardware spec; see
  // AppSettings.rapidRiseDeltaCelsius doc comment.
  static const double defaultRapidRiseDeltaCelsius = 10.0;
  static const Duration defaultRapidRiseWindow = Duration(minutes: 3);
}
