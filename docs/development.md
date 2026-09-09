# Development

## Requirements

- Flutter 3.41.x / Dart 3.11.x (stable channel) — matches this repo's `.metadata`.
- macOS: Xcode + CocoaPods (`pod install` runs automatically via `flutter build macos`).
- Linux: standard Flutter Linux desktop toolchain (`clang`, `cmake`, `ninja-build`,
  `pkg-config`, `libgtk-3-dev`) plus, for full telemetry, `smartmontools` and `nvme-cli`.
  See "Linux build prerequisites" below for tray/notification/hot-plug dev packages —
  missing them fails the CMake configure step, not just a runtime feature.
- Windows: standard Flutter Windows desktop toolchain (Visual Studio + Desktop C++
  workload). PowerShell is built in.

## Linux build prerequisites

`flutter run -d linux` / `flutter build linux` will fail at the CMake configure step
(before compiling anything) unless these dev packages are installed, because
`tray_manager` and `local_notifier` each `FATAL_ERROR` when their native dependency is
missing:

```bash
sudo apt-get install libayatana-appindicator3-dev libnotify-dev libudev-dev
```

- `libayatana-appindicator3-dev` (or `libappindicator3-dev` on distros without the
  Ayatana fork) — required by `tray_manager` for the system tray icon.
- `libnotify-dev` — required by `local_notifier` for native notifications.
- `libudev-dev` — required directly by DriveGuard's
  `native_storage/storage_native_channel.cc` for drive hot-plug detection.

## Commands

```bash
flutter pub get

# Run on each platform
flutter run -d macos
flutter run -d windows
flutter run -d linux

# Tests
flutter test

# Static analysis
flutter analyze

# Release builds
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

## Developer/demo mode

Settings → Advanced → "Use simulated devices" forces `MockStorageMonitor`, which
simulates an NVMe/SATA SSD/HDD with independent thermal curves plus a USB device with
genuinely unavailable telemetry, without touching real hardware. Useful for UI/alert work
on a machine where the real backend has nothing interesting to show.

`MockStorageMonitor.forceTemperature(deviceId, celsius)` is available for scripting a
specific spike (e.g. `48 → 55 → 70 → 80 → 65`) when manually testing alert transitions.

## Where to add a new backend capability

- New OS API/tool → implement it inside the relevant
  `infrastructure/storage/<platform>_storage_monitor.dart`, behind the existing
  `StorageMonitor` interface. Never leak platform-specific types into `domain/` or
  `presentation/`.
- New setting → add the field to `AppSettings` (with `toJson`/`fromJson`), a control in
  `presentation/settings/settings_screen.dart`, and let `SettingsNotifier.updateWith`
  persist + push it to `MonitoringService.updateSettings`.
