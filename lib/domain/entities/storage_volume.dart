/// A mounted filesystem volume living on a partition of a physical
/// [StorageDevice]. A physical disk may host zero (unformatted/raw), one, or
/// several volumes — this is deliberately a separate model from
/// [StorageDevice] so the UI never confuses filesystem usage with physical
/// disk health.
class StorageVolume {
  const StorageVolume({
    required this.id,
    this.mountPoint,
    this.volumeName,
    this.filesystem,
    this.volumeUuid,
    this.isReadOnly = false,
    this.isBootVolume = false,
    this.isEncrypted,
    this.totalBytes,
    this.usedBytes,
    this.freeBytes,
  });

  /// Stable identifier for this volume (platform-specific: APFS/HFS UUID on
  /// macOS, volume GUID path on Windows, device path on Linux).
  final String id;

  final String? mountPoint;
  final String? volumeName;
  final String? filesystem;
  final String? volumeUuid;

  final bool isReadOnly;
  final bool isBootVolume;

  /// `null` when encryption status could not be reliably determined (do not
  /// default this to `false` — that reads as "confirmed unencrypted").
  final bool? isEncrypted;

  final int? totalBytes;
  final int? usedBytes;
  final int? freeBytes;

  double? get usagePercent {
    if (totalBytes == null || usedBytes == null || totalBytes == 0) {
      return null;
    }
    return (usedBytes! / totalBytes!) * 100;
  }
}
