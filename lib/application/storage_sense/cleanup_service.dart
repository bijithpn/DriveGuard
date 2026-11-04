import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../core/logging/app_logger.dart';
import '../protection/privileged_runner.dart';
import '../../core/utils/safe_process_runner.dart';
import '../../domain/entities/cleanup_item.dart';
import 'cleanup_catalog.dart';
import 'project_scanner.dart';

/// Deletes [CleanupItem]s — but only ever inside the folders in the
/// [CleanupCatalog]. Every path is resolved (symlinks included) and checked
/// against the catalog roots immediately before deletion, so a bad item, a
/// symlink pointing elsewhere or a stale path can never escape.
///
/// Safe items are removed permanently. Review/manual items go to the Trash so
/// the user can undo; if the Trash is unavailable they are NOT deleted.
class CleanupService {
  CleanupService({
    required List<CleanupTarget> targets,
    SafeProcessRunner? runner,
    String? operatingSystem,
    Future<bool> Function(String path)? trash,
    PrivilegedRunner? privileged,
    List<String>? projectRoots,
  }) : _privileged = privileged,
       _projectRoots = projectRoots,
       _runner = runner ?? SafeProcessRunner.instance,
       _os = operatingSystem ?? Platform.operatingSystem,
       _trashOverride = trash,
       _roots = [
         for (final t in targets)
           if (_resolve(t.path) != null) _resolve(t.path)!,
       ];

  static const _tag = 'CleanupService';
  final SafeProcessRunner _runner;
  final String _os;
  final Future<bool> Function(String path)? _trashOverride;
  final List<String> _roots;
  final PrivilegedRunner? _privileged;
  final List<String>? _projectRoots;

  static String? _resolve(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.notFound
          ? null
          : (FileSystemEntity.isDirectorySync(path)
                ? Directory(path).resolveSymbolicLinksSync()
                : File(path).resolveSymbolicLinksSync());
    } catch (_) {
      return null;
    }
  }

  /// True only for an existing, non-symlink path inside a catalog root.
  bool isAllowed(String path) {
    final sep = Platform.pathSeparator;
    final home = CleanupCatalog.home;
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      return false;
    }
    final resolved = _resolve(path);
    if (resolved == null) return false;
    if (resolved == home || resolved == sep || resolved.length < 4) {
      return false;
    }
    // Build folders of real projects (node_modules, build, …) anywhere under
    // the user's code folders — validated by their project marker file.
    final pRoots = [
      for (final r in _projectRoots ?? [home]) _resolve(r) ?? r,
    ];
    if (pRoots.any(
          (r) => resolved.startsWith(r.endsWith(sep) ? r : '$r$sep'),
        ) &&
        isProjectArtifact(resolved)) {
      return true;
    }
    return _roots.any(
      (r) =>
          resolved == r || resolved.startsWith(r.endsWith(sep) ? r : '$r$sep'),
    );
  }

  /// Deletes [items]. Items that need administrator rights are only touched
  /// when [allowAdmin] is true (i.e. the user confirmed it), and all of them
  /// are removed under a single OS authentication prompt.
  Future<CleanupResult> delete(
    List<CleanupItem> items, {
    bool allowAdmin = false,
  }) async {
    var freed = 0;
    var trashed = 0;
    var count = 0;
    final failures = <String, String>{};
    final needAdmin = <CleanupItem>[];

    for (final item in items) {
      if (!isAllowed(item.path)) {
        failures[item.id] = 'Outside the allowed cleanup locations';
        continue;
      }
      try {
        if (item.safety == CleanupSafety.safe) {
          if (item.requiresAdmin) {
            if (allowAdmin) {
              needAdmin.add(item);
            } else {
              failures[item.id] = 'Needs administrator permission';
            }
            continue;
          }
          final ok = await _deletePermanently(item);
          if (ok) {
            freed += item.sizeBytes;
            count++;
          } else if (allowAdmin) {
            // Some files were protected — retry the folder with admin rights.
            needAdmin.add(item);
          } else {
            failures[item.id] = 'Some files are in use or protected';
            count++;
          }
        } else {
          final ok = await _moveToTrash(item.path);
          if (ok) {
            trashed += item.sizeBytes;
            count++;
          } else {
            failures[item.id] = 'Could not move to Trash';
          }
        }
      } catch (e) {
        AppLogger.instance.warning(_tag, 'Delete failed for ${item.path}: $e');
        failures[item.id] = '$e';
      }
    }

    if (needAdmin.isNotEmpty) {
      final ok = await _deleteElevated(needAdmin);
      for (final item in needAdmin) {
        if (_isEmpty(item)) {
          freed += item.sizeBytes;
          count++;
        } else {
          failures[item.id] = ok
              ? 'Some files are in use and could not be removed'
              : 'Administrator permission was not granted';
        }
      }
    }

    return CleanupResult(
      freedBytes: freed,
      trashedBytes: trashed,
      deletedItems: count,
      failures: failures,
    );
  }

  bool _isEmpty(CleanupItem item) {
    try {
      if (!item.deleteContentsOnly) {
        return FileSystemEntity.typeSync(item.path, followLinks: false) ==
            FileSystemEntityType.notFound;
      }
      return Directory(item.path).listSync(followLinks: false).isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// One administrator prompt for every item. Paths were already validated
  /// against the catalog roots; the commands only ever *empty* or remove
  /// exactly those paths and never follow symlinks.
  Future<bool> _deleteElevated(List<CleanupItem> items) async {
    final priv = _privileged;
    if (priv == null || !await priv.isAvailable) return false;
    // Re-validate right before handing anything to a privileged process.
    final paths = [
      for (final i in items)
        if (isAllowed(i.path)) i,
    ];
    if (paths.isEmpty) return false;
    const reason =
        'DriveGuard needs administrator permission to remove system cache '
        'files and free up disk space.';
    if (_os == 'windows') {
      final script = paths
          .map((i) {
            final p = i.path.replaceAll("'", "''");
            return i.deleteContentsOnly
                ? "Get-ChildItem -LiteralPath '$p' -Force | "
                      "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"
                : "Remove-Item -LiteralPath '$p' -Recurse -Force "
                      "-ErrorAction SilentlyContinue";
          })
          .join('; ');
      return priv.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        _encodePs(script),
      ], reason: reason);
    }
    String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
    final script = paths
        .map(
          (i) => i.deleteContentsOnly
              ? 'find ${q(i.path)} -mindepth 1 -maxdepth 1 '
                    '-exec rm -rf -- {} +'
              : 'rm -rf -- ${q(i.path)}',
        )
        .join('; ');
    return priv.run('/bin/sh', ['-c', script], reason: reason);
  }

  static String _encodePs(String script) {
    final bytes = <int>[];
    for (final u in script.codeUnits) {
      bytes
        ..add(u & 0xFF)
        ..add(u >> 8);
    }
    return base64.encode(bytes);
  }

  /// Empties the whole system Trash / Recycle Bin (permanent). Review and
  /// Manual cleanups only move files there, so this is what really frees the
  /// space.
  Future<bool> emptyTrash() async {
    try {
      switch (_os) {
        case 'macos':
          await _runner.run('osascript', [
            '-e',
            'tell application "Finder" to empty trash',
          ], timeout: const Duration(minutes: 5));
          return true;
        case 'linux':
          await _runner.run('gio', [
            'trash',
            '--empty',
          ], timeout: const Duration(minutes: 5));
          return true;
        case 'windows':
          await _runner.run('powershell', [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            'Clear-RecycleBin -Force -ErrorAction Stop',
          ], timeout: const Duration(minutes: 5));
          return true;
      }
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Empty trash failed: $e');
    }
    return false;
  }

  Future<bool> _deletePermanently(CleanupItem item) {
    final path = item.path;
    final contentsOnly = item.deleteContentsOnly;
    return Isolate.run(() => deleteTree(path, contentsOnly: contentsOnly));
  }

  Future<bool> _moveToTrash(String path) async {
    final override = _trashOverride;
    if (override != null) return override(path);
    try {
      switch (_os) {
        case 'macos':
          final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
          await _runner.run('osascript', [
            '-e',
            'tell application "Finder" to delete POSIX file "$escaped"',
          ], timeout: const Duration(seconds: 60));
          return true;
        case 'linux':
          await _runner.run('gio', ['trash', path]);
          return true;
        case 'windows':
          final p = path.replaceAll("'", "''");
          final isDir = FileSystemEntity.isDirectorySync(path);
          await _runner.run('powershell', [
            '-NoProfile',
            '-Command',
            "Add-Type -AssemblyName Microsoft.VisualBasic; "
                "[Microsoft.VisualBasic.FileIO.FileSystem]::"
                "${isDir ? 'DeleteDirectory' : 'DeleteFile'}"
                "('$p','OnlyErrorDialogs','SendToRecycleBin')",
          ], timeout: const Duration(seconds: 60));
          return true;
      }
    } catch (e) {
      AppLogger.instance.warning(_tag, 'Trash failed for $path: $e');
    }
    return false;
  }
}

/// Removes [path] (or just its contents). Returns false if anything could not
/// be removed. Top-level so it can run in an isolate.
bool deleteTree(String path, {required bool contentsOnly}) {
  var clean = true;
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      File(path).deleteSync();
      return true;
    }
    if (type != FileSystemEntityType.directory) return true;
    if (!contentsOnly) {
      Directory(path).deleteSync(recursive: true);
      return true;
    }
    for (final e in Directory(path).listSync(followLinks: false)) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {
        clean = false;
      }
    }
  } catch (_) {
    clean = false;
  }
  return clean;
}
