




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

  
  
  final String id;

  final String? mountPoint;
  final String? volumeName;
  final String? filesystem;
  final String? volumeUuid;

  final bool isReadOnly;
  final bool isBootVolume;

  
  
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
