import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../domain/repositories/storage_monitor.dart';
import '../native/native_storage_monitor.dart';
import 'fallback_storage_monitor.dart';
import 'linux_storage_monitor.dart';
import 'macos_storage_monitor.dart';
import 'mock_storage_monitor.dart';
import 'unavailable_storage_monitor.dart';
import 'windows_storage_monitor.dart';

class StorageMonitorFactory {
  const StorageMonitorFactory._();

  static Future<StorageMonitor> create({bool forceMock = false}) async {
    if (forceMock) {
      AppLogger.instance.info(
        'StorageMonitorFactory',
        'Using mock backend (forced)',
      );
      return MockStorageMonitor();
    }

    final StorageMonitor legacy;
    if (Platform.isMacOS) {
      legacy = MacOSStorageMonitor();
    } else if (Platform.isLinux) {
      legacy = LinuxStorageMonitor();
    } else if (Platform.isWindows) {
      legacy = WindowsStorageMonitor();
    } else {
      AppLogger.instance.warning(
        'StorageMonitorFactory',
        'Unsupported OS (${Platform.operatingSystem}); no real backend available',
      );
      return UnavailableStorageMonitor(
        reason: 'Unsupported OS (${Platform.operatingSystem})',
      );
    }

    final candidate = FallbackStorageMonitor(
      native: NativeStorageMonitor(),
      legacy: legacy,
    );

    if (await candidate.isAvailable()) {
      AppLogger.instance.info(
        'StorageMonitorFactory',
        'Using ${legacy.runtimeType} (+ native channel)',
      );
      return candidate;
    }

    AppLogger.instance.warning(
      'StorageMonitorFactory',
      '${legacy.runtimeType} reported unavailable; no real backend available',
    );
    return UnavailableStorageMonitor(
      reason: '${legacy.runtimeType} reported unavailable',
    );
  }
}
