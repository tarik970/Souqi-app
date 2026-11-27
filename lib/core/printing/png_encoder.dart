/// A minimal PNG writer: 8-bit RGB, no interlacing, filter 0 on every row.
///
/// Why not `ui.Image.toByteData(format: png)`: that needs the whole receipt
/// as ONE GPU image, and a long receipt at 2× is taller than the maximum
/// texture size of low-end phones. The renderer captures the invoice in
/// slices and hands the joined pixels to this encoder instead, so the height
/// is limited only by memory. Compression is native zlib from dart:io.
library;

import 'dart:io';
import 'dart:typed_data';

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
}, growable: false);

int _crc32(List<int> a, List<int> b) {
  var c = 0xFFFFFFFF;
  for (final byte in a) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  for (final byte in b) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(typeBytes, data));
  out
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add(crc.buffer.asUint8List());
}

/// Encodes [rgb] (3 bytes per pixel, row by row) as a PNG file.
Uint8List encodePngRgb({
  required int width,
  required int height,
  required Uint8List rgb,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('image must not be empty ($width × $height)');
  }
  if (rgb.length != width * height * 3) {
    throw ArgumentError.value(rgb.length, 'rgb.length', 'expected ${width * height * 3}');
  }
  final stride = width * 3;
  // Each scanline is prefixed with its filter type; 0 = none.
  final raw = Uint8List((stride + 1) * height);
  for (var y = 0; y < height; y++) {
    raw.setRange(y * (stride + 1) + 1, (y + 1) * (stride + 1), rgb, y * stride);
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: truecolour
    ..setUint8(10, 0) // compression: deflate
    ..setUint8(11, 0) // filter method
    ..setUint8(12, 0); // no interlace

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', ZLibCodec(level: 6).encode(raw));
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}

/// Reads a PNG back into 8-bit RGB: the PNGs this app writes itself
/// ([encodePngRgb] — the payment QR kept "as is" is one, stored in the
/// settings). 8-bit grey or RGB, with or without alpha (alpha is dropped,
/// not composited), no interlacing, any of the five row filters. Returns
/// null for anything else, or for damaged bytes.
({int width, int height, Uint8List rgb})? decodePngRgb(Uint8List bytes) {
  final size = readPngSize(bytes);
  if (size == null || size.width <= 0 || size.height <= 0) return null;
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 29) return null;
  final depth = bytes[24];
  final colourType = bytes[25];
  final interlace = bytes[28];
  final channels = switch (colourType) {
    0 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => 0,
  };
  if (depth != 8 || channels == 0 || interlace != 0) return null;

  final idat = BytesBuilder(copy: false);
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final start = offset + 8;
    if (start + length > bytes.length) return null;
    if (type == 'IDAT') idat.add(Uint8List.sublistView(bytes, start, start + length));
    if (type == 'IEND') break;
    offset = start + length + 4;
  }
  final List<int> raw;
  try {
    raw = ZLibCodec().decode(idat.toBytes());
  } on FormatException {
    return null;
  }
  final width = size.width;
  final height = size.height;
  final stride = width * channels;
  if (raw.length < (stride + 1) * height) return null;

  final pixels = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    final src = y * (stride + 1) + 1;
    final row = y * stride;
    for (var i = 0; i < stride; i++) {
      final x = raw[src + i];
      final a = i >= channels ? pixels[row + i - channels] : 0;
      final b = y > 0 ? pixels[row - stride + i] : 0;
      final c = i >= channels && y > 0 ? pixels[row - stride + i - channels] : 0;
      final int value;
      switch (filter) {
        case 0:
          value = x;
        case 1:
          value = x + a;
        case 2:
          value = x + b;
        case 3:
          value = x + ((a + b) >> 1);
        case 4:
          final p = a + b - c;
          final pa = (p - a).abs();
          final pb = (p - b).abs();
          final pc = (p - c).abs();
          value = x + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c));
        default:
          return null;
      }
      pixels[row + i] = value & 0xFF;
    }
  }

  if (channels == 3) return (width: width, height: height, rgb: pixels);
  final rgb = Uint8List(width * height * 3);
  for (var p = 0; p < width * height; p++) {
    final grey = channels <= 2;
    final s = p * channels;
    rgb[p * 3] = pixels[s];
    rgb[p * 3 + 1] = grey ? pixels[s] : pixels[s + 1];
    rgb[p * 3 + 2] = grey ? pixels[s] : pixels[s + 2];
  }
  return (width: width, height: height, rgb: rgb);
}

/// Width and height stored in a PNG's IHDR, or null if [bytes] is not a PNG.
({int width, int height})? readPngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}
