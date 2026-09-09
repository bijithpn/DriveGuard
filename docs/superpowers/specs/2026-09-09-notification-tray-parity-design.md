# Notification/Tray Parity — Design

Date: 2026-09-09

## Problem

DriveGuard uses `tray_manager` (system tray) and `local_notifier` (native
notifications) to behave consistently across Windows, macOS, and Linux. An
audit of `lib/infrastructure/tray/app_tray_service.dart` and
`lib/infrastructure/notifications/local_notifier_service.dart` against both
packages' native plugin source found the Dart-level logic is already correct
and platform-gated properly. The real gaps are all on the Linux
build/packaging side:

1. Both `tray_manager` and `local_notifier` `FATAL_ERROR` at CMake configure
   time if the Linux system is missing `libayatana-appindicator3-dev` (or
   `appindicator3-0.1`) and `libnotify-dev`, respectively. `libudev-dev`
   (used directly by `native_storage/storage_native_channel.cc`) has the same
   problem. None of this is documented, so a first-time Linux build fails
   with a raw CMake error and no pointer to the fix.
2. `linux/CMakeLists.txt` still carries the Flutter template default
   `APPLICATION_ID "com.example.driveguard"`.
3. `local_notifier`'s Linux plugin never sets a notification icon
   (`notify_notification_new(title, body, 0)`). Fixing this properly requires
   a `.desktop` file + installed icon resolved through real Linux packaging
   (`.deb`/AppImage), which doesn't exist yet for this project — out of scope
   here, but worth a documented, deliberate deferral so it isn't silently
   forgotten.

## Non-goals

- No Dart or C++ logic changes to `AppTrayService` or `LocalNotifierService`
  — both already behave correctly per-platform.
- No Windows changes — `local_notifier`'s Windows toast shortcut policy
  already defaults to `requireCreate`, which is correct.
- No `.deb`/AppImage packaging or `.desktop` file authoring in this pass.

## Changes

1. **`docs/development.md`** — add a "Linux build prerequisites" section
   listing the exact apt packages needed before `flutter run -d linux` /
   `flutter build linux` will configure successfully:
   `libayatana-appindicator3-dev` (or `appindicator3-0.1` +
   `libappindicator3-dev` as the alternative), `libnotify-dev`, and
   `libudev-dev`, with the `apt-get install` command and a one-line note on
   why each is needed.
2. **`README.md`** — one-line pointer to that section so it's visible before
   someone runs into the CMake failure.
3. **`linux/CMakeLists.txt`** — rename `APPLICATION_ID` from
   `com.example.driveguard` to `com.intersmart.driveguard`.
4. **`docs/platform-support.md`** and **`docs/troubleshooting.md`** — add a
   known-limitation entry: Linux notifications currently show no icon
   because there's no installed `.desktop` file/icon theme entry for
   `notify-send`/libnotify to resolve; deferred until real Linux packaging
   (`.deb`/AppImage) exists.

## Testing

No automated test covers native CMake configuration or notification
rendering. Verification is manual, on the user's own machines:

- Linux: fresh `flutter run -d linux` / `flutter build linux` on a machine
  without the listed dev packages should now fail fast with a clear
  actionable step (install the packages from the doc), not a confusing raw
  CMake error discovered by accident.
- Windows: no behavior change expected; existing toast notifications and
  tray icon continue to work as before.
- macOS: no behavior change (already verified working).

## Risk

Very low — this is documentation plus a cosmetic identifier rename. The
`APPLICATION_ID` change has no functional effect since the app isn't
installed into the system application registry yet (no `.desktop` file
ships), so renaming it cannot break anything currently working.
