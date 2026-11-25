import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/printing/print_job.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/printing/tspl.dart';

/// One label of a parsed TSPL job: its command lines in order (BITMAP
/// without its data) and the data of its bitmap.
typedef Page = ({List<String> lines, Uint8List data});

/// Walks a TSPL job the way the printer does: ASCII lines ending in CR LF,
/// except that `BITMAP x,y,w,h,mode,` is followed by exactly w × h bytes of
/// binary (which may themselves contain CR or LF) and then a CR LF. A page
/// ends at its PRINT. Fails on a byte that belongs to no command.
List<Page> parseTspl(Uint8List job) {
  final pages = <Page>[];
  var lines = <String>[];
  Uint8List? data;
  var at = 0;
  while (at < job.length) {
    final start = at;
    while (job[at] != 0x0D) {
      if (job[at] == 0x2C && ascii.decode(job.sublist(start, at)).startsWith('BITMAP')) {
        // The fifth comma ends the header; the data starts right after it.
        final header = ascii.decode(job.sublist(start, at + 1));
        if (','.allMatches(header).length == 5) break;
      }
      at++;
    }
    final text = ascii.decode(job.sublist(start, at));
    if (text.startsWith('BITMAP')) {
      final parts = text.substring('BITMAP '.length).split(',');
      final length = int.parse(parts[2]) * int.parse(parts[3]);
      at++; // the comma
      data = job.sublist(at, at + length);
      at += length;
      lines.add('$text,');
    } else if (text.isNotEmpty) {
      lines.add(text);
    }
    expect(job.sublist(at, at + 2), [0x0D, 0x0A], reason: 'CR LF after "$text"');
    at += 2;
    if (text.startsWith('PRINT')) {
      pages.add((lines: lines, data: data!));
      lines = <String>[];
      data = null;
    }
  }
  expect(lines, isEmpty, reason: 'commands after the last PRINT');
  return pages;
}

/// A [width]×[height] image with every byte of row y set to [byteOf] (y).
MonoImage rowsOf(int width, int height, int Function(int y) byteOf) {
  final bytesPerRow = (width + 7) ~/ 8;
  final bits = Uint8List(bytesPerRow * height);
  for (var y = 0; y < height; y++) {
    bits.fillRange(y * bytesPerRow, (y + 1) * bytesPerRow, byteOf(y));
  }
  return MonoImage(width: width, height: height, bits: bits);
}

MonoImage solid(int width, int height, [int byte = 0xAA]) =>
    rowsOf(width, height, (_) => byte);

void main() {
  group('header lines', () {
    test('one label: SIZE, GAP, DIRECTION, REFERENCE, CLS, BITMAP, PRINT', () {
      final job = buildTsplJob(solid(576, 80));
      const header = '\r\n'
          'SIZE 72 mm,10 mm\r\n'
          'GAP 0 mm,0 mm\r\n'
          'DIRECTION 0\r\n'
          'REFERENCE 0,0\r\n'
          'CLS\r\n'
          'BITMAP 0,0,72,80,0,';
      // Byte for byte: an empty line first, then the commands, each on its
      // own CR LF line.
      expect(ascii.decode(job.sublist(0, header.length)), header);
      // The data, then CR LF, then PRINT — and nothing after it.
      expect(
        ascii.decode(job.sublist(header.length + 72 * 80)),
        '\r\nPRINT 1,1\r\n',
      );
      expect(job.length, header.length + 72 * 80 + 13);
    });

    test('the label is exactly as wide and as long as the image', () {
      // 384 dots = 48 mm, 160 rows = 20 mm at 8 dots per mm.
      var page = parseTspl(buildTsplJob(solid(384, 160))).single;
      expect(page.lines.first, 'SIZE 48 mm,20 mm');
      // 608 dots is the whole 76 mm head.
      page = parseTspl(buildTsplJob(solid(608, 8))).single;
      expect(page.lines.first, 'SIZE 76 mm,1 mm');
    });

    test('a height that is not a whole millimetre is rounded UP', () {
      // 161 rows = 20.125 mm: a 20 mm label would cut the last row off.
      final page = parseTspl(buildTsplJob(solid(384, 161))).single;
      expect(page.lines.first, 'SIZE 48 mm,21 mm');
      expect(page.lines, contains('BITMAP 0,0,48,161,0,'));
    });

    test('feed lines lengthen the label, not the bitmap', () {
      // 3 lines of 1/6 inch at 203 dpi = 102 dots; 80 + 102 = 182 dots
      // = 22.75 mm → 23 mm.
      final page = parseTspl(buildTsplJob(solid(576, 80), feedLines: 3)).single;
      expect(page.lines.first, 'SIZE 72 mm,23 mm');
      expect(page.lines, contains('BITMAP 0,0,72,80,0,'));
      expect(page.data.length, 72 * 80);
    });

    test('millimetres follow the resolution', () {
      // 300 dpi is 12 dots per mm: 864 dots = 72 mm, 120 rows = 10 mm.
      expect(tsplDotsPerMm(203), 8);
      expect(tsplDotsPerMm(300), 12);
      final page = parseTspl(buildTsplJob(solid(864, 120), dpi: 300)).single;
      expect(page.lines.first, 'SIZE 72 mm,10 mm');
    });

    test('nothing but label commands: no cut, no cash drawer', () {
      final job = buildTsplJob(solid(576, 2500, 0x00), feedLines: 5);
      const known = ['SIZE', 'GAP', 'DIRECTION', 'REFERENCE', 'CLS', 'BITMAP', 'PRINT'];
      for (final page in parseTspl(job)) {
        for (final line in page.lines) {
          expect(known, contains(line.split(' ').first), reason: line);
        }
      }
      // An all-white picture: the whole job is printable ASCII, CR, LF and
      // 0xFF — no ESC (0x1B) or GS (0x1D) byte can be hiding in it.
      expect(job.where((b) => b == 0x1B || b == 0x1D), isEmpty);
    });
  });

  group('bitmap size', () {
    test('width in BYTES, height in dots, and width × height bytes of data', () {
      final page = parseTspl(buildTsplJob(solid(384, 37))).single;
      expect(page.lines, contains('BITMAP 0,0,48,37,0,'));
      expect(page.data.length, 48 * 37);
    });

    test('a width that is not a multiple of 8 takes one more byte', () {
      final page = parseTspl(buildTsplJob(solid(10, 16))).single;
      // 10 dots at 8 per mm = 1.25 mm → 2 mm.
      expect(page.lines.first, 'SIZE 2 mm,2 mm');
      expect(page.lines, contains('BITMAP 0,0,2,16,0,'));
      expect(page.data.length, 2 * 16);
    });

    test('data that looks like a line ending is still data', () {
      // 0xF2 flipped is 0x0D (CR) and 0xF5 flipped is 0x0A (LF).
      final image = rowsOf(16, 4, (y) => y.isEven ? 0xF2 : 0xF5);
      final page = parseTspl(buildTsplJob(image)).single;
      expect(page.data, [0x0D, 0x0D, 0x0A, 0x0A, 0x0D, 0x0D, 0x0A, 0x0A]);
    });
  });

  group('inversion', () {
    test('by default a black dot is sent as a 0 bit', () {
      // MonoImage: 1 = black. Row 0 all black, row 1 all white.
      final image = rowsOf(16, 2, (y) => y == 0 ? 0xFF : 0x00);
      final page = parseTspl(buildTsplJob(image)).single;
      expect(page.data, [0x00, 0x00, 0xFF, 0xFF]);
    });

    test('every bit is flipped, not just whole bytes', () {
      final page = parseTspl(buildTsplJob(solid(8, 2, 0xA5))).single;
      expect(page.data, [0x5A, 0x5A]);
    });

    test('the padding past the last dot stays white', () {
      // 10 black dots: 0xFF 0xC0. Flipped, the six padding bits are 1 —
      // white — so nothing is burned to the right of the image.
      final image = MonoImage(
        width: 10,
        height: 1,
        bits: Uint8List.fromList([0xFF, 0xC0]),
      );
      expect(parseTspl(buildTsplJob(image)).single.data, [0x00, 0x3F]);
      // And with the other polarity they are 0 — white there as well.
      expect(
        parseTspl(buildTsplJob(image, zeroIsBlack: false)).single.data,
        [0xFF, 0xC0],
      );
    });

    test('zeroIsBlack: false sends the bits as they are', () {
      final image = rowsOf(16, 2, (y) => y == 0 ? 0xFF : 0x00);
      final page = parseTspl(buildTsplJob(image, zeroIsBlack: false)).single;
      expect(page.data, [0xFF, 0xFF, 0x00, 0x00]);
    });

    test('the image itself is left untouched', () {
      final image = solid(16, 4, 0xAA);
      buildTsplJob(image);
      expect(image.bits.every((b) => b == 0xAA), isTrue);
    });
  });

  group('page split', () {
    test('an image up to the page limit is one label', () {
      expect(parseTspl(buildTsplJob(solid(384, 1000))), hasLength(1));
      expect(tsplPageHeights(1000, dotsPerMm: 8), [1000]);
    });

    test('a longer one is split into even pages of whole millimetres', () {
      // 2500 rows need 3 pages; 834 rows each, rounded up to 840 (105 mm).
      expect(tsplPageHeights(2500, dotsPerMm: 8), [840, 840, 820]);
      // One row too many does not leave a one-row label behind.
      expect(tsplPageHeights(1001, dotsPerMm: 8), [504, 497]);
      // 12 dots per mm: the limit is 996 rows (83 mm).
      expect(tsplPageHeights(996, dotsPerMm: 12), [996]);
      expect(tsplPageHeights(997, dotsPerMm: 12), [504, 493]);
    });

    test('each page is its own label with its own PRINT', () {
      final pages = parseTspl(buildTsplJob(solid(384, 2500)));
      expect(pages, hasLength(3));
      expect(pages[0].lines, [
        'SIZE 48 mm,105 mm',
        'GAP 0 mm,0 mm',
        'DIRECTION 0',
        'REFERENCE 0,0',
        'CLS',
        'BITMAP 0,0,48,840,0,',
        'PRINT 1,1',
      ]);
      // The paper set-up is sent once; a later page only changes its size.
      expect(pages[1].lines, [
        'SIZE 48 mm,105 mm',
        'CLS',
        'BITMAP 0,0,48,840,0,',
        'PRINT 1,1',
      ]);
      // 820 rows = 102.5 mm → 103 mm.
      expect(pages[2].lines, [
        'SIZE 48 mm,103 mm',
        'CLS',
        'BITMAP 0,0,48,820,0,',
        'PRINT 1,1',
      ]);
    });

    test('no visible gap: every page but the last is exactly its label', () {
      final pages = parseTspl(buildTsplJob(solid(576, 4321)));
      for (final page in pages.take(pages.length - 1)) {
        final size = RegExp(r'^SIZE 72 mm,(\d+) mm$').firstMatch(page.lines.first)!;
        final bitmap = page.lines.firstWhere((l) => l.startsWith('BITMAP'));
        final rows = int.parse(bitmap.split(',')[3]);
        expect(int.parse(size[1]!) * 8, rows);
      }
    });

    test('the pages hold every row once, in order', () {
      // Row y is filled with y mod 251, so a lost, repeated or swapped row
      // shows (251 is prime: no page length lines up with it).
      const rows = 2345;
      final job = buildTsplJob(
        rowsOf(16, rows, (y) => y % 251),
        zeroIsBlack: false,
      );
      final all = [for (final page in parseTspl(job)) ...page.data];
      expect(all.length, rows * 2);
      for (var y = 0; y < rows; y++) {
        expect(all[y * 2], y % 251, reason: 'row $y');
        expect(all[y * 2 + 1], y % 251, reason: 'row $y');
      }
    });

    test('the feed is added to the last page only', () {
      final pages = parseTspl(buildTsplJob(solid(384, 2000), feedLines: 3));
      expect(pages, hasLength(2));
      // 1000 rows = 125 mm; the last one gets 102 more dots → 137.75 mm.
      expect(pages[0].lines.first, 'SIZE 48 mm,125 mm');
      expect(pages[1].lines.first, 'SIZE 48 mm,138 mm');
    });

    test('the page limit can be changed, and must be positive', () {
      final pages = parseTspl(buildTsplJob(solid(16, 100), pageRows: 40));
      expect(
        [for (final page in pages) page.data.length ~/ 2],
        [40, 40, 20],
      );
      expect(() => buildTsplJob(solid(16, 8), pageRows: 0), throwsArgumentError);
    });
  });

  group('position on the label', () {
    test('the image is centred on the print head', () {
      // 576 dots on the 608-dot head of a 76 mm label printer: 16 on each
      // side.
      expect(tsplBitmapX(headDots: 608, imageDots: 576), 16);
      expect(tsplBitmapX(headDots: 608, imageDots: 608), 0);
      expect(tsplBitmapX(headDots: 384, imageDots: 368), 8);
      // Wider than the head: nothing to centre, it starts at the edge.
      expect(tsplBitmapX(headDots: 576, imageDots: 608), 0);
    });

    test('the calibration offset moves it, but never left of dot 0', () {
      expect(tsplBitmapX(headDots: 608, imageDots: 576, offsetDots: 8), 24);
      expect(tsplBitmapX(headDots: 608, imageDots: 576, offsetDots: 64), 80);
      expect(tsplBitmapX(headDots: 608, imageDots: 576, offsetDots: -8), 8);
      expect(tsplBitmapX(headDots: 608, imageDots: 576, offsetDots: -16), 0);
      expect(tsplBitmapX(headDots: 608, imageDots: 576, offsetDots: -64), 0);
    });

    test('x goes into BITMAP, and the label is as wide as the paper', () {
      final page = parseTspl(
        buildTsplJob(solid(576, 80), x: 16, labelWidthMm: 80),
      ).single;
      expect(page.lines, [
        'SIZE 80 mm,10 mm',
        'GAP 0 mm,0 mm',
        'DIRECTION 0',
        'REFERENCE 0,0',
        'CLS',
        'BITMAP 16,0,72,80,0,',
        'PRINT 1,1',
      ]);
      // The data is the image itself: x moves it, it does not pad it.
      expect(page.data.length, 72 * 80);
    });

    test('a paper width that is not whole keeps one decimal', () {
      final page = parseTspl(
        buildTsplJob(solid(384, 80), labelWidthMm: 57.5),
      ).single;
      expect(page.lines.first, 'SIZE 57.5 mm,10 mm');
    });

    test('the label is never narrower than the image where it sits', () {
      // 608 dots starting at 40 end at dot 648 = 81 mm: more than the paper.
      var page = parseTspl(
        buildTsplJob(solid(608, 8), x: 40, labelWidthMm: 80),
      ).single;
      expect(page.lines.first, 'SIZE 81 mm,1 mm');
      // And with no paper width given it is just wide enough: 592 dots.
      page = parseTspl(buildTsplJob(solid(576, 8), x: 16)).single;
      expect(page.lines.first, 'SIZE 74 mm,1 mm');
    });

    test('every page of a long receipt sits at the same x', () {
      final pages = parseTspl(
        buildTsplJob(solid(576, 2500), x: 24, labelWidthMm: 80),
      );
      expect(pages, hasLength(3));
      for (final page in pages) {
        expect(page.lines.first, startsWith('SIZE 80 mm,'));
        expect(
          page.lines.where((l) => l.startsWith('BITMAP')).single,
          startsWith('BITMAP 24,0,72,'),
        );
      }
    });

    test('x cannot be negative', () {
      expect(() => buildTsplJob(solid(16, 8), x: -8), throwsArgumentError);
    });
  });

  group('buildPrintJob', () {
    PrintFormat labelPrinter({int offsetDots = 0}) => PrintFormat(
          language: PrinterLanguage.tspl,
          headDots: 608,
          paperWidthMm: 80,
          offsetDots: offsetDots,
        );

    String bitmapOf(Uint8List job) => parseTspl(job)
        .single
        .lines
        .firstWhere((line) => line.startsWith('BITMAP'));

    test('a label printer: paper-wide label, image centred on the head', () {
      final job = buildPrintJob(
        solid(576, 80),
        format: labelPrinter(),
        feedLines: 0,
      );
      expect(parseTspl(job).single.lines.first, 'SIZE 80 mm,10 mm');
      expect(bitmapOf(job), 'BITMAP 16,0,72,80,0,');
    });

    test('the offset of the format moves the bitmap', () {
      Uint8List job(int offset) => buildPrintJob(
            solid(576, 80),
            format: labelPrinter(offsetDots: offset),
            feedLines: 0,
          );
      expect(bitmapOf(job(16)), 'BITMAP 32,0,72,80,0,');
      expect(bitmapOf(job(-8)), 'BITMAP 8,0,72,80,0,');
      expect(bitmapOf(job(-64)), 'BITMAP 0,0,72,80,0,');
    });

    test('a TSPL printer gets TSPL, with no cut even when cutting is on', () {
      final job = buildPrintJob(
        solid(576, 80, 0x00),
        format: const PrintFormat(language: PrinterLanguage.tspl, cut: true),
        feedLines: 0,
      );
      expect(ascii.decode(job.sublist(0, 18)), '\r\nSIZE 72 mm,10 mm');
      expect(job.where((b) => b == 0x1B || b == 0x1D), isEmpty);
    });

    test('the polarity of the format reaches the bitmap', () {
      final job = buildPrintJob(
        solid(8, 1, 0xFF),
        format: const PrintFormat(
          language: PrinterLanguage.tspl,
          tsplZeroIsBlack: false,
        ),
        feedLines: 0,
      );
      expect(parseTspl(job).single.data, [0xFF]);
    });

    test('an ESC/POS printer still gets the same raster job as before', () {
      final job = buildPrintJob(solid(576, 10), format: const PrintFormat());
      expect(job.sublist(0, 10), [0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00, 72, 0, 10, 0]);
      expect(job.sublist(job.length - 3), [0x1B, 0x64, 3]);
    });
  });
}
