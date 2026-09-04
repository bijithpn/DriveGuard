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

  static const double defaultRapidRiseDeltaCelsius = 10.0;
  static const Duration defaultRapidRiseWindow = Duration(minutes: 3);
  static const List<Duration> allowedRapidRiseWindows = [
    Duration(minutes: 1),
    Duration(minutes: 3),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  static const Duration defaultHealthPollingInterval = Duration(seconds: 60);
  static const List<Duration> allowedHealthPollingIntervals = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(minutes: 5),
  ];

  static const int defaultWearJumpAlertPercent = 3;

  
  
  
  
  
  static const bool defaultPredictiveAlertsEnabled = true;

  
  
  static const double predictiveMinRSquared = 0.6;
  static const int predictiveMinSamples = 4;

  
  
  static const Duration predictiveTemperatureLookback = Duration(minutes: 5);
  static const Duration predictiveTemperatureLeadTime = Duration(minutes: 15);

  
  
  static const Duration predictiveCapacityLookback = Duration(days: 3);
  static const Duration predictiveCapacityLeadTime = Duration(days: 3);
  static const Duration predictiveCapacitySampleInterval = Duration(
    minutes: 15,
  );
  static const Duration predictiveCapacityRetention = Duration(days: 14);

  static const Duration predictiveHealthLookback = Duration(days: 7);
  static const Duration predictiveHealthLeadTime = Duration(days: 14);
  static const Duration predictiveHealthSampleInterval = Duration(minutes: 30);
  static const Duration predictiveHealthRetention = Duration(days: 30);
}
