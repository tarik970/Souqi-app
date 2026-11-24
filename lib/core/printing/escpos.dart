/// The handful of ESC/POS commands Souqi needs.
///
/// The invoice is printed as a picture (so Arabic shapes and joins correctly
/// with no code pages involved), which leaves exactly four commands:
/// initialise, raster image, feed, cut. Pure Dart and fully unit-tested —
/// no ESC/POS package is used, see the phase 3 notes.
library;

import 'dart:typed_data';

import 'raster.dart';

/// Rows per `GS v 0` command. The image is sent as a stack of short bands
/// instead of one tall command: a cheap printer buffers a whole command
/// before printing it, and a band this size (72 bytes × 96 rows ≈ 7 KB on
/// 80 mm paper) fits the small receive buffer of Xprinter-class clones.
/// Bands butt against each other — raster commands add no line feed.
const int defaultBandRows = 96;

abstract final class EscPos {
  /// ESC @ — reset the printer to its power-on state.
  static const List<int> initialize = [0x1B, 0x40];

  /// ESC d n — print the buffer and feed [lines] lines (0–255).
  static List<int> feed(int lines) => [0x1B, 0x64, lines.clamp(0, 255)];

  /// GS V 66 0 — feed to the cutter and cut (partial cut on most printers).
  /// Printers without a cutter ignore it.
  static const List<int> cut = [0x1D, 0x56, 0x42, 0x00];

  /// GS v 0 m xL xH yL yH — header of a raster bit image, [widthBytes] bytes
  /// per row and [rows] rows, normal scale (m = 0). The image data follows.
  static List<int> rasterHeader({required int widthBytes, required int rows}) => [
        0x1D, 0x76, 0x30, 0x00,
        widthBytes & 0xFF, (widthBytes >> 8) & 0xFF,
        rows & 0xFF, (rows >> 8) & 0xFF,
      ];
}

/// Builds the complete byte stream for one print job: initialise, the image
/// as `GS v 0` bands, then feed and (optionally) cut.
Uint8List buildRasterJob(
  MonoImage image, {
  int feedLines = 3,
  bool cut = false,
  int bandRows = defaultBandRows,
}) {
  if (bandRows <= 0) {
    throw ArgumentError.value(bandRows, 'bandRows', 'must be > 0');
  }
  final bytesPerRow = image.bytesPerRow;
  final out = BytesBuilder(copy: false)..add(EscPos.initialize);
  for (var row = 0; row < image.height; row += bandRows) {
    final rows = row + bandRows > image.height ? image.height - row : bandRows;
    out
      ..add(EscPos.rasterHeader(widthBytes: bytesPerRow, rows: rows))
      ..add(Uint8List.sublistView(
        image.bits,
        row * bytesPerRow,
        (row + rows) * bytesPerRow,
      ));
  }
  if (feedLines > 0) out.add(EscPos.feed(feedLines));
  if (cut) out.add(EscPos.cut);
  return out.toBytes();
}
