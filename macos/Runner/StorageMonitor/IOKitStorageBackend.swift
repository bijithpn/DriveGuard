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
