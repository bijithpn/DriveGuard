import FlutterMacOS
import Foundation
import WidgetKit

/// Registers the `driveguard/native_widget` MethodChannel used to push the
/// current drive snapshot into the shared App Group container that the
/// DriveGuardWidget extension reads from (see DriveGuardWidget.swift).
///
/// This is intentionally one-way and fire-and-forget: the widget extension
/// never calls back into the running app, and the app never blocks waiting
/// on the widget - that's the whole point of the two being independent
/// processes/lifecycles (see lib/infrastructure/native/native_widget_bridge.dart).
enum NativeWidgetChannel {
  // Keep in sync with kAppGroupId in DriveGuardWidget.swift. macOS (unlike
  // iOS) requires the group id to start with the signing Team ID
  // (PUA3NSL244 - Jithin Wails) rather than a literal "group." prefix.
  private static let appGroupId = "PUA3NSL244.driveguard.widget"
  private static let snapshotKey = "driveguard.snapshot"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "driveguard/native_widget",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let json = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "expected a JSON string", details: nil))
        return
      }
      guard let defaults = UserDefaults(suiteName: appGroupId) else {
        // App Group not provisioned yet (no signing team set in Xcode) -
        // fail soft, the widget just keeps showing its placeholder/last data.
        result(nil)
        return
      }
      defaults.set(json, forKey: snapshotKey)
      // Deprecated, but still the only way to force an immediate
      // cross-process flush to the shared container - without it the write
      // can sit in cfprefsd's write-behind cache long enough that a widget
      // reload right after this call still sees stale data.
      defaults.synchronize()
      if #available(macOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
