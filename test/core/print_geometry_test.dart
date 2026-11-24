import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/printing/print_geometry.dart';
import 'package:souqi/domain/models/invoice_settings.dart';

void main() {
  group('computePrintableDots', () {
    test('80 mm paper with its default margin is the 576-dot head', () {
      // round((80 - 2 × 3.5) × 203 / 25.4) = round(583.4) = 583 → 576.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 3.5, dpi: 203),
        576,
      );
    });

    test('58 mm paper with its default margin is the 384-dot head', () {
      // round((58 - 2 × 5) × 203 / 25.4) = round(383.6) = 384.
      expect(
        computePrintableDots(paperWidthMm: 58, sideMarginMm: 5, dpi: 203),
        384,
      );
    });

    test('the result is always a multiple of 8, rounded down', () {
      // (80 - 8) × 203 / 25.4 = 575.4 → 575 → 568, not 576.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 4, dpi: 203),
        568,
      );
      for (var paper = 40.0; paper <= 120; paper += 0.5) {
        for (final margin in [0.0, 1.5, 3.5, 5.0]) {
          final dots = computePrintableDots(
            paperWidthMm: paper,
            sideMarginMm: margin,
            dpi: 203,
          );
          expect(dots % 8, 0, reason: 'paper $paper margin $margin');
          expect(dots, lessThanOrEqualTo((paper - 2 * margin) * 203 / 25.4 + 0.5));
        }
      }
    });

    test('follows the resolution: a 300 dpi head has more dots', () {
      // (80 - 7) × 300 / 25.4 = 862.2 → 862 → 856.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 3.5, dpi: 300),
        856,
      );
    });

    test('nonsense input is clamped, never zero or negative', () {
      expect(
        computePrintableDots(paperWidthMm: 5, sideMarginMm: 10, dpi: 203),
        minPrintableDots,
      );
      expect(
        computePrintableDots(paperWidthMm: 5000, sideMarginMm: 0, dpi: 600),
        maxPrintableDots,
      );
    });

    test('each standard paper has the margin that matches its head', () {
      expect(defaultSideMarginFor(80), 3.5);
      expect(defaultSideMarginFor(58), 5);
    });
  });

  group('InvoiceSettings widths', () {
    test('defaults give 576 dots, and 58 mm gives 384', () {
      const settings = InvoiceSettings();
      expect(settings.printableDots, 576);
      expect(
        settings
            .copyWith(paperWidthMm: 58, sideMarginMm: defaultSideMarginFor(58))
            .printableDots,
        384,
      );
    });

    test('the advanced override wins and is snapped to a multiple of 8', () {
      const settings = InvoiceSettings();
      expect(
        settings.copyWith(printableDotsOverride: () => 560).printableDots,
        560,
      );
      expect(
        settings.copyWith(printableDotsOverride: () => 580).printableDots,
        576,
      );
      // The computed value is still available for display.
      expect(
        settings.copyWith(printableDotsOverride: () => 560).computedPrintableDots,
        576,
      );
    });

    test('the share width follows the printer unless set on its own', () {
      const settings = InvoiceSettings();
      expect(settings.shareDots, settings.printableDots);
      expect(
        settings.copyWith(printableDotsOverride: () => 560).shareDots,
        560,
      );
      // A shop on 58 mm paper that wants wider shared images.
      final wide = settings.copyWith(
        paperWidthMm: 58,
        sideMarginMm: 5,
        shareWidthMm: () => 80,
      );
      expect(wide.printableDots, 384);
      expect(wide.shareDots, 552); // round((80 - 10) × 203 / 25.4) = 559 → 552
      expect(wide.sharePageWidthMm, 80);
    });
  });
}
