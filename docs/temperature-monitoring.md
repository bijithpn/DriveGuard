# Temperature Monitoring

## How a temperature reading reaches the UI

```
Backend.readTemperature(deviceId)
    → null                          → SensorAvailability.unsupported → "Temperature unavailable"
    → throws PermissionDeniedException → SensorAvailability.permissionDenied → explained in UI
    → throws other StorageMonitorException → MonitoringStatus.error, previous value kept
    → TemperatureReading(celsius, ...)
        → TemperatureUtils.isPlausibleValue()      (rejects NaN/Infinity/outside -40..125°C)
        → TemperatureUtils.isPlausibleTransition()  (rejects a >40°C jump from the last valid reading)
        → recorded in TemperatureHistoryStore, becomes StorageDevice.primaryTemperature
```

A reading is **never** coerced to `0` or silently reused past its staleness window. See
`MonitoringService._pollOne` and `_checkStale`.

## Validity and staleness

- Plausibility bounds and jump-rejection: `TemperatureUtils` (section 6). These reject
  garbage; they are not a "safe operating temperature" claim about any drive.
- Staleness: a reading older than `pollingInterval × AppConstants.staleThresholdMultiplier`
  (default 4× → 20s at the 5s default interval) flips `MonitoringStatus.staleData`, and the
  device details screen shows "Sensor data is currently stale" instead of presenting the
  old number as current.

## Multiple sensors

`StorageMonitor.getSensors(deviceId)` returns every sensor a backend can see (NVMe
composite + any per-namespace values it parses out of `smartctl`/`nvme-cli` JSON). The
device's `primaryTemperature` always comes from the **composite/controller** reading — the
one vendors intend as the representative value — never "whichever sensor came first in the
tool's output" (section 12). Additional sensors are listed in the device details screen
only, not folded into the dashboard card.

## Three distinct kinds of threshold (section 7)

1. **User-configured alert threshold** — `AppSettings.globalThresholds` /
   `perDeviceThresholds`, editable in Settings. This is the only thing that drives alerts.
2. **Manufacturer-reported limit** — not currently surfaced by any backend in this pass
   (none of `system_profiler`/`smartctl`/`nvme-cli`/`Get-StorageReliabilityCounter` reliably
   expose a per-model max-safe-temperature field across vendors); if a future backend adds
   it, it must be displayed as a separate, clearly-labeled fact, never merged into #1.
3. **Application safety threshold** — `AppConstants.defaultWarningCelsius` /
   `defaultCriticalCelsius` (60°C / 70°C) are only the out-of-the-box *default* for #1, not
   a claim that 70°C is dangerous for any specific SSD/HDD.

## Alerting

See `application/alerts/alert_engine.dart` and `docs/architecture.md`. In short: hysteresis
(a breach must recover past `threshold − recoveryHysteresisCelsius` before it can notify
again from scratch) plus a configurable cooldown (a sustained breach still reminds
periodically, but never on every poll). Fully covered by `test/unit/alert_engine_test.dart`.
