/// ============================================================================
///  DOCK & INFO-CARD STYLE  -  the one file to edit when tuning the look.
/// ============================================================================
///
/// All values are logical pixels unless noted. After editing, save and run
/// `flutter run -d macos`: the dock lives in its own window, so hot reload will
/// not pick these up.
///
/// Three groups:
///   [DockRailTuning]  the pill the drives sit in (width, curved ends, corners)
///   [DockCardTuning]  the info card that opens beside a drive
///   [DockArcTuning]   the thin hint arcs beyond each curved end
///
/// Keep the card's *height* maths in mind: its blocks have fixed heights (see
/// EdgeDockGeometry.panelHeaderHeight), so changing the card's width, radius,
/// arrow, opacity or padding is safe; changing fonts/row heights is not.
library;

/// The rail: the pill docked to the screen edge that holds the drive rings.
abstract final class DockRailTuning {
  // ---- size -----------------------------------------------------------------

  /// How wide the rail is, measured away from the screen edge.
  /// Bigger = a chunkier rail. (Ring + padding must fit: keep >= ringDiameter+24)
  static const double thickness = 76;

  /// Width of the slim strip that stays when the dock is collapsed.
  static const double collapsedThickness = 14;

  // ---- the drive rings --------------------------------------------------------

  /// Diameter of each drive's temperature ring.
  static const double ringDiameter = 44;

  /// Gap between two drives' rings.
  static const double itemSpacing = 22;

  /// Thickness of the ring's coloured arc.
  static const double ringStroke = 3.6;

  // ---- curved ends ------------------------------------------------------------

  /// Length of each end's curve ALONG the screen edge. Longer = a gentler,
  /// wider flare into the screen edge.
  static const double sweepLength = 44;

  /// How far each end's curve reaches INTO the rail. Bigger = deeper flare.
  static const double sweepDepth = 26;

  /// Smoothness of the end curves, 0.45..0.8. 0.45 is a plain circular
  /// corner; higher flattens the curve into the edge and the body (smoother,
  /// more "continuous"). 0.64 is the default.
  static const double sweepSmoothness = 0.64;

  /// Space reserved at each end of the rail, outside the body, where the curve
  /// lives and the hand / gear buttons float. Must be >= [sweepLength].
  static const double endMargin = 56;

  // ---- body -------------------------------------------------------------------

  /// Corner radius of the rail's rounded free side ("border radius").
  /// Larger = rounder, up to about half of [thickness].
  static const double faceRadius = 26;

  /// Breathing room between the body's ends and the first / last drive.
  static const double bodyPadding = 22;

  // ---- surface ----------------------------------------------------------------

  /// Opacity of the rail's fill (1 = solid, lower = more see-through).
  static const double fillOpacity = 0.90;

  /// Opacity and width of the thin light outline around the rail.
  static const double borderOpacity = 0.16;
  static const double borderWidth = 1.0;

  /// Soft diagonal light sheen across the glass.
  static const bool glassSheen = true;
}

/// The info card that opens beside a drive on hover.
abstract final class DockCardTuning {
  // ---- size & position --------------------------------------------------------

  /// Width of the card.
  static const double width = 264;

  /// Gap between the card's arrow tip and the rail.
  static const double gap = 10;

  // ---- shape ------------------------------------------------------------------

  /// Corner radius of the card ("border radius").
  static const double cornerRadius = 20;

  /// The little pointer toward the rail: how far it sticks out, and how wide
  /// its base is.
  static const double arrowDepth = 8;
  static const double arrowWidth = 16;

  // ---- padding ----------------------------------------------------------------

  /// Space between the card's edge and its content.
  static const double paddingHorizontal = 16;
  static const double paddingVertical = 14;

  // ---- surface ----------------------------------------------------------------

  /// Opacity of the card's fill (1 = solid, lower = more see-through).
  static const double fillOpacity = 0.82;

  /// Opacity and width of the thin light outline around the card.
  static const double borderOpacity = 0.14;
  static const double borderWidth = 1.0;

  /// Soft diagonal light sheen across the glass.
  static const bool glassSheen = true;
}

/// The thin arcs drawn beyond each curved end of the rail (they fade out and
/// the hand / gear button takes over on hover).
abstract final class DockArcTuning {
  /// Length of the arc along the rail's end (the rail is
  /// [DockRailTuning.thickness] wide).
  static const double span = 68;

  /// How far the middle of the arc sags toward the rail body.
  /// Small = nearly flat line, large = deeper curve.
  static const double depth = 6;

  /// Line thickness.
  static const double strokeWidth = 3.4;

  /// Shifts the arc toward (+) or away from (-) the rail body. 0 centres it
  /// in the margin between the rail's end and the dock window's edge.
  static const double shiftTowardBody = 0;

  /// Opacity of the arc's colour (it uses the rail's own fill colour).
  static const double opacity = 0.9;

  /// Smoothness of the draw-on / flatten animation.
  static const Duration animation = Duration(milliseconds: 320);
}
