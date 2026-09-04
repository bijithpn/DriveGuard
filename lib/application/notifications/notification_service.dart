abstract class NotificationService {
  Future<void> initialize();

  Stream<String> get deviceClicks;

  Future<void> showWarning({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  Future<void> showCritical({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  Future<void> showRecovered({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  });

  Future<void> showRapidRise({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    required String riseText,
    String? detailsText,
  });

  Future<void> showStorageWarning({
    required String deviceId,
    required String deviceName,
    required String usageText,
  });

  Future<void> showStorageCritical({
    required String deviceId,
    required String deviceName,
    required String usageText,
  });

  Future<void> showStorageRecovered({
    required String deviceId,
    required String deviceName,
    required String usageText,
  });

  Future<void> showHealthAlert({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String message,
    String? detailsText,
  });

  
  
  Future<void> showPredictiveTemperature({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String etaText,
    String? detailsText,
  });

  
  Future<void> showPredictiveCapacity({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String etaText,
  });

  
  
  Future<void> showPredictiveHealth({
    required String deviceId,
    required String deviceName,
    required String etaText,
  });
}
