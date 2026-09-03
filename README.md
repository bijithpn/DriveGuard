# DriveGuard

Cross-platform SSD/HDD temperature monitor for Windows, macOS and Linux, built in Flutter.

See `docs/` for architecture, platform support (with an honest per-platform verification
status), hardware detection, temperature-monitoring semantics, permissions, development
setup, and troubleshooting.

```bash
flutter pub get
flutter run -d macos    # verified working in this repo's history
flutter run -d windows  # written against documented APIs, not yet build-tested here
flutter run -d linux    # written against documented APIs, not yet build-tested here
flutter test
```
