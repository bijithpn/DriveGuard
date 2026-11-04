import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../application/monitoring/metric_history_store.dart';
import '../../domain/entities/cleanup_item.dart';
import '../../core/logging/app_logger.dart';

/// Small bits of state that must survive a restart but don't belong in
/// settings: which one-time advisories were already shown, and the drive
/// usage history behind the Storage Sense trend line. Writes are tiny and
/// callers throttle them.
class LocalStateRepository {
  static const _tag = 'LocalStateRepository';
  static const _advisoriesKey = 'driveguard.advisories.v1';
  static const _capacityPrefix = 'driveguard.capacity.v1.';
  static const _maxCapacityPoints = 700;

  Future<Set<String>> loadSentAdvisories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_advisoriesKey) ?? const []).toSet();
    } catch (e) {
      AppLogger.instance.debug(_tag, 'load advisories failed: $e');
      return {};
    }
  }

  Future<void> saveSentAdvisories(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep the list bounded; old keys only matter for drives still present.
      final list = keys.toList();
      final trimmed = list.length > 200
          ? list.sublist(list.length - 200)
          : list;
      await prefs.setStringList(_advisoriesKey, trimmed);
    } catch (e) {
      AppLogger.instance.debug(_tag, 'save advisories failed: $e');
    }
  }

  Future<List<MetricPoint>> loadCapacity(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_capacityPrefix$deviceId');
      if (raw == null) return const [];
      return [
        for (final e in jsonDecode(raw) as List)
          MetricPoint(
            DateTime.fromMillisecondsSinceEpoch((e as List)[0] as int),
            ((e)[1] as num).toDouble(),
          ),
      ];
    } catch (e) {
      AppLogger.instance.debug(_tag, 'load capacity failed: $e');
      return const [];
    }
  }

  Future<void> saveCapacity(String deviceId, List<MetricPoint> points) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = points.length > _maxCapacityPoints
          ? points.sublist(points.length - _maxCapacityPoints)
          : points;
      await prefs.setString(
        '$_capacityPrefix$deviceId',
        jsonEncode([
          for (final m in p)
            [
              m.timestamp.millisecondsSinceEpoch,
              double.parse(m.value.toStringAsFixed(2)),
            ],
        ]),
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'save capacity failed: $e');
    }
  }

  static const _scanKey = 'driveguard.lastscan.v1';

  /// Remembers the last Storage Sense scan so the page can show it instantly
  /// next time while a fresh scan runs in the background.
  Future<void> saveScan(List<CleanupItem> items, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scanKey,
        jsonEncode({
          'at': at.millisecondsSinceEpoch,
          'items': [
            for (final i in items.take(250))
              {
                'id': i.id,
                'name': i.name,
                'desc': i.description,
                'path': i.path,
                'safety': i.safety.index,
                'cat': i.category.name,
                'size': i.sizeBytes,
                'mod': i.lastModified?.millisecondsSinceEpoch,
                'partial': i.sizeIsPartial,
                'contents': i.deleteContentsOnly,
                'admin': i.requiresAdmin,
                'project': i.project,
              },
          ],
        }),
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'save scan failed: $e');
    }
  }

  Future<({DateTime at, List<CleanupItem> items})?> loadScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scanKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final items = <CleanupItem>[];
      for (final e in m['items'] as List) {
        final j = e as Map<String, dynamic>;
        items.add(
          CleanupItem(
            id: j['id'] as String,
            name: j['name'] as String,
            description: j['desc'] as String,
            path: j['path'] as String,
            safety: CleanupSafety.values[j['safety'] as int],
            category: CleanupCategory.values.firstWhere(
              (c) => c.name == j['cat'],
              orElse: () => CleanupCategory.systemCaches,
            ),
            sizeBytes: j['size'] as int,
            lastModified: j['mod'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(j['mod'] as int),
            sizeIsPartial: j['partial'] as bool? ?? false,
            deleteContentsOnly: j['contents'] as bool? ?? true,
            requiresAdmin: j['admin'] as bool? ?? false,
            project: j['project'] as String?,
          ),
        );
      }
      return (
        at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        items: items,
      );
    } catch (e) {
      AppLogger.instance.debug(_tag, 'load scan failed: $e');
      return null;
    }
  }
}
