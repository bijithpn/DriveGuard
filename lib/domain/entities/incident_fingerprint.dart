import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../enums/incident_enums.dart';

/// Stable identity of a real-world event, independent of which monitoring
/// session happened to notice it.
///
/// Several sessions can describe the same event (rapid app restarts after one
/// crash, a dev hot-restart loop, one power loss seen by every relaunch), so
/// de-duplicating on `session_id` alone is not enough.
class IncidentFingerprint {
  const IncidentFingerprint._();

  static const _appWindow = Duration(minutes: 10);

  /// A machine-level event (panic, BSOD, power loss, unexpected shutdown) is
  /// identified by the boot that followed it: a machine can only come back up
  /// from one such event per boot.
  static String system({
    required ShutdownClassification classification,
    required DateTime? currentBootAt,
    required DateTime? eventAt,
  }) {
    final anchor = currentBootAt != null
        ? 'boot:${_seconds(currentBootAt)}'
        : 'at:${_minutes(eventAt)}';
    return _hash('system|${classification.name}|$anchor');
  }

  /// An app-only stop is identified by the boot it happened in plus a coarse
  /// time window, so a burst of restarts collapses into a single incident.
  static String app({
    required ShutdownClassification classification,
    required DateTime? currentBootAt,
    required DateTime? lastActiveAt,
  }) {
    final window = lastActiveAt == null
        ? 'none'
        : '${lastActiveAt.millisecondsSinceEpoch ~/ _appWindow.inMilliseconds}';
    final boot = currentBootAt == null ? 'unknown' : _seconds(currentBootAt);
    return _hash('app|${classification.name}|$boot|$window');
  }

  /// Best-effort identity for rows saved before fingerprints existed.
  static String legacy({
    required String classification,
    required int detectedAtMs,
    required int? estimatedShutdownAtMs,
  }) {
    final detectedMinute = detectedAtMs ~/ Duration.millisecondsPerMinute;
    final shutdownMinute = estimatedShutdownAtMs == null
        ? 'none'
        : '${estimatedShutdownAtMs ~/ Duration.millisecondsPerMinute}';
    return _hash('legacy|$classification|$detectedMinute|$shutdownMinute');
  }

  static String _seconds(DateTime t) => '${t.millisecondsSinceEpoch ~/ 1000}';

  static String _minutes(DateTime? t) => t == null
      ? 'none'
      : '${t.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute}';

  static String _hash(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
