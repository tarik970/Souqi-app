/// The picture of the printer calibration test: a ruler across the whole
/// printable width, so what the printer cuts off can be READ off the paper.
///
/// Drawn dot by dot (no fonts, no antialiasing — pure Dart, unit-tested):
///
///  * a frame one dot thick around the whole image — if a side of it is
///    missing on paper, that side is cut off;
///  * along the top, a tick every 8 dots and a longer one with its number
///    every 64 dots, counted from the left edge of the IMAGE;
///  * "LEFT" and "RIGHT" inside the two ends;
///  * the width and the offset it was printed with ("W 576 X +16").
library;

import 'dart:typed_data';

import 'raster.dart';

/// Height of the pattern in dots (14 mm at 203 dpi).
const int calibrationPatternRows = 112;

/// Ticks: one every [calibrationTickDots], a long numbered one every
/// [calibrationNumberDots].
const int calibrationTickDots = 8;
const int calibrationNumberDots = 64;
const int calibrationTickRows = 8;
const int calibrationLongTickRows = 16;

/// A 5 × 7 dot font with just the characters the pattern needs.
const Map<String, List<String>> _glyphs = {
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
  'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
};

/// Dots from one character to the next at [scale]: five of the glyph and
/// one of space.
int _advance(int scale) => 6 * scale;

/// Width in dots of [text] at [scale] (no space after the last character).
int calibrationTextWidth(String text, int scale) =>
    text.isEmpty ? 0 : text.length * _advance(scale) - scale;

/// "+16", "-8", "0" — how an offset is written on the pattern and on screen.
String formatOffsetDots(int dots) => dots > 0 ? '+$dots' : '$dots';

class _Canvas {
  _Canvas(this.width, this.height)
      : bytesPerRow = (width + 7) ~/ 8,
        bits = Uint8List(((width + 7) ~/ 8) * height);

  final int width;
  final int height;
  final int bytesPerRow;
  final Uint8List bits;

  /// Burns the dot at ([x], [y]); outside the image nothing happens.
  void dot(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    bits[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
  }

  void rect(int left, int top, int w, int h) {
    for (var y = top; y < top + h; y++) {
      for (var x = left; x < left + w; x++) {
        dot(x, y);
      }
    }
  }

  void text(String text, int left, int top, int scale) {
    var x = left;
    for (final char in text.split('')) {
      final glyph = _glyphs[char];
      if (glyph != null) {
        for (var row = 0; row < 7; row++) {
          for (var column = 0; column < 5; column++) {
            if (glyph[row][column] == '#') {
              rect(x + column * scale, top + row * scale, scale, scale);
            }
          }
        }
      }
      x += _advance(scale);
    }
  }
}

/// The calibration pattern, [width] dots wide (the printable width) and
/// [calibrationPatternRows] tall. [offsetDots] is only written on it — the
/// offset itself is applied when the job is built.
MonoImage buildCalibrationPattern({required int width, int offsetDots = 0}) {
  if (width < 16) {
    throw ArgumentError.value(width, 'width', 'must be >= 16');
  }
  const height = calibrationPatternRows;
  final canvas = _Canvas(width, height)
    // The frame: one dot on every side.
    ..rect(0, 0, width, 1)
    ..rect(0, height - 1, width, 1)
    ..rect(0, 0, 1, height)
    ..rect(width - 1, 0, 1, height);

  // The ruler along the top.
  for (var x = 0; x < width; x += calibrationTickDots) {
    final numbered = x % calibrationNumberDots == 0;
    canvas.rect(
      x,
      0,
      1,
      numbered ? calibrationLongTickRows : calibrationTickRows,
    );
    if (numbered) {
      final label = '$x';
      // Right of its tick; left out where it would run into the frame.
      if (x + 3 + calibrationTextWidth(label, 2) < width - 2) {
        canvas.text(label, x + 3, calibrationLongTickRows + 2, 2);
      }
    }
  }

  // LEFT and RIGHT, as large as the width allows.
  final scale = width >= 320 ? 4 : (width >= 176 ? 2 : 1);
  const top = 40;
  canvas
    ..text('LEFT', 8, top, scale)
    ..text(
      'RIGHT',
      width - 8 - calibrationTextWidth('RIGHT', scale),
      top,
      scale,
    );

  // What it was printed with.
  final info = 'W $width X ${formatOffsetDots(offsetDots)}';
  final infoScale = calibrationTextWidth(info, 2) <= width - 16 ? 2 : 1;
  canvas.text(
    info,
    (width - calibrationTextWidth(info, infoScale)) ~/ 2,
    height - 10 - 7 * infoScale,
    infoScale,
  );

  return MonoImage(width: width, height: height, bits: canvas.bits);
}
