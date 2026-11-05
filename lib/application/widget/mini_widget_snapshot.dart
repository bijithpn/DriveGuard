import '../../domain/enums/storage_enums.dart';

class MiniWidgetDeviceSnapshot {
  const MiniWidgetDeviceSnapshot({
    required this.id,
    required this.name,
    required this.valueText,
    required this.fraction,
    required this.severity,
    this.type = StorageDeviceType.unknown,
    this.healthStatus = 'OK',
    this.lifePercent,
    this.freeCapacityText,
    this.readSpeedText,
    this.writeSpeedText,
    this.tbwText,
    this.powerOnHoursText,
    this.usedFraction,
  });

  final String id;
  final String name;
  final String valueText;
  final double fraction;
  final TemperatureSeverity severity;
  final StorageDeviceType type;
  final String healthStatus;
  final int? lifePercent;
  final String? freeCapacityText;
  final String? readSpeedText;
  final String? writeSpeedText;
  final String? tbwText;
  final String? powerOnHoursText;

  /// Share of the drive's capacity in use (0..1), or null when unknown.
  /// [fraction] is the *temperature* gauge, not capacity.
  final double? usedFraction;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'valueText': valueText,
    'fraction': fraction,
    'severity': severity.name,
    'type': type.name,
    'healthStatus': healthStatus,
    'lifePercent': lifePercent,
    'freeCapacityText': freeCapacityText,
    'readSpeedText': readSpeedText,
    'writeSpeedText': writeSpeedText,
    'tbwText': tbwText,
    'powerOnHoursText': powerOnHoursText,
    'usedFraction': usedFraction,
  };

  factory MiniWidgetDeviceSnapshot.fromJson(Map<String, dynamic> json) =>
      MiniWidgetDeviceSnapshot(
        id: json['id'] as String,
        name: json['name'] as String,
        valueText: json['valueText'] as String,
        fraction: (json['fraction'] as num).toDouble(),
        severity: TemperatureSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => TemperatureSeverity.unavailable,
        ),
        type: StorageDeviceType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => StorageDeviceType.unknown,
        ),
        healthStatus: json['healthStatus'] as String? ?? 'OK',
        lifePercent: json['lifePercent'] as int?,
        freeCapacityText: json['freeCapacityText'] as String?,
        readSpeedText: json['readSpeedText'] as String?,
        writeSpeedText: json['writeSpeedText'] as String?,
        tbwText: json['tbwText'] as String?,
        powerOnHoursText: json['powerOnHoursText'] as String?,
        usedFraction: (json['usedFraction'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MiniWidgetDeviceSnapshot &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          valueText == other.valueText &&
          fraction == other.fraction &&
          severity == other.severity &&
          type == other.type &&
          healthStatus == other.healthStatus &&
          lifePercent == other.lifePercent &&
          freeCapacityText == other.freeCapacityText &&
          readSpeedText == other.readSpeedText &&
          writeSpeedText == other.writeSpeedText &&
          tbwText == other.tbwText &&
          powerOnHoursText == other.powerOnHoursText &&
          usedFraction == other.usedFraction;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    valueText,
    fraction,
    severity,
    type,
    healthStatus,
    lifePercent,
    freeCapacityText,
    readSpeedText,
    writeSpeedText,
    tbwText,
    powerOnHoursText,
    usedFraction,
  );
}

/// A memory / heavy-write alert as shown in the floating windows.
class MiniWidgetAlert {
  const MiniWidgetAlert({
    required this.id,
    required this.title,
    required this.critical,
    this.culpritName,
    this.culpritPid,
    this.canQuit = false,
  });

  final String id;
  final String title;
  final bool critical;
  final String? culpritName;
  final int? culpritPid;

  /// True when the app may quit [culpritName] without admin rights.
  final bool canQuit;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'critical': critical,
    'culpritName': culpritName,
    'culpritPid': culpritPid,
    'canQuit': canQuit,
  };

  factory MiniWidgetAlert.fromJson(Map<String, dynamic> json) =>
      MiniWidgetAlert(
        id: json['id'] as String,
        title: json['title'] as String,
        critical: json['critical'] as bool? ?? false,
        culpritName: json['culpritName'] as String?,
        culpritPid: (json['culpritPid'] as num?)?.toInt(),
        canQuit: json['canQuit'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is MiniWidgetAlert &&
      id == other.id &&
      title == other.title &&
      critical == other.critical &&
      culpritName == other.culpritName &&
      culpritPid == other.culpritPid &&
      canQuit == other.canQuit;

  @override
  int get hashCode =>
      Object.hash(id, title, critical, culpritName, culpritPid, canQuit);
}

class MiniWidgetSnapshot {
  const MiniWidgetSnapshot({
    required this.devices,
    required this.compact,
    this.alerts = const [],
  });

  final List<MiniWidgetDeviceSnapshot> devices;
  final bool compact;
  final List<MiniWidgetAlert> alerts;

  static const empty = MiniWidgetSnapshot(devices: [], compact: false);

  Map<String, dynamic> toJson() => {
    'devices': devices.map((d) => d.toJson()).toList(),
    'compact': compact,
    'alerts': alerts.map((a) => a.toJson()).toList(),
  };

  factory MiniWidgetSnapshot.fromJson(Map<String, dynamic> json) =>
      MiniWidgetSnapshot(
        devices: (json['devices'] as List)
            .map(
              (d) =>
                  MiniWidgetDeviceSnapshot.fromJson(d as Map<String, dynamic>),
            )
            .toList(),
        compact: json['compact'] as bool? ?? false,
        alerts: ((json['alerts'] as List?) ?? const [])
            .map((a) => MiniWidgetAlert.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MiniWidgetSnapshot || runtimeType != other.runtimeType) {
      return false;
    }
    if (compact != other.compact ||
        devices.length != other.devices.length ||
        alerts.length != other.alerts.length) {
      return false;
    }
    for (var i = 0; i < alerts.length; i++) {
      if (alerts[i] != other.alerts[i]) return false;
    }
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] != other.devices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(compact, Object.hashAll(devices), Object.hashAll(alerts));
}
