import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/printing/escpos.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/raster.dart';

/// A [width]×[height] image whose pixel colour comes from [pixel] (r, g, b, a).
RgbaImage imageOf(
  int width,
  int height,
  List<int> Function(int x, int y) pixel,
) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      rgba.setRange((y * width + x) * 4, (y * width + x) * 4 + 4, pixel(x, y));
    }
  }
  return RgbaImage(width: width, height: height, rgba: rgba);
}

const black = [0, 0, 0, 255];
const white = [255, 255, 255, 255];

void main() {
  group('toMonochrome', () {
    test('packs 8 dots per byte, most significant bit first, 1 = black', () {
      // Row 0: black at x = 0 and x = 9. Row 1: all white.
      final mono = toMonochrome(
        imageOf(16, 2, (x, y) => y == 0 && (x == 0 || x == 9) ? black : white),
      );
      expect(mono.bytesPerRow, 2);
      expect(mono.bits, [0x80, 0x40, 0x00, 0x00]);
      expect(mono.isBlack(0, 0), isTrue);
      expect(mono.isBlack(9, 0), isTrue);
      expect(mono.isBlack(1, 0), isFalse);
    });

    test('is a plain threshold: no dithering pattern on mid grey', () {
      // A flat grey field must come out all one colour, not a checkerboard.
      final light = toMonochrome(imageOf(16, 4, (_, _) => [200, 200, 200, 255]));
      expect(light.bits.every((b) => b == 0x00), isTrue);
      final dark = toMonochrome(imageOf(16, 4, (_, _) => [100, 100, 100, 255]));
      expect(dark.bits.every((b) => b == 0xFF), isTrue);
    });

    test('the threshold is adjustable', () {
      final grey = imageOf(8, 1, (_, _) => [150, 150, 150, 255]);
      expect(toMonochrome(grey, threshold: 160).bits, [0xFF]);
      expect(toMonochrome(grey, threshold: 128).bits, [0x00]);
    });

    test('transparent pixels are paper white', () {
      final mono = toMonochrome(imageOf(8, 1, (_, _) => [0, 0, 0, 0]));
      expect(mono.bits, [0x00]);
    });

    test('a width that is not a multiple of 8 pads the last byte with white', () {
      final mono = toMonochrome(imageOf(10, 1, (_, _) => black));
      expect(mono.bytesPerRow, 2);
      expect(mono.bits, [0xFF, 0xC0]);
    });
  });

  group('buildRasterJob', () {
    MonoImage solid(int width, int height) => MonoImage(
          width: width,
          height: height,
          bits: Uint8List((width ~/ 8) * height)..fillRange(0, (width ~/ 8) * height, 0xAA),
        );

    test('initialises, sends one GS v 0 raster, feeds', () {
      final job = buildRasterJob(solid(576, 10), feedLines: 3);
      // ESC @
      expect(job.sublist(0, 2), [0x1B, 0x40]);
      // GS v 0, m = 0, xL xH = 72 bytes per row, yL yH = 10 rows.
      expect(job.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 72, 0, 10, 0]);
      expect(job.sublist(10, 10 + 720).every((b) => b == 0xAA), isTrue);
      // ESC d 3, and nothing after it (no cut).
      expect(job.sublist(10 + 720), [0x1B, 0x64, 3]);
    });

    test('a tall image is split into bands that keep every row', () {
      const rows = 250;
      final job = buildRasterJob(solid(384, rows), bandRows: 96, feedLines: 0);
      var offset = 2;
      final bandHeights = <int>[];
      while (offset < job.length) {
        expect(job.sublist(offset, offset + 4), [0x1D, 0x76, 0x30, 0x00]);
        final widthBytes = job[offset + 4] | (job[offset + 5] << 8);
        final height = job[offset + 6] | (job[offset + 7] << 8);
        expect(widthBytes, 48);
        bandHeights.add(height);
        offset += 8 + widthBytes * height;
      }
      expect(offset, job.length);
      expect(bandHeights, [96, 96, 58]);
      expect(bandHeights.reduce((a, b) => a + b), rows);
    });

    test('band heights above 255 use both height bytes', () {
      final job = buildRasterJob(solid(8, 300), bandRows: 300, feedLines: 0);
      expect(job.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 1, 0, 0x2C, 0x01]);
    });

    test('cut is only sent when asked, after the feed', () {
      final job = buildRasterJob(solid(8, 1), feedLines: 4, cut: true);
      expect(job.sublist(job.length - 7), [0x1B, 0x64, 4, 0x1D, 0x56, 0x42, 0x00]);
      final noFeed = buildRasterJob(solid(8, 1), feedLines: 0, cut: true);
      expect(noFeed.sublist(noFeed.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(noFeed.length, 2 + 8 + 1 + 4);
    });
  });

  group('encodePngRgb', () {
    test('writes a valid PNG with the given size', () {
      final image = imageOf(5, 3, (x, y) => [x * 50, y * 80, 7, 255]);
      final png = encodePngRgb(width: 5, height: 3, rgb: flattenToRgb(image));
      expect(readPngSize(png), (width: 5, height: 3));
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // Ends with the IEND chunk and its fixed CRC.
      expect(png.sublist(png.length - 8), [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]);
    });

    test('the pixel data survives a decode', () {
      final image = imageOf(4, 2, (x, y) => [x * 60, y * 200, 90, 255]);
      final png = encodePngRgb(width: 4, height: 2, rgb: flattenToRgb(image));
      // IDAT starts after the 8-byte signature and the 25-byte IHDR chunk.
      final data = ByteData.sublistView(png);
      final idatLength = data.getUint32(33);
      expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
      final raw = zlib.decode(png.sublist(41, 41 + idatLength));
      // Each scanline: filter byte 0, then width × RGB.
      expect(raw.length, 2 * (1 + 4 * 3));
      expect(raw.sublist(0, 4), [0, 0, 0, 90]);
      expect(raw.sublist(13, 20), [0, 0, 200, 90, 60, 200, 90]);
    });

    test('flattening composites transparency on white', () {
      final rgb = flattenToRgb(imageOf(2, 1, (x, _) => x == 0 ? [0, 0, 0, 0] : black));
      expect(rgb, [255, 255, 255, 0, 0, 0]);
    });

    test('rejects a buffer of the wrong size', () {
      expect(
        () => encodePngRgb(width: 2, height: 2, rgb: Uint8List(5)),
        throwsArgumentError,
      );
      expect(readPngSize(Uint8List(40)), isNull);
    });
  });
}
