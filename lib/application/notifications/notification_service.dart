/// Platform-independent notification contract (section 9). The concrete
/// implementation uses `local_notifier`, which wraps Windows toast
/// notifications, macOS Notification Center and Linux libnotify/D-Bus
/// behind one API - a legitimate case for a Flutter plugin per section 2's
/// "use Flutter plugins where they provide reliable cross-platform
/// functionality", since this is OS notification plumbing, not hardware
/// telemetry.
abstract class NotificationService {
  Future<void> initialize();

  Future<void> showWarning({required String deviceName, required String temperatureText});

  Future<void> showCritical({required String deviceName, required String temperatureText});

  Future<void> showRecovered({required String deviceName, required String temperatureText});
}
