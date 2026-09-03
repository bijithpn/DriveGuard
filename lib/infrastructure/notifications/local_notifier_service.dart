import 'package:local_notifier/local_notifier.dart';

import '../../application/notifications/notification_service.dart';
import '../../core/logging/app_logger.dart';

class LocalNotifierService implements NotificationService {
  static const _tag = 'LocalNotifierService';
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await localNotifier.setup(appName: 'DriveGuard');
      _initialized = true;
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to initialize notifier', e);
    }
  }

  Future<void> _show(String title, String body) async {
    if (!_initialized) return;
    try {
      final notification = LocalNotification(title: title, body: body);
      await notification.show();
    } catch (e) {
      AppLogger.instance.error(_tag, 'Failed to show notification', e);
    }
  }

  String _withDetails(String body, String? detailsText) {
    if (detailsText == null || detailsText.isEmpty) return body;
    return '$body\n$detailsText';
  }

  @override
  Future<void> showWarning({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) {
    return _show(
      'Storage Temperature Warning',
      _withDetails(
        '$deviceName\nTemperature: $temperatureText\n\nThe drive is approaching its configured temperature limit.',
        detailsText,
      ),
    );
  }

  @override
  Future<void> showCritical({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) {
    return _show(
      'Critical Storage Temperature',
      _withDetails(
        '$deviceName\nTemperature: $temperatureText\n\nThe drive has exceeded your configured critical temperature limit.',
        detailsText,
      ),
    );
  }

  @override
  Future<void> showRecovered({
    required String deviceName,
    required String temperatureText,
    String? detailsText,
  }) {
    return _show(
      'Storage Temperature Normal',
      _withDetails(
        '$deviceName\nTemperature: $temperatureText\n\nThe drive has returned to a normal temperature range.',
        detailsText,
      ),
    );
  }

  @override
  Future<void> showRapidRise({
    required String deviceName,
    required String temperatureText,
    required String riseText,
    String? detailsText,
  }) {
    return _show(
      'Rapid Temperature Rise Detected',
      _withDetails(
        '$deviceName\nTemperature: $temperatureText ($riseText)\n\n'
        'This drive heated up unusually fast. Check airflow, cooling, and '
        'whether a heavy workload is running - this may indicate a cooling '
        'or fan problem even if the temperature is still below your '
        'critical threshold.',
        detailsText,
      ),
    );
  }

  @override
  Future<void> showStorageWarning({
    required String deviceName,
    required String usageText,
  }) {
    return _show(
      'Low Disk Space Warning',
      '$deviceName\n$usageText\n\nThis drive is approaching your configured free-space limit.',
    );
  }

  @override
  Future<void> showStorageCritical({
    required String deviceName,
    required String usageText,
  }) {
    return _show(
      'Critical: Disk Almost Full',
      '$deviceName\n$usageText\n\nThis drive has exceeded your configured critical free-space limit.',
    );
  }

  @override
  Future<void> showStorageRecovered({
    required String deviceName,
    required String usageText,
  }) {
    return _show(
      'Disk Space Normal',
      '$deviceName\n$usageText\n\nFree space on this drive has returned to a normal level.',
    );
  }
}
