# SMART Attribute Deep-Dive — Design

Date: 2026-09-09

## Problem

`DeviceHealth` and each platform's `getHealth()` already capture NVMe health
fairly completely (percentage used, available spare, media errors, power
cycles/hours, unsafe shutdowns, data units read/written) on all three
platforms. What's missing everywhere is the classic ATA/SATA SMART attribute
table: reallocated sectors, reallocated events, pending sectors, offline
uncorrectable count, and wear-leveling/SSD-life-left — the attributes that
most directly predict imminent drive failure for SATA SSDs/HDDs and USB
bridges, which are a large share of real-world DriveGuard devices.

## Domain changes

Add nullable fields to `lib/domain/entities/device_health.dart`:

- `reallocatedSectorCount` (SMART id 5)
- `reallocatedEventCount` (id 196)
- `currentPendingSectorCount` (id 197)
- `offlineUncorrectableCount` (id 198)
- `ssdLifeLeftPercent` — best-effort, vendor-specific (searched by common ids
  173/177/202/231 or name containing "wear"/"life_left"/"lifetime_remain");
  `null` when not found (e.g. on HDDs, or vendors that don't expose it)

Add `bool get hasAtaWarningSigns` — true when any of the four sector/error
counts is non-null and greater than zero. Used by both the UI and the new
alert check.

These are additive fields with default `null`; no existing call site breaks.

## Shared parsing helper

New file `lib/infrastructure/storage/ata_smart_attributes.dart` with a small
value class `AtaSmartExtras` (the 5 fields above) and two factories:

- `AtaSmartExtras.fromSmartctlJson(Map<String, dynamic> json)` — reads
  `json['ata_smart_attributes']['table']` (a list of
  `{id, name, value, worst, thresh, raw: {value, string}}` entries) and picks
  out the ids/names above. Used by `linux_storage_monitor.dart` and
  `macos_storage_monitor.dart`, both of which already fetch this exact JSON
  via `smartctl -a -j` for temperature/health and can pass it straight
  through — no new process invocation.
- `AtaSmartExtras.fromRawAttributeBlock(List<int> bytes)` — parses the
  standard ATA SMART attribute binary layout (2-byte header, then up to 30
  fixed 12-byte records: id, 2-byte status flags, current value, worst
  value, 6-byte raw value, 1 reserved byte; a record with id 0 ends the
  list) used by Windows' `MSStorageDriver_FailurePredictData.VendorSpecific`
  byte array. This factory is pure and unit-testable with synthetic byte
  arrays — the one part of this feature we can verify without a Windows
  machine.

Both factories return an all-null `AtaSmartExtras` on any parse failure
(consistent with the codebase's existing defensive style) rather than
throwing.

## Platform integration

- **Linux / macOS** (`linux_storage_monitor.dart`, `macos_storage_monitor.dart`):
  in the existing non-NVMe branch of `getHealth()`, call
  `AtaSmartExtras.fromSmartctlJson(json)` on the JSON already fetched, and
  merge its fields into the returned `DeviceHealth`.
- **Windows** (`windows_storage_monitor.dart`): new PowerShell script that
  joins `Win32_DiskDrive.PNPDeviceID` (for the disk at the given index) to
  `MSStorageDriver_FailurePredictData.InstanceName` (root\wmi namespace,
  matched by substring since WMI mangles PNPDeviceID slightly), returning
  the `VendorSpecific` byte array as JSON. Parsed with
  `AtaSmartExtras.fromRawAttributeBlock`. Wrapped in the same
  try/catch-log-and-continue pattern as the existing reliability-counter
  call; on any failure the existing health data (from
  `Get-StorageReliabilityCounter`/`Win32_DiskDrive.Status`) is still
  returned, just without the extra ATA fields. **This path is unverified —
  no Windows machine available in this environment** — flagged in
  `docs/platform-support.md` alongside the rest of the Windows backend's
  existing "build and smoke-test before trusting" status.

## UI

`device_details_screen.dart`'s `_HealthTab`: new `_HealthGrid` section
titled "ATA SMART Attributes", same `_HealthEntry` tile pattern as the
existing "SMART & NVMe Data" grid, placed directly after it. Entries:
Reallocated Sectors, Reallocated Events, Pending Sectors, Offline
Uncorrectable, SSD Life Left (`--` when null, consistent with existing
entries). Sector-count entries get `AppColors.critical`/`warning` styling
when non-zero, matching the existing `statusColor` pattern used for
Percentage Used/Life Remaining.

## Alerting

`MonitoringService._evaluateHealthAlert` already diffs `previous` vs.
`health` (`DeviceHealth`) each poll and fires `showHealthAlert` for status
worsening, wear jumps, and new media errors. Add one more `else if` branch:
any of the four sector/error-count fields increasing from the previous
reading (including first appearance of a non-null non-zero value) triggers
the same `showHealthAlert` call, with a message naming which attribute
changed and by how much. No new alert path, no `alert_engine.dart` changes
— this fits the existing per-device previous/current health comparison.

## Mock backend

`mock_storage_monitor.dart`'s `getHealth()` gets small static/plausible
values for the new fields (e.g. 0 reallocated sectors on the healthy
simulated SSD, a nonzero reallocated count on the "warning" device if one
exists) so the new UI tiles and alert path are exercisable in demo mode.

## Testing

- Unit test `AtaSmartExtras.fromSmartctlJson` against a handful of realistic
  smartctl JSON fixtures (healthy SATA SSD, HDD with reallocated sectors,
  device with no `ata_smart_attributes` key at all).
- Unit test `AtaSmartExtras.fromRawAttributeBlock` against synthetic byte
  arrays: a well-formed block with a few attributes, an empty/all-zero
  block, a truncated/malformed block — this is the only part of the Windows
  path we can verify here.
- `MonitoringService._evaluateHealthAlert`'s new branch gets a unit test
  using the existing test harness pattern (previous health with 0 reallocated
  sectors → current health with 3 → expects `showHealthAlert` called).
- No existing test should need to change; new `DeviceHealth` fields default
  to `null`.
- Manual verification on real Linux and Windows hardware is on the user —
  Linux should mostly just work (reuses existing smartctl JSON already
  proven to parse); Windows needs a real build/run per
  `docs/platform-support.md`'s existing caveat.

## Non-goals

- No generic/full SMART attribute table display (just the 5 fields above).
- No predictive-engine/trend-analyzer integration for these new fields in
  this pass.
- No changes to `alert_engine.dart` (temperature/capacity severity state
  machines) — this reuses the separate health-diff alert path already in
  `MonitoringService`.
