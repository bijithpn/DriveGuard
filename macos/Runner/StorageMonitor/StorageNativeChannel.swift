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

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
