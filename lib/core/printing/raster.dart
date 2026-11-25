/// Pixel buffers on their way to a printer or a file. Pure Dart, no Flutter:
/// everything here is unit-testable without a device.
library;

import 'dart:typed_data';

/// An image as raw pixels: 4 bytes per pixel, R, G, B, A, row by row,
/// alpha premultiplied (what `ui.Image.toByteData()` returns by default).
class RgbaImage {
  RgbaImage({required this.width, required this.height, required this.rgba})
      : assert(rgba.length == width * height * 4, 'buffer size mismatch');

  final int width;
  final int height;
  final Uint8List rgba;
}

/// A 1-bit image packed for a thermal printer: one bit per dot, most
/// significant bit first, 1 = black (burn), rows padded to whole bytes.
class MonoImage {
  MonoImage({required this.width, required this.height, required this.bits})
      : assert(bits.length == ((width + 7) ~/ 8) * height, 'buffer size mismatch');

  final int width;
  final int height;
  final Uint8List bits;

  int get bytesPerRow => (width + 7) ~/ 8;

  bool isBlack(int x, int y) =>
      bits[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;
}

/// [image] moved [dots] to the right: white columns are added on its left,
/// so it becomes that much wider. Whole bytes only — [dots] is rounded down
/// to a multiple of 8, and nothing happens for 0 or less. This is how a
/// receipt printer, which always starts at its left edge, is given a
/// horizontal offset.
MonoImage padLeft(MonoImage image, int dots) {
  final pad = dots <= 0 ? 0 : dots ~/ 8;
  if (pad == 0) return image;
  final from = image.bytesPerRow;
  final to = from + pad;
  final bits = Uint8List(to * image.height);
  for (var y = 0; y < image.height; y++) {
    bits.setRange(y * to + pad, (y + 1) * to, image.bits, y * from);
  }
  return MonoImage(
    width: image.width + pad * 8,
    height: image.height,
    bits: bits,
  );
}

/// Luminance below which a dot is printed. Text is antialiased, so its edges
/// are grey: a threshold above the midpoint keeps those edge pixels and gives
/// strokes their full weight on paper, where thin strokes fade first.
const int defaultMonoThreshold = 160;

/// Converts [image] to 1-bit with a plain threshold — no dithering, which
/// would turn the grey edges of text into noise.
///
/// Transparent pixels are composited on white first (paper is white).
MonoImage toMonochrome(RgbaImage image, {int threshold = defaultMonoThreshold}) {
  final width = image.width;
  final height = image.height;
  final bytesPerRow = (width + 7) ~/ 8;
  final bits = Uint8List(bytesPerRow * height);
  final rgba = image.rgba;
  var src = 0;
  for (var y = 0; y < height; y++) {
    final rowStart = y * bytesPerRow;
    for (var x = 0; x < width; x++) {
      final a = rgba[src + 3];
      // Premultiplied colour over white: c + (255 - a).
      final under = 255 - a;
      final r = rgba[src] + under;
      final g = rgba[src + 1] + under;
      final b = rgba[src + 2] + under;
      src += 4;
      // Integer Rec. 601 luma, weights sum to 256.
      final luma = (r * 77 + g * 150 + b * 29) >> 8;
      if (luma < threshold) {
        bits[rowStart + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return MonoImage(width: width, height: height, bits: bits);
}

/// Flattens [image] onto white and drops the alpha channel: 3 bytes per
/// pixel, R, G, B. This is what the PNG and PDF writers store.
Uint8List flattenToRgb(RgbaImage image) {
  final pixels = image.width * image.height;
  final rgb = Uint8List(pixels * 3);
  final rgba = image.rgba;
  var src = 0;
  var dst = 0;
  for (var i = 0; i < pixels; i++) {
    final under = 255 - rgba[src + 3];
    final r = rgba[src] + under;
    final g = rgba[src + 1] + under;
    final b = rgba[src + 2] + under;
    rgb[dst] = r > 255 ? 255 : r;
    rgb[dst + 1] = g > 255 ? 255 : g;
    rgb[dst + 2] = b > 255 ? 255 : b;
    src += 4;
    dst += 3;
  }
  return rgb;
}
