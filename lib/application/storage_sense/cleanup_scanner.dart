import 'dart:async';
import 'dart:io';

import '../../domain/entities/cleanup_item.dart';
import 'cleanup_catalog.dart';
import 'size_measurer.dart';

class SizeResult {
  const SizeResult(this.bytes, this.files, this.modified, this.partial);
  final int bytes;
  final int files;
  final DateTime? modified;
  final bool partial;
}

/// Measures [path] without following symlinks, stopping at [budget].
/// Top-level so it can run in a background isolate.
SizeResult measurePath(String path, Duration budget) {
  final sw = Stopwatch()..start();
  var bytes = 0;
  var files = 0;
  DateTime? modified;
  var partial = false;
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      final st = File(path).statSync();
      return SizeResult(st.size, 1, st.modified, false);
    }
    if (type != FileSystemEntityType.directory) {
      return const SizeResult(0, 0, null, false);
    }
    modified = Directory(path).statSync().modified;
    final stack = <Directory>[Directory(path)];
    while (stack.isNotEmpty) {
      if (sw.elapsed > budget) {
        partial = true;
        break;
      }
      final dir = stack.removeLast();
      try {
        for (final e in dir.listSync(followLinks: false)) {
          if (e is Link) continue;
          if (e is Directory) {
            stack.add(e);
          } else if (e is File) {
            try {
              final st = e.statSync();
              bytes += st.size;
              files++;
              if (modified == null || st.modified.isAfter(modified)) {
                modified = st.modified;
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        // Unreadable folder (permissions) — skip it.
      }
    }
  } catch (_) {}
  return SizeResult(bytes, files, modified, partial);
}

/// Live scan status for the UI.
class ScanProgress {
  const ScanProgress({
    required this.done,
    required this.total,
    required this.current,
    required this.foundBytes,
    this.listing = false,
  });

  final int done;

  /// Known work items so far (grows while folders are being listed).
  final int total;
  final String current;
  final int foundBytes;

  /// Still discovering what to measure (total not final yet).
  final bool listing;

  double? get fraction => (listing || total == 0) ? null : done / total;
}

/// One reportable item whose size is the sum of its measured parts.
class _Group {
  _Group(this.target, this.path, this.name, this.id, this.isChild);
  final CleanupTarget target;
  final String path;
  final String name;
  final String id;
  final bool isChild;
  int bytes = 0;
  int pending = 0;
  bool partial = false;
  DateTime? modified;
}

class _Task {
  const _Task(this.group, this.path);
  final _Group group;
  final String path;
}

/// Finds reclaimable space quickly. Everything to measure is listed first;
/// big folders are split into their sub-folders so a single huge cache can't
/// serialise the scan; then many parts are measured at once (native `du`, or
/// isolates) and finished items stream out as they complete.
class CleanupScanner {
  CleanupScanner({
    this.measurer,
    this.perTargetBudget = const Duration(seconds: 30),
    this.splitDepth = 1,
    this.maxTasksPerTarget = 400,
  });

  /// Defaults to the best measurer for the platform.
  final SizeMeasurer? measurer;
  final Duration perTargetBudget;

  /// How many folder levels a large target is split into for parallelism.
  final int splitDepth;
  final int maxTasksPerTarget;

  Future<List<CleanupItem>> scan(
    List<CleanupTarget> targets, {
    void Function(ScanProgress)? onProgress,
    void Function(List<CleanupItem>)? onItems,
    bool Function()? isCancelled,
  }) async {
    final m = measurer ?? await defaultMeasurer();
    final results = <CleanupItem>[];
    var found = 0;
    var done = 0;
    var total = 0;
    var listing = true;
    var current = 'Preparing…';
    final sep = Platform.pathSeparator;

    void report() => onProgress?.call(
      ScanProgress(
        done: done,
        total: total,
        current: current,
        foundBytes: found,
        listing: listing,
      ),
    );

    void finish(_Group g) {
      if (g.bytes <= 0 || g.bytes < g.target.minChildBytes) return;
      final isFile = FileSystemEntity.isFileSync(g.path);
      final item = CleanupItem(
        id: g.id,
        name: g.name,
        description: g.target.description,
        path: g.path,
        safety: g.target.safety,
        category: g.target.category,
        sizeBytes: g.bytes,
        lastModified: g.modified,
        sizeIsPartial: g.partial,
        deleteContentsOnly:
            g.target.deleteContentsOnly && !(g.isChild && isFile),
        requiresAdmin: g.target.requiresAdmin,
      );
      results.add(item);
      found += g.bytes;
      onItems?.call([item]);
    }

    Future<int> statSize(String path) async {
      try {
        return (await FileStat.stat(path)).size;
      } catch (_) {
        return 0;
      }
    }

    /// Lists [dir]; loose files are summed immediately, sub-folders are
    /// returned for measuring (or further splitting).
    Future<(int, List<String>)> listOne(String dir) async {
      var fileBytes = 0;
      final dirs = <String>[];
      try {
        await for (final e in Directory(dir).list(followLinks: false)) {
          if (e is Link) continue;
          if (e is Directory) {
            dirs.add(e.path);
          } else if (e is File) {
            fileBytes += await statSize(e.path);
          }
        }
      } catch (_) {}
      return (fileBytes, dirs);
    }

    // 1) Discover work (cheap async listing, all targets at once).
    final tasks = <_Task>[];
    final groups = <_Group>[];
    await Future.wait([
      for (final t in targets)
        () async {
          if (!await Directory(t.path).exists()) return;
          if (t.expandChildren) {
            try {
              await for (final e in Directory(
                t.path,
              ).list(followLinks: false)) {
                if (e is Link) continue;
                final base = e.path.split(sep).last;
                final g = _Group(
                  t,
                  e.path,
                  t.deleteContentsOnly ? '${t.name}: $base' : base,
                  '${t.id}:$base',
                  true,
                )..pending = 1;
                groups.add(g);
                tasks.add(_Task(g, e.path));
              }
            } catch (_) {}
            return;
          }

          final g = _Group(t, t.path, t.name, t.id, false);
          try {
            g.modified = (await FileStat.stat(t.path)).modified;
          } catch (_) {}
          groups.add(g);

          // Split into sub-folders so one huge folder runs in parallel.
          var frontier = [t.path];
          final parts = <String>[];
          for (var level = 0; level < splitDepth; level++) {
            final next = <String>[];
            for (final dir in frontier) {
              final (fileBytes, dirs) = await listOne(dir);
              g.bytes += fileBytes;
              next.addAll(dirs);
            }
            if (next.isEmpty) {
              frontier = const [];
              break;
            }
            if (next.length > maxTasksPerTarget) {
              // Too fragmented to split further: measure this level whole.
              parts.addAll(next);
              frontier = const [];
              break;
            }
            frontier = next;
          }
          parts.addAll(frontier);
          g.pending = parts.length;
          for (final p in parts) {
            tasks.add(_Task(g, p));
          }
        }(),
    ]);
    // Parts of big targets first (they run longest), small expansions last.
    tasks.sort(
      (a, b) => (a.group.isChild ? 1 : 0).compareTo(b.group.isChild ? 1 : 0),
    );
    total = tasks.length;
    listing = false;
    for (final g in groups) {
      if (g.pending == 0) finish(g); // only loose files
    }
    report();

    // 2) Measure with a bounded pool.
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        if (next >= tasks.length) return;
        final task = tasks[next++];
        current = task.group.name;
        report();
        final r = await m.measure(task.path, budget: perTargetBudget);
        done++;
        final g = task.group;
        g.bytes += r.bytes;
        g.partial = g.partial || r.partial;
        g.modified ??= r.modified;
        if (--g.pending == 0) finish(g);
        report();
      }
    }

    await Future.wait(List.generate(m.concurrency, (_) => worker()));
    return results;
  }
}
