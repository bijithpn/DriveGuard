/// How risky it is to delete something.
///
/// * [safe]   – regenerated automatically (caches, logs, temp files).
/// * [review] – re-creatable but costs time or loses state (old simulators,
///              build archives, package caches). Moved to the Trash.
/// * [manual] – personal data. Never auto-selected; moved to the Trash.
enum CleanupSafety { safe, review, manual }

enum CleanupCategory {
  systemCaches('System & app caches'),
  logs('Logs & diagnostics'),
  trash('Trash'),
  developer('Developer tools'),
  packages('Package caches'),
  downloads('Downloads'),
  projects('Project build files');

  const CleanupCategory(this.label);
  final String label;
}

class CleanupItem {
  const CleanupItem({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
    required this.safety,
    required this.category,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.lastModified,
    this.sizeIsPartial = false,
    this.deleteContentsOnly = true,
    this.requiresAdmin = false,
    this.project,
  });

  final String id;
  final String name;
  final String description;
  final String path;
  final CleanupSafety safety;
  final CleanupCategory category;
  final int sizeBytes;
  final int fileCount;
  final DateTime? lastModified;

  /// The scan hit its time budget, so the real size is at least [sizeBytes].
  final bool sizeIsPartial;

  /// Empty the folder but keep the folder itself (true for caches that apps
  /// expect to exist); false removes the entry (e.g. one large download).
  final bool deleteContentsOnly;

  /// Owned by the system: deleting needs the OS administrator prompt.
  final bool requiresAdmin;

  /// Name of the project folder this item belongs to (project artifacts).
  final String? project;

  CleanupItem copyWith({
    int? sizeBytes,
    int? fileCount,
    DateTime? lastModified,
    bool? sizeIsPartial,
  }) => CleanupItem(
    id: id,
    name: name,
    description: description,
    path: path,
    safety: safety,
    category: category,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    fileCount: fileCount ?? this.fileCount,
    lastModified: lastModified ?? this.lastModified,
    sizeIsPartial: sizeIsPartial ?? this.sizeIsPartial,
    deleteContentsOnly: deleteContentsOnly,
    requiresAdmin: requiresAdmin,
    project: project,
  );
}

class CleanupResult {
  const CleanupResult({
    required this.freedBytes,
    required this.trashedBytes,
    required this.deletedItems,
    required this.failures,
  });

  /// Bytes permanently deleted (space is free immediately).
  final int freedBytes;

  /// Bytes moved to the Trash (space is freed once the Trash is emptied).
  final int trashedBytes;
  final int deletedItems;

  /// item id → reason.
  final Map<String, String> failures;
}
