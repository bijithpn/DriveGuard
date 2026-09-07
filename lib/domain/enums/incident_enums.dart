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
