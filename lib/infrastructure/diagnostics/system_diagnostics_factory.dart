import 'dart:io';

import '../../domain/enums/incident_enums.dart';
import 'linux_system_diagnostics.dart';
import 'macos_system_diagnostics.dart';
import 'system_diagnostics.dart';
import 'windows_system_diagnostics.dart';

class SystemDiagnosticsFactory {
  SystemDiagnosticsFactory._();

  static SystemDiagnostics create() {
    if (Platform.isWindows) return WindowsSystemDiagnostics();
    if (Platform.isMacOS) return MacOSSystemDiagnostics();
    if (Platform.isLinux) return LinuxSystemDiagnostics();
    return _UnsupportedSystemDiagnostics();
  }
}

class _UnsupportedSystemDiagnostics implements SystemDiagnostics {
  @override
  String get backendName => 'Unsupported platform';

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PreviousBootDiagnosis> diagnosePreviousBoot({
    DateTime? approximateShutdownTime,
  }) async => const PreviousBootDiagnosis(
    classification: ShutdownClassification.unknown,
    events: [],
  );
}
