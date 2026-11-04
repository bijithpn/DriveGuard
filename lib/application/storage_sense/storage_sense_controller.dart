import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/cleanup_item.dart';
import '../../domain/entities/storage_device.dart';
import '../../domain/enums/storage_enums.dart';
import '../providers.dart';
import 'cleanup_catalog.dart';
import 'cleanup_scanner.dart';
import 'cleanup_service.dart';
import 'project_scanner.dart';
import 'size_measurer.dart';

enum SenseStatus { idle, scanning, ready, deleting }

class StorageSenseState {
  const StorageSenseState({
    this.status = SenseStatus.idle,
    this.items = const [],
    this.selected = const {},
    this.progress = 0,
    this.scanProgress,
    this.scanPhase = '',
    this.query = '',
    this.reclaimedBytes = 0,
    this.trashedBytes = 0,
    this.message,
    this.hasScanned = false,
    this.groupByProject = false,
    this.cachedAt,
  });

  final SenseStatus status;
  final List<CleanupItem> items;
  final Set<String> selected;
  final double progress;

  /// Live detail while scanning (null otherwise).
  final ScanProgress? scanProgress;
  final String scanPhase;
  final String query;
  final int reclaimedBytes;
  final int trashedBytes;
  final String? message;
  final bool hasScanned;
  final bool groupByProject;

  /// Set while showing results from a previous scan that is being refreshed.
  final DateTime? cachedAt;

  int bytesFor(CleanupSafety s) => items
      .where((i) => i.safety == s)
      .fold<int>(0, (sum, i) => sum + i.sizeBytes);

  int get totalReclaimable => items.fold<int>(0, (s, i) => s + i.sizeBytes);

  int get selectedBytes => items
      .where((i) => selected.contains(i.id))
      .fold<int>(0, (s, i) => s + i.sizeBytes);

  List<CleanupItem> get visible {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return [
      for (final i in items)
        if (i.name.toLowerCase().contains(q) ||
            i.description.toLowerCase().contains(q) ||
            i.path.toLowerCase().contains(q))
          i,
    ];
  }

  StorageSenseState copyWith({
    SenseStatus? status,
    List<CleanupItem>? items,
    Set<String>? selected,
    double? progress,
    ScanProgress? scanProgress,
    bool clearScanProgress = false,
    String? scanPhase,
    String? query,
    int? reclaimedBytes,
    int? trashedBytes,
    String? message,
    bool clearMessage = false,
    bool? hasScanned,
    bool? groupByProject,
    DateTime? cachedAt,
    bool clearCachedAt = false,
  }) => StorageSenseState(
    status: status ?? this.status,
    items: items ?? this.items,
    selected: selected ?? this.selected,
    progress: progress ?? this.progress,
    scanProgress: clearScanProgress
        ? null
        : (scanProgress ?? this.scanProgress),
    scanPhase: scanPhase ?? this.scanPhase,
    query: query ?? this.query,
    reclaimedBytes: reclaimedBytes ?? this.reclaimedBytes,
    trashedBytes: trashedBytes ?? this.trashedBytes,
    message: clearMessage ? null : (message ?? this.message),
    hasScanned: hasScanned ?? this.hasScanned,
    groupByProject: groupByProject ?? this.groupByProject,
    cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
  );
}

class StorageSenseController extends Notifier<StorageSenseState> {
  late final List<CleanupTarget> _targets = CleanupCatalog.forPlatform();
  late final CleanupService _service = CleanupService(
    targets: _targets,
    privileged: ref.read(privilegedRunnerProvider),
  );

  @override
  StorageSenseState build() => const StorageSenseState();

  bool _cancelScan = false;

  /// Stops an in-progress scan; whatever was found so far stays listed.
  void cancelScan() => _cancelScan = true;

  Future<void> scan() async {
    if (state.status == SenseStatus.scanning ||
        state.status == SenseStatus.deleting) {
      return;
    }
    _cancelScan = false;

    // Show the previous scan immediately (only entries that still exist) so
    // the page is useful from the first frame while the fresh scan runs.
    final repo = ref.read(localStateRepositoryProvider);
    final cached = state.hasScanned ? null : await repo?.loadScan();
    final stale = [
      if (cached != null)
        for (final i in cached.items)
          if (FileSystemEntity.typeSync(i.path, followLinks: false) !=
              FileSystemEntityType.notFound)
            i,
    ];
    state = state.copyWith(
      status: SenseStatus.scanning,
      progress: 0,
      items: stale,
      cachedAt: stale.isEmpty ? null : cached!.at,
      selected: {},
      scanPhase: 'Looking for caches and logs',
      clearMessage: true,
    );

    final measurer = await defaultMeasurer();
    final found = <CleanupItem>[];
    var sysDone = 0, sysTotal = 0, projDone = 0, projTotal = 0;
    var sysListing = true;
    var foundBytes = 0;
    var current = '';
    var best = 0.0;

    void publish() {
      // The first fresh result replaces the cached snapshot.
      if (state.cachedAt != null && found.isNotEmpty) {
        state = state.copyWith(clearCachedAt: true);
      }
      final total = sysTotal + projTotal;
      var frac = total == 0 ? 0.0 : (sysDone + projDone) / total;
      if (sysListing) frac = 0;
      best = frac > best ? frac : best; // never move backwards
      found.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      state = state.copyWith(
        items: List.of(found),
        progress: best,
        scanProgress: ScanProgress(
          done: sysDone + projDone,
          total: total,
          current: current,
          foundBytes: foundBytes,
          listing: sysListing,
        ),
      );
    }

    void addItems(List<CleanupItem> more) {
      for (final i in more) {
        found.add(i);
        foundBytes += i.sizeBytes;
      }
    }

    await Future.wait([
      CleanupScanner(measurer: measurer).scan(
        _targets,
        isCancelled: () => _cancelScan,
        onItems: addItems,
        onProgress: (p) {
          sysDone = p.done;
          sysTotal = p.total;
          sysListing = p.listing;
          current = p.current;
          publish();
        },
      ),
      ProjectScanner(measurer: measurer).scan(
        ProjectScanner.defaultRoots(CleanupCatalog.home),
        isCancelled: () => _cancelScan,
        onItems: addItems,
        onProgress: (d, t, c) {
          projDone = d;
          projTotal = t;
          if (sysListing || c.isNotEmpty) current = c;
          publish();
        },
      ),
    ]);

    found.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final cancelled = _cancelScan;
    state = state.copyWith(
      status: SenseStatus.ready,
      items: found.isEmpty && cancelled ? state.items : found,
      progress: 1,
      clearScanProgress: true,
      clearCachedAt: found.isNotEmpty || !cancelled,
      hasScanned: true,
    );
    if (!cancelled && repo != null) {
      unawaited(repo.saveScan(found, DateTime.now()));
    }
  }

  void setGroupByProject(bool v) => state = state.copyWith(groupByProject: v);

  /// Permanently empties the system Trash, finally freeing space that
  /// Review/Manual cleanups only moved there.
  Future<void> emptyTrash() async {
    if (state.status == SenseStatus.deleting) return;
    state = state.copyWith(status: SenseStatus.deleting, clearMessage: true);
    final ok = await _service.emptyTrash();
    final freed = state.trashedBytes;
    state = state.copyWith(
      status: SenseStatus.ready,
      trashedBytes: ok ? 0 : state.trashedBytes,
      reclaimedBytes: ok ? state.reclaimedBytes + freed : state.reclaimedBytes,
      message: ok
          ? 'Trash emptied — ${formatBytes(freed)} of your cleanups is now free'
          : 'Could not empty the Trash',
    );
    unawaited(ref.read(monitoringServiceProvider).rescan());
  }

  void setQuery(String q) => state = state.copyWith(query: q);

  void toggle(String id) {
    final next = {...state.selected};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(selected: next);
  }

  /// Selects every item that is regenerated automatically.
  void selectSafe() => state = state.copyWith(
    selected: {
      for (final i in state.items)
        // Admin items prompt for a password, so they are never auto-picked.
        if (i.safety == CleanupSafety.safe && !i.requiresAdmin) i.id,
    },
  );

  void clearSelection() => state = state.copyWith(selected: {});

  Future<void> deleteItems(Set<String> ids) => _delete([
    for (final i in state.items)
      if (ids.contains(i.id)) i,
  ]);

  Future<void> _delete(List<CleanupItem> items) async {
    if (items.isEmpty || state.status == SenseStatus.deleting) return;
    state = state.copyWith(status: SenseStatus.deleting, clearMessage: true);
    final result = await _service.delete(items, allowAdmin: true);
    final removed = {
      for (final i in items)
        if (!result.failures.containsKey(i.id)) i.id,
    };
    final remaining = [
      for (final i in state.items)
        if (!removed.contains(i.id)) i,
    ];
    final parts = <String>[];
    if (result.freedBytes > 0) {
      parts.add('Freed ${formatBytes(result.freedBytes)}');
    }
    if (result.trashedBytes > 0) {
      parts.add(
        '${formatBytes(result.trashedBytes)} moved to Trash — '
        'empty the Trash to reclaim it',
      );
    }
    if (result.failures.isNotEmpty) {
      parts.add('${result.failures.length} item(s) could not be removed');
    }
    state = state.copyWith(
      status: SenseStatus.ready,
      items: remaining,
      selected: {...state.selected}..removeAll(removed),
      reclaimedBytes: state.reclaimedBytes + result.freedBytes,
      trashedBytes: state.trashedBytes + result.trashedBytes,
      message: parts.join(' · '),
    );
    // Refresh drive capacity so the donut/alerts reflect the new free space.
    unawaited(ref.read(monitoringServiceProvider).rescan());
  }

  Future<void> reveal(String path) async {
    try {
      if (Platform.isMacOS) {
        await SafeProcessRunner.instance.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await SafeProcessRunner.instance.run('explorer', [
          '/select,$path',
        ], requireZeroExit: false);
      } else {
        await SafeProcessRunner.instance.run('xdg-open', [
          FileSystemEntity.isDirectorySync(path)
              ? path
              : File(path).parent.path,
        ]);
      }
    } catch (_) {}
  }
}

final storageSenseProvider =
    NotifierProvider<StorageSenseController, StorageSenseState>(
      StorageSenseController.new,
    );

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var u = 0;
  while (size >= 1024 && u < units.length - 1) {
    size /= 1024;
    u++;
  }
  return '${size.toStringAsFixed(u == 0 || size >= 100 ? 0 : 1)} ${units[u]}';
}

/// Totals for the volume that holds the user's home folder.
class VolumeUsage {
  const VolumeUsage({
    required this.name,
    required this.total,
    required this.used,
    required this.free,
    this.deviceName,
    this.isSsd = false,
    this.deviceId,
  });
  final String? deviceId;
  final String name;
  final int total;
  final int used;
  final int free;
  final String? deviceName;
  final bool isSsd;
}

VolumeUsage? homeVolumeUsage(List<StorageDevice> devices, {String? home}) {
  final h = home ?? CleanupCatalog.home;
  VolumeUsage? best;
  var bestLen = -1;
  for (final d in devices) {
    for (final v in d.volumes) {
      final mp = v.mountPoint;
      if (mp == null || v.totalBytes == null || v.freeBytes == null) continue;
      if (h == mp ||
          h.startsWith(mp.endsWith('/') ? mp : '$mp/') ||
          mp == '/') {
        if (mp.length > bestLen) {
          bestLen = mp.length;
          best = VolumeUsage(
            name: v.volumeName ?? mp,
            total: v.totalBytes!,
            used: v.usedBytes ?? (v.totalBytes! - v.freeBytes!),
            free: v.freeBytes!,
            deviceName: d.displayName,
            isSsd:
                d.type == StorageDeviceType.ssd ||
                d.type == StorageDeviceType.nvme,
          );
        }
      }
    }
  }
  if (best != null) return best;
  for (final d in devices) {
    final c = d.capacity;
    if (c.isValid && c.totalBytes != null && c.freeBytes != null) {
      return VolumeUsage(
        name: d.displayName,
        total: c.totalBytes!,
        used: c.usedBytes ?? c.totalBytes! - c.freeBytes!,
        free: c.freeBytes!,
        deviceName: d.displayName,
        isSsd:
            d.type == StorageDeviceType.ssd || d.type == StorageDeviceType.nvme,
      );
    }
  }
  return null;
}
