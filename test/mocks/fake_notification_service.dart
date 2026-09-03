import 'package:driveguard/application/notifications/notification_service.dart';

/// No-op [NotificationService] for widget/unit tests - never touches the
/// real OS notification center.
class FakeNotificationService implements NotificationService {
  final List<String> shown = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showWarning({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('warning:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showCritical({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('critical:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showRecovered({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('recovered:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showRapidRise({
    required String deviceName,
    required String temperatureText,
    required String riseText,
    String? detailsText,
  }) async {
    shown.add(
      'rapid-rise:$deviceName:$temperatureText:$riseText:${detailsText ?? ''}',
    );
  }

  @override
  Future<void> showStorageWarning({
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-warning:$deviceName:$usageText');
  }

  @override
  Future<void> showStorageCritical({
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-critical:$deviceName:$usageText');
  }

  @override
  Future<void> showStorageRecovered({
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-recovered:$deviceName:$usageText');
  }
}
