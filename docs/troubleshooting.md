# Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| "Temperature unavailable" for every device | Backend capability check failed, or required tool missing | Settings → Advanced shows the active backend and any `missingTools`. Install `smartmontools` (macOS/Linux) or `nvme-cli` (Linux). |
| "Permission required" on one specific drive | `smartctl`/`nvme-cli` denied access to that block device | Linux: add your user to the `disk` group or run with elevated privileges for that one tool invocation (not the whole app). macOS: some drives need `sudo smartctl`; DriveGuard will not do this for you automatically — by design, it never silently elevates. |
| Apple Silicon internal SSD always "unavailable" | Apple does not expose vendor NVMe SMART log pages for the internal controller to user space | Expected, documented limitation (docs/platform-support.md) — not a bug. External/Intel-Mac NVMe SSDs are far more likely to work via `smartctl`. |
| smartctl reports "Unable to detect device type" | Common with USB bridge chipsets that don't support SAT (SCSI/ATA Translation) pass-through | The device correctly shows unavailable rather than a guessed value; there is no reliable workaround from user space in that case. |
| nvme-cli missing on Linux | Not installed | `apt install nvme-cli` / distro equivalent. sysfs hwmon values will still work for many NVMe drives even without it. |
| Tray icon doesn't appear | No bundled icon asset shipped in this pass (see platform-support.md) | Add real `.ico` (Windows) / `.png` (macOS/Linux) assets and point `AppTrayService`'s `trayManager.setIcon(...)` at them before release. |
| App doesn't detect resume from sleep promptly | Flutter's `AppLifecycleState.resumed` is used as a best-effort proxy, not a native OS power-notification hook | Use Settings → Advanced → "Rescan Drives" to force immediate re-discovery + poll if it hasn't caught up within one discovery interval. |
| Windows backend behaves unexpectedly | Not yet build/run-tested on real Windows hardware (see platform-support.md) | File exact PowerShell error text (visible in Settings → Advanced → Export Diagnostic Report) when reporting an issue. |
| macOS build fails to install to `/dev/disk*` | App Sandbox re-enabled accidentally | Confirm `com.apple.security.app-sandbox` is `false` in both `macos/Runner/*.entitlements` files. |
| Linux: `cmake` configure fails mentioning `appindicator` or `libnotify` | `tray_manager`/`local_notifier` require dev packages not installed | `sudo apt-get install libayatana-appindicator3-dev libnotify-dev libudev-dev` — see docs/development.md's "Linux build prerequisites". |
| Linux: notifications show up with no icon | No `.desktop` file shipped yet for the notification daemon to resolve an icon by app name (see platform-support.md) | Known limitation, deferred until real Linux packaging (`.deb`/AppImage) exists; not fixable from app code alone. |
