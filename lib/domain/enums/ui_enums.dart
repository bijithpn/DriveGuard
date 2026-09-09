/// Which screen edge the edge-docked hover panel is anchored to. Lives in
/// domain (rather than application/infrastructure) since both
/// `AppSettings` and the window-geometry code need it without creating a
/// layering dependency between them.
enum ScreenEdge { left, right, top, bottom }

/// The edge dock's accent color. `auto` keeps the existing behavior (tinted
/// by the worst connected drive's severity); the rest are a small curated
/// palette rather than a full color picker, matching how the app already
/// exposes a fixed set of design-system colors elsewhere.
enum EdgeDockAccent { auto, blue, teal, purple, pink, orange, red }
