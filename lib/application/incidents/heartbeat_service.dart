import 'dart:async';

import '../../infrastructure/persistence/incident_repository.dart';

/// Writes a lightweight heartbeat for the current session every 30 seconds.
/// This is the only signal the next launch has that the session was still
/// alive at a given time if the app never gets to mark itself closed
/// cleanly (crash, kill, power loss).
class HeartbeatService {
  HeartbeatService({
    required IncidentRepository repository,
    required String sessionId,
    this.interval = const Duration(seconds: 30),
  }) : _repository = repository,
       _sessionId = sessionId;

  final IncidentRepository _repository;
  final String _sessionId;
  final Duration interval;
  Timer? _timer;

  void start() {
    _beat();
    _timer = Timer.periodic(interval, (_) => _beat());
  }

  void _beat() {
    unawaited(_repository.heartbeat(_sessionId, DateTime.now()));
  }

  Future<void> stop({bool markClosedCleanly = true}) async {
    _timer?.cancel();
    _timer = null;
    if (markClosedCleanly) {
      await _repository.markSessionClosed(_sessionId, DateTime.now());
    }
  }
}
