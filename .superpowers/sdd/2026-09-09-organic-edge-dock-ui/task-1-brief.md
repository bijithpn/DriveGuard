# Task 1 Brief: Vector Organic Edge Path & Speech-Bubble Popover Painters

## Objective
Implement high-performance vector canvas painters in Flutter to draw:
1. The continuous organic Bezier curve dock shape attached flush to the screen edge (supporting left/right/top/bottom edges), including top concave blend, convex rail body, concave bridge to bottom action pod, and bottom concave blend.
2. The speech-bubble popover card with a dynamic arrow beak pointing at the target center coordinate of the hovered item.

## Files
- Create: `lib/presentation/widget/edge_dock_organic_painter.dart`
- Create: `lib/presentation/widget/edge_dock_popover_bubble.dart`
- Create / Test: `test/presentation/widget/edge_dock_painter_test.dart`

## Specifications
1. `EdgeDockOrganicPainter` (`CustomPainter`):
   - Parameters:
     - `ScreenEdge edge`
     - `Color backgroundColor` (default `#0A0A0C`)
     - `Color borderColor` (default `#1E1E26`)
     - `double borderWidth` (default 1.0)
     - `double mainRailLength` (height of main gauge rail)
     - `double podDiameter` (diameter of bottom action pod, e.g. 36-40px)
     - `double podSpacing` (spacing between main rail and bottom pod, with smooth concave bridge)
     - `double expansionProgress` (0.0 for collapsed edge tab, 1.0 for fully expanded rail)
     - `bool showPod` (whether bottom pod is present)
   - Behavior:
     - Calculates a closed `Path` using cubic Bezier curves (`cubicTo` / `conicTo` / `arcToPoint`) starting from edge coordinate $(0, 0)$ on left edge, curving smoothly out, rounding down, bridging concavely to the pod circle, and sweeping back into $(0, \text{totalHeight})$.
     - Handles right edge symmetrically (mirrored horizontally) and top/bottom edges appropriately.
     - Paints soft dark drop shadow (`BoxShadow` / `Canvas.drawShadow` or blurred path paint) and clean outline border.
2. `EdgeDockPopoverBubble` (`StatelessWidget`) & `EdgeDockSpeechBubblePainter` (`CustomPainter`):
   - Parameters:
     - `Widget child`
     - `ScreenEdge edge`
     - `double targetArrowY` (local vertical center of the hovered ring item relative to the bubble)
     - `Color backgroundColor` (default `#0A0A0C`)
     - `Color borderColor` (default `#1E1E26`)
     - `double borderRadius` (default 16.0)
     - `double arrowSize` (e.g. 8.0 width, 12.0 height)
   - Behavior:
     - Paints a rounded rectangle container with an arrow pointer / beak sticking out toward the rail at `targetArrowY`.
     - Draws shadow and border cleanly around the combined path (bubble + arrow).

## Testing
- Write tests in `test/presentation/widget/edge_dock_painter_test.dart`:
  - Verify path construction without exceptions.
  - Verify bounding box correctness for collapsed vs expanded progress.
  - Verify speech bubble painter path includes the arrow beak.
- Run `flutter test test/presentation/widget/edge_dock_painter_test.dart` to verify all tests pass.
