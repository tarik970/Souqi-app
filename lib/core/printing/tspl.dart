/// TSPL — the language of label printers, and of dual label/receipt printers
/// (Xprinter XP-365B and its kind) while they are in LABEL mode. In that
/// mode ESC/POS bytes are noise: the printer beeps and prints nothing.
///
/// The receipt is the same picture as for ESC/POS, printed as a "label"
/// exactly as long as its content on continuous paper:
///
///   SIZE w mm,h mm · GAP 0 mm,0 mm · DIRECTION 0 · REFERENCE 0,0 ·
///   CLS · BITMAP x,0,widthBytes,rows,0,data · PRINT 1,1
///
/// The label (SIZE) is as wide as the PAPER; the image is narrower and is
/// placed on it with the BITMAP x position — centred on the print head by
/// default ([tsplBitmapX]), then moved by the printer's calibration offset.
///
/// Commands are ASCII lines ending in CR LF; only the BITMAP data is binary.
/// Nothing here cuts paper or opens a cash drawer. Pure Dart, unit-tested.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'print_geometry.dart';
import 'raster.dart';

/// Most rows of one TSPL page. A label printer draws the whole label into
/// its image buffer before printing it, and that buffer is small on cheap
/// firmware: a longer receipt is sent as several labels one after another.
/// With no gap between labels the pages join on paper. 1000 rows are
/// 125 mm at 203 dpi.
const int defaultTsplPageRows = 1000;

const String _eol = '\r\n';

/// Whole dots per millimetre of a [dpi] head, the way TSPL firmware counts
/// them: 8 at 203 dpi, 12 at 300 dpi.
int tsplDotsPerMm(int dpi) {
  final dots = (dpi / mmPerInch).round();
  return dots < 1 ? 1 : dots;
}

/// The rows of each page of an image [rows] tall: as few pages as
/// [pageRows] allows, of even height — never a last page of a few rows,
/// which is shorter than the shortest label a printer accepts. Every page
/// but the last is a whole number of millimetres ([dotsPerMm]), so its
/// label is exactly as long as its bitmap and the pages join without a gap.
List<int> tsplPageHeights(
  int rows, {
  required int dotsPerMm,
  int pageRows = defaultTsplPageRows,
}) {
  if (rows <= 0) return const [];
  // The page limit itself, in whole millimetres.
  var limit = pageRows - pageRows % dotsPerMm;
  if (limit < dotsPerMm) limit = dotsPerMm;
  if (rows <= limit) return [rows];
  final pages = (rows / limit).ceil();
  var each = (rows / pages).ceil();
  each += (dotsPerMm - each % dotsPerMm) % dotsPerMm;
  final heights = <int>[];
  for (var left = rows; left > 0; left -= each) {
    heights.add(left < each ? left : each);
  }
  return heights;
}

/// Where the image starts on the label, in dots from its left edge: centred
/// on a print head of [headDots] — a 576-dot image on the 608-dot head of a
/// 76 mm label printer starts at 16 — and then moved by [offsetDots], the
/// printer's calibration (negative = left). Never left of the label: a
/// BITMAP cannot start before dot 0.
int tsplBitmapX({
  required int headDots,
  required int imageDots,
  int offsetDots = 0,
}) {
  final centred = headDots > imageDots ? (headDots - imageDots) ~/ 2 : 0;
  final x = centred + offsetDots;
  return x < 0 ? 0 : x;
}

String _mm(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : mm.toStringAsFixed(1);

/// Builds the complete TSPL byte stream for one print job.
///
/// The label is [labelWidthMm] wide — the paper — or, when that is not
/// given or too narrow, just wide enough for the image at [x], the dot the
/// image starts at ([tsplBitmapX]). It is as long as the image's rows
/// (rounded UP to a whole millimetre — at most 7 blank dots). [feedLines] are blank text
/// lines (1/6 inch each, as on a receipt printer) added to the END of the
/// last page, so the print clears the tear bar.
///
/// [zeroIsBlack] is the TSPL convention: in BITMAP data a 0 bit burns a dot
/// and a 1 bit leaves the paper white — the opposite of [MonoImage]. A few
/// firmwares have it the other way round; for those pass false.
Uint8List buildTsplJob(
  MonoImage image, {
  int dpi = 203,
  int feedLines = 0,
  bool zeroIsBlack = true,
  int pageRows = defaultTsplPageRows,
  int x = 0,
  double? labelWidthMm,
}) {
  if (pageRows <= 0) {
    throw ArgumentError.value(pageRows, 'pageRows', 'must be > 0');
  }
  if (x < 0) {
    throw ArgumentError.value(x, 'x', 'must be >= 0');
  }
  final dotsPerMm = tsplDotsPerMm(dpi);
  final bytesPerRow = image.bytesPerRow;
  // Never narrower than what is printed: a firmware clips at the label.
  final neededMm = ((x + image.width) / dotsPerMm).ceil();
  final widthMm = labelWidthMm == null || labelWidthMm < neededMm
      ? '$neededMm'
      : _mm(labelWidthMm);
  final feedDots = feedLines <= 0 ? 0 : (feedLines * dpi / 6).round();
  final heights = tsplPageHeights(
    image.height,
    dotsPerMm: dotsPerMm,
    pageRows: pageRows,
  );

  final out = BytesBuilder(copy: false);
  void line(String command) => out.add(ascii.encode('$command$_eol'));

  // An empty line first: whatever a previous job in another language left
  // in the printer's line buffer ends here instead of eating SIZE.
  out.add(ascii.encode(_eol));
  var row = 0;
  for (var page = 0; page < heights.length; page++) {
    final rows = heights[page];
    final last = page == heights.length - 1;
    final heightMm = ((rows + (last ? feedDots : 0)) / dotsPerMm).ceil();
    line('SIZE $widthMm mm,$heightMm mm');
    if (page == 0) {
      // Continuous paper: no gap to look for between two labels.
      line('GAP 0 mm,0 mm');
      line('DIRECTION 0');
      line('REFERENCE 0,0');
    }
    line('CLS');
    out.add(ascii.encode('BITMAP $x,0,$bytesPerRow,$rows,0,'));
    final data = Uint8List.sublistView(
      image.bits,
      row * bytesPerRow,
      (row + rows) * bytesPerRow,
    );
    out
      ..add(zeroIsBlack ? _flipped(data) : data)
      ..add(ascii.encode(_eol));
    line('PRINT 1,1');
    row += rows;
  }
  return out.toBytes();
}

Uint8List _flipped(Uint8List data) {
  final flipped = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    flipped[i] = data[i] ^ 0xFF;
  }
  return flipped;
}
