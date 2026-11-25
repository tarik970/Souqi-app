/// The handful of ESC/POS commands Souqi needs.
///
/// The invoice is printed as a picture (so Arabic shapes and joins correctly
/// with no code pages involved), which leaves exactly four commands:
/// initialise, image, feed, cut. Pure Dart and fully unit-tested — no ESC/POS
/// package is used, see the phase 3 notes.
///
/// The image itself can travel in three dialects ([EscPosImageMode]): every
/// printer understands at least one of them, and cheap clones often only one.
library;

import 'dart:typed_data';

import 'raster.dart';

/// Rows per `GS v 0` command. The image is sent as a stack of short bands
/// instead of one tall command: a cheap printer buffers a whole command
/// before printing it, and a band this size (72 bytes × 96 rows ≈ 7 KB on
/// 80 mm paper) fits the small receive buffer of Xprinter-class clones.
/// Bands butt against each other — raster commands add no line feed.
const int defaultBandRows = 96;

/// Rows of one `ESC *` line in 24-dot mode.
const int escStarRows = 24;

/// How the picture is handed to an ESC/POS printer.
enum EscPosImageMode {
  /// `GS v 0` — the raster bit image. What almost every printer takes.
  gsV0('GS_V0', 'GS v 0'),

  /// `ESC * 33` — 24-dot bit image, one text line at a time. The oldest
  /// command; the fallback for printers that ignore `GS v 0`.
  escStar('ESC_STAR', 'ESC *'),

  /// `GS ( L` — the graphics command of newer Epson-compatible firmware,
  /// which has dropped `GS v 0`.
  gsL('GS_L', 'GS ( L');

  const EscPosImageMode(this.db, this.label);

  final String db;

  /// The command itself — the same in every language.
  final String label;

  static EscPosImageMode fromDb(String? value) => values
      .firstWhere((m) => m.db == value, orElse: () => EscPosImageMode.gsV0);
}

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

  /// ESC 3 n — line spacing of [dots] dots, so 24-dot lines butt.
  static List<int> lineSpacing(int dots) => [0x1B, 0x33, dots.clamp(0, 255)];

  /// ESC 2 — back to the default line spacing.
  static const List<int> defaultLineSpacing = [0x1B, 0x32];

  /// ESC * 33 nL nH — header of one 24-dot line, [widthDots] columns wide.
  /// Three bytes per column follow, top dot in the high bit.
  static List<int> bitImageHeader({required int widthDots}) => [
        0x1B, 0x2A, 33,
        widthDots & 0xFF, (widthDots >> 8) & 0xFF,
      ];

  static const int lineFeed = 0x0A;

  /// GS ( L pL pH 48 112 48 1 1 49 xL xH yL yH — "store the raster graphics
  /// in the print buffer": monochrome, normal scale, [widthDots] × [rows].
  /// The image data follows; pL pH count it plus the ten bytes after them.
  static List<int> graphicsStoreHeader({
    required int widthDots,
    required int rows,
  }) {
    final length = ((widthDots + 7) ~/ 8) * rows + 10;
    return [
      0x1D, 0x28, 0x4C,
      length & 0xFF, (length >> 8) & 0xFF,
      48, 112, 48, 1, 1, 49,
      widthDots & 0xFF, (widthDots >> 8) & 0xFF,
      rows & 0xFF, (rows >> 8) & 0xFF,
    ];
  }

  /// GS ( L 2 0 48 50 — print the stored graphics.
  static const List<int> graphicsPrint = [0x1D, 0x28, 0x4C, 2, 0, 48, 50];
}

/// Builds the complete byte stream for one print job: initialise, the image
/// in the chosen [mode], then feed and (optionally) cut.
Uint8List buildRasterJob(
  MonoImage image, {
  int feedLines = 3,
  bool cut = false,
  int bandRows = defaultBandRows,
  EscPosImageMode mode = EscPosImageMode.gsV0,
}) {
  if (bandRows <= 0) {
    throw ArgumentError.value(bandRows, 'bandRows', 'must be > 0');
  }
  final out = BytesBuilder(copy: false)..add(EscPos.initialize);
  switch (mode) {
    case EscPosImageMode.gsV0:
      _addRasterBands(out, image, bandRows);
    case EscPosImageMode.escStar:
      _addBitImageLines(out, image);
    case EscPosImageMode.gsL:
      _addGraphicsBands(out, image, bandRows);
  }
  if (feedLines > 0) out.add(EscPos.feed(feedLines));
  if (cut) out.add(EscPos.cut);
  return out.toBytes();
}

Uint8List _rows(MonoImage image, int row, int rows) => Uint8List.sublistView(
      image.bits,
      row * image.bytesPerRow,
      (row + rows) * image.bytesPerRow,
    );

void _addRasterBands(BytesBuilder out, MonoImage image, int bandRows) {
  for (var row = 0; row < image.height; row += bandRows) {
    final rows = row + bandRows > image.height ? image.height - row : bandRows;
    out
      ..add(EscPos.rasterHeader(widthBytes: image.bytesPerRow, rows: rows))
      ..add(_rows(image, row, rows));
  }
}

/// `ESC *` sends columns, not rows: three bytes per column, top dot first.
/// Each 24-dot line ends with a line feed, and the line spacing is set to
/// the same 24 dots so the lines butt. The last line is padded with white.
void _addBitImageLines(BytesBuilder out, MonoImage image) {
  final width = image.width;
  final bytesPerRow = image.bytesPerRow;
  final bits = image.bits;
  out.add(EscPos.lineSpacing(escStarRows));
  for (var top = 0; top < image.height; top += escStarRows) {
    final columns = Uint8List(width * 3);
    final bottom =
        top + escStarRows > image.height ? image.height : top + escStarRows;
    for (var y = top; y < bottom; y++) {
      final rowStart = y * bytesPerRow;
      final line = y - top;
      final byteInColumn = line >> 3;
      final mask = 0x80 >> (line & 7);
      for (var x = 0; x < width; x++) {
        if (bits[rowStart + (x >> 3)] & (0x80 >> (x & 7)) != 0) {
          columns[x * 3 + byteInColumn] |= mask;
        }
      }
    }
    out
      ..add(EscPos.bitImageHeader(widthDots: width))
      ..add(columns)
      ..addByte(EscPos.lineFeed);
  }
  out.add(EscPos.defaultLineSpacing);
}

/// `GS ( L`: each band is stored, then printed. The two-byte length of the
/// command caps a band at 65,535 − 10 bytes; [bandRows] is cut down to fit.
void _addGraphicsBands(BytesBuilder out, MonoImage image, int bandRows) {
  final most = (0xFFFF - 10) ~/ image.bytesPerRow;
  if (most < 1) {
    throw ArgumentError.value(image.width, 'image.width', 'too wide for GS ( L');
  }
  final band = bandRows > most ? most : bandRows;
  for (var row = 0; row < image.height; row += band) {
    final rows = row + band > image.height ? image.height - row : band;
    out
      ..add(EscPos.graphicsStoreHeader(widthDots: image.width, rows: rows))
      ..add(_rows(image, row, rows))
      ..add(EscPos.graphicsPrint);
  }
}
