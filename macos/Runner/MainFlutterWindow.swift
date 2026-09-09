import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    StorageNativeChannel.register(
      with: flutterViewController.registrar(forPlugin: "StorageNativeChannel")
    )
    NativeWidgetChannel.register(
      with: flutterViewController.registrar(forPlugin: "NativeWidgetChannel")
    )

    // The mini-widget window (see DesktopWindowController/MiniWidgetApp in
    // Dart) is a genuinely separate FlutterViewController/engine created
    // by desktop_multi_window, not a reshaped main window. It needs its
    // own plugin registrations - notably window_manager, so that window
    // sets its own frameless/always-on-top/opacity/position independent
    // of the main dashboard window - which only happens via this callback.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)

      // By default AppKit only delivers mouseMoved: events to the *key*
      // window, so hover-driven UI (the edge dock's MouseRegion-based
      // expand/detail-card behavior) silently did nothing until the user
      // clicked the dock once to make it key - after which hover worked,
      // since the window stayed key. The dock is an always-on-top overlay
      // that's meant to react to hover without ever stealing focus, so it
      // needs mouse-moved events regardless of key status.
      if let window = controller.view.window {
        window.acceptsMouseMovedEvents = true
      }
    }

    super.awakeFromNib()
  }
}
