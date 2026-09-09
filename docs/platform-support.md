# Platform Support

Verification status is stated explicitly per platform — see section 42/50 of the original
spec ("do not fake cross-platform support").

| Platform | Verified how | Status |
|---|---|---|
| macOS (Apple Silicon) | Built, run and smoke-tested in this session (`flutter build macos`, launched, ran for 10s+ with no crash, device discovery via `system_profiler` executed) | **Verified working** |
| macOS (Intel) | Same code path as Apple Silicon; not tested on Intel hardware | Not tested — expected to work, smartctl SMART access more commonly succeeds on Intel Macs than Apple Silicon |
| Windows 10/11 | Written against documented `MSFT_PhysicalDisk`/`Get-StorageReliabilityCounter` WMI APIs; **not compiled or run** — no Windows machine in this environment | **Untested — build and smoke-test before trusting** |
| Linux (any distro) | Written against `/sys/block`, `/sys/class/nvme`, `smartctl`, `nvme-cli`; **not compiled or run** — no Linux machine in this environment | **Untested — build and smoke-test before trusting** |

## Hardware compatibility matrix

| Platform | Device | Temperature source | Requirement | Fallback if unavailable |
|---|---|---|---|---|
| macOS | NVMe (internal, Apple Silicon) | smartctl NVMe log page | smartmontools installed | Usually unavailable — Apple does not expose vendor SMART log pages for the internal controller to user space on Apple Silicon. Shown as "Temperature unavailable". |
| macOS | NVMe (internal, Intel) / external | smartctl NVMe log page | smartmontools installed, disk accessible outside App Sandbox | "Temperature unavailable" if smartctl missing or reports "not supported" |
| macOS | SATA SSD/HDD | smartctl SMART attribute 194/190 (`temperature.current`) | smartmontools installed | "Temperature unavailable" |
| Windows | NVMe/SATA (storport-attached) | `Get-StorageReliabilityCounter -PhysicalDisk` | PowerShell + Storage Management WMI provider (built into Windows 10/11) | "Temperature unavailable" if the counter has no `Temperature` field, or the controller doesn't route through storport |
| Windows | USB / third-party RAID | Same API, low success rate | — | Very commonly unavailable — many USB bridges and RAID controllers do not surface reliability counters at all |
| Linux | NVMe | `/sys/class/nvme/*/device/hwmon*/temp1_input`, else `nvme smart-log` | Kernel hwmon support, or nvme-cli installed | "Temperature unavailable" |
| Linux | SATA SSD/HDD | `smartctl -a -j` | smartmontools installed, read access to `/dev/sdX` (root or `disk` group) | "Temperature unavailable"; permission errors surfaced explicitly, not silently swallowed |
| Linux | USB bridge | `smartctl` via bridge pass-through | Bridge chipset must support SAT (SCSI/ATA Translation) | Frequently unsupported — reported as such, never guessed |
| All | Virtual disks (RAM disk, loop, dm-, LVM) | — | — | Excluded from enumeration entirely, not shown as a drive with unavailable temperature |

## Known limitations

- No FFI/native `DeviceIoControl` or IOKit backend yet — see docs/architecture.md's
  "documented upgrade path".
- Windows and Linux backends are correctness-reviewed against documented APIs but have not
  been executed. **Build and run them on real hardware before relying on this for actual
  thermal safety monitoring.**
- The mini "widget" is the main window switched into a compact/borderless/always-on-top
  mode, not a second native OS-level widget/gadget — no such uniform API exists across all
  three OSes (see section 21 of the spec, and docs/architecture.md).
- System tray icon artwork is not bundled (no image-generation tooling in this session);
  `AppTrayService` is fully wired but ships without real `.ico`/`.png` assets — see
  troubleshooting.md.
- True OS sleep/resume detection uses Flutter's `AppLifecycleState.resumed` as a
  best-effort proxy, not a native power-notification API — see troubleshooting.md.
- Linux notifications show no icon: `local_notifier`'s Linux plugin calls libnotify's
  `notify_notification_new()` without an icon, and there's no `.desktop` file shipped yet
  for a notification daemon to resolve one by app name. This is deferred until DriveGuard
  ships real Linux packaging (`.deb`/AppImage) with a proper desktop entry — see
  troubleshooting.md.
