import 'dart:io';
import 'dart:isolate';

import '../../domain/entities/cleanup_item.dart';
import 'size_measurer.dart';

/// A regenerable build folder, and the files that prove it belongs to a real
/// project (so a random folder called "build" is never touched).
class ArtifactRule {
  const ArtifactRule(this.name, this.markers, this.safety, this.label);
  final String name;
  final Set<String> markers;
  final CleanupSafety safety;
  final String label;
}

const artifactRules = <ArtifactRule>[
  ArtifactRule(
    'node_modules',
    {'package.json'},
    CleanupSafety.safe,
    'Installed npm packages. `npm install` restores them.',
  ),
  ArtifactRule(
    '.dart_tool',
    {'pubspec.yaml'},
    CleanupSafety.safe,
    'Dart tool cache. `flutter pub get` restores it.',
  ),
  ArtifactRule(
    'Pods',
    {'Podfile'},
    CleanupSafety.safe,
    'CocoaPods dependencies. `pod install` restores them.',
  ),
  ArtifactRule(
    'target',
    {'Cargo.toml', 'pom.xml'},
    CleanupSafety.safe,
    'Compiler output. Rebuilt on the next build.',
  ),
  ArtifactRule(
    '.gradle',
    {
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
      'settings.gradle.kts',
    },
    CleanupSafety.safe,
    'Gradle project cache.',
  ),
  ArtifactRule(
    '.next',
    {'package.json'},
    CleanupSafety.safe,
    'Next.js build cache.',
  ),
  ArtifactRule(
    '.build',
    {'Package.swift'},
    CleanupSafety.safe,
    'Swift package build output.',
  ),
  ArtifactRule(
    'build',
    {
      'pubspec.yaml',
      'build.gradle',
      'build.gradle.kts',
      'package.json',
      'CMakeLists.txt',
    },
    CleanupSafety.review,
    'Build output. Rebuilding takes time.',
  ),
  ArtifactRule(
    'dist',
    {'package.json'},
    CleanupSafety.review,
    'Distribution output. Rebuild to recreate.',
  ),
  ArtifactRule(
    '.venv',
    {'pyproject.toml', 'requirements.txt'},
    CleanupSafety.review,
    'Python virtual environment. Recreate and reinstall to restore.',
  ),
];

ArtifactRule? artifactRuleFor(String path) {
  final sep = Platform.pathSeparator;
  final i = path.lastIndexOf(sep);
  if (i <= 0) return null;
  final name = path.substring(i + 1);
  final parent = path.substring(0, i);
  for (final r in artifactRules) {
    if (r.name != name) continue;
    for (final m in r.markers) {
      if (File('$parent$sep$m').existsSync()) return r;
    }
  }
  return null;
}

/// True when [path] is a known build folder next to its project marker.
bool isProjectArtifact(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.directory &&
    artifactRuleFor(path) != null;

class _Found {
  const _Found(this.project, this.artifact);
  final String project;
  final String artifact;
}

List<_Found> _walk(List<String> roots, int maxDepth, int budgetMs) {
  final sw = Stopwatch()..start();
  final sep = Platform.pathSeparator;
  final out = <_Found>[];
  const skip = {
    'Library',
    '.git',
    '.Trash',
    'node_modules',
    '.cache',
    'Applications',
    'AppData',
  };

  void visit(Directory dir, int depth) {
    if (sw.elapsedMilliseconds > budgetMs || out.length > 400) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    // Artifacts directly inside this directory.
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = e.path.split(sep).last;
      if (artifactRules.any((r) => r.name == name) &&
          artifactRuleFor(e.path) != null) {
        out.add(_Found(dir.path, e.path));
      }
    }
    if (depth >= maxDepth) return;
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = e.path.split(sep).last;
      if (skip.contains(name) ||
          artifactRules.any((r) => r.name == name) ||
          (name.startsWith('.') && name != '.')) {
        continue;
      }
      visit(e, depth + 1);
    }
  }

  for (final r in roots) {
    final d = Directory(r);
    if (d.existsSync()) visit(d, 0);
  }
  return out;
}

/// Finds node_modules, build, .dart_tool … inside the user's code folders.
class ProjectScanner {
  ProjectScanner({
    this.maxDepth = 5,
    this.minBytes = 5 * 1024 * 1024,
    this.measurer,
  });

  final int maxDepth;
  final int minBytes;
  final SizeMeasurer? measurer;

  static List<String> defaultRoots(String home) {
    final sep = Platform.pathSeparator;
    return [
      for (final n in const [
        'Developer',
        'Projects',
        'dev',
        'code',
        'src',
        'repos',
        'workspace',
        'Work',
        'Documents',
        'Desktop',
      ])
        '$home$sep$n',
    ];
  }

  Future<List<CleanupItem>> scan(
    List<String> roots, {
    void Function(int done, int total, String current)? onProgress,
    void Function(List<CleanupItem>)? onItems,
    bool Function()? isCancelled,
  }) async {
    // The directory walk is the only heavy sequential part: keep it off the
    // UI isolate.
    final found = await Isolate.run(() => _walk(roots, maxDepth, 15000));
    final m = measurer ?? await defaultMeasurer();
    final items = <CleanupItem>[];
    var next = 0;
    var done = 0;
    final sep = Platform.pathSeparator;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        if (next >= found.length) return;
        final f = found[next++];
        final rule = artifactRuleFor(f.artifact);
        if (rule == null) {
          done++;
          continue;
        }
        final project = f.project.split(sep).last;
        onProgress?.call(done, found.length, '$project/${rule.name}');
        final r = await m.measure(
          f.artifact,
          budget: const Duration(seconds: 20),
        );
        done++;
        if (r.bytes >= minBytes) {
          final item = CleanupItem(
            id: 'proj:${f.artifact}',
            name: rule.name,
            description: rule.label,
            path: f.artifact,
            safety: rule.safety,
            category: CleanupCategory.projects,
            sizeBytes: r.bytes,
            fileCount: r.files,
            lastModified: r.modified,
            sizeIsPartial: r.partial,
            deleteContentsOnly: false,
            project: project,
          );
          items.add(item);
          onItems?.call([item]);
        }
        onProgress?.call(done, found.length, '$project/${rule.name}');
      }
    }

    onProgress?.call(0, found.length, 'Project build folders');
    await Future.wait(
      List.generate(m.concurrency.clamp(2, 8), (_) => worker()),
    );
    return items;
  }
}
