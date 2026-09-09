# Organic Edge Dock UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform DriveGuard's edge dock into an organic Bezier screen-edge protrusion with fluid collapsed/expanded animations, circular gauges with percentage readouts, a bottom action pod, and floating arrow-beak popovers matching `video.mov`.

**Architecture:** A high-performance Flutter vector canvas rendering pipeline using custom Bezier math (`CustomPainter`), hardware-accelerated spring animations (`AnimationController`), and non-flickering transparent window bounds management (`EdgeDockGeometry` + `EdgeDockApp`).

**Tech Stack:** Flutter / Dart, `desktop_multi_window`, `window_manager`, `screen_retriever`.

## Global Constraints
- Target platforms: macOS, Windows, Linux.
- Zero frame drops: Pure vector rendering with 60/120fps hardware acceleration.
- No continuous cursor polling: Event-driven `MouseRegion` hit-testing.
- Maintain existing architecture and telemetry persistence integration.

---

### Task 1: Vector Organic Edge Path & Speech-Bubble Popover Painters

**Files:**
- Create: `lib/presentation/widget/edge_dock_organic_painter.dart`
- Create: `lib/presentation/widget/edge_dock_popover_bubble.dart`
- Test: `test/presentation/widget/edge_dock_painter_test.dart`

**Interfaces:**
- Produces:
  - `class EdgeDockOrganicPainter extends CustomPainter`: builds organic Bezier path with top fillet, convex rail, concave bridge to bottom pod, and bottom fillet.
  - `class EdgeDockPopoverBubble extends StatelessWidget`: wraps child in a speech-bubble container with an arrow pointer beak at a specified Y offset.

- [x] **Step 1: Write test for organic Bezier path computation**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `EdgeDockOrganicPainter` and `EdgeDockPopoverBubble`**
- [x] **Step 4: Run test to verify it passes**
- [x] **Step 5: Commit changes**

---

### Task 2: Refined Circular Ring Gauges & Bottom Action Pod

**Files:**
- Modify: `lib/presentation/widget/edge_dock_view.dart`
- Test: `test/presentation/widget/edge_dock_view_test.dart`

**Interfaces:**
- Produces:
  - `_OrganicRingItem`: Circular gauge with outer background track, glowing colored progress arc, centered device type icon, and tabular bold percentage text.
  - `_BottomActionPod`: Bottom circular pod button (settings/quick actions) connected via organic bridge.

- [ ] **Step 1: Write unit/widget tests for ring item and pod**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `_OrganicRingItem` and `_BottomActionPod`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 3: Arrow-Beak Detail Popover with Linear Progress Bars

**Files:**
- Modify: `lib/presentation/widget/edge_dock_view.dart`
- Test: `test/presentation/widget/edge_dock_popover_test.dart`

**Interfaces:**
- Produces:
  - `_ModernDetailCard`: High-contrast dark popover with arrow beak, device header with badge, linear progress bar breakdown, and secondary telemetry list.

- [ ] **Step 1: Write widget test for `_ModernDetailCard`**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `_ModernDetailCard` inside `edge_dock_view.dart`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 4: Fluid State Machine, Edge Collapse/Expand, and Smooth Animations

**Files:**
- Modify: `lib/presentation/widget/edge_dock_view.dart`
- Modify: `lib/presentation/widget/edge_dock_app.dart`
- Modify: `lib/infrastructure/tray/edge_dock_geometry.dart`
- Test: `test/infrastructure/tray/edge_dock_geometry_test.dart`

**Interfaces:**
- Produces:
  - Expandable / collapsible edge state with smooth spring easing.
  - Responsive window bounds resizing that synchronizes without frame jitter.

- [ ] **Step 1: Write unit tests for updated geometry and bounds**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement expansion state machine and animation controllers**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 5: End-to-End Verification & Analysis

**Files:**
- Verify: Full codebase

- [ ] **Step 1: Run `flutter analyze`**
- [ ] **Step 2: Run `flutter test` across all test suites**
- [ ] **Step 3: Commit and finalize**
