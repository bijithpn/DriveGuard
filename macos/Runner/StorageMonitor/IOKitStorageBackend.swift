import DiskArbitration
import Foundation
import IOKit
import IOKit.storage

/// Native macOS storage enumeration via the public IOKit registry - no
/// subprocess, no private entitlement required.
///
/// Enumerates from `IOBlockStorageDevice` (IOKit's class-hierarchy match
/// also returns its concrete subclasses - `IOAHCIBlockStorageDevice` for
/// SATA, USB mass-storage device nubs, and Apple Silicon's
/// `IOEmbeddedNVMeBlockDevice` for the internal NVMe controller). This is
/// the real physical-device nub, one per physical disk - confirmed
/// on-device via `ioreg -c IOBlockStorageDevice -l`, which returns exactly
/// one node on a single-internal-SSD Mac.
///
/// Starting here rather than from `IOMedia` and climbing up is deliberate:
/// climbing up from every "whole" `IOMedia` (as an earlier version of this
/// file did) also picks up APFS-synthesized system volumes (Preboot, VM,
/// Update, ...), which macOS marks `Whole = true` at the IOMedia level too
/// and whose IOService-plane provider chain eventually reaches the same
/// physical nub - producing duplicate entries for one physical disk. Going
/// nub -> down to the first `Whole = true` `IOMedia` child avoids that
/// ambiguity entirely.
///
/// IMPORTANT (see docs/macos-telemetry.md): public IOKit does not expose
/// SMART/NVMe temperature or health. Reading that requires a private
/// `IONVMeSMARTUserClient`/`IOATASMARTInterface` connection gated behind
/// entitlements Apple does not grant third-party apps, and Apple Silicon's
/// internal NVMe controller does not expose vendor SMART log pages to *any*
/// user-space client, entitled or not. This backend is honest about that:
/// it only implements enumeration; `StorageNativeChannel` returns `nil` for
/// `readTemperature`/`getHealth` so the Dart layer falls through to the
/// `smartctl` CLI backend, which does work for third-party NVMe/SATA drives
/// (including most external enclosures) when smartmontools is installed.
final class IOKitStorageBackend {
  static let shared = IOKitStorageBackend()

  struct Device {
    let id: String
    let model: String?
    let manufacturer: String?
    let serial: String?
    let type: String
    let interfaceType: String
    let capacityBytes: Int64?
    let removable: Bool
  }

  struct Volume {
    let id: String
    let mountPoint: String?
    let volumeName: String?
    let filesystem: String?
    let volumeUuid: String?
    let isReadOnly: Bool
    let isBootVolume: Bool
    let totalBytes: Int64?
    let usedBytes: Int64?
    let freeBytes: Int64?
  }

  struct Capacity {
    let totalBytes: Int64?
    let usedBytes: Int64?
    let freeBytes: Int64?
  }

  /// Cumulative (since driver load, not since boot) I/O counters read from
  /// the `IOBlockStorageDriver`'s public "Statistics" property - the same
  /// counters `iostat`/Activity Monitor's disk view read. Callers compute
  /// rates by diffing two samples over the elapsed wall-clock time; this
  /// struct only ever reports what IOKit actually returned, never a rate.
  struct ActivityCounters {
    let bytesRead: Int64
    let bytesWritten: Int64
    let operationsRead: Int64
    let operationsWritten: Int64
  }

  func enumerateDevices() -> [Device] {
    var result: [Device] = []
    var iterator: io_iterator_t = 0

    guard let matchDict = IOServiceMatching("IOBlockStorageDevice") else { return result }
    let kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchDict, &iterator)
    guard kr == KERN_SUCCESS else { return result }
    defer { IOObjectRelease(iterator) }

    var nub = IOIteratorNext(iterator)
    while nub != 0 {
      if let device = describeNub(nub) {
        result.append(device)
      }
      IOObjectRelease(nub)
      nub = IOIteratorNext(iterator)
    }
    return result
  }

  private func describeNub(_ nub: io_object_t) -> Device? {
    var model: String?
    var vendor: String?
    var serial: String?
    var mediumType: String?
    if let dc = ioProperty(nub, "Device Characteristics") as? [String: Any] {
      model = dc["Product Name"] as? String
      vendor = dc["Vendor Name"] as? String
      serial = dc["Serial Number"] as? String
      mediumType = dc["Medium Type"] as? String
    }
    var interconnect: String?
    if let pc = ioProperty(nub, "Protocol Characteristics") as? [String: Any] {
      interconnect = pc["Physical Interconnect"] as? String
    }

    // AppleDiskImageDevice (a mounted .dmg/.sparsebundle) conforms to
    // IOBlockStorageDevice's class hierarchy and therefore matches this
    // query too, but reports "Virtual Interface" - it is not physical
    // storage and must not be surfaced as a monitorable drive (confirmed
    // via `ioreg -c IOBlockStorageDevice -l`: "Physical Interconnect
    // Location" = "File" on these nubs).
    if (interconnect ?? "").lowercased().contains("virtual") {
      return nil
    }

    guard let media = findWholeMediaChild(of: nub, maxDepth: 4) else { return nil }
    defer { IOObjectRelease(media) }
    guard let bsdName = ioProperty(media, "BSD Name") as? String else { return nil }
    let sizeNumber = ioProperty(media, "Size") as? NSNumber
    let removable = (ioProperty(media, "Removable") as? NSNumber)?.boolValue ?? false

    let interconnectLower = (interconnect ?? "").lowercased()
    let interfaceType: String
    if interconnectLower.contains("pci") || interconnectLower.contains("nvme")
      || interconnectLower.contains("apple fabric")
    {
      // "Apple Fabric" is what Apple Silicon's embedded NVMe controller
      // (IOEmbeddedNVMeBlockDevice) reports in place of "PCI-Express" -
      // confirmed via `ioreg -c IOBlockStorageDevice -l` on-device; it is
      // still an NVMe device, just not discrete PCIe.
      interfaceType = "nvme"
    } else if interconnectLower.contains("usb") {
      interfaceType = "usb"
    } else if interconnectLower.contains("sata") || interconnectLower.contains("ata") {
      interfaceType = "sata"
    } else if interconnectLower.contains("scsi") || interconnectLower.contains("fibre") {
      interfaceType = "scsi"
    } else {
      interfaceType = "unknown"
    }

    // "Medium Type" ("Solid State" / "Rotational") is a real, non-fabricated
    // IOKit-reported property - safe to use for ssd/hdd classification
    // where the interconnect alone doesn't already imply it (spec section
    // 42 only forbids guessing, not reading a value IOKit actually gives us).
    let mediumLower = (mediumType ?? "").lowercased()
    let type: String
    if interfaceType == "nvme" {
      type = "nvme"
    } else if mediumLower.contains("solid state") {
      type = "ssd"
    } else if mediumLower.contains("rotational") {
      type = "hdd"
    } else {
      type = "unknown"
    }

    return Device(
      id: "macos-\(bsdName)",
      model: trimmed(model),
      manufacturer: trimmed(vendor),
      serial: trimmed(serial),
      type: type,
      interfaceType: interfaceType,
      capacityBytes: sizeNumber?.int64Value,
      removable: removable
    )
  }

  /// Mounted filesystem volumes living on the partitions of the whole disk
  /// identified by [wholeBsdName] (e.g. "disk0"). Re-looks-up the whole
  /// `IOMedia` node by BSD name (rather than reusing a handle from
  /// [enumerateDevices], which releases its handles) and walks its
  /// IOService-plane children for partition `IOMedia` nodes - the
  /// `PhysicalDisk -> Partition -> Volume` split the Dart model expects.
  /// Mount point / volume name / filesystem / UUID come from
  /// DiskArbitration (`DADiskCopyDescription`), the same public API Disk
  /// Utility uses; capacity comes from `URLResourceValues` on the mount
  /// point. A partition that exists but isn't mounted (no mount point) is
  /// still returned with capacity fields `nil` - that's a real, non-fabricated
  /// "we don't know" state, not an error.
  func volumes(forWholeBsdName wholeBsdName: String) -> [Volume] {
    guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
    var result: [Volume] = []
    for bsdName in partitionBsdNames(ofWhole: wholeBsdName) {
      if let volume = describeVolume(bsdName: bsdName, session: session) {
        result.append(volume)
      }
    }
    return result
  }

  /// Aggregate capacity for the whole disk: total from the IOKit `Size`
  /// property (authoritative, physical), used/free summed across its
  /// mounted volumes (an APFS container may not fully reconcile to the
  /// physical total due to container overhead/snapshots - documented
  /// limitation, not a bug). Returns `nil` fields when nothing could be
  /// determined rather than fabricating zero.
  func capacity(forWholeBsdName wholeBsdName: String) -> Capacity {
    let vols = volumes(forWholeBsdName: wholeBsdName)
    var usedSum: Int64 = 0
    var freeSum: Int64 = 0
    var haveAny = false
    for v in vols {
      if let used = v.usedBytes {
        usedSum += used
        haveAny = true
      }
      if let free = v.freeBytes {
        freeSum += free
        haveAny = true
      }
    }
    let total = totalSize(ofWholeBsdName: wholeBsdName)
    return Capacity(
      totalBytes: total,
      usedBytes: haveAny ? usedSum : nil,
      freeBytes: haveAny ? freeSum : nil
    )
  }

  /// Reads the whole disk's `IOBlockStorageDriver` "Statistics" dictionary -
  /// the provider chain is nub -> IOBlockStorageDriver -> IOMedia, so this
  /// is the parent of the whole `IOMedia` node found by BSD name. `nil`
  /// when the property is absent (some virtual/synthetic media don't
  /// publish it) rather than fabricating zero counters.
  func activityCounters(forWholeBsdName wholeBsdName: String) -> ActivityCounters? {
    guard let matchDict = IOBSDNameMatching(kIOMasterPortDefault, 0, wholeBsdName) else { return nil }
    let media = IOServiceGetMatchingService(kIOMasterPortDefault, matchDict)
    guard media != 0 else { return nil }
    defer { IOObjectRelease(media) }

    var parent: io_registry_entry_t = 0
    guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &parent) == KERN_SUCCESS else {
      return nil
    }
    defer { IOObjectRelease(parent) }

    guard let stats = ioProperty(parent, "Statistics") as? [String: Any] else { return nil }
    // Key names per <IOKit/storage/IOBlockStorageDriver.h>
    // (kIOBlockStorageDriverStatisticsBytesReadKey = "Bytes (Read)",
    // kIOBlockStorageDriverStatisticsBytesWrittenKey = "Bytes (Write)",
    // kIOBlockStorageDriverStatisticsReadsKey = "Operations (Read)",
    // kIOBlockStorageDriverStatisticsWritesKey = "Operations (Write)") -
    // IOKit vends them as plain string keys in the dictionary, not exported
    // Swift constants.
    func intValue(_ key: String) -> Int64 {
      (stats[key] as? NSNumber)?.int64Value ?? 0
    }
    return ActivityCounters(
      bytesRead: intValue("Bytes (Read)"),
      bytesWritten: intValue("Bytes (Write)"),
      operationsRead: intValue("Operations (Read)"),
      operationsWritten: intValue("Operations (Write)")
    )
  }

  private func totalSize(ofWholeBsdName wholeBsdName: String) -> Int64? {
    guard let matchDict = IOBSDNameMatching(kIOMasterPortDefault, 0, wholeBsdName) else { return nil }
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, matchDict)
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return (ioProperty(service, "Size") as? NSNumber)?.int64Value
  }

  /// BSD names of the non-whole `IOMedia` children directly below the whole
  /// disk's own `IOMedia` node - i.e. its partitions.
  private func partitionBsdNames(ofWhole wholeBsdName: String) -> [String] {
    guard let matchDict = IOBSDNameMatching(kIOMasterPortDefault, 0, wholeBsdName) else { return [] }
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, matchDict)
    guard service != 0 else { return [] }
    defer { IOObjectRelease(service) }

    var names: [String] = []
    var iterator: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
      return []
    }
    defer { IOObjectRelease(iterator) }

    var child = IOIteratorNext(iterator)
    while child != 0 {
      let isWhole = (ioProperty(child, "Whole") as? NSNumber)?.boolValue ?? false
      if !isWhole, let bsd = ioProperty(child, "BSD Name") as? String {
        names.append(bsd)
      }
      IOObjectRelease(child)
      child = IOIteratorNext(iterator)
    }
    return names
  }

  private func describeVolume(bsdName: String, session: DASession) -> Volume? {
    guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else { return nil }
    guard let descCF = DADiskCopyDescription(disk) else {
      // Unformatted/raw partition (e.g. an EFI or recovery slice DA can't
      // describe) - still a real partition, just not a mountable volume.
      return Volume(
        id: "macos-\(bsdName)", mountPoint: nil, volumeName: nil, filesystem: nil,
        volumeUuid: nil, isReadOnly: false, isBootVolume: false,
        totalBytes: nil, usedBytes: nil, freeBytes: nil
      )
    }
    let desc = descCF as NSDictionary

    let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL
    let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String
    let filesystem = desc[kDADiskDescriptionVolumeKindKey as String] as? String
    var volumeUuid: String?
    if let uuidRef = desc[kDADiskDescriptionVolumeUUIDKey as String] {
      let cfUuid = uuidRef as CFTypeRef
      if CFGetTypeID(cfUuid) == CFUUIDGetTypeID() {
        // swiftlint:disable:next force_cast
        volumeUuid = CFUUIDCreateString(kCFAllocatorDefault, (cfUuid as! CFUUID)) as String
      }
    }

    var totalBytes: Int64?
    var usedBytes: Int64?
    var freeBytes: Int64?
    var isReadOnly = false
    var isBoot = false
    if let mountURL {
      isBoot = mountURL.path == "/"
      do {
        let values = try mountURL.resourceValues(forKeys: [
          .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey,
        ])
        if let total = values.volumeTotalCapacity { totalBytes = Int64(total) }
        if let available = values.volumeAvailableCapacity {
          freeBytes = Int64(available)
          if let totalBytes { usedBytes = max(0, totalBytes - freeBytes!) }
        }
        isReadOnly = values.volumeIsReadOnly ?? false
      } catch {
        // Volume mounted but statfs-equivalent failed (e.g. transient
        // unmount race) - report the volume without capacity rather than
        // dropping it or fabricating numbers.
      }
    }

    return Volume(
      id: "macos-\(bsdName)",
      mountPoint: mountURL?.path,
      volumeName: volumeName,
      filesystem: filesystem,
      volumeUuid: volumeUuid,
      isReadOnly: isReadOnly,
      isBootVolume: isBoot,
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: freeBytes
    )
  }

  /// Breadth-first search of the IOService-plane children below a physical
  /// device nub for the first `IOMedia` with `Whole = true` - the
  /// nub's own top-level disk representation (its provider chain is
  /// typically nub -> IOBlockStorageDriver -> IOMedia, i.e. depth 2, but
  /// [maxDepth] leaves headroom without risking runaway recursion into an
  /// unrelated subtree).
  private func findWholeMediaChild(of entry: io_registry_entry_t, maxDepth: Int) -> io_registry_entry_t? {
    guard maxDepth > 0 else { return nil }
    var iterator: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
      return nil
    }
    defer { IOObjectRelease(iterator) }

    var child = IOIteratorNext(iterator)
    var deferredChildren: [io_registry_entry_t] = []
    while child != 0 {
      if (ioProperty(child, "Whole") as? NSNumber)?.boolValue == true,
        ioProperty(child, "BSD Name") != nil
      {
        // Caller only reads properties off this handle - release the
        // deferred siblings/nephews and hand back this one still retained.
        for d in deferredChildren { IOObjectRelease(d) }
        return child
      }
      deferredChildren.append(child)
      child = IOIteratorNext(iterator)
    }

    defer { for d in deferredChildren { IOObjectRelease(d) } }
    for d in deferredChildren {
      if let found = findWholeMediaChild(of: d, maxDepth: maxDepth - 1) {
        return found
      }
    }
    return nil
  }

  private func trimmed(_ s: String?) -> String? {
    guard let s else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private func ioProperty(_ entry: io_registry_entry_t, _ key: String) -> AnyObject? {
    return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }
}
