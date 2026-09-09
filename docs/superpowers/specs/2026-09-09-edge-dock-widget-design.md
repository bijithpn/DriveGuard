# Edge-Docked Hover Panel — Design

Date: 2026-09-09

## Problem

DriveGuard's existing mini monitor (`mini_monitor_view.dart`) is a freely
positioned, explicitly opened/closed window. The user wants a lighter-weight,
always-present glanceable element: a thin strip docked flush to a screen
edge, tinted by worst-drive severity, that expands into a small panel with
live temperatures on hover and collapses again when the cursor leaves. Edge
(left/right/top/bottom) is user-configurable. This is a new, independent
addition — the existing mini monitor is untouched.

## Why this is feasible without new native code

The app already depends on `window_manager` (frameless/always-on-top/
skip-taskbar/setBounds, used for the dashboard and mini-monitor windows) and
`desktop_multi_window` (secondary windows with argument-passed config, same
pattern as the mini widget in `main.dart`/`mini_widget_app.dart`). `screen_
retriever` is already present transitively via `window_manager` and exposes
`getCursorScreenPoint()` and display bounds — enough to implement hover
detection without any new platform channel or native plugin code.

## Scope (v1)

- Docks to the **primary display only** — no multi-monitor picker.
- **Centered** on the chosen edge, fixed length — no drag-to-reposition
  along the edge, no user resizing.
- Collapsed state: a slim strip (approx. 6px thick, ~120px long), tinted by
  the worst connected drive's severity color (normal/warning/critical),
  matching the "slim colored tab" choice already confirmed.
- Expanded state (on hover): a compact panel (~260x200, sized like the
  existing mini monitor's compact mode) sliding out from the docked edge,
  reusing the mini monitor's existing device-row/temp-ring presentation.
- Opt-in via Settings, off by default (same pattern as the existing mini
  widget).

## Data model

New `EdgeDockSettings` class in `app_settings.dart`, following the exact
`WidgetSettings` pattern (immutable, `copyWith`, `toJson`/`fromJson`):

```dart
class EdgeDockSettings {
  final bool enabled;       // default false
  final ScreenEdge edge;    // left | right | top | bottom, default right
}
```

Added to `AppSettings` as `edgeDock`, alongside the existing `widget` field,
persisted the same way through `SettingsRepository`.

## Window lifecycle

- `DesktopWindowController` gains `enterEdgeDockMode`/`exitEdgeDockMode`,
  mirroring `enterWidgetMode`/`exitWidgetMode`, opening a third secondary
  window (`desktop_multi_window`) with `mode: 'edgeDock'` in its arguments
  so `main.dart`'s existing argument-dispatch (`WindowController.
  fromCurrentEngine()` branch) can route to a new `EdgeDockApp` entry point,
  the same way it already routes to `MiniWidgetApp`.
- On start (and whenever `edgeDock.enabled`/`edgeDock.edge` changes), the
  window is created/repositioned: frameless, always-on-top, skip-taskbar,
  `setBounds` computed from `screenRetriever.getPrimaryDisplay()` and the
  configured edge, initially sized to the collapsed strip.
- A `Timer.periodic` (started when the window opens, cancelled when it
  closes) polls `screenRetriever.getCursorScreenPoint()` roughly 8x/second.
  A pure, unit-testable function `EdgeDockHoverState.next(cursor, stripRect,
  panelRect, currentlyExpanded)` decides expand/collapse, with a short
  collapse grace period (cursor must be outside both rects for ~400ms
  before collapsing) so moving toward the panel doesn't flicker.
- On expand/collapse, `window_manager.setBounds` animates between the strip
  rect and the panel rect (computed from the edge + collapsed anchor point).

## Content

**As implemented** (revised from the original plan below): `edge_dock_view.dart`
implements its own compact list-of-rows presentation (ring + name + value per
device) rather than extracting shared widgets out of the already-stable,
recently-redesigned `mini_monitor_view.dart`. That file's actual current
structure is a single-device paged carousel (`_SingleDeviceCard` +
`_MiniGaugePainter`), not the row-list shape this panel needs — extracting
from it would have meant reshaping a working, private-widget file for a
payoff (avoiding ~150 lines of independent, simple painting code) that
wasn't worth the risk. Both share the same `AppColors`/`AppTheme` tokens so
they read as the same visual language without being literally the same
widgets.

Data arrives via the same `MiniWidgetSnapshot` push mechanism already used
for the mini widget, over a second channel constant `kEdgeDockChannel`
(`desktop_window_controller.dart`), since it's a distinct secondary window.

**Original plan (superseded by the above):** factor `mini_monitor_view.dart`'s
device-row/temp-ring widgets out into a shared `presentation/widget/
mini_widgets.dart` file that both `MiniMonitorView` and the new
`EdgeDockView` import.

## UI: Settings

Settings → Widget section gets a new subsection: "Edge Dock" toggle +
segmented edge picker (Left/Right/Top/Bottom), following the existing
`_SettingRow`/`_SegmentedControl` patterns already in `settings_screen.dart`.

## Testing

- Unit tests for `EdgeDockHoverState.next(...)`: cursor inside strip →
  expand; cursor inside panel while expanded → stays expanded; cursor
  outside both, elapsed < grace period → stays expanded; elapsed >= grace
  period → collapses. Pure function, no window/platform dependency.
- Unit tests for the strip/panel rect computation given a display size and
  each of the four edges.
- `EdgeDockSettings.toJson`/`fromJson` round-trip test, matching the
  existing `WidgetSettings` test pattern if one exists (check first).
- No automated test can cover real window placement/always-on-top/hover
  behavior — manual verification on your Windows/Linux/macOS machines is
  required, same caveat as the mini widget and every other window_manager-
  dependent feature. I can verify basic window creation/positioning on
  macOS only.

## Non-goals

- Multi-monitor support, drag-to-reposition, and user resizing (all
  deferred, noted above).
- No changes to the existing mini monitor window's behavior.
- No new platform channel / native plugin code.
