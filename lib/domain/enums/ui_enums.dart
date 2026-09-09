/// Which screen edge the edge-docked hover panel is anchored to. Lives in
/// domain (rather than application/infrastructure) since both
/// `AppSettings` and the window-geometry code need it without creating a
/// layering dependency between them.
enum ScreenEdge { left, right, top, bottom }
