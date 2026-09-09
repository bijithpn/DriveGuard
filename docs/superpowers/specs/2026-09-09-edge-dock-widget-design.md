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

## Follow-up revision (2026-09-09, same day)

Requested after first landing: visual polish, customizable accent color,
smoother hover response, and visibility over native fullscreen apps.

- **Collapsed state redesign**: the collapsed element is now a rounded pill
  "badge" (40x96, `stripThickness`/`stripLength` in `EdgeDockGeometry`
  repurposed to these dimensions) showing a small thermometer icon + the
  worst device's value, instead of a bare 6px color sliver — legible even
  before hovering, closer to the requested reference interaction (a small
  glanceable indicator that reveals detail on hover).
- **Accent color**: `EdgeDockSettings.accent` (`EdgeDockAccent` enum: auto +
  6 curated colors) lets the user override the automatic severity tint.
  `auto` preserves the original behavior. Implemented as a fixed palette
  rather than a full color picker (matches how the rest of the app already
  exposes fixed design-system colors; avoids a picker dependency for a
  window that's mostly glanced at, not styled precisely).
- **Smoother interaction**: cursor poll interval reduced from 120ms to 60ms;
  content now cross-fades via `AnimatedSwitcher` between the badge and panel
  instead of an abrupt swap, while `window_manager`'s native `setBounds`
  animation still handles the actual window-size/position motion.
- **Fullscreen visibility (macOS)**: `window_manager` already wraps the
  NSWindow `collectionBehavior` flags needed for a window to join all
  Spaces and stay visible over fullscreen apps
  (`setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true)`) — this is
  called for the edge dock window on macOS. No native Swift code needed;
  it was a matter of using an already-wrapped API. Windows/Linux have no
  equivalent call in `window_manager`; their always-on-top + skip-taskbar
  behavior over fullscreen windows is unverified and left as-is.

## Second follow-up revision (2026-09-09, same day): per-device rail + native hover

The user reported a `RenderFlex` overflow in the badge widget and asked for
a full redesign: a rail of individually-hoverable per-device ring
indicators (not one worst-device badge), a detail card beside whichever
ring is hovered, and — critically — genuinely smooth, native-feeling hover
instead of a polling loop.

### Architecture change: dropped cursor polling entirely

The earlier `Timer.periodic` + `screen_retriever.getCursorScreenPoint()`
polling loop is gone. Realization: once hover state is driven by content
*within* the dock's own OS window, ordinary Flutter `MouseRegion` widgets
receive real native mouse enter/exit events from the OS (NSTrackingArea on
macOS, WM_MOUSEMOVE/WM_MOUSELEAVE on Windows, X11/Wayland motion+crossing
events on Linux via GTK) — no polling needed at all. `screen_retriever` is
now called exactly once per window (`getPrimaryDisplay()` at startup) to
learn the display's bounds; it plays no role in hover detection.

The window still has to be *resized* on hover (Flutter can only render
within its own native window), so `window_manager.setBounds` is still
called reactively from the hover-state change, not from a poll tick.

### New geometry (`EdgeDockGeometry`, rewritten)

- `railRect(displayPos, displaySize, edge, deviceCount)`: the collapsed
  rail's rect, sized to fit one ring-and-label block per device
  (`railLength` grows with `deviceCount`).
- `ringCenter(rail, edge, index)`: screen-space center of the Nth device's
  ring, used only to position the detail panel next to it (not for hit
  testing — that's native `MouseRegion` now).
- `panelRectFor(rail, edge, ringCenter, displayPos, displaySize)`: the
  detail card's rect, opening away from the docked edge, clamped to the
  display's visible bounds so it never renders off-screen near the top/
  bottom (or left/right for a horizontal rail).
- `windowRectFor(rail, panel)`: the bounding box the OS window must cover
  to show both regions at once.

`EdgeDockHoverTracker` (still pure/unit-tested) is kept as a defensive
grace-period debounce, used in tests; in the running app the equivalent
role is played by `EdgeDockCollapseDebouncer`, a tiny `Timer` wrapper: an
`onExit` from the dock's outer `MouseRegion` schedules a collapse ~150ms
out, cancelled if hover resumes first.

### Content (`edge_dock_view.dart`, rewritten)

- `EdgeDockContent`: one `MouseRegion`-wrapped `Stack` containing the rail
  (`Positioned.fromRect`) and, when a ring is hovered, the detail card
  (`Positioned.fromRect`) — both positioned in window-local coordinates
  (screen rect minus the window's current origin). Because both live
  inside one `MouseRegion`, moving the cursor from a ring to its card is
  invisible to hover tracking - `onExit` only fires when the cursor leaves
  the window entirely.
- Each ring (`_RingItem`) is its own `MouseRegion` reporting its index on
  `onEnter`, with a small `AnimatedScale` (120ms) for hover feedback.
- The detail card (`_DetailCard`) shows the hovered device's name plus
  whichever of temperature/health/SMART status/power-on hours/read+write
  speed/free capacity are non-null on the existing `MiniWidgetDeviceSnapshot`
  - no new data plumbing; this was already exactly the field set the
  mini-widget snapshot pipeline provides.

### Settings addition: opacity

`EdgeDockSettings.opacity` (0.4-1.0, default 1.0) added alongside `accent`,
applied via `window_manager.setOpacity` (the same mechanism the existing
mini-widget already uses for its own opacity setting) - whole-window
opacity, not a separate background-only alpha channel, kept simple.

### Explicitly not built (scope discipline given the size of the request)

- Multi-monitor picker - still primary-display only.
- A fully generic arbitrary-color picker - still a fixed accent palette.
- Per-metric visibility toggles, keyboard navigation, reduced-motion
  preference - not implemented; the existing fixed field set and
  mouse-only interaction cover the core ask without an open-ended settings
  surface.
- A separate `MonitorWidgetTheme` class with independently configurable
  success/warning/danger colors - reuses the app's existing `AppColors`
  severity palette instead, consistent with how every other screen in the
  app already sources its severity colors.
