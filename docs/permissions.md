# Permissions

DriveGuard never requests elevation up front. It attempts an unprivileged read first and
reports exactly what failed if that doesn't work (section 23).

## macOS

- **App Sandbox is disabled** (`com.apple.security.app-sandbox = false` in both
  entitlements files). This is required because DriveGuard invokes `system_profiler` and
  `smartctl` via `Process` and reads `/dev/disk*` — none of which a sandboxed app can do.
  This means the app **cannot be distributed through the Mac App Store** as built; that's
  an inherent trade-off of doing real SMART/NVMe telemetry on macOS, not an oversight.
- `smartctl` itself may still need elevated privileges (`sudo`) to open `/dev/disk*`
  directly, depending on the drive and macOS version. When it does, DriveGuard reports
  `SensorAvailability.permissionDenied` for that device and explains it in the UI — it
  does not prompt for a password or relaunch itself elevated.
- No permission dialog will appear for enumeration (`system_profiler` needs none).

## Linux

- Reading `/sys/block/*` metadata needs no special permission.
- `smartctl -a` on a raw block device typically requires root or membership in the `disk`
  group. If access is denied, the specific device shows `permissionDenied` with the
  `smartctl` error text — other devices keep working.
- `nvme smart-log` has similar requirements on some distributions; hwmon (`/sys/class/nvme`)
  values are usually readable by any user.

## Windows

- `Get-CimInstance`/`Get-StorageReliabilityCounter` generally work for the interactively
  logged-in user without elevation for read access on most systems. If a specific
  controller/driver requires elevation, DriveGuard surfaces that device's failure rather
  than requesting admin rights for the whole app.
- DriveGuard does not request "Run as Administrator".

## What DriveGuard never does

- Never requests root/admin for the whole application "just in case".
- Never silently swallows a permission failure — it always shows which device is affected
  and why (section 23).
- Never falls back to a fabricated value when access is denied.
