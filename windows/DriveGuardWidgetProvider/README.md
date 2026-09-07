# Windows 11 Widgets Board provider — scaffold, unbuilt

Written on macOS with no Windows machine to compile or run it against —
**nothing in this folder has been built or tested.** It's a concrete
starting point, not a working feature. `WidgetProvider.h`/`.cpp` are not
referenced by `windows/CMakeLists.txt`, so they cannot break your existing
`flutter build windows` / `flutter run -d windows` — they're inert until
you wire them into a project.

## Why this can't just be added to the existing Flutter Windows build

The Widgets Board only activates providers declared by an **MSIX-packaged**
app via `<com:ComServer>` + `<uap3:Extension Category="windows.appExtension">`
entries in `Package.appxmanifest`, backed by a registered out-of-process COM
class. `flutter build windows` produces a plain unpackaged Win32 `.exe` —
there is no manifest to extend and no packaging identity for Windows to
associate the widget with. This is a Windows platform restriction, not a
Flutter limitation.

## What real integration needs (in order)

1. **A packaging project.** Either the `msix` pub package (simplest: pure
   pubspec config, generates the appx manifest for you) or a hand-rolled
   `.wapproj` in Visual Studio wrapping the existing `windows/` build output.
   Either way you end up with a `Package.appxmanifest`.
2. **Windows App SDK** ≥ 1.4 referenced by whatever project hosts the COM
   server (a small separate DLL/EXE target — the widget provider runs
   out-of-process from the main app, so it does **not** need to live inside
   the Flutter runner binary at all).
3. **Register the provider** in `Package.appxmanifest`:
   - a `<com:ComServer><com:ExeServer>` (or `SurrogateServer`) entry
     pointing at the provider executable, with the CLSID implemented by
     `WidgetProvider`
   - a `<uap3:Extension Category="windows.appExtension">` with
     `Name="com.microsoft.windows.widgets"` declaring the widget's
     definition (id, display name, icon, supported sizes) — see Microsoft's
     [Widgets Board provider sample](https://github.com/microsoft/Windows-AppSDK-Samples)
     for the exact schema, it changes between App SDK versions.
4. **Sign it.** A local dev certificate (New-SelfSignedCertificate +
   `signtool`) is enough to sideload and test; the Microsoft Store requires
   a real certificate to publish.
5. **Wire live updates.** `WidgetProvider::CreateWidget`/`Activate` already
   render from the snapshot file once, per the TODO in `WidgetProvider.cpp`
   add a directory watch (`ReadDirectoryChangesW`, or
   `Windows.Storage.Search.StorageFolderQueryResult` if staying in C++/WinRT)
   so `PushUpdateToAllActive()` fires on every write, not just on
   create/activate.

## Data contract (already implemented, Dart side)

`lib/infrastructure/native/native_widget_bridge.dart` writes the same JSON
shape on Windows as it does for the Linux GNOME extension, to:

```
%LOCALAPPDATA%\<application id>\driveguard\widget_snapshot.json
```

```json
{
  "devices": [
    {"id": "...", "name": "NVMe SSD", "valueText": "47°C", "fraction": 0.5, "severity": "normal"}
  ],
  "updatedAt": "2026-09-07T12:00:00.000"
}
```

`RenderCardJson()` in `WidgetProvider.cpp` already parses this and maps it
onto `widget_template.json`'s `FactSet` — that part needs no further work
once the provider is actually hosted.
