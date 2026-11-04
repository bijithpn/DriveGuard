import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../domain/entities/cleanup_item.dart';
import 'cleanup_catalog.dart';

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

List<String> _listChildren(String path) {
  try {
    return Directory(path)
        .listSync(followLinks: false)
        .where((e) => e is! Link)
        .map((e) => e.path)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Finds reclaimable space. Heavy filesystem walking happens off the UI
/// isolate, a few targets at a time.
class CleanupScanner {
  const CleanupScanner({
    this.perTargetBudget = const Duration(seconds: 25),
    this.concurrency = 4,
  });

  final Duration perTargetBudget;
  final int concurrency;

  Future<List<CleanupItem>> scan(
    List<CleanupTarget> targets, {
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <CleanupItem>[];
    var done = 0;
    final queue = List<CleanupTarget>.of(targets);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final t = queue.removeAt(0);
        final items = await _scanTarget(t);
        results.addAll(items);
        onProgress?.call(++done, targets.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return results;
  }

  Future<List<CleanupItem>> _scanTarget(CleanupTarget t) async {
    if (!Directory(t.path).existsSync()) return const [];
    if (!t.expandChildren) {
      final r = await Isolate.run(() => measurePath(t.path, perTargetBudget));
      if (r.bytes <= 0) return const [];
      return [_item(t, t.path, t.name, r, t.id)];
    }
    final children = await Isolate.run(() => _listChildren(t.path));
    final out = <CleanupItem>[];
    for (final child in children) {
      final r = await Isolate.run(() => measurePath(child, perTargetBudget));
      if (r.bytes < t.minChildBytes || r.bytes <= 0) continue;
      final base = child.split(Platform.pathSeparator).last;
      final isFile = FileSystemEntity.isFileSync(child);
      out.add(
        _item(
          t,
          child,
          t.deleteContentsOnly ? '${t.name}: $base' : base,
          r,
          '${t.id}:$base',
          contentsOnly: t.deleteContentsOnly && !isFile,
        ),
      );
    }
    return out;
  }

  CleanupItem _item(
    CleanupTarget t,
    String path,
    String name,
    SizeResult r,
    String id, {
    bool? contentsOnly,
  }) => CleanupItem(
    id: id,
    name: name,
    description: t.description,
    path: path,
    safety: t.safety,
    category: t.category,
    sizeBytes: r.bytes,
    fileCount: r.files,
    lastModified: r.modified,
    sizeIsPartial: r.partial,
    deleteContentsOnly: contentsOnly ?? t.deleteContentsOnly,
    requiresAdmin: t.requiresAdmin,
  );
}
