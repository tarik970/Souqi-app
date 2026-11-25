import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/printing/escpos.dart';
import 'package:souqi/core/printing/print_job.dart';
import 'package:souqi/core/printing/raster.dart';

MonoImage solid(int width, int height, [int byte = 0xAA]) {
  final bytesPerRow = (width + 7) ~/ 8;
  return MonoImage(
    width: width,
    height: height,
    bits: Uint8List(bytesPerRow * height)
      ..fillRange(0, bytesPerRow * height, byte),
  );
}

void main() {
  group('snapOffsetDots', () {
    test('keeps a multiple of 8 within ±64', () {
      expect(snapOffsetDots(0), 0);
      expect(snapOffsetDots(16), 16);
      expect(snapOffsetDots(-24), -24);
      expect(snapOffsetDots(64), 64);
      expect(snapOffsetDots(-64), -64);
    });

    test('rounds towards zero and clamps', () {
      expect(snapOffsetDots(12), 8);
      expect(snapOffsetDots(-12), -8);
      expect(snapOffsetDots(7), 0);
      expect(snapOffsetDots(100), 64);
      expect(snapOffsetDots(-100), -64);
    });
  });

  group('padLeft', () {
    test('adds white bytes on the left of every row', () {
      final padded = padLeft(solid(8, 2, 0xFF), 16);
      expect(padded.width, 24);
      expect(padded.height, 2);
      expect(padded.bits, [0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF]);
    });

    test('keeps the rows apart', () {
      final image = MonoImage(
        width: 16,
        height: 2,
        bits: Uint8List.fromList([0x12, 0x34, 0x56, 0x78]),
      );
      expect(padLeft(image, 8).bits, [0x00, 0x12, 0x34, 0x00, 0x56, 0x78]);
    });

    test('a width that is not a multiple of 8 keeps its last byte', () {
      final image = MonoImage(
        width: 10,
        height: 1,
        bits: Uint8List.fromList([0xFF, 0xC0]),
      );
      final padded = padLeft(image, 8);
      expect(padded.width, 18);
      expect(padded.bits, [0x00, 0xFF, 0xC0]);
    });

    test('whole bytes only: 12 dots pad 8', () {
      expect(padLeft(solid(8, 1), 12).width, 16);
    });

    test('zero or less changes nothing', () {
      final image = solid(8, 1);
      expect(identical(padLeft(image, 0), image), isTrue);
      expect(identical(padLeft(image, -16), image), isTrue);
      expect(identical(padLeft(image, 7), image), isTrue);
    });
  });

  group('buildPrintJob on a receipt printer (ESC/POS)', () {
    test('without an offset it is the raster job it always was', () {
      final image = solid(576, 10);
      expect(
        buildPrintJob(image, format: const PrintFormat(cut: true)),
        buildRasterJob(image, cut: true),
      );
    });

    test('a positive offset is white columns on the left of the image', () {
      final job = buildPrintJob(
        solid(576, 3, 0xFF),
        format: const PrintFormat(offsetDots: 16),
        feedLines: 0,
      );
      // ESC @, then GS v 0 with 74 bytes per row (72 + 2) and 3 rows.
      expect(job.sublist(0, 10), [0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00, 74, 0, 3, 0]);
      for (var row = 0; row < 3; row++) {
        final start = 10 + row * 74;
        expect(job.sublist(start, start + 2), [0x00, 0x00], reason: 'row $row');
        expect(
          job.sublist(start + 2, start + 74).every((b) => b == 0xFF),
          isTrue,
          reason: 'row $row',
        );
      }
      expect(job.length, 10 + 3 * 74);
    });

    test('a negative offset does nothing: there is no left of the edge', () {
      final image = solid(576, 3);
      expect(
        buildPrintJob(
          image,
          format: const PrintFormat(offsetDots: -16),
          feedLines: 0,
        ),
        buildRasterJob(image, feedLines: 0),
      );
    });

    test('the offset applies in every image mode', () {
      for (final mode in EscPosImageMode.values) {
        final image = solid(16, 24, 0xFF);
        expect(
          buildPrintJob(
            image,
            format: PrintFormat(imageMode: mode, offsetDots: 8),
            feedLines: 0,
          ),
          buildRasterJob(padLeft(image, 8), feedLines: 0, mode: mode),
          reason: mode.name,
        );
      }
    });

    test('the head and the paper width are TSPL matters only', () {
      final image = solid(576, 3);
      expect(
        buildPrintJob(
          image,
          format: const PrintFormat(headDots: 608, paperWidthMm: 80),
          feedLines: 0,
        ),
        buildRasterJob(image, feedLines: 0),
      );
    });
  });
}
