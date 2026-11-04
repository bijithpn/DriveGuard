# Packaging and release

Release builds (all platforms):

    flutter build <windows|macos|linux> --release --obfuscate --split-debug-info=build/symbols

Keep `build/symbols` per release; it is needed to symbolicate crash stacks.

## macOS
- The app is **not sandboxed** (`com.apple.security.app-sandbox` = false) because it
  shells out to `smartctl` / `system_profiler`. This rules out the Mac App Store.
- Distribute outside the store: sign with a *Developer ID Application* certificate,
  enable the hardened runtime, then notarize and staple:

      codesign --deep --force --options runtime --sign "Developer ID Application: <name>" DriveGuard.app
      xcrun notarytool submit DriveGuard.zip --keychain-profile <profile> --wait
      xcrun stapler staple DriveGuard.app

## Windows
- Build on Windows. Sign the `.exe`/installer with `signtool` (EV cert avoids SmartScreen
  warnings). Package as MSIX or Inno Setup.
- Needs no extra runtime; SMART reads use the bundled native plugin / PowerShell.

## Linux
- Build deps: `libgtk-3-dev libayatana-appindicator3-dev libnotify-dev libsqlite3-dev`
  (install via apt; do not commit `.deb` files).
- SMART access needs elevated rights. Either add the user to the `disk` group or ship a
  udev rule / polkit helper so `smartctl` and `nvme` can read `/dev/*` without root.
- `linux/packaging/99-driveguard.rules` grants the `disk` group access to NVMe controller
  nodes (install steps are in the file). It has **not** been verified on real hardware.
  `smartctl` on SATA may additionally need `CAP_SYS_RAWIO` (e.g. `setcap cap_sys_rawio+ep
  $(which smartctl)`) or running via a polkit helper; test per distribution.
- Package as `.deb` or AppImage. Flatpak/Snap sandboxes block raw `/dev` access and need
  explicit device permissions.
- Wayland: window positioning and always-on-top are limited; verify the edge dock on
  both X11 and Wayland sessions.
