<div align="center">

<img src="assets/images/app_logo.png" alt="DriveGuard logo" width="120" />

# DriveGuard

**Keep your SSDs and HDDs cool, healthy and out of trouble.**
A cross-platform desktop monitor for drive temperature, health, thermal protection and disk clean-up, built with Flutter.

[![CI](https://github.com/bijithpn/DriveGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/bijithpn/DriveGuard/actions/workflows/ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.11-0175C2?logo=dart&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux-444)
![Version](https://img.shields.io/badge/version-1.0.0-2ea44f)

[Features](#-features) · [Install](#-install) · [How it works](#-how-it-works) · [Platform support](#-platform-support) · [Docs](#-documentation) · [Contributing](#-development)

</div>

---

## Why DriveGuard?

Drives fail quietly: a hot NVMe throttles, a worn SSD runs out of spare blocks, a machine shuts down and nobody knows why. DriveGuard sits in your tray, watches every physical drive, warns you early, and, if you opt in, acts before the heat does damage.

> **Honesty first.** DriveGuard never invents a number. If a drive's sensor is unavailable (common on Apple Silicon internal NVMe, USB bridges and RAID controllers) it says *"Temperature unavailable"* and explains why, rather than showing `0` or a stale value.

---

## ✨ Features

### 🌡️ Live drive monitoring

- Auto-discovers **NVMe, SATA SSD, HDD and USB** drives, with hot-plug detection; virtual disks (RAM, loop, LVM) are filtered out.
- Polls every 2 / 5 / 10 / 30 / 60 s (default 5 s), adaptive: slower when idle or hidden, **5 s when a drive is hot, 2 s in an emergency**.
- Plausibility checks reject garbage readings (NaN, out of range, impossible jumps); data older than 4× the poll interval is flagged **stale** instead of being shown as current.
- Reads the **composite/controller** sensor as the primary value, and lists extra sensors on the details screen.
- Per-drive failure isolation: one drive erroring or being permission-denied never affects the others.

### 🔔 Smart alerts

- Configurable **warning / critical thresholds** (defaults 60 °C / 70 °C), global or per drive.
- **Hysteresis and cooldown** (5 min – 1 h) so you are reminded, never spammed.
- **Rapid-rise detection**: alerts when a drive heats by e.g. 10 °C within 3 minutes.
- **Predictive alerts**: a linear trend fit estimates *"will hit the limit in ~N min"* for temperature and for storage filling up.
- Native desktop notifications that name the likely cause.

### 🛡️ Thermal protection

- Per-drive state machine: `nominal → elevated → danger → emergency`, with a 5 °C release hysteresis so it never flaps.
- **Cause analyzer** ranks why a drive is hot: heavy writes, memory pressure/swap, heavy reads, saturation, nearly-full SSD, CPU load, rapid rise, poor airflow. A process is named only when the evidence supports it (*confirmed* from measured disk writes, otherwise *likely* from CPU).
- **Opt-in emergency shutdown countdown.** Decisions at T-0 use only fresh data (< 30 s); sleep/resume, sensor loss or cooling cancels it. Tries a normal shutdown first, then an admin prompt.
- **Resource guard**: watches memory, swap and sustained disk writes (≥ 25 MB/s over 10 min) and offers *Quit → Force quit → Force quit as admin*. PIDs are re-verified by name and protected OS processes are never offered.

### 💾 SSD health and longevity

- SMART health: wear level, ATA life remaining, spare blocks, reallocated/pending sectors, unsafe shutdowns, power-on hours.
- **SSD life advisor** flags wear ≥ 80 / 90 %, life left ≤ 20 / 10 %, spare blocks near threshold, new unsafe shutdowns, SSD ≥ 80 % full, and cumulative heat exposure.
- History charts per drive (up to 24 h) with the temperature, health, storage and diagnostics tabs.

### 🧹 Storage Sense (disk clean-up)

- Finds reclaimable space: package-manager caches (npm and friends), per-app caches, build artifacts in your projects (background-isolate scanner), large downloads, system folders.
- Every item carries a **safety level**: *Safe* items are deleted permanently, *Review/Manual* items go to the Trash, *Admin* items are never auto-selected and removed under a single prompt.
- Hard guard rails: only catalog folders are touched, symlinks are resolved, and your home directory or `/` is refused outright.

### 🕵️ Shutdown incident forensics

- A 60 s session heartbeat lets DriveGuard detect an **unexpected shutdown, crash, BSOD or power loss** on the next launch.
- The correlation engine cross-references the previous boot's OS diagnostics with the last drive temperatures to say whether overheating was involved, and at what confidence.
- Incident report with timeline chart, per-drive stats, and a browsable history.

### 🪟 Always-there UI

- **System tray** icon with a live temperature, and launch-at-startup.
- **Mini monitor widget**: compact, borderless, always-on-top window.
- **Edge dock**: a hover panel that slides out from a screen edge.
- Manrope typography, Material 3, light and dark themes, animated gauges and drive cards.
- **Simulated devices mode** (Settings → Advanced) to demo or test the UI with no real hardware.

---

## 📦 Install

One-line build-and-install scripts for each OS. They install missing prerequisites (Flutter, build tools) and place the app for the current user.

```bash
# macOS: installs to /Applications or ~/Applications (needs full Xcode)
./scripts/install_macos.sh

# Linux: installs under ~/.local with a launcher and menu entry
./scripts/install_linux.sh
```

```powershell
# Windows: installs to %LOCALAPPDATA%\Programs\DriveGuard with Start Menu + Desktop shortcuts
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
```

Add `--no-launch` (`-NoLaunch` on Windows) to skip starting the app afterwards.

**For full SMART/NVMe telemetry**, install the optional tools:

| OS | Command |
| --- | --- |
| macOS | `brew install smartmontools` |
| Linux | `sudo apt install smartmontools nvme-cli` (or your distro's equivalent) |
| Windows | Nothing extra, uses built-in PowerShell / Storage WMI |

---

## 🧠 How it works

```
┌──────────────────────────────────────────────────────────────┐
│ presentation/   Dashboard · Details · Storage Sense · Settings│
│                 Incidents · Mini widget · Edge dock           │
├──────────────────────────────────────────────────────────────┤
│ application/    Monitoring · Alerts · Protection · Prediction │
│                 Storage Sense · Incidents · Notifications     │
├──────────────────────────────────────────────────────────────┤
│ domain/         Pure Dart entities + StorageMonitor interface │
├──────────────────────────────────────────────────────────────┤
│ infrastructure/ Per-OS backends · SQLite · Tray · Window mgmt │
└──────────────────────────────────────────────────────────────┘
                              ↓
        Windows · macOS · Linux (OS tools via safe Process calls)
```

- **State management:** Riverpod. `MonitoringService` is plain Dart so it is unit-testable without a widget tree.
- **Telemetry:** one `StorageMonitor` per OS, called through `SafeProcessRunner` (no shell strings, argument arrays only, binary existence checked, hard timeout).

  | OS | Sources |
  | --- | --- |
  | macOS | `system_profiler`, `smartctl` |
  | Linux | `/sys/block`, `/sys/class/nvme` hwmon, `smartctl`, `nvme-cli`, udev hot-plug |
  | Windows | `MSFT_PhysicalDisk`, `Get-StorageReliabilityCounter`, WMI SMART via PowerShell |

- **Persistence:** settings in `shared_preferences`; history, sessions and incidents in SQLite (`sqflite_common_ffi`). History writes are throttled to once every 5 min so DriveGuard doesn't wear the drive it's watching.
- **Elevation is never silent:** macOS `osascript`, Linux `pkexec`, Windows UAC. It never stores credentials, and cleanup paths are re-validated immediately before elevation.

### Privacy and permissions

DriveGuard works fully offline, with no telemetry and no accounts. It never asks for root/admin up front: it tries an unprivileged read first and tells you exactly which drive failed and why. On macOS the App Sandbox is disabled (required to run `smartctl`/`system_profiler`), so the app cannot ship on the Mac App Store. See [docs/permissions.md](docs/permissions.md).

---

## 🖥️ Platform support

| Platform | Status |
| --- | --- |
| macOS (Apple Silicon) | ✅ **Built, run and verified** |
| macOS (Intel) | 🟡 Same code path, not tested on hardware |
| Windows 10 / 11 | 🟠 Written against documented APIs, **not yet build-tested** |
| Linux | 🟠 Written against documented APIs, **not yet build-tested** |

Temperature availability depends on the drive and OS: internal NVMe on Apple Silicon usually exposes no temperature to user space, and USB bridges often don't pass SMART through. Full matrix and known limitations: [docs/platform-support.md](docs/platform-support.md).

> Build and run on real hardware before relying on DriveGuard for actual thermal safety, especially on Windows and Linux.

---

## 🛠️ Development

**Requirements:** Flutter 3.41.x / Dart 3.11.x. Platform toolchains: Xcode + CocoaPods (macOS), Visual Studio with the Desktop C++ workload (Windows), `clang cmake ninja-build pkg-config libgtk-3-dev` (Linux).

```bash
flutter pub get
flutter run -d macos      # or: windows, linux
flutter analyze
flutter test
```

Linux also needs these dev packages or CMake configure fails:

```bash
sudo apt-get install libayatana-appindicator3-dev libnotify-dev libudev-dev
```

Release builds:

```bash
flutter build <macos|windows|linux> --release --obfuscate --split-debug-info=build/symbols
```

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds all three platforms and attaches the archives to a GitHub release (signing only runs when the secrets exist; see [docs/packaging.md](docs/packaging.md)).

### Project layout

```
lib/
├── domain/           entities, enums, StorageMonitor interface
├── application/      monitoring, alerts, protection, prediction, storage_sense, incidents
├── infrastructure/   storage backends, persistence, tray, diagnostics, native bridges
├── presentation/     dashboard, device_details, settings, storage_sense, incidents, widget
└── core/             constants, utils, logging, errors
linux/ macos/ windows/   native runners and plugins
scripts/                 one-shot installers
third_party/             patched desktop_multi_window
test/                    unit, application, infrastructure, widget tests
```

### Key packages

`flutter_riverpod` · `window_manager` · `tray_manager` · `desktop_multi_window` · `local_notifier` · `launch_at_startup` · `fl_chart` · `sqflite_common_ffi` · `shared_preferences` · `flutter_svg`

---

## 📚 Documentation

| Topic | Doc |
| --- | --- |
| Layers, state, failure isolation | [architecture.md](docs/architecture.md) |
| Per-platform verification and limits | [platform-support.md](docs/platform-support.md) |
| Drive detection | [hardware-detection.md](docs/hardware-detection.md) |
| Reading, validity and alert semantics | [temperature-monitoring.md](docs/temperature-monitoring.md) |
| Thermal guard, resource guard, Storage Sense | [protection.md](docs/protection.md) |
| Backends | [macOS](docs/macos-telemetry.md) · [Windows](docs/windows-telemetry.md) · [Linux](docs/linux-telemetry.md) |
| Permissions | [permissions.md](docs/permissions.md) |
| Dev setup | [development.md](docs/development.md) |
| Signing and releases | [packaging.md](docs/packaging.md) |
| Common problems | [troubleshooting.md](docs/troubleshooting.md) |

---

<div align="center">

Made with Flutter · Keep your drives cool 🧊

</div>
