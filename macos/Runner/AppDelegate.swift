import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The app must keep running in the tray/menu bar even when every window
  // is closed - the whole point of "close to tray" and the mini widget is
  // that the app survives with no window open. Returning true here (the
  // old behavior) tears down the whole process - engine included - the
  // moment the last window goes away, which is almost certainly what
  // produced the "Invalid engine handle" crash right after the mini
  // widget's window was created and the main window was hidden: with no
  // window left visible, AppKit terminated the app out from under the
  // running Flutter engine. Quitting is still available via the tray's
  // "Quit" item / AppRoot.onQuit, which calls windowManager.destroy()
  // explicitly.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
