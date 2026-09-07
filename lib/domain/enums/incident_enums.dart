/// Classification of how the previous run of the application/OS ended.
///
/// This is deliberately fine-grained: an application crash must never be
/// reported to the user as an OS-level shutdown, and an OS shutdown must
/// never be reported as proven-caused-by-storage unless evidence supports it.
enum ShutdownClassification {
  /// The app itself exited cleanly (user quit, normal close-to-tray-then-quit).
  cleanAppExit,

  /// The previous DriveGuard session never marked itself closed, but platform
  /// diagnostics show the OS shut down/rebooted normally around that time —
  /// i.e. the app was killed/crashed independently of the OS.
  appSessionEndedUnexpectedly,

  /// Platform diagnostics show a normal, user-initiated OS shutdown.
  osShutdownClean,

  /// Platform diagnostics show a normal, user-initiated OS reboot.
  osRebootClean,

  /// Platform diagnostics show the OS stopped without a clean shutdown
  /// sequence (no clean shutdown event found in the expected window).
  osShutdownUnexpected,

  /// Platform diagnostics found explicit kernel panic / bugcheck evidence.
  kernelPanic,

  /// Windows-specific: a bugcheck (BSOD) event was found.
  bsod,

  /// Diagnostics suggest the machine lost power abruptly (no shutdown
  /// sequence, no panic — the log simply stops).
  possiblePowerLoss,

  /// Not enough evidence to classify.
  unknown,
}

/// How strongly available evidence supports a thermal/storage cause for an
/// unexpected shutdown. Never assigned `high` without corroborating platform
/// diagnostic evidence in addition to the temperature data itself.
enum CorrelationLevel { none, low, moderate, high }
