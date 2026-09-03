# Linux telemetry

**Status: written against the documented Linux NVMe/ATA ioctl UAPIs, not
yet compiled or run on Linux hardware** (no Linux machine in the
development environment). Smoke-test before trusting in production.

## Native backend (`linux/native_storage/storage_backend.cc`)

- **Enumeration**: `/sys/block` directory walk (skipping `loop`/`ram`/
  `zram`/`dm-`/`sr`/`fd`), model/serial/size/rotational from sysfs files -
  kernel-native, no external tool, no elevated permission needed. This is
  the same source the pre-existing Dart `LinuxStorageMonitor` already
  used; the native version exists for architectural symmetry with
  Windows/macOS, not because the Dart file-read path was unreliable.
- **Temperature, in priority order**:
  1. sysfs hwmon (`/sys/block/<dev>/device/hwmon*/temp1_input`) - works
     unprivileged when the kernel exposes it (common for NVMe).
  2. NVMe admin `Get Log Page` via `NVME_IOCTL_ADMIN_CMD` against
     `/dev/nvme<N>` (the **controller** device, not the `nvme<N>n1`
     namespace block device) - log ID `0x02` (SMART/Health Information),
     512 bytes. This is a genuinely new capability over the Dart-only
     path: full NVMe health without spawning `nvme-cli`.
  3. Falls through to `FallbackStorageMonitor`'s `nvme-cli`/`smartctl`
     CLI tier if neither native source is available.
- **NVMe health**: same log page - `percentage_used`, `available_spare`,
  `critical_warning`, and the 128-bit little-endian lifetime counters
  (power cycles, power-on hours, unsafe shutdowns, media errors) at their
  documented byte offsets.
- **ATA/SATA health**: `HDIO_DRIVE_CMD` with the legacy `WIN_SMART` /
  `SMART_READ_VALUES` subcommand, parsing the SMART attribute table for
  IDs 5/197 (reallocated/pending sectors). This ioctl is older and less
  consistently supported across USB-SATA bridges and SATA-behind-RAID
  controllers than `SG_IO`/`ATA_16` would be - kept deliberately simple
  *because* `smartctl` remains the fallback for anything it doesn't work
  on, not as the only line of defense.

## Permissions

`/dev/nvme<N>` admin commands and most SATA SMART ioctls require root or
membership in a group a udev rule grants access to (distributions vary -
see docs/permissions.md). Without it, this backend reports
`kPermissionDenied` for that one call and `FallbackStorageMonitor` falls
through to `nvme-cli`/`smartctl`, which fail the same way for the same
reason - the app should surface "Temperature unavailable - permission
required", not silently retry forever.

## Distribution coverage

sysfs enumeration and hwmon temperature require nothing beyond the kernel
and work identically on Ubuntu/Debian/Fedora/Arch/Mint. `nvme-cli` and
`smartctl` availability (for the CLI fallback tier) is checked at runtime
via `SafeProcessRunner.exists` rather than assumed - see
docs/permissions.md and docs/troubleshooting.md for what happens when
they're missing.
