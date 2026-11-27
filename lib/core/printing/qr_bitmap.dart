/// The payment QR kept "as is": a picture of a QR code that the phone could
/// not read, turned into a square of pure black and white dots that prints
/// as sharp as a thermal head allows. Pure Dart, no Flutter.
///
/// A code that CAN be read is never kept as a picture: its text is stored
/// and the code is drawn again, module by module, at print time (see
/// lib/features/invoice/payment_qr.dart). This file is only the fallback.
library;

import 'dart:typed_data';

import 'png_encoder.dart';
import 'raster.dart';

/// The largest side kept, in pixels. Plenty for a code printed about 38 mm
/// wide (≈ 300 dots), small enough to sit in the settings table.
const int maxQrBitmapSide = 400;

/// Below this spread between the darkest and the lightest pixel the picture
/// has no code in it worth keeping (a blank page, a photo of a wall).
const int minQrContrast = 48;

/// A square of black and white pixels, one byte per pixel (1 = black).
class QrBitmap {
  QrBitmap({required this.side, required this.bits})
      : assert(side > 0 && bits.length == side * side, 'bitmap size mismatch');

  final int side;
  final Uint8List bits;

  bool isBlack(int x, int y) => bits[y * side + x] != 0;

  /// The bitmap as a PNG — what is stored (like the shop logo) and carried
  /// by backups.
  Uint8List toPng() {
    final rgb = Uint8List(side * side * 3);
    for (var i = 0; i < bits.length; i++) {
      final v = bits[i] != 0 ? 0 : 255;
      rgb[i * 3] = v;
      rgb[i * 3 + 1] = v;
      rgb[i * 3 + 2] = v;
    }
    return encodePngRgb(width: side, height: side, rgb: rgb);
  }

  /// Reads a stored PNG back; null when it is not a square PNG this app
  /// wrote (or is damaged).
  static QrBitmap? fromPng(Uint8List png) {
    final decoded = decodePngRgb(png);
    if (decoded == null || decoded.width != decoded.height) return null;
    final side = decoded.width;
    final bits = Uint8List(side * side);
    final rgb = decoded.rgb;
    for (var i = 0; i < bits.length; i++) {
      final luma =
          (rgb[i * 3] * 77 + rgb[i * 3 + 1] * 150 + rgb[i * 3 + 2] * 29) >> 8;
      bits[i] = luma < 128 ? 1 : 0;
    }
    return QrBitmap(side: side, bits: bits);
  }
}

/// A stored "as is" payment QR: the PNG bytes as they sit in the settings
/// and the pixels decoded from them, made once — the renderer paints the
/// pixels synchronously (the off-screen capture renders a single frame).
class QrPicture {
  const QrPicture._(this.png, this.bitmap);

  factory QrPicture.fromBitmap(QrBitmap bitmap) =>
      QrPicture._(bitmap.toPng(), bitmap);

  /// Null when [png] cannot be read back.
  static QrPicture? fromPng(Uint8List png) {
    final bitmap = QrBitmap.fromPng(png);
    return bitmap == null ? null : QrPicture._(png, bitmap);
  }

  final Uint8List png;
  final QrBitmap bitmap;
}

/// Luminance of every pixel of [image], composited on white (paper).
Uint8List lumaOf(RgbaImage image) {
  final pixels = image.width * image.height;
  final luma = Uint8List(pixels);
  final rgba = image.rgba;
  for (var i = 0; i < pixels; i++) {
    final s = i * 4;
    final under = 255 - rgba[s + 3];
    final r = (rgba[s] + under).clamp(0, 255);
    final g = (rgba[s + 1] + under).clamp(0, 255);
    final b = (rgba[s + 2] + under).clamp(0, 255);
    luma[i] = (r * 77 + g * 150 + b * 29) >> 8;
  }
  return luma;
}

/// Otsu's threshold: the grey level that best splits [luma] into two
/// classes. A QR code is exactly two classes — dark modules on a light
/// ground — so this finds the split a fixed midpoint misses on a dim photo
/// or a grey screenshot. Pixels BELOW the result are dark.
int otsuThreshold(Uint8List luma) {
  final histogram = List<int>.filled(256, 0);
  for (final v in luma) {
    histogram[v]++;
  }
  final total = luma.length;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * histogram[i];
  }
  var sumBelow = 0.0;
  var weightBelow = 0;
  var best = 0.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    weightBelow += histogram[t];
    if (weightBelow == 0) continue;
    final weightAbove = total - weightBelow;
    if (weightAbove == 0) break;
    sumBelow += t * histogram[t];
    final meanBelow = sumBelow / weightBelow;
    final meanAbove = (sumAll - sumBelow) / weightAbove;
    final between =
        weightBelow * weightAbove * (meanBelow - meanAbove) * (meanBelow - meanAbove);
    if (between > best) {
      best = between;
      // Levels 0..t are the dark class.
      threshold = t + 1;
    }
  }
  return threshold;
}

/// "Use the image as is": [image] cropped to the square around its dark
/// content, made pure black and white with [otsuThreshold] (no dithering —
/// a dithered module is grey noise to a scanner) and scaled with nearest
/// neighbour to at most [maxSide] pixels. Null when the picture has no
/// contrast at all.
QrBitmap? qrBitmapFromImage(RgbaImage image, {int maxSide = maxQrBitmapSide}) {
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0) return null;
  final luma = lumaOf(image);
  var lo = 255;
  var hi = 0;
  for (final v in luma) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < minQrContrast) return null;
  final threshold = otsuThreshold(luma);

  // Rows and columns that carry real ink: a speck of dust or a JPEG
  // artefact must not stretch the crop to the edge of the photo.
  final rowInk = List<int>.filled(height, 0);
  final colInk = List<int>.filled(width, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (luma[y * width + x] < threshold) {
        rowInk[y]++;
        colInk[x]++;
      }
    }
  }
  final minRow = (width * 0.01).ceil().clamp(2, width);
  final minCol = (height * 0.01).ceil().clamp(2, height);
  var top = 0;
  while (top < height && rowInk[top] < minRow) {
    top++;
  }
  var bottom = height - 1;
  while (bottom > top && rowInk[bottom] < minRow) {
    bottom--;
  }
  var left = 0;
  while (left < width && colInk[left] < minCol) {
    left++;
  }
  var right = width - 1;
  while (right > left && colInk[right] < minCol) {
    right--;
  }
  if (top >= height || left >= width) return null;

  // The square around it, centred on the content; outside the photo is
  // white.
  final side = (right - left + 1) > (bottom - top + 1)
      ? right - left + 1
      : bottom - top + 1;
  final x0 = (left + right + 1 - side) ~/ 2;
  final y0 = (top + bottom + 1 - side) ~/ 2;
  final out = side < maxSide ? side : maxSide;
  final bits = Uint8List(out * out);
  for (var j = 0; j < out; j++) {
    final sy = y0 + ((j * 2 + 1) * side) ~/ (out * 2);
    if (sy < 0 || sy >= height) continue;
    for (var i = 0; i < out; i++) {
      final sx = x0 + ((i * 2 + 1) * side) ~/ (out * 2);
      if (sx < 0 || sx >= width) continue;
      if (luma[sy * width + sx] < threshold) bits[j * out + i] = 1;
    }
  }
  return QrBitmap(side: out, bits: bits);
}
