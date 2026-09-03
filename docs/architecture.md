# Architecture

```
Flutter UI (presentation/)
        ↓
Application layer (application/) — monitoring, alerts, notifications, settings
        ↓
Domain layer (domain/) — entities, enums, repository abstraction
        ↓
Infrastructure (infrastructure/) — storage backends, persistence, notifications, tray/window
        ↓
Windows / macOS / Linux (OS tools & APIs, invoked via dart:io Process)
```

## Layers

- **`domain/`** — pure Dart, no Flutter/IO imports. `StorageDevice`, `TemperatureReading`,
  `DeviceHealth`, `TemperatureThresholds`, the enums, and the `StorageMonitor` abstract
  repository every backend implements. Nothing here knows which OS it's running on.
- **`application/`** — `MonitoringService` (the single poll/discovery scheduler),
  `DeviceAlertState`/hysteresis engine, `TemperatureHistoryStore`, `AppSettings` and the
  Riverpod providers wiring it together. Platform-independent; unit-tested against a
  scripted fake `StorageMonitor`.
- **`infrastructure/`** — one `StorageMonitor` implementation per OS
  (`WindowsStorageMonitor`, `MacOSStorageMonitor`, `LinuxStorageMonitor`), plus
  `MockStorageMonitor` for development, `SettingsRepository` (shared_preferences),
  `LocalNotifierService`, and the tray/window wrappers.
- **`presentation/`** — dashboard, device details, settings, mini monitor widget, theme.
  Consumes only `domain` models via Riverpod providers; never imports a platform backend
  directly.

## State management

Riverpod (`flutter_riverpod`) is the single state-management solution, chosen because the
project had none prior to this work (see the Phase-1 assessment). `MonitoringService` is a
plain Dart class (not itself a Riverpod object) so it can be unit-tested without a
`ProviderScope`; a thin `Notifier` layer (`DevicesNotifier`, `SettingsNotifier`) bridges it
into the widget tree.

## Why OS tools/APIs via `Process`, not FFI, for v1

Every real backend calls documented OS tools/APIs (`system_profiler`/`smartctl` on macOS,
`/sys` + `smartctl`/`nvme-cli` on Linux, `MSFT_PhysicalDisk`/`Get-StorageReliabilityCounter`
via PowerShell on Windows) through `SafeProcessRunner`, which never builds a shell string,
always passes argument arrays, verifies the binary exists first, and enforces a timeout
(section 26/43). This was a deliberate choice for this pass: it is fully cross-platform
buildable without a native toolchain per OS, and — critically — it's the only backend type
this session could actually compile and runtime-verify (macOS, on this machine).

**Documented upgrade path**: a `dart:ffi` backend using `DeviceIoControl` with
`IOCTL_STORAGE_QUERY_PROPERTY` / `IOCTL_SCSI_MINIPORT` on Windows, and IOKit registry
matching for lower-latency macOS enumeration, would remove the per-poll process-spawn cost.
The `StorageMonitor` abstraction was designed so such a backend is a drop-in replacement —
nothing above `infrastructure/storage/` would need to change.

## Failure isolation

`MonitoringService._pollOne` wraps every device's read in its own try/catch. A
`PermissionDeniedException`, any other `StorageMonitorException`, or an unexpected error
updates only that device's status — the `Future.wait` over all devices never propagates one
device's exception to the others (section 27/28, rule 8).
