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

/// Optional rows shown in the edge dock's hover detail panel. Temperature is
/// always shown (it's the rail's primary metric); these control the rest.
enum EdgeDockMetric { health, smart, powerOnHours, transferSpeed, freeCapacity }

/// How the system-tray / menu-bar icon looks.
enum TrayIconStyle {
  glyph('Drive', 'A drive icon that changes colour when attention is needed.'),
  dot('Status dot', 'A single dot: calm when fine, amber or red when not.'),
  temperature('Temperature', 'The temperature with its unit — nothing else.'),
  ring('Ring gauge', 'A ring that fills as the drive heats up, number inside.'),
  bars('Level bars', 'Three bars that rise with the temperature.');

  const TrayIconStyle(this.label, this.description);
  final String label;
  final String description;
}

/// Which reading the tray icon represents.
enum TrayMetric {
  hottest('Hottest drive'),
  average('Average of all drives');

  const TrayMetric(this.label);
  final String label;
}

/// How much each drive row in the tray menu shows.
enum TrayMenuDetail {
  compact('Compact'),
  detailed('Detailed');

  const TrayMenuDetail(this.label);
  final String label;
}
