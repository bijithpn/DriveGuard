# Protection, resource guard & Storage Sense

## Thermal protection (`lib/application/protection/`)
- `ThermalGuard` — per-drive state machine: nominal → elevated → danger → emergency.
  Emergency needs N consecutive hot readings, a spike of limit+5 °C, or a fast
  rise predicted to cross the limit within 60 s. Released only after a 5 °C
  hysteresis (no flapping).
- `ThermalCauseAnalyzer` — ranks causes (heavy writes, memory pressure/swap, reads,
  saturation, nearly-full SSD, CPU load, rapid rise, poor airflow). Names a
  process only when supported: *confirmed* when its disk writes were measured
  (Linux `/proc/<pid>/io`, Windows perf counters), otherwise *likely* (CPU).
  macOS exposes no per-process disk writes without root tooling.
- `ThermalProtectionService` — notifications carrying the cause; opt-in shutdown
  countdown. The decision at T-0 uses only **fresh** data (<30 s old); sleep/resume,
  sensor loss and cooling all cancel it. Shutdown tries the normal OS path first,
  then the admin prompt (forced).
- Polling is adaptive: slow when idle/hidden, 5 s when any drive is hot, 2 s in emergency.

## Resource guard
`ResourceGuardService` samples memory/swap about once a minute (slower when hidden)
and integrates drive write throughput. Alerts: low memory / heavy swap, sustained
writes ≥ 25 MB/s averaged over 10 min. Quit buttons: Quit → Force quit → Force quit
as administrator (explicit consent each time). PIDs are re-verified by name before
any signal; protected OS processes are never offered.

## Elevation (`PrivilegedRunner`)
macOS `osascript … with administrator privileges`, Linux `pkexec`, Windows UAC via
`Start-Process -Verb RunAs`. Never silent, never stores credentials, arguments
are quoted/encoded, and cleanup paths are validated against the catalog roots
immediately before elevation.

## Storage Sense
Only catalog folders are ever touched (symlinks resolved, home and `/` refused).
Safe items are deleted permanently; Review/Manual items go to the Trash. System
folders are flagged *Admin*, never auto-selected, and removed under one prompt.

## SSD longevity advisories (`SsdLifeAdvisor`)
Wear ≥ 80/90 %, ATA life left ≤ 20/10 %, spare blocks near threshold, new unsafe
shutdowns, SSD ≥ 80 % full, and cumulative heat exposure (30/120 min per session).

## Disk-write hygiene of the app itself
History is persisted at most every 5 minutes (flushed on shutdown/overheat); the
session heartbeat is 60 s.
