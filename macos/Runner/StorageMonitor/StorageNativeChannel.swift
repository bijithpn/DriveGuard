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
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "driveguard/storage_native",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      handle(call, result: result)
    }
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
