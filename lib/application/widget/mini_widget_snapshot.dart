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
          powerOnHoursText == other.powerOnHoursText;

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
  );
}

class MiniWidgetSnapshot {
  const MiniWidgetSnapshot({required this.devices, required this.compact});

  final List<MiniWidgetDeviceSnapshot> devices;
  final bool compact;

  static const empty = MiniWidgetSnapshot(devices: [], compact: false);

  Map<String, dynamic> toJson() => {
    'devices': devices.map((d) => d.toJson()).toList(),
    'compact': compact,
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
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MiniWidgetSnapshot || runtimeType != other.runtimeType) {
      return false;
    }
    if (compact != other.compact || devices.length != other.devices.length) {
      return false;
    }
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] != other.devices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(compact, Object.hashAll(devices));
}
