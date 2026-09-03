import DiskArbitration
import FlutterMacOS
import Foundation

/// Registers and implements the `driveguard/storage_native` MethodChannel
/// contract (docs/architecture.md "Native data contract") for macOS.
///
/// Delegates enumeration to [IOKitStorageBackend]. `readTemperature` and
/// `getHealth` deliberately return `nil` (not an error) - see
/// IOKitStorageBackend's header comment for why public IOKit cannot supply
/// SMART/NVMe data - which the Dart `FallbackStorageMonitor` treats as
/// "fall through to the smartctl CLI backend", exactly as the contract
/// intends.
enum StorageNativeChannel {
  // Retained for the process lifetime - FlutterEventChannel does not keep a
  // strong reference to the handler passed to setStreamHandler.
  private static let deviceEventHandler = DeviceEventStreamHandler()
  private static let activityHandler = ActivityStreamHandler()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "driveguard/storage_native",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(
      name: "driveguard/storage_device_events",
      binaryMessenger: registrar.messenger
    )
    eventChannel.setStreamHandler(deviceEventHandler)

    let activityChannel = FlutterEventChannel(
      name: "driveguard/storage_activity",
      binaryMessenger: registrar.messenger
    )
    activityChannel.setStreamHandler(activityHandler)
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      result([
        "backendName": "macOS (IOKit native enumeration)",
        "canEnumerateDevices": true,
        "canReadTemperature": false,
        "canReadHealth": false,
        "missingTools": [String](),
        "notes": [
          "Public IOKit APIs do not expose SMART/NVMe telemetry on macOS; temperature and health come from the smartctl fallback where installed.",
          "Apple Silicon internal NVMe controllers do not expose vendor SMART log pages to any user-space process, native or otherwise.",
        ],
      ] as [String: Any])

    case "getDevices":
      let devices = IOKitStorageBackend.shared.enumerateDevices().map { d -> [String: Any?] in
        [
          "id": d.id,
          "model": d.model,
          "manufacturer": d.manufacturer,
          "serial": d.serial,
          "type": d.type,
          "interface": d.interfaceType,
          "capacityBytes": d.capacityBytes.map { NSNumber(value: $0) },
          "removable": d.removable,
        ]
      }
      result(devices)

    case "readTemperature", "getHealth":
      result(nil)

    case "getCapacity":
      guard let bsdName = bsdName(from: call) else {
        result(nil)
        return
      }
      let cap = IOKitStorageBackend.shared.capacity(forWholeBsdName: bsdName)
      if cap.totalBytes == nil && cap.usedBytes == nil {
        result(nil)
        return
      }
      result([
        "totalBytes": cap.totalBytes.map { NSNumber(value: $0) },
        "usedBytes": cap.usedBytes.map { NSNumber(value: $0) },
        "freeBytes": cap.freeBytes.map { NSNumber(value: $0) },
      ] as [String: Any?])

    case "getVolumes":
      guard let bsdName = bsdName(from: call) else {
        result([Any]())
        return
      }
      let volumes = IOKitStorageBackend.shared.volumes(forWholeBsdName: bsdName).map { v -> [String: Any?] in
        [
          "id": v.id,
          "mountPoint": v.mountPoint,
          "volumeName": v.volumeName,
          "filesystem": v.filesystem,
          "volumeUuid": v.volumeUuid,
          "isReadOnly": v.isReadOnly,
          "isBootVolume": v.isBootVolume,
          "totalBytes": v.totalBytes.map { NSNumber(value: $0) },
          "usedBytes": v.usedBytes.map { NSNumber(value: $0) },
          "freeBytes": v.freeBytes.map { NSNumber(value: $0) },
        ]
      }
      result(volumes)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Device ids from [IOKitStorageBackend] are always "macos-<bsdName>" -
  /// strip the prefix rather than keeping a separate id->bsdName cache.
  private static func bsdName(from call: FlutterMethodCall) -> String? {
    guard let args = call.arguments as? [String: Any],
      let deviceId = args["deviceId"] as? String,
      deviceId.hasPrefix("macos-")
    else { return nil }
    return String(deviceId.dropFirst("macos-".count))
  }
}

/// Pushes `{"kind": "added"|"removed", "deviceId": "macos-<bsdName>"}` over
/// the `driveguard/storage_device_events` EventChannel via DiskArbitration's
/// `DARegisterDiskAppearedCallback`/`DARegisterDiskDisappearedCallback` -
/// the public API Disk Utility itself uses for hot-plug notifications.
///
/// The match dictionary restricts callbacks to whole-disk appearances
/// (`kDADiskDescriptionMediaWholeKey = true`), which also fires for
/// non-physical whole media (e.g. a mounted .dmg) that
/// [IOKitStorageBackend.enumerateDevices] would filter out. That's
/// deliberately not filtered again here: this event only carries a
/// `deviceId` hint telling `MonitoringService` to re-run discovery
/// immediately - the authoritative filtered device list still comes from
/// `getDevices`, so an extra rediscovery triggered by a disk image is
/// harmless, just a no-op diff.
private final class DeviceEventStreamHandler: NSObject, FlutterStreamHandler {
  private var session: DASession?
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    guard let session = DASessionCreate(kCFAllocatorDefault) else {
      return FlutterError(
        code: "UNSUPPORTED", message: "DiskArbitration session could not be created", details: nil)
    }
    self.session = session

    let matchDict = [kDADiskDescriptionMediaWholeKey: true] as CFDictionary
    let context = Unmanaged.passUnretained(self).toOpaque()

    DARegisterDiskAppearedCallback(session, matchDict, { disk, ctx in
      DeviceEventStreamHandler.fromContext(ctx).emit(disk: disk, kind: "added")
    }, context)
    DARegisterDiskDisappearedCallback(session, matchDict, { disk, ctx in
      DeviceEventStreamHandler.fromContext(ctx).emit(disk: disk, kind: "removed")
    }, context)

    DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let session {
      DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
    session = nil
    eventSink = nil
    return nil
  }

  private static func fromContext(_ ctx: UnsafeMutableRawPointer?) -> DeviceEventStreamHandler {
    Unmanaged<DeviceEventStreamHandler>.fromOpaque(ctx!).takeUnretainedValue()
  }

  private func emit(disk: DADisk, kind: String) {
    guard let bsdNamePtr = DADiskGetBSDName(disk) else { return }
    let bsdName = String(cString: bsdNamePtr)
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["kind": kind, "deviceId": "macos-\(bsdName)"])
    }
  }
}

/// Pushes per-device real-time I/O activity (Phase 8, STORAGE_MONITORING.md)
/// by polling `IOKitStorageBackend.activityCounters` on a short interval and
/// diffing against the previous sample - "currentTotalBytes -
/// previousTotalBytes / elapsedTime", never derived from capacity or any
/// static value. The first sample after `onListen` (or after a device first
/// appears) has no prior counters to diff against, so it is skipped rather
/// than reported as a fabricated zero/instant rate.
private final class ActivityStreamHandler: NSObject, FlutterStreamHandler {
  private static let pollInterval: TimeInterval = 1.5

  private var timer: Timer?
  private var eventSink: FlutterEventSink?
  private var lastSample: [String: (counters: IOKitStorageBackend.ActivityCounters, at: Date)] = [:]

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    lastSample.removeAll()
    let t = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    timer?.invalidate()
    timer = nil
    eventSink = nil
    lastSample.removeAll()
    return nil
  }

  private func tick() {
    guard let eventSink else { return }
    let now = Date()
    for device in IOKitStorageBackend.shared.enumerateDevices() {
      guard let bsdName = bsdName(fromDeviceId: device.id),
        let counters = IOKitStorageBackend.shared.activityCounters(forWholeBsdName: bsdName)
      else { continue }

      defer { lastSample[device.id] = (counters, now) }
      guard let previous = lastSample[device.id] else { continue }

      let elapsed = now.timeIntervalSince(previous.at)
      guard elapsed > 0 else { continue }
      // A driver reload or counter reset can make the "current" value
      // smaller than the previous sample - report unavailable for this
      // tick rather than a nonsensical negative rate.
      guard counters.bytesRead >= previous.counters.bytesRead,
        counters.bytesWritten >= previous.counters.bytesWritten,
        counters.operationsRead >= previous.counters.operationsRead,
        counters.operationsWritten >= previous.counters.operationsWritten
      else { continue }

      let event: [String: Any] = [
        "deviceId": device.id,
        "readBytesPerSecond": Double(counters.bytesRead - previous.counters.bytesRead) / elapsed,
        "writeBytesPerSecond": Double(counters.bytesWritten - previous.counters.bytesWritten) / elapsed,
        "readOpsPerSecond": Double(counters.operationsRead - previous.counters.operationsRead) / elapsed,
        "writeOpsPerSecond": Double(counters.operationsWritten - previous.counters.operationsWritten) / elapsed,
        // IOBlockStorageDriver's Statistics dictionary has no direct
        // "percent busy" field - utilization is left unreported rather than
        // approximated from latency/time fields that don't reliably sum to
        // a wall-clock busy fraction.
      ]
      eventSink(event)
    }
  }

  private func bsdName(fromDeviceId id: String) -> String? {
    guard id.hasPrefix("macos-") else { return nil }
    return String(id.dropFirst("macos-".count))
  }
}
