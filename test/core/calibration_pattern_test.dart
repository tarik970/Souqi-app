import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/printing/calibration_pattern.dart';
import 'package:souqi/core/printing/raster.dart';

/// Black dots of row [y].
int inRow(MonoImage image, int y) {
  var count = 0;
  for (var x = 0; x < image.width; x++) {
    if (image.isBlack(x, y)) count++;
  }
  return count;
}

/// Black dots inside the rectangle.
int inBox(MonoImage image, int left, int top, int width, int height) {
  var count = 0;
  for (var y = top; y < top + height; y++) {
    for (var x = left; x < left + width; x++) {
      if (image.isBlack(x, y)) count++;
    }
  }
  return count;
}

void main() {
  const width = 576;
  final image = buildCalibrationPattern(width: width);
  const bottom = calibrationPatternRows - 1;

  test('it is as wide as the printable width', () {
    expect(image.width, width);
    expect(image.height, calibrationPatternRows);
    expect(buildCalibrationPattern(width: 384).width, 384);
  });

  group('frame', () {
    test('the first and last row are black from edge to edge', () {
      expect(inRow(image, 0), width);
      expect(inRow(image, bottom), width);
    });

    test('the first and last column are black from top to bottom', () {
      for (var y = 0; y <= bottom; y++) {
        expect(image.isBlack(0, y), isTrue, reason: 'left, row $y');
        expect(image.isBlack(width - 1, y), isTrue, reason: 'right, row $y');
      }
    });

    test('it is one dot thick', () {
      // The row above the bottom line: only the two side lines.
      expect(inRow(image, bottom - 1), 2);
      // The columns next to the side lines, below the ruler: white.
      for (var y = calibrationLongTickRows; y < bottom; y++) {
        expect(image.isBlack(1, y), isFalse, reason: 'row $y');
        expect(image.isBlack(width - 2, y), isFalse, reason: 'row $y');
      }
    });
  });

  group('ruler', () {
    test('a tick every 8 dots, and nothing between two ticks', () {
      const y = calibrationTickRows - 1;
      for (var x = 0; x < width - 1; x++) {
        expect(image.isBlack(x, y), x % 8 == 0, reason: 'x $x');
      }
      // 72 ticks, and the right side of the frame.
      expect(inRow(image, y), 72 + 1);
    });

    test('a short tick is 8 dots long', () {
      expect(image.isBlack(8, calibrationTickRows - 1), isTrue);
      expect(image.isBlack(8, calibrationTickRows), isFalse);
    });

    test('every 64 dots the tick is twice as long', () {
      const y = calibrationLongTickRows - 1;
      for (var x = 0; x < width - 1; x++) {
        expect(image.isBlack(x, y), x % 64 == 0, reason: 'x $x');
      }
      expect(image.isBlack(64, calibrationLongTickRows), isFalse);
    });

    test('the long ticks are numbered with their position', () {
      // "0" at the first tick, in the 5 × 7 font doubled: its top row is
      // .###. — white, three black, white.
      const top = calibrationLongTickRows + 2;
      expect(image.isBlack(3, top), isFalse);
      expect(image.isBlack(5, top), isTrue);
      expect(image.isBlack(9, top), isTrue);
      expect(image.isBlack(11, top), isFalse);
      // Every numbered tick has ink right of it, where its number is.
      for (var x = 0; x + 64 < width; x += 64) {
        expect(inBox(image, x + 3, top, 36, 14), greaterThan(20), reason: 'x $x');
      }
      // "64" and "128" are different numbers.
      expect(
        calibrationTextWidth('128', 2),
        greaterThan(calibrationTextWidth('64', 2)),
      );
    });

    test('a number that would run into the frame is left out', () {
      // 80 dots wide: "64" (22 dots, 3 right of its tick) would end at dot
      // 89 — it is left out, and the tick stays.
      final narrow = buildCalibrationPattern(width: 80);
      expect(narrow.isBlack(64, calibrationLongTickRows - 1), isTrue);
      expect(inBox(narrow, 66, calibrationLongTickRows + 2, 13, 14), 0);
    });
  });

  group('labels', () {
    test('LEFT is at the left end and RIGHT at the right end', () {
      // LEFT at scale 4 starts 8 dots in: the stem of the L.
      expect(image.isBlack(8, 40), isTrue);
      expect(image.isBlack(12, 40), isFalse);
      // RIGHT ends 8 dots before the right edge: the bar of the T.
      expect(image.isBlack(width - 9, 40), isTrue);
      expect(image.isBlack(width - 8, 40), isFalse);
      // The two words, and white paper between them.
      expect(inBox(image, 8, 40, 92, 28), greaterThan(300));
      expect(inBox(image, width - 124, 40, 116, 28), greaterThan(300));
      expect(inBox(image, 110, 40, width - 244, 28), 0);
    });

    test('they shrink on narrow paper instead of overlapping', () {
      final narrow = buildCalibrationPattern(width: 200);
      // Scale 2: LEFT is 46 dots wide, RIGHT 58.
      expect(inBox(narrow, 8, 40, 46, 14), greaterThan(80));
      expect(inBox(narrow, 60, 40, 200 - 60 - 8 - 58 - 2, 14), 0);
    });

    test('the width and the offset it was printed with are on it', () {
      expect(formatOffsetDots(16), '+16');
      expect(formatOffsetDots(0), '0');
      expect(formatOffsetDots(-8), '-8');
      final moved = buildCalibrationPattern(width: width, offsetDots: 16);
      // Same frame and ruler; only the line of text at the bottom differs.
      const infoTop = calibrationPatternRows - 24;
      for (var y = 0; y < infoTop; y++) {
        for (var x = 0; x < width; x++) {
          if (image.isBlack(x, y) != moved.isBlack(x, y)) {
            fail('differs at ($x, $y), above the info line');
          }
        }
      }
      expect(moved.bits, isNot(image.bits));
      expect(inBox(image, 100, infoTop, width - 200, 14), greaterThan(100));
    });
  });

  test('any printable width works, down to the narrowest', () {
    for (final w in [96, 104, 200, 384, 568, 608, 2400]) {
      final pattern = buildCalibrationPattern(width: w, offsetDots: -64);
      expect(pattern.width, w);
      expect(inRow(pattern, 0), w);
    }
    expect(() => buildCalibrationPattern(width: 8), throwsArgumentError);
  });
}
