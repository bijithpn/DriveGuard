# Design Specification: Organic Edge Dock UI & Fluid Animation System

**Date:** 2026-09-09  
**Status:** Approved  
**Target:** macOS, Windows, Linux  

---

## 1. Overview & Objective

Redesign the DriveGuard Edge Dock to match the visual aesthetic, organic silhouette, and fluid interactive animations shown in `video.mov`. The dock attaches flush against the screen edge with continuous Bezier curves, provides an edge trigger/collapsed state that expands smoothly on hover, features circular ring gauges with bold percentage indicators, includes an organic bottom action pod bridge (settings / quick toggle), and renders floating speech-bubble detail popovers with an arrow beak aligned dynamically to hovered items.

---

## 2. Visual & Architectural Design

### 2.1 Organic Screen-Edge Contour & Silhouette
- **Screen-Flush Geometry**: The dock base is flush with the screen edge ($x = 0$ for left edge, $x = W$ for right edge).
- **Curved Fillets & Waists**:
  - **Top Transition**: Smooth concave Bezier arc sweeping from screen edge out into the main body width.
  - **Main Rail Body**: Uniform convex pill width (~$68\text{px}$) containing device metrics.
  - **Bottom Bridge & Action Pod**: Smooth concave curve connecting the main rail to a circular bottom pod (housing Settings or global quick action).
  - **Bottom Transition**: Smooth concave Bezier arc returning back into the screen edge.
- **Color Palette & Styling**:
  - Background: Deep AMOLED Pitch Black (`#0A0A0C` / `#000000`) with soft dark elevation shadow (`blurRadius: 20`, `offset: (4, 0)`).
  - Borders/Outlines: Subtle dark surface highlight (`#1E1E26`).
  - Active Accents: Vibrant device-state / temperature / severity colors (Green `#22C55E`, Amber `#F59E0B`, Crimson `#EF4444`, Cyan `#06B6D4`, Indigo `#818CF8`).

### 2.2 Gauge & Item Visuals
- **Ring Gauges**:
  - Circular background track with dark outline.
  - Colored progress arc with rounded caps reflecting usage / temperature percentage.
  - Center icon (NVMe memory chip, SSD drive, disk, AI/activity badge).
  - Tabular bold numeric percentage below ring (`98%`, `29%`).
  - Subtle scale transition on hover (`1.0 -> 1.08`).

### 2.3 Floating Arrow-Beak Detail Popover
- **Speech Bubble Beak**:
  - Custom-painted speech bubble container with an arrow pointer / beak extending toward the active ring's exact vertical center.
- **Content Hierarchy**:
  - **Header**: Device Icon + Device Name (`Codex Usage`, `Drive 1 - Samsung 980 Pro`) + Subtitle/Status (`Monthly limit`, `Normal`).
  - **Linear Progress Bar**: Glowing horizontal progress bar with percentage readout and split metrics (`98% Used · 2% left` or `42°C · 98% Health`).
  - **Details List**: Secondary telemetry rows (SMART status, Power-on hours, Transfer read/write speeds, Free capacity).

### 2.4 Animation & State Machine
- **State 1: Collapsed / Idle Trigger**
  - Dock retracts toward the screen edge, showing only a sleek minimal edge tab (~12px width).
  - Zero performance draw when idle.
- **State 2: Expanded Rail**
  - Triggered by pointer entry into edge trigger zone.
  - Smooth spring / cubic expansion (`Curves.easeOutCubic`, duration 250ms).
  - Gauge items stagger-fade in with spring overshoot.
- **State 3: Popover Active**
  - Triggered by item hover.
  - Popover fades & slides out beside the active item with beak precisely anchored to the item center.
  - Debounced unhover allows seamless travel between rail and popover without flickering.

---

## 3. Component Structure & Data Flow

1. **`EdgeDockOrganicPainter` (`lib/presentation/widget/edge_dock_organic_painter.dart`)**:
   - High-performance `CustomPainter` rendering the continuous cubic Bezier contour for left, right, top, or bottom screen edges.
   - Paints the main rail, top/bottom concave blends, and bottom bridge pod.

2. **`EdgeDockSpeechBubblePainter` (`lib/presentation/widget/edge_dock_popover_bubble.dart`)**:
   - `CustomPainter` rendering the popover card background with dynamic arrow beak anchored to the target ring's Y coordinate.

3. **`EdgeDockContent` (`lib/presentation/widget/edge_dock_view.dart`)**:
   - Interactive surface managing hover state, expansion animation controllers, ring lists, bottom action button, and popover positioning.

4. **`EdgeDockGeometry` (`lib/infrastructure/tray/edge_dock_geometry.dart`)**:
   - Screen coordinate computations for rail bounds, collapsed trigger bounds, item centers, and popover window regions.

5. **`EdgeDockApp` (`lib/presentation/widget/edge_dock_app.dart`)**:
   - Multi-window frameless transparent window host, handling seamless OS window resizing and event handling.

---

## 4. Performance & Cross-Platform Guarantees

- **No Continuous Polling**: Hover and transitions are purely event-driven using Flutter's native `MouseRegion` and `AnimationController`.
- **Hardware Acceleration**: All vector paths are cached in `Path` objects and drawn directly onto GPU canvas.
- **Cross-Platform**: Zero platform-specific UI forks; runs natively on macOS, Windows, and Linux.
- **Frameless Transparency**: Uses OS-level transparent composition with clean hit-testing.
