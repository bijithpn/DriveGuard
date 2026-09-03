import '../../domain/enums/storage_enums.dart';

class MiniWidgetDeviceSnapshot {
  const MiniWidgetDeviceSnapshot({
    required this.id,
    required this.name,
    required this.valueText,
    required this.fraction,
    required this.severity,
  });

  final String id;
  final String name;
  final String valueText;
  final double fraction;
  final TemperatureSeverity severity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'valueText': valueText,
    'fraction': fraction,
    'severity': severity.name,
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
}
