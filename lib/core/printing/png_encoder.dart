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
