import 'dart:io';

import '../../domain/entities/cleanup_item.dart';

/// A place that may hold reclaimable data. Sizes are filled in by the scanner.
class CleanupTarget {
  const CleanupTarget({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
    required this.safety,
    required this.category,
    this.expandChildren = false,
    this.minChildBytes = 0,
    this.deleteContentsOnly = true,
    this.requiresAdmin = false,
  });

  final String id;
  final String name;
  final String description;
  final String path;
  final CleanupSafety safety;
  final CleanupCategory category;

  /// List each direct child as its own item (per-app caches, big downloads).
  final bool expandChildren;
  final int minChildBytes;
  final bool deleteContentsOnly;
  final bool requiresAdmin;
}

/// The only places Storage Sense will ever touch. Anything outside this list
/// (and the home directory) is refused by the deleter.
class CleanupCatalog {
  const CleanupCatalog._();

  static String get home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/';

  static List<CleanupTarget> forPlatform({
    String? homeDir,
    String? os,
    Map<String, String>? env,
  }) {
    final h = homeDir ?? home;
    final e = env ?? Platform.environment;
    final system = os ?? Platform.operatingSystem;
    final sep = system == 'windows' ? r'\' : '/';
    String j(List<String> parts) => parts.join(sep);

    final common = <CleanupTarget>[
      CleanupTarget(
        id: 'npm-cache',
        name: 'npm cache',
        description:
            'Downloaded npm packages. `npm install` fetches them again.',
        path: system == 'windows'
            ? j([
                e['LOCALAPPDATA'] ?? j([h, 'AppData', 'Local']),
                'npm-cache',
              ])
            : j([h, '.npm', '_cacache']),
        safety: CleanupSafety.safe,
        category: CleanupCategory.packages,
      ),
      CleanupTarget(
        id: 'gradle-caches',
        name: 'Gradle caches',
        description: 'Build caches. Rebuilt on the next Gradle build.',
        path: j([h, '.gradle', 'caches']),
        safety: CleanupSafety.safe,
        category: CleanupCategory.developer,
      ),
      CleanupTarget(
        id: 'gradle-dists',
        name: 'Gradle distributions',
        description: 'Downloaded Gradle versions.',
        path: j([h, '.gradle', 'wrapper', 'dists']),
        safety: CleanupSafety.safe,
        category: CleanupCategory.developer,
      ),
      CleanupTarget(
        id: 'pub-cache',
        name: 'Dart/Flutter pub cache',
        description: '`flutter pub get` re-downloads packages you still use.',
        path: system == 'windows'
            ? j([
                e['LOCALAPPDATA'] ?? j([h, 'AppData', 'Local']),
                'Pub',
                'Cache',
              ])
            : j([h, '.pub-cache']),
        safety: CleanupSafety.review,
        category: CleanupCategory.packages,
      ),
      CleanupTarget(
        id: 'downloads',
        name: 'Large download',
        description:
            'Personal file in Downloads. Only you know if you need it.',
        path: j([h, 'Downloads']),
        safety: CleanupSafety.manual,
        category: CleanupCategory.downloads,
        expandChildren: true,
        minChildBytes: 100 * 1024 * 1024,
        deleteContentsOnly: false,
      ),
    ];

    switch (system) {
      case 'macos':
        return [
          CleanupTarget(
            id: 'mac-app-caches',
            name: 'App cache',
            description: 'Temporary files apps rebuild when needed.',
            path: j([h, 'Library', 'Caches']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
            expandChildren: true,
            minChildBytes: 20 * 1024 * 1024,
          ),
          CleanupTarget(
            id: 'mac-logs',
            name: 'User logs',
            description: 'Old app and crash logs.',
            path: j([h, 'Library', 'Logs']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.logs,
          ),
          CleanupTarget(
            id: 'mac-trash',
            name: 'Trash',
            description: 'Files you already deleted.',
            path: j([h, '.Trash']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.trash,
          ),
          CleanupTarget(
            id: 'xcode-derived',
            name: 'Xcode DerivedData',
            description: 'Build products and indexes. Xcode regenerates them.',
            path: j([h, 'Library', 'Developer', 'Xcode', 'DerivedData']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.developer,
          ),
          CleanupTarget(
            id: 'xcode-archives',
            name: 'Xcode Archives',
            description: 'Past app archives. You cannot rebuild old releases.',
            path: j([h, 'Library', 'Developer', 'Xcode', 'Archives']),
            safety: CleanupSafety.review,
            category: CleanupCategory.developer,
          ),
          CleanupTarget(
            id: 'xcode-device-support',
            name: 'iOS DeviceSupport',
            description:
                'Symbols for connected devices. Re-downloaded on connect.',
            path: j([h, 'Library', 'Developer', 'Xcode', 'iOS DeviceSupport']),
            safety: CleanupSafety.review,
            category: CleanupCategory.developer,
          ),
          CleanupTarget(
            id: 'ios-simulators',
            name: 'iOS Simulators',
            description:
                'Simulator devices and their data. Deleting resets them.',
            path: j([h, 'Library', 'Developer', 'CoreSimulator', 'Devices']),
            safety: CleanupSafety.review,
            category: CleanupCategory.developer,
          ),
          const CleanupTarget(
            id: 'mac-system-caches',
            name: 'System caches',
            description: 'Shared caches for all users. Rebuilt automatically.',
            path: '/Library/Caches',
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
            requiresAdmin: true,
          ),
          const CleanupTarget(
            id: 'mac-diagnostic-reports',
            name: 'System crash reports',
            description: 'Old crash and diagnostic reports.',
            path: '/Library/Logs/DiagnosticReports',
            safety: CleanupSafety.safe,
            category: CleanupCategory.logs,
            requiresAdmin: true,
          ),
          CleanupTarget(
            id: 'cocoapods',
            name: 'CocoaPods specs repos',
            description: '`pod setup` rebuilds them.',
            path: j([h, '.cocoapods', 'repos']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.packages,
          ),
          ...common,
        ];
      case 'windows':
        final local = e['LOCALAPPDATA'] ?? j([h, 'AppData', 'Local']);
        return [
          CleanupTarget(
            id: 'win-temp',
            name: 'Temporary files',
            description: 'Leftovers from installers and apps.',
            path: e['TEMP'] ?? j([local, 'Temp']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
          ),
          CleanupTarget(
            id: 'win-system-temp',
            name: 'System temporary files',
            description: 'Temp files shared by all users and services.',
            path: j([e['WINDIR'] ?? r'C:\Windows', 'Temp']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
            requiresAdmin: true,
          ),
          CleanupTarget(
            id: 'win-update-cache',
            name: 'Windows Update downloads',
            description:
                'Already-installed update files. Windows re-downloads if needed.',
            path: j([
              e['WINDIR'] ?? r'C:\Windows',
              'SoftwareDistribution',
              'Download',
            ]),
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
            requiresAdmin: true,
          ),
          CleanupTarget(
            id: 'win-crash',
            name: 'Crash dumps',
            description: 'Application crash reports.',
            path: j([local, 'CrashDumps']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.logs,
          ),
          ...common,
        ];
      default:
        return [
          CleanupTarget(
            id: 'linux-cache',
            name: 'App cache',
            description: 'Temporary files apps rebuild when needed.',
            path: j([h, '.cache']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.systemCaches,
            expandChildren: true,
            minChildBytes: 20 * 1024 * 1024,
          ),
          const CleanupTarget(
            id: 'linux-crash',
            name: 'System crash reports',
            description: 'Old crash dumps written by the system.',
            path: '/var/crash',
            safety: CleanupSafety.safe,
            category: CleanupCategory.logs,
            requiresAdmin: true,
          ),
          const CleanupTarget(
            id: 'linux-coredumps',
            name: 'Core dumps',
            description: 'Memory dumps from crashed programs.',
            path: '/var/lib/systemd/coredump',
            safety: CleanupSafety.safe,
            category: CleanupCategory.logs,
            requiresAdmin: true,
          ),
          CleanupTarget(
            id: 'linux-trash',
            name: 'Trash',
            description: 'Files you already deleted.',
            path: j([h, '.local', 'share', 'Trash', 'files']),
            safety: CleanupSafety.safe,
            category: CleanupCategory.trash,
          ),
          ...common,
        ];
    }
  }
}
