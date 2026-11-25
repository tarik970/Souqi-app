import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/printing/print_geometry.dart';
import 'package:souqi/domain/models/invoice_settings.dart';

void main() {
  group('computePrintableDots', () {
    test('80 mm paper with its default margin is 512 dots', () {
      // round((80 - 2 × 7.5) × 203 / 25.4) = round(519.5) = 519 → 512.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 7.5, dpi: 203),
        512,
      );
    });

    test('80 mm paper with a 3.5 mm margin is still the whole 576-dot head', () {
      // The first default, and what a shop that saved it keeps:
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
      // (80 - 16) × 203 / 25.4 = 511.5 → 511 → 504, not 512: why the
      // default margin is 7.5 mm and not a round 8.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 8, dpi: 203),
        504,
      );
      for (var paper = 40.0; paper <= 120; paper += 0.5) {
        for (final margin in [0.0, 1.5, 3.5, 5.0, 7.5]) {
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
      // The default margin: (80 - 15) × 300 / 25.4 = 767.7 → 768.
      expect(
        computePrintableDots(paperWidthMm: 80, sideMarginMm: 7.5, dpi: 300),
        768,
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
  });

  group('default margins', () {
    test('80 mm paper: 7.5 mm, 58 mm paper: 5 mm', () {
      expect(defaultSideMarginFor(80), 7.5);
      expect(defaultSideMarginFor(58), 5);
      expect(defaultSideMargin80Mm, 7.5);
      expect(defaultSideMargin58Mm, 5);
    });

    test('they give 512 dots on 80 mm paper and 384 on 58 mm', () {
      for (final (paper, dots) in [(80.0, 512), (58.0, 384)]) {
        expect(
          computePrintableDots(
            paperWidthMm: paper,
            sideMarginMm: defaultSideMarginFor(paper),
            dpi: 203,
          ),
          dots,
          reason: '$paper mm',
        );
      }
    });

    test('the settings table, the model and the geometry agree', () {
      // Three places hold the default of 80 mm paper; a shop that has
      // saved nothing must get the same width from each of them.
      expect(
        double.parse(SettingsKeys.defaults[SettingsKeys.sideMarginMm]!),
        defaultSideMargin80Mm,
      );
      expect(const InvoiceSettings().sideMarginMm, defaultSideMargin80Mm);
      expect(
        InvoiceSettings.fromMap(const {}).sideMarginMm,
        defaultSideMargin80Mm,
      );
      expect(SettingsKeys.defaults[SettingsKeys.paperWidthMm], '80');
    });

    test('the default width fits the head it is printed with', () {
      // 512 dots on the 576-dot head of a receipt printer and on the
      // 608-dot head of a label printer: nothing to warn about.
      expect(standardHeadDots(paperWidthMm: 80, dpi: 203), 576);
      expect(
        standardHeadDots(paperWidthMm: 80, dpi: 203, labelPrinter: true),
        608,
      );
      expect(standardHeadDots(paperWidthMm: 58, dpi: 203), 384);
      expect(const InvoiceSettings().widerThanHead, isFalse);
    });
  });

  group('InvoiceSettings widths', () {
    test('defaults give 512 dots, and 58 mm gives 384', () {
      const settings = InvoiceSettings();
      expect(settings.printableDots, 512);
      expect(InvoiceSettings.fromMap(const {}).printableDots, 512);
      expect(
        settings
            .copyWith(paperWidthMm: 58, sideMarginMm: defaultSideMarginFor(58))
            .printableDots,
        384,
      );
    });

    test('a saved margin keeps its width: the new default does not touch it',
        () {
      // A shop that saved the old 3.5 mm margin still prints 576 dots.
      final saved = InvoiceSettings.fromMap(const {
        SettingsKeys.paperWidthMm: '80',
        SettingsKeys.sideMarginMm: '3.5',
      });
      expect(saved.sideMarginMm, 3.5);
      expect(saved.printableDots, 576);
      // And it is written back as it was read.
      expect(saved.toMap()[SettingsKeys.sideMarginMm], '3.5');
    });

    test('a saved width override keeps its width', () {
      for (final dots in [576, 560, 608]) {
        final saved = InvoiceSettings.fromMap({
          SettingsKeys.printableDotsOverride: '$dots',
        });
        expect(saved.printableDots, dots);
        expect(saved.toMap()[SettingsKeys.printableDotsOverride], '$dots');
      }
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
        512,
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
