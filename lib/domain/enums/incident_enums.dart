enum ShutdownClassification {
  cleanAppExit,

  appSessionEndedUnexpectedly,

  osShutdownClean,

  osRebootClean,

  osShutdownUnexpected,

  kernelPanic,

  bsod,

  possiblePowerLoss,

  unknown,
}

enum CorrelationLevel { none, low, moderate, high }

/// How serious an incident is. Drives list filtering and popup behaviour.
enum IncidentSeverity { info, warning, error }

/// Which incidents may pop up a dialog at startup.
enum IncidentPopupLevel { off, errorsOnly, warningsAndErrors }
