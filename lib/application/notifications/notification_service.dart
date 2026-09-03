abstract class NotificationService {
  Future<void> initialize();

  
  
  
  
  
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
