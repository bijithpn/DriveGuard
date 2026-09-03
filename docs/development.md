# Development

## Requirements

- Flutter 3.41.x / Dart 3.11.x (stable channel) — matches this repo's `.metadata`.
- macOS: Xcode + CocoaPods (`pod install` runs automatically via `flutter build macos`).
- Linux: standard Flutter Linux desktop toolchain (`clang`, `cmake`, `ninja-build`,
  `pkg-config`, `libgtk-3-dev`) plus, for full telemetry, `smartmontools` and `nvme-cli`.
- Windows: standard Flutter Windows desktop toolchain (Visual Studio + Desktop C++
  workload). PowerShell is built in.

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
