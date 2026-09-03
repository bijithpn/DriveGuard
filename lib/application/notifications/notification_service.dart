abstract class NotificationService {
  Future<void> initialize();

  /// [detailsText], when provided, is appended to the notification body -
  /// a short, human-readable summary of other currently-available metrics
  /// (health status, free space, ...) built by the caller from real data
  /// only; omitted entirely rather than showing a placeholder when nothing
  /// else is available.
  Future<void> showWarning({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  Future<void> showCritical({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  Future<void> showRecovered({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  /// A sudden rise detected independently of the warning/critical
  /// thresholds above - see `AppSettings.rapidRiseDeltaCelsius`. [riseText]
  /// describes the measured rise itself (e.g. "+14°C in 3 min").
  Future<void> showRapidRise({
    required String deviceName,
    required String temperatureText,
    required String riseText,
    String? detailsText,
  });

  Future<void> showStorageWarning({
    required String deviceName,
    required String usageText,
  });

  Future<void> showStorageCritical({
    required String deviceName,
    required String usageText,
  });

  Future<void> showStorageRecovered({
    required String deviceName,
    required String usageText,
  });
}
