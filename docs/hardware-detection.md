# Hardware Detection

## Enumeration per platform

- **macOS**: `system_profiler SPNVMeDataType SPSerialATADataType -json`. No permissions
  required, always present. Produces model, serial (when reported), size, and bus type.
  The BSD device name (e.g. `disk0`) is captured for later `smartctl` calls but never
  exposed to the UI.
- **Linux**: `/sys/block/*`, filtering out `loop*`, `ram*`, `zram*`, `dm-*`, `sr*`, `fd*`.
  Rotational flag (`queue/rotational`) distinguishes HDD from SSD for non-NVMe devices;
  `removable` flags USB-attached disks.
- **Windows**: `Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName
  MSFT_PhysicalDisk`, mapping `BusType`/`MediaType` to the domain enums.

## Stable device IDs

Per section 33, device IDs must survive restarts and must never be the display name.
Each backend derives its ID from a platform-stable handle:

- macOS: `macos-<bsd device name>` (e.g. `macos-disk0`)
- Linux: `linux-<sysfs block name>` (e.g. `linux-nvme0n1`)
- Windows: `windows-<MSFT_PhysicalDisk DeviceId>`

These IDs back per-device threshold overrides in Settings, so a rename of the drive's
reported model string does not orphan a user's configured thresholds.

## Hotplug / rescan

`MonitoringService` runs a discovery timer independent of the temperature-poll timer
(`AppConstants.deviceDiscoveryInterval`, default 15s). On each discovery pass:

1. Devices present now but not previously known are added and immediately polled once.
2. Devices previously known but absent this pass are marked `disconnected` (shown in the
   UI) rather than removed immediately.
3. A device still absent on the *next* discovery pass is removed, along with its history
   and alert state.
4. A device reappearing while marked `disconnected` is treated as reconnected: its history
   and alert hysteresis state are preserved rather than reset.

This gives the UI one visible "Disconnected" state before a device disappears, instead of
either flickering on every transient enumeration miss or leaving stale ghost entries
forever.
