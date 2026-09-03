# macOS telemetry

## Enumeration (native, verified)

`macos/Runner/StorageMonitor/IOKitStorageBackend.swift` enumerates physical
drives via the public IOKit registry - no subprocess, no entitlement:

1. `IOServiceMatching("IOBlockStorageDevice")` - class-hierarchy match, so
   this also returns concrete subclasses: `IOAHCIBlockStorageDevice` (SATA),
   USB mass-storage nubs, and Apple Silicon's `IOEmbeddedNVMeBlockDevice`
   (internal NVMe). One nub per physical disk.
2. For each nub, `Device Characteristics` (model/vendor/serial/medium type)
   and `Protocol Characteristics` (physical interconnect) are read directly.
3. The nub's `Whole = true` `IOMedia` child (BSD name, size) is found by a
   bounded breadth-first walk down the IOService plane.

Two on-device findings shaped this:

- Apple Silicon's embedded NVMe controller reports interconnect
  `"Apple Fabric"`, not `"PCI-Express"` - classified as `nvme` explicitly.
- `AppleDiskImageDevice` (a mounted `.dmg`) also matches
  `IOBlockStorageDevice` and must be excluded (`Physical Interconnect` =
  `"Virtual Interface"`), or every mounted disk image appears as a fake
  drive.

An earlier version walked *up* from every `Whole = true` `IOMedia` instead;
that also matched APFS-synthesized system volumes (Preboot, VM, Update...),
which share the same physical nub in their provider chain and produced
duplicate entries for one physical disk. Nub-down is unambiguous; IOMedia-up
is not.

## Temperature / health (CLI fallback only - documented OS limitation)

Public IOKit does **not** expose SMART or NVMe log-page data. Reading it
requires a private `IONVMeSMARTUserClient`/`IOATASMARTInterface` connection
gated behind entitlements Apple does not grant third-party apps. Apple
Silicon's internal NVMe controller does not expose vendor SMART log pages
to *any* user-space client, entitled or not - this is a hardware/OS
limitation, not something a better implementation could work around.

`StorageNativeChannel.readTemperature`/`getHealth` therefore return `nil`
unconditionally, and `FallbackStorageMonitor` falls through to
`MacOSStorageMonitor`'s `smartctl` path:

- Third-party NVMe/SATA drives (internal or via most external enclosures)
  read normally through smartctl when smartmontools is installed
  (`brew install smartmontools`).
- The internal SSD on Apple Silicon Macs will show "Temperature
  unavailable" even with smartctl installed - expected, not a bug.
- Intel Macs with a third-party NVMe upgrade (non-Apple SSD) are more
  likely to expose SMART via smartctl than the stock Apple SSD.

## Verified on-device

Apple Silicon (M1) Mac, one internal SSD (`APPLE SSD AP0256Q`): native
enumeration correctly reports exactly one physical device, classified
`nvme`/`nvme`; temperature correctly reports unavailable (smartctl not
installed in the dev environment) rather than a fabricated value.
