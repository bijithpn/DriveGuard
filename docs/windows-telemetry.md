# Windows telemetry

**Status: written against Microsoft's public IOCTL documentation, not yet
compiled or run on physical Windows hardware** (no Windows machine in the
development environment). Smoke-test before trusting in production - see
docs/troubleshooting.md.

## Native backend (`windows/native_storage/storage_backend.cpp`)

All enumeration and telemetry go through `DeviceIoControl` against
`\\.\PhysicalDriveN` handles - no PowerShell, no WMI:

- **Enumeration**: `IOCTL_STORAGE_QUERY_PROPERTY` /
  `StorageDeviceProperty` -> `STORAGE_DEVICE_DESCRIPTOR` (vendor, product,
  serial, bus type). Works with a handle opened at `0` desired access.
  Capacity via `IOCTL_DISK_GET_LENGTH_INFO`.
- **NVMe temperature/health**: `IOCTL_STORAGE_QUERY_PROPERTY` /
  `StorageDeviceProtocolSpecificProperty` with
  `STORAGE_PROTOCOL_SPECIFIC_DATA{ProtocolType=ProtocolTypeNvme,
  DataType=NVMeDataTypeLogPage, ProtocolDataRequestValue=0x02}` - the NVMe
  "SMART / Health Information" log page. Composite temperature is bytes
  1-2 (Kelvin, little-endian); power cycles/power-on hours/unsafe
  shutdowns/media errors are the 128-bit little-endian counters at their
  documented offsets.
- **ATA/SATA temperature/health**: `IOCTL_ATA_PASS_THROUGH` issuing a
  `SMART READ DATA` (`0xB0`/`0xD0`) command, parsing the returned 512-byte
  attribute table for IDs 194/190 (temperature) and 5/197 (reallocated /
  pending sector counts, used as the warning heuristic).

Device IDs are `"windows-<PhysicalDrive index>"`. This assumes
`MSFT_PhysicalDisk.DeviceId` (used by the legacy PowerShell backend) lines
up with the `\\.\PhysicalDriveN` index, which holds on every
single-controller consumer system but is not guaranteed on exotic
multi-HBA/RAID configurations - worth re-verifying once this runs on real
hardware.

## Fallback

`FallbackStorageMonitor` tries the native backend first, per field
(enumeration / temperature / health independently), then falls through to
`WindowsStorageMonitor` (PowerShell + `MSFT_PhysicalDisk` /
`Get-StorageReliabilityCounter`, Storage Management WMI) - see that file's
header comment for why WMI was chosen as the CLI-tier fallback over raw
PowerShell scripting.

## Known risk areas to verify on real hardware

- Third-party RAID/USB-bridge controllers may reject
  `StorageDeviceProtocolSpecificProperty` entirely (reported as
  `NativeStorageStatus::kUnsupported`, not an error) - the WMI fallback
  should still cover many of these via `Get-StorageReliabilityCounter`.
- `IOCTL_ATA_PASS_THROUGH` support varies by USB-SATA bridge chipset; when
  unsupported, temperature/health fall through to WMI.
- Administrator privileges: `IOCTL_STORAGE_QUERY_PROPERTY` for basic
  enumeration works unprivileged on most systems; `IOCTL_ATA_PASS_THROUGH`
  may require elevation depending on driver/policy - unverified here.
