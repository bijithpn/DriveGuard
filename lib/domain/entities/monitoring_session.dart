class MonitoringSession {
  const MonitoringSession({
    required this.id,
    required this.startedAt,
    required this.operatingSystem,
    required this.appVersion,
    required this.pollingIntervalSeconds,
    this.endedAt,
    this.endedCleanly = false,
    this.lastHeartbeatAt,
  });

  final String id;
  final DateTime startedAt;
  final String operatingSystem;
  final String appVersion;
  final int pollingIntervalSeconds;
  final DateTime? endedAt;
  final bool endedCleanly;
  final DateTime? lastHeartbeatAt;

  MonitoringSession copyWith({
    DateTime? endedAt,
    bool? endedCleanly,
    DateTime? lastHeartbeatAt,
  }) {
    return MonitoringSession(
      id: id,
      startedAt: startedAt,
      operatingSystem: operatingSystem,
      appVersion: appVersion,
      pollingIntervalSeconds: pollingIntervalSeconds,
      endedAt: endedAt ?? this.endedAt,
      endedCleanly: endedCleanly ?? this.endedCleanly,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'started_at': startedAt.millisecondsSinceEpoch,
    'operating_system': operatingSystem,
    'app_version': appVersion,
    'polling_interval_seconds': pollingIntervalSeconds,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'ended_cleanly': endedCleanly ? 1 : 0,
    'last_heartbeat_at': lastHeartbeatAt?.millisecondsSinceEpoch,
  };

  factory MonitoringSession.fromMap(Map<String, Object?> map) {
    return MonitoringSession(
      id: map['id'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
      operatingSystem: map['operating_system'] as String,
      appVersion: map['app_version'] as String,
      pollingIntervalSeconds: map['polling_interval_seconds'] as int,
      endedAt: map['ended_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int)
          : null,
      endedCleanly: (map['ended_cleanly'] as int? ?? 0) != 0,
      lastHeartbeatAt: map['last_heartbeat_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_heartbeat_at'] as int)
          : null,
    );
  }
}

class PreIncidentSample {
  const PreIncidentSample({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
    required this.celsius,
  });

  final String sessionId;
  final String deviceId;

  final String deviceName;
  final DateTime timestamp;
  final double celsius;

  Map<String, Object?> toMap() => {
    'session_id': sessionId,
    'device_id': deviceId,
    'device_name': deviceName,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'celsius': celsius,
  };

  factory PreIncidentSample.fromMap(Map<String, Object?> map) {
    return PreIncidentSample(
      sessionId: map['session_id'] as String,
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String? ?? map['device_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      celsius: (map['celsius'] as num).toDouble(),
    );
  }
}
