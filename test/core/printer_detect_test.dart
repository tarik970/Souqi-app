import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/printing/print_geometry.dart';
import 'package:souqi/core/printing/print_job.dart';
import 'package:souqi/core/printing/printer_detect.dart';
import 'package:souqi/core/printing/tspl.dart';
import 'package:souqi/domain/models/invoice_settings.dart';

/// A printer that answers the status questions as configured, and records
/// what it was asked.
class _Printer {
  _Printer({this.escPos = const [], this.tspl = const []});

  final List<int> escPos;
  final List<int> tspl;
  final asked = <List<int>>[];

  Future<Uint8List> query(Uint8List request, int timeoutMs) async {
    asked.add(request.toList());
    return Uint8List.fromList(request.first == 0x10 ? escPos : tspl);
  }
}

void main() {
  group('built-in profiles', () {
    test('a Bluetooth name that contains XP-365B is the label printer', () {
      for (final name in [
        'XP-365B',
        'xp-365b',
        'Xprinter XP 365B',
        'XP-365B_4F2A',
        'Printer_XP365B',
      ]) {
        final profile = builtInProfileFor(name);
        expect(profile, same(xp365bProfile), reason: name);
      }
      expect(xp365bProfile.language, PrinterLanguage.tspl);
      expect(xp365bProfile.printableDots, 512);
      expect(xp365bProfile.offsetDots, 0);
    });

    test('other printers have none', () {
      for (final name in ['XP-P323B', 'XP-365', 'POS-80', '', null]) {
        expect(builtInProfileFor(name), isNull, reason: '$name');
      }
    });
  });

  group('detectPrinterLanguage', () {
    test('a known printer is never asked', () async {
      final printer = _Printer();
      final found = await detectPrinterLanguage(
        name: 'XP-365B',
        query: printer.query,
      );
      expect(found.language, PrinterLanguage.tspl);
      expect(found.source, DetectionSource.profile);
      expect(found.profile, same(xp365bProfile));
      expect(printer.asked, isEmpty);
    });

    test('a receipt printer answers the ESC/POS question — and is not sent '
        'the TSPL one, which would change its text mode', () async {
      // 0x16: a real-time status byte (0xx1xx10).
      final printer = _Printer(escPos: [0x16]);
      final found = await detectPrinterLanguage(
        name: 'POS-80',
        query: printer.query,
      );
      expect(found.language, PrinterLanguage.escPos);
      expect(found.source, DetectionSource.answered);
      expect(printer.asked, [
        [0x10, 0x04, 0x01],
      ]);
    });

    test('a label printer ignores the first question and answers the second',
        () async {
      // 0x00: TSPL "ready".
      final printer = _Printer(tspl: [0x00]);
      final found = await detectPrinterLanguage(
        name: 'Label printer',
        query: printer.query,
      );
      expect(found.language, PrinterLanguage.tspl);
      expect(found.source, DetectionSource.answered);
      expect(printer.asked, [
        [0x10, 0x04, 0x01],
        [0x1B, 0x21, 0x3F],
      ]);
    });

    test('a printer that never answers is taken for a receipt printer',
        () async {
      final printer = _Printer();
      final found = await detectPrinterLanguage(
        name: null,
        query: printer.query,
      );
      expect(found.language, PrinterLanguage.escPos);
      expect(found.source, DetectionSource.silent);
      expect(printer.asked, hasLength(2));
    });

    test('a slow ESC/POS answer that only arrives with the second question '
        'is still an ESC/POS answer', () async {
      final printer = _Printer(tspl: [0x12]);
      final found = await detectPrinterLanguage(
        name: 'Slow',
        query: printer.query,
      );
      expect(found.language, PrinterLanguage.escPos);
      expect(found.source, DetectionSource.answered);
    });

    test('a printer that cannot be reached decides nothing', () async {
      await expectLater(
        detectPrinterLanguage(
          name: 'Off',
          query: (_, _) async =>
              throw const OutputException(OutputFailure.printerUnreachable),
        ),
        throwsA(isA<OutputException>()),
      );
    });

    test('the ESC/POS status shape', () {
      for (final byte in [0x12, 0x16, 0x1A, 0x1E, 0x32, 0x7E]) {
        expect(PrinterProbe.isEscPosStatus(byte), isTrue, reason: '$byte');
      }
      // The TSPL status bytes are never mistaken for one.
      for (final byte in [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x80]) {
        expect(PrinterProbe.isEscPosStatus(byte), isFalse, reason: '$byte');
      }
    });
  });

  group('settings', () {
    const address = 'AA:BB:CC:DD:EE:FF';
    const chosen = InvoiceSettings(printerAddress: address);

    test('a printer is unknown until something was decided for it', () {
      expect(chosen.printerLanguageKnown, isFalse);
      expect(const InvoiceSettings().printerLanguageKnown, isTrue,
          reason: 'no printer: nothing to find out');
      expect(
        chosen.withPrinterLanguage(PrinterLanguage.escPos).printerLanguageKnown,
        isTrue,
      );
    });

    test('the XP-365B profile: TSPL, 512 dots, centred on the 608-dot head',
        () {
      // Whatever was set before: another paper, a width override, an offset.
      final before = const InvoiceSettings(
        printerAddress: address,
        paperWidthMm: 58,
        sideMarginMm: 5,
        printableDotsOverride: 576,
        printerOffsets: {address: 16},
      );
      final s = before.withDetection(
        const PrinterDetection(
          PrinterLanguage.tspl,
          DetectionSource.profile,
          xp365bProfile,
        ),
      );
      expect(s.printerLanguage, PrinterLanguage.tspl);
      expect(s.paperWidthMm, 80);
      expect(s.printableDots, 512);
      expect(s.printableDotsOverride, isNull,
          reason: '80 mm with its default margin already gives 512');
      expect(s.printerOffsetDots, 0);
      final format = s.printFormat;
      expect(format.headDots, 608);
      expect(
        tsplBitmapX(
          headDots: format.headDots!,
          imageDots: s.printableDots,
          offsetDots: format.offsetDots,
        ),
        48,
        reason: '(608 - 512) / 2',
      );
      // It survives being stored.
      final stored = InvoiceSettings.fromMap(s.toMap());
      expect(stored.printerLanguage, PrinterLanguage.tspl);
      expect(stored.printableDots, 512);
    });

    test('an unknown printer: ESC/POS, and 512 dots on 80 mm paper', () {
      final s = chosen.withDetection(
        const PrinterDetection(PrinterLanguage.escPos, DetectionSource.silent),
      );
      expect(s.printerLanguage, PrinterLanguage.escPos);
      expect(s.printerLanguageKnown, isTrue);
      expect(s.printableDots, 512);
      expect(
        computePrintableDots(
          paperWidthMm: 80,
          sideMarginMm: defaultSideMargin80Mm,
          dpi: 203,
        ),
        512,
      );
    });

    test('a detected language changes nothing else', () {
      final before = const InvoiceSettings(
        printerAddress: address,
        printableDotsOverride: 480,
        printerOffsets: {address: -8},
      );
      final s = before.withDetection(
        const PrinterDetection(PrinterLanguage.tspl, DetectionSource.answered),
      );
      expect(s.printerLanguage, PrinterLanguage.tspl);
      expect(s.printableDots, 480);
      expect(s.printerOffsetDots, -8);
    });
  });
}
