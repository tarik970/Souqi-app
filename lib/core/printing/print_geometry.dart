/// Paper geometry for thermal printers. Pure math, no Flutter.
///
/// The printable width is always COMPUTED from the paper width, the side
/// margins and the printer resolution — never hard-coded — so any paper size
/// or print head works by changing settings.
library;

const double mmPerInch = 25.4;

/// Narrowest and widest raster we will ever lay an invoice out on. Below the
/// minimum nothing readable fits; the maximum is far beyond any receipt
/// printer (a 4-inch 300 dpi head is 1248 dots) and only guards typos.
const int minPrintableDots = 96;
const int maxPrintableDots = 2400;

/// Rounds [dots] down to a multiple of 8 (a raster row is sent as whole
/// bytes) and clamps it to the supported range.
int snapDots(int dots) {
  final snapped = dots - dots % 8;
  if (snapped < minPrintableDots) return minPrintableDots;
  if (snapped > maxPrintableDots) return maxPrintableDots;
  return snapped;
}

/// Printable width in printer dots:
///
///   dots = round((paperMm - 2 × marginMm) × dpi / 25.4)
///
/// then rounded DOWN to a multiple of 8.
///
/// With the default margins ([defaultSideMarginFor]) at 203 dpi: 80 mm
/// paper with 7.5 mm → 519 → 512 dots, and 58 mm paper with 5 mm → 384
/// dots.
int computePrintableDots({
  required double paperWidthMm,
  required double sideMarginMm,
  required int dpi,
}) {
  final printableMm = paperWidthMm - 2 * sideMarginMm;
  return snapDots((printableMm * dpi / mmPerInch).round());
}

/// A length in millimetres as dots at [dpi] (not snapped).
double mmToDots(double mm, int dpi) => mm * dpi / mmPerInch;

/// A width in dots back to millimetres, for showing the user what a dot
/// count means on paper.
double dotsToMm(int dots, int dpi) => dots * mmPerInch / dpi;

/// Dots of the print head a printer for [paperWidthMm] paper normally has —
/// the widest image it can print. A wider one is cut off, wraps into
/// garbage or is refused outright.
///
/// 58 mm paper has a 48 mm head (384 dots at 203 dpi) and 80 mm paper a
/// 72 mm one (576 dots); the label printers that take 80 mm rolls
/// ([labelPrinter]) have a 76 mm head (608 dots). For any other paper the
/// only limit known is the paper itself. Dots per millimetre are whole, as
/// print heads are built: 8 at 203 dpi, 12 at 300 dpi.
int standardHeadDots({
  required double paperWidthMm,
  required int dpi,
  bool labelPrinter = false,
}) {
  final double headMm;
  if (paperWidthMm == 58) {
    headMm = 48;
  } else if (paperWidthMm == 80) {
    headMm = labelPrinter ? 76 : 72;
  } else {
    headMm = paperWidthMm;
  }
  final dotsPerMm = (dpi / mmPerInch).round();
  return snapDots((headMm * (dotsPerMm < 1 ? 1 : dotsPerMm)).floor());
}

/// The default side margin of 80 mm paper: 7.5 mm, a printable width of
/// 512 dots (64 mm) at 203 dpi.
///
/// NOT the whole 72 mm head (3.5 mm, 576 dots), which was the default at
/// first: measured on a real printer (Xprinter XP-365B, 80 mm roll), 576
/// dots came out cut off at the side and 512 printed complete. A print
/// head is wider than what a given printer lands on the paper; a default
/// has to fit without calibration, and a shop whose printer does print the
/// full head can still widen it.
const double defaultSideMargin80Mm = 7.5;

/// The default side margin of 58 mm paper: its 48 mm head, 384 dots.
const double defaultSideMargin58Mm = 5;

/// The default side margin of each standard paper — what a new shop
/// starts with, and what picking a paper preset sets. A margin the shop
/// has saved is never replaced by it.
double defaultSideMarginFor(double paperWidthMm) {
  if (paperWidthMm == 58) return defaultSideMargin58Mm; // → 384 dots
  return defaultSideMargin80Mm; // → 512 dots
}
