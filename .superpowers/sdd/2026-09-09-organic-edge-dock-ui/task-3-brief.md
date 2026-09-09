# Task 3 Brief: Arrow-Beak Detail Popover with Linear Progress Bars

## Objective
Redesign the detail popover (`_DetailCard`) in `lib/presentation/widget/edge_dock_view.dart` using `EdgeDockPopoverBubble` to match the exact visual presentation seen in `video.mov`:
1. Speech-bubble container with an arrow pointer beak anchored to the target hovered ring's center.
2. Sleek card layout: Device icon + Title + Status badge header.
3. Horizontal glowing linear progress bar with usage / temperature percentage breakdown text (`X% Used · Y% Left` / `Temp · Health`).
4. Secondary telemetry rows (SMART status, transfer speed, free storage, power-on hours).

## Files
- Modify: `lib/presentation/widget/edge_dock_view.dart`
- Create / Modify: `test/presentation/widget/edge_dock_popover_test.dart`

## Specifications
1. **`_DetailCard` & `EdgeDockPopoverBubble` Integration**:
   - Wrap the card content in `EdgeDockPopoverBubble(edge: edge, targetArrowY: targetArrowY, ...)`.
   - Calculate `targetArrowY`: the local Y position of the active ring's center relative to the top of the detail popover card.
2. **Card Structure**:
   - Deep AMOLED dark styling (`EdgeDockTheme.background` / `#0A0A0C`), subtle border (`#1E1E26`), soft elevation shadow.
   - **Header Section**:
     - Left: Icon (NVMe/SSD/Memory chip) + Bold Title (`device.name`).
     - Right: Status badge or secondary subtitle (e.g. `device.healthStatus` or status pill).
   - **Linear Progress Section**:
     - Horizontal progress bar (height ~5px, track `#1E1E28`, animated fill in severity/accent color, radius 3px).
     - Breakdown label underneath: e.g. `${(device.fraction * 100).round()}% Used · ${(100 - (device.fraction * 100).round())}% left` or `${device.valueText} · Health ${device.lifePercent ?? 100}%`.
   - **Metrics List**:
     - Render enabled `visibleMetrics` (SMART status, Power-on hours, Transfer speed, Free storage) in clean two-column key-value rows.
3. **Motion**:
   - Snappy spring/cubic entrance animation (`scale: 0.94 -> 1.0`, `opacity: 0 -> 1`, curve `Curves.easeOutCubic`, duration 180ms).

## Testing
- Add tests in `test/presentation/widget/edge_dock_popover_test.dart`:
  - Verify detail card renders `EdgeDockPopoverBubble` with correct `targetArrowY`.
  - Verify header, linear progress bar, breakdown text, and telemetry rows are correctly formatted and rendered.
- Run `flutter test test/presentation/widget/edge_dock_popover_test.dart` and `flutter analyze`.
