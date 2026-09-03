abstract class NotificationService {
  Future<void> initialize();

  Future<void> showWarning({
    required String deviceName,
    required String temperatureText,
  });

  Future<void> showCritical({
    required String deviceName,
    required String temperatureText,
  });

  Future<void> showRecovered({
    required String deviceName,
    required String temperatureText,
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
