// A QR decoder for TESTS: it reads a code that is upright and evenly
// scaled — what the app's own renderer draws, and a screenshot of a bank
// app's code — standing in for ML Kit, which only runs on a phone. It reads
// the module grid, the format bits and every data codeword, and returns the
// text only when the codewords are EXACTLY what the qr package would encode
// for that text: a single wrong module anywhere in the data or the error
// correction fails the decode.
//
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:typed_data';

import 'package:qr/qr.dart';
import 'package:qr/src/rs_block.dart';
import 'package:qr/src/util.dart' as qr_util;
import 'package:souqi/core/printing/qr_bitmap.dart';
import 'package:souqi/core/printing/raster.dart';

/// Reads the QR code in a [width] × [height] picture where [isBlack] says
/// which pixels are dark. The code may sit anywhere in it, on white.
/// Returns null when there is no code it can read exactly.
String? decodeQrGrid({
  required int width,
  required int height,
  required bool Function(int x, int y) isBlack,
}) {
  final matrix = sampleQrGrid(width: width, height: height, isBlack: isBlack);
  if (matrix == null) return null;
  return decodeQrMatrix(matrix);
}

/// The module grid of the code in the picture: the bounding box of its
/// dark pixels, the module size from the top-left finder (7 modules wide),
/// each module read at its centre.
List<List<bool>>? sampleQrGrid({
  required int width,
  required int height,
  required bool Function(int x, int y) isBlack,
}) {
  var minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!isBlack(x, y)) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  // The top edge of the top-left finder: a solid run 7 modules long.
  var run = 0;
  while (minX + run <= maxX && isBlack(minX + run, minY)) {
    run++;
  }
  final estimate = run / 7;
  if (estimate <= 0) return null;
  final span = maxX - minX + 1;
  var n = (span / estimate).round();
  // Snap to a real size: 21, 25, 29, …
  n = 17 + 4 * (((n - 17) / 4).round());
  if (n < 21 || n > 177) return null;
  final module = span / n;
  final spanY = maxY - minY + 1;
  if ((spanY / module - n).abs() > 0.6) return null;
  return [
    for (var r = 0; r < n; r++)
      [
        for (var c = 0; c < n; c++)
          isBlack(
            (minX + (c + 0.5) * module).floor().clamp(0, width - 1),
            (minY + (r + 0.5) * module).floor().clamp(0, height - 1),
          ),
      ],
  ];
}

bool _mask(int pattern, int i, int j) => switch (pattern) {
      0 => (i + j).isEven,
      1 => i.isEven,
      2 => j % 3 == 0,
      3 => (i + j) % 3 == 0,
      4 => ((i ~/ 2) + (j ~/ 3)).isEven,
      5 => (i * j) % 2 + (i * j) % 3 == 0,
      6 => ((i * j) % 2 + (i * j) % 3).isEven,
      _ => ((i * j) % 3 + (i + j) % 2).isEven,
    };

/// Which modules are NOT data: finders with their separators and the
/// format strips, timing, alignment patterns, version blocks.
List<List<bool>> _functionModules(int version) {
  final n = version * 4 + 17;
  final f = List.generate(n, (_) => List<bool>.filled(n, false));
  void box(int r0, int r1, int c0, int c1) {
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (r >= 0 && r < n && c >= 0 && c < n) f[r][c] = true;
      }
    }
  }

  box(0, 8, 0, 8);
  box(0, 8, n - 8, n - 1);
  box(n - 8, n - 1, 0, 8);
  for (var i = 0; i < n; i++) {
    f[6][i] = true;
    f[i][6] = true;
  }
  final pos = qr_util.patternPosition(version);
  for (final r in pos) {
    for (final c in pos) {
      final inFinder = (r <= 8 && c <= 8) ||
          (r <= 8 && c >= n - 8) ||
          (r >= n - 8 && c <= 8);
      if (inFinder) continue;
      box(r - 2, r + 2, c - 2, c + 2);
    }
  }
  if (version >= 7) {
    box(0, 5, n - 11, n - 9);
    box(n - 11, n - 9, 0, 5);
  }
  return f;
}

/// The text of a sampled module grid, or null.
String? decodeQrMatrix(List<List<bool>> m) {
  final n = m.length;
  if ((n - 17) % 4 != 0) return null;
  final version = (n - 17) ~/ 4;

  // Format: 15 bits down column 8, as the qr package writes them.
  var format = 0;
  for (var i = 0; i < 15; i++) {
    final row = i < 6 ? i : (i < 8 ? i + 1 : n - 15 + i);
    if (m[row][8]) format |= 1 << i;
  }
  var best = -1, bestDistance = 99;
  for (var data = 0; data < 32; data++) {
    var diff = qr_util.bchTypeInfo(data) ^ format, distance = 0;
    while (diff != 0) {
      distance += diff & 1;
      diff >>= 1;
    }
    if (distance < bestDistance) {
      bestDistance = distance;
      best = data;
    }
  }
  if (bestDistance > 3) return null;
  final level = best >> 3;
  final maskPattern = best & 7;

  // Data bits, in the zig-zag order of the qr package's _mapData.
  final function = _functionModules(version);
  final bits = <bool>[];
  var inc = -1;
  var row = n - 1;
  for (var col = n - 1; col > 0; col -= 2) {
    if (col == 6) col--;
    for (;;) {
      for (var c = 0; c < 2; c++) {
        if (!function[row][col - c]) {
          bits.add(m[row][col - c] ^ _mask(maskPattern, row, col - c));
        }
      }
      row += inc;
      if (row < 0 || n <= row) {
        row -= inc;
        inc = -inc;
        break;
      }
    }
  }
  final blocks = QrRsBlock.getRSBlocks(version, level);
  final total = blocks.fold<int>(0, (sum, b) => sum + b.totalCount);
  if (bits.length < total * 8) return null;
  final codewords = [
    for (var i = 0; i < total; i++)
      [for (var b = 0; b < 8; b++) bits[i * 8 + b] ? 1 << (7 - b) : 0]
          .reduce((a, b) => a | b),
  ];

  // Undo the interleaving: data codewords block by block.
  final data = List.generate(blocks.length, (r) => <int>[]);
  var k = 0;
  final maxData = blocks.map((b) => b.dataCount).reduce((a, b) => a > b ? a : b);
  for (var i = 0; i < maxData; i++) {
    for (var r = 0; r < blocks.length; r++) {
      if (i < blocks[r].dataCount) data[r].add(codewords[k++]);
    }
  }
  final stream = [for (final block in data) ...block];

  // The segments: byte, numeric, alphanumeric; ECI skipped.
  var at = 0;
  int take(int count) {
    var v = 0;
    for (var i = 0; i < count; i++) {
      final byte = stream[(at + i) >> 3];
      v = (v << 1) | ((byte >> (7 - ((at + i) & 7))) & 1);
    }
    at += count;
    return v;
  }

  final bytes = <int>[];
  final small = version < 10;
  final large = version >= 27;
  const alnum = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
  while (at + 4 <= stream.length * 8) {
    final mode = take(4);
    if (mode == 0) break;
    if (mode == 7) {
      take(8);
      continue;
    }
    if (mode == 4) {
      final count = take(small ? 8 : 16);
      for (var i = 0; i < count; i++) {
        bytes.add(take(8));
      }
    } else if (mode == 1) {
      var count = take(small ? 10 : (large ? 14 : 12));
      while (count >= 3) {
        bytes.addAll(take(10).toString().padLeft(3, '0').codeUnits);
        count -= 3;
      }
      if (count == 2) bytes.addAll(take(7).toString().padLeft(2, '0').codeUnits);
      if (count == 1) bytes.addAll(take(4).toString().codeUnits);
    } else if (mode == 2) {
      var count = take(small ? 9 : (large ? 13 : 11));
      while (count >= 2) {
        final v = take(11);
        bytes
          ..add(alnum.codeUnitAt(v ~/ 45))
          ..add(alnum.codeUnitAt(v % 45));
        count -= 2;
      }
      if (count == 1) bytes.add(alnum.codeUnitAt(take(6)));
    } else {
      return null;
    }
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return null;
  }

  // Exactly what the qr package encodes for this text at this size and
  // level, error correction included — or no answer at all.
  final QrImage reencoded;
  try {
    reencoded = QrImage.withMaskPattern(
      QrCode(version, level)..addData(text),
      maskPattern,
    );
  } on Exception {
    return null;
  }
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (reencoded.isDark(r, c) != m[r][c]) return null;
    }
  }
  return text;
}

/// Payloads like the ones shops will bring: a payment link, an EMV-style
/// merchant string (long, digits and letters), and Arabic text.
const upi = 'upi://pay?pa=souqi.shop@bank&pn=Souqi%20Shop&cu=SYP';
const emv = '00020101021126360014SY.SYRIATEL.CASH0114963944123456'
    '5204541153037605802SY5911ABU AHMAD 16004DAMASCUS6304A1B2'
    '62290525INVOICE-PAYMENT-REFERENCE';
const arabic = 'ادفع لمحل أبو أحمد — حساب ٠٩٤٤١٢٣٤٥٦';

/// [text] drawn as a phone screenshot or photo would carry it: [scale]
/// pixels per module, grey-on-grey (not pure black and white), off-centre
/// in a bigger picture.
RgbaImage qrPhoto(
  String text, {
  int scale = 7,
  int left = 37,
  int top = 23,
  int right = 61,
  int bottom = 45,
  int dark = 45,
  int light = 205,
}) {
  final qr = QrImage(QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M));
  final n = qr.moduleCount;
  final width = left + n * scale + right;
  final height = top + n * scale + bottom;
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = (x - left) ~/ scale;
      final r = (y - top) ~/ scale;
      final inside = x >= left && y >= top && c < n && r < n;
      final v = inside && qr.isDark(r, c) ? dark : light;
      final i = (y * width + x) * 4;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return RgbaImage(width: width, height: height, rgba: rgba);
}

String? decodeRgba(RgbaImage image) => decodeQrGrid(
      width: image.width,
      height: image.height,
      isBlack: (x, y) => image.rgba[(y * image.width + x) * 4] < 128,
    );

String? decodeBitmap(QrBitmap bitmap) => decodeQrGrid(
      width: bitmap.side,
      height: bitmap.side,
      isBlack: bitmap.isBlack,
    );

