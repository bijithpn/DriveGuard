enum CapacitySeverity { normal, warning, critical, unavailable }

/// Usage-percentage thresholds for low-disk-space alerts, the capacity
/// counterpart to [TemperatureThresholds]. Free space, unlike temperature,
/// has no vendor-specified danger point - these are just sensible UI
/// defaults, always user-configurable, never presented as a hardware spec.
class StorageThresholds {
  const StorageThresholds({
    this.warningPercent = 85,
    this.criticalPercent = 95,
    this.recoveryHysteresisPercent = 5,
  });

  final double warningPercent;
  final double criticalPercent;
  final double recoveryHysteresisPercent;

  static const defaults = StorageThresholds();

  CapacitySeverity classify(double usagePercent) {
    if (usagePercent >= criticalPercent) return CapacitySeverity.critical;
    if (usagePercent >= warningPercent) return CapacitySeverity.warning;
    return CapacitySeverity.normal;
  }

  double get criticalRecoveryPercent =>
      criticalPercent - recoveryHysteresisPercent;
  double get warningRecoveryPercent =>
      warningPercent - recoveryHysteresisPercent;

  StorageThresholds copyWith({
    double? warningPercent,
    double? criticalPercent,
    double? recoveryHysteresisPercent,
  }) {
    return StorageThresholds(
      warningPercent: warningPercent ?? this.warningPercent,
      criticalPercent: criticalPercent ?? this.criticalPercent,
      recoveryHysteresisPercent:
          recoveryHysteresisPercent ?? this.recoveryHysteresisPercent,
    );
  }

  Map<String, dynamic> toJson() => {
    'warningPercent': warningPercent,
    'criticalPercent': criticalPercent,
    'recoveryHysteresisPercent': recoveryHysteresisPercent,
  };

  factory StorageThresholds.fromJson(Map<String, dynamic> json) {
    return StorageThresholds(
      warningPercent: (json['warningPercent'] as num?)?.toDouble() ?? 85,
      criticalPercent: (json['criticalPercent'] as num?)?.toDouble() ?? 95,
      recoveryHysteresisPercent:
          (json['recoveryHysteresisPercent'] as num?)?.toDouble() ?? 5,
    );
  }
}
