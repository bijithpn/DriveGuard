import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../domain/repositories/storage_monitor.dart';
import '../native/native_storage_monitor.dart';
import 'fallback_storage_monitor.dart';
import 'linux_storage_monitor.dart';
import 'macos_storage_monitor.dart';
import 'mock_storage_monitor.dart';
import 'windows_storage_monitor.dart';

/// Selects the real platform backend, falling back to [MockStorageMonitor]
/// only when explicitly requested (dev/demo mode) or when no real backend
/// reports itself available - never silently on a supported OS, so a
/// broken real backend is visible rather than papered over.
///
/// Per platform, the "real" backend is [FallbackStorageMonitor] composing
/// the native channel (DeviceIoControl/IOKit/sysfs+ioctl - see
/// docs/architecture.md) with the legacy CLI backend (PowerShell/
/// smartctl/nvme-cli), per spec section 7's "Native -> CLI -> unavailable"
/// chain. The native channel simply reports itself unavailable
/// ([MissingPluginException]) on any build where the platform runner
/// hasn't registered `driveguard/storage_native` yet, so this composition
/// degrades to the pre-native behavior automatically.
class StorageMonitorFactory {
  const StorageMonitorFactory._();

  static Future<StorageMonitor> create({bool forceMock = false}) async {
    if (forceMock) {
      AppLogger.instance.info('StorageMonitorFactory', 'Using mock backend (forced)');
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
          'StorageMonitorFactory', 'Unsupported OS (${Platform.operatingSystem}); using mock backend');
      return MockStorageMonitor();
    }

    final candidate = FallbackStorageMonitor(native: NativeStorageMonitor(), legacy: legacy);

    if (await candidate.isAvailable()) {
      AppLogger.instance.info('StorageMonitorFactory', 'Using ${legacy.runtimeType} (+ native channel)');
      return candidate;
    }
    AppLogger.instance.warning('StorageMonitorFactory',
        '${legacy.runtimeType} reported unavailable; falling back to mock backend');
    return MockStorageMonitor();
  }
}
