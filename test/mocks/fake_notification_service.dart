import 'dart:async';

import 'package:driveguard/application/notifications/notification_service.dart';

/// No-op [NotificationService] for widget/unit tests - never touches the
/// real OS notification center.
class FakeNotificationService implements NotificationService {
  final List<String> shown = [];

  final _clicksController = StreamController<String>.broadcast();
  @override
  Stream<String> get deviceClicks => _clicksController.stream;

  /// Test helper: simulates the user clicking the most recent notification
  /// shown for [deviceId].
  void simulateClick(String deviceId) => _clicksController.add(deviceId);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showWarning({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('warning:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showCritical({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('critical:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showRecovered({
    required String deviceId,
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) async {
    shown.add('recovered:$deviceName:$temperatureText:${detailsText ?? ''}');
  }

  @override
  Future<void> showRapidRise({
    required String deviceId,
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
    required String deviceId,
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-warning:$deviceName:$usageText');
  }

  @override
  Future<void> showStorageCritical({
    required String deviceId,
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-critical:$deviceName:$usageText');
  }

  @override
  Future<void> showStorageRecovered({
    required String deviceId,
    required String deviceName,
    required String usageText,
  }) async {
    shown.add('storage-recovered:$deviceName:$usageText');
  }

  @override
  Future<void> showHealthAlert({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String message,
    String? detailsText,
  }) async {
    shown.add(
      'health-${critical ? 'critical' : 'warning'}:$deviceName:$message:${detailsText ?? ''}',
    );
  }

  @override
  Future<void> showPredictiveTemperature({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String etaText,
    String? detailsText,
  }) async {
    shown.add(
      'predictive-temperature-${critical ? 'critical' : 'warning'}:$deviceName:$etaText:${detailsText ?? ''}',
    );
  }

  @override
  Future<void> showPredictiveCapacity({
    required String deviceId,
    required String deviceName,
    required bool critical,
    required String etaText,
  }) async {
    shown.add(
      'predictive-capacity-${critical ? 'critical' : 'warning'}:$deviceName:$etaText',
    );
  }

  @override
  Future<void> showPredictiveHealth({
    required String deviceId,
    required String deviceName,
    required String etaText,
  }) async {
    shown.add('predictive-health:$deviceName:$etaText');
  }
}
