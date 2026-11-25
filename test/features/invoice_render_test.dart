import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_text.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The rendering pipeline end to end: the real [InvoiceView] is laid out
/// off-screen, rasterised and encoded. Rasterising needs real async, so
/// everything runs inside [WidgetTester.runAsync].
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late ProviderContainer container;

  Future<T> real<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<void> open(WidgetTester tester, [Map<String, String> settings = const {}]) async {
    database = await real(tester, openTestDb);
    await tester.runAsync(() async {
      for (final entry in settings.entries) {
        await database.db.insert('settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  }

  /// True when row [y] of [image] has at least one dark pixel.
  bool rowHasInk(RgbaImage image, int y) {
    for (var x = 0; x < image.width; x++) {
      if (image.rgba[(y * image.width + x) * 4] < 128) return true;
    }
    return false;
  }

  testWidgets('share render is a PNG twice the printable width', (tester) async {
    await open(tester);
    final output = container.read(invoiceOutputProvider);
    final png = await real(tester, () => output.sharePng(crossCurrencyInvoice()));

    // Default paper: 512 dots, shared at 2×.
    expect(readPngSize(png)!.width, 2 * 512);

    // And it is a real PNG the platform can decode, with the same size.
    final decoded = await real(tester, () async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });
    expect(decoded.$1, 1024);
    expect(decoded.$2, readPngSize(png)!.height);
    expect(decoded.$2, greaterThan(200));
  });

  testWidgets('share render follows the 58 mm paper and the share width',
      (tester) async {
    await open(tester, {
      SettingsKeys.paperWidthMm: '58',
      SettingsKeys.sideMarginMm: '5',
    });
    final output = container.read(invoiceOutputProvider);
    final narrow = await real(tester, () => output.sharePng(sypInvoice()));
    expect(readPngSize(narrow)!.width, 2 * 384);

    // A shop with no printer set up widens only the shared image.
    final stored = await real(tester, () async {
      await container
          .read(invoiceSettingsProvider.notifier)
          .change((s) => s.copyWith(shareWidthMm: () => 80));
      return container
          .read(settingsRepositoryProvider)
          .getString(SettingsKeys.shareWidthMm);
    });
    expect(stored, '80'); // the change reached the database
    final wide = await real(tester, () => output.sharePng(sypInvoice()));
    expect(readPngSize(wide)!.width, 2 * 552);
    // The printer width is untouched by the share width.
    final print = await real(tester, () => output.renderForPrinter(sypInvoice()));
    expect(print.width, 384);
  });

  testWidgets('printer render is exactly the printable width in dots',
      (tester) async {
    await open(tester);
    final output = container.read(invoiceOutputProvider);
    final image =
        await real(tester, () => output.renderForPrinter(crossCurrencyInvoice()));
    expect(image.width, 512);
    // White paper with ink on it: the corners are background, some row is not.
    expect(image.rgba.sublist(0, 4), [255, 255, 255, 255]);
    expect(
      [for (var y = 0; y < image.height; y++) rowHasInk(image, y)],
      contains(true),
    );

    final job = await real(tester, () => output.printJob(crossCurrencyInvoice()));
    expect(job.sublist(0, 2), [0x1B, 0x40]); // ESC @
    expect(job.sublist(2, 6), [0x1D, 0x76, 0x30, 0x00]); // GS v 0
    expect(job[6] | (job[7] << 8), 512 ~/ 8); // bytes per row
    // Default settings: feed 3 lines, no cut.
    expect(job.sublist(job.length - 3), [0x1B, 0x64, 3]);
  });

  testWidgets('the advanced dots override sets the print width', (tester) async {
    await open(tester, {SettingsKeys.printableDotsOverride: '400'});
    final output = container.read(invoiceOutputProvider);
    final image = await real(tester, () => output.renderForPrinter(sypInvoice()));
    expect(image.width, 400);
  });

  testWidgets('a long receipt is captured whole, across slices', (tester) async {
    await open(tester, {SettingsKeys.footerText: 'END OF RECEIPT'});
    final output = container.read(invoiceOutputProvider);
    final image =
        await real(tester, () => output.renderForPrinter(sypInvoice(lines: 80)));
    // Taller than several capture slices (1024 rows each).
    expect(image.height, greaterThan(3 * 1024));
    // Ink in the first slice, in a middle slice and near the very bottom
    // (the footer), so no slice came back blank or misplaced.
    bool inkBetween(int from, int to) {
      for (var y = from; y < to; y++) {
        if (rowHasInk(image, y)) return true;
      }
      return false;
    }

    expect(inkBetween(0, 200), isTrue);
    expect(inkBetween(1024, 1224), isTrue);
    expect(inkBetween(2048, 2248), isTrue);
    expect(inkBetween(image.height - 200, image.height), isTrue);
  });

  testWidgets('the PDF is one page as wide as the paper', (tester) async {
    await open(tester);
    final output = container.read(invoiceOutputProvider);
    final pdf = await real(tester, () => output.sharePdf(sypInvoice()));
    final text = String.fromCharCodes(pdf);
    expect(text.startsWith('%PDF-'), isTrue);
    // 80 mm = 226.77 pt.
    expect(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+226\.7\d*').hasMatch(text), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
  });

  group('InvoiceView', () {
    Future<void> pump(
      WidgetTester tester,
      InvoiceSettings settings, {
      Locale appLocale = const Locale('en'),
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        // The APP is in [appLocale]; the invoice must not care.
        Directionality(
          textDirection: appLocale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: settings.printableDots.toDouble(),
              child: InvoiceView(
                invoice: crossCurrencyInvoice(
                  customerName: 'Ahmad',
                  customerPhone: '0944 123 456',
                  accountNumber: '0011223344',
                ),
                settings: settings,
                currencies: testCurrencies,
              ),
            ),
          ),
        ),
      );
    }

    TextDirection directionOf(WidgetTester tester, String text) =>
        Directionality.of(tester.element(find.text(text).first));

    testWidgets('direction follows the INVOICE language, not the app',
        (tester) async {
      // English app, Arabic invoice → right-to-left.
      await pump(tester, const InvoiceSettings(language: 'ar'));
      expect(directionOf(tester, 'Sugar'), TextDirection.rtl);
      expect(find.text('الإجمالي'), findsOneWidget);

      // Arabic app, English invoice → left-to-right.
      await pump(
        tester,
        const InvoiceSettings(language: 'en'),
        appLocale: const Locale('ar'),
      );
      expect(directionOf(tester, 'Sugar'), TextDirection.ltr);
      expect(find.text('Total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prints the cross-currency rule and the rate used',
        (tester) async {
      await pump(
        tester,
        const InvoiceSettings(
          language: 'en',
          currencyDisplay: CurrencyDisplay.code,
        ),
      );
      // "10 kg × 5,000 SYP" … "3.85 USD": original price, converted total.
      expect(find.text('10 kg'), findsOneWidget);
      expect(find.text('5,000 SYP'), findsOneWidget);
      expect(find.text('3.85 USD'), findsOneWidget);
      expect(find.text('0.38'), findsNothing);
      expect(find.text('0.38 USD'), findsNothing);
      // Same-currency line: plain numbers.
      expect(find.text('2.50'), findsOneWidget);
      expect(find.text('5.00'), findsOneWidget);
      // Total, and the rate that makes the first line checkable.
      expect(find.text('8.85 USD'), findsOneWidget);
      expect(find.text('1 USD'), findsOneWidget);
      expect(find.text('13,000 SYP'), findsOneWidget);
      // No "=" before a line total: the only one left on the invoice is the
      // rate line's ("1 USD = 13,000 SYP"), not one per item.
      expect(find.text('='), findsOneWidget);
    });

    testWidgets('toggles hide their fields', (tester) async {
      await pump(
        tester,
        const InvoiceSettings(
          language: 'en',
          showItemCode: true,
          currencyDisplay: CurrencyDisplay.code,
        ),
      );
      expect(find.text('101'), findsOneWidget);
      expect(find.text('Invoice no. 12'), findsOneWidget);
      expect(find.text('2026/11/24 14:35'), findsOneWidget);
      expect(find.text('Ahmad'), findsOneWidget);
      expect(find.text('0944 123 456'), findsOneWidget);
      expect(find.text('0011223344'), findsOneWidget);
      expect(find.text('Powered by Souqi'), findsOneWidget);

      await pump(
        tester,
        const InvoiceSettings(
          language: 'en',
          showItemCode: false,
          showUnit: false,
          showUnitPrice: false,
          showDateTime: false,
          showInvoiceNumber: false,
          showCustomerName: false,
          showCustomerPhone: false,
          maskAccountNumber: true,
          showPoweredBy: false,
          currencyDisplay: CurrencyDisplay.code,
        ),
      );
      expect(find.text('101'), findsNothing);
      expect(find.text('Invoice no. 12'), findsNothing);
      expect(find.text('2026/11/24 14:35'), findsNothing);
      expect(find.text('Ahmad'), findsNothing);
      expect(find.text('0944 123 456'), findsNothing);
      expect(find.text('******3344'), findsOneWidget);
      expect(find.text('Powered by Souqi'), findsNothing);
      expect(find.text('10'), findsOneWidget); // quantity without its unit
      expect(find.text('5,000 SYP'), findsNothing); // unit price hidden
      expect(find.text('×'), findsNothing);
      expect(find.text('3.85'), findsOneWidget);

      await pump(
        tester,
        const InvoiceSettings(language: 'en', showAccountNumber: false),
      );
      expect(find.text('0011223344'), findsNothing);
    });

    testWidgets('shop name, header and footer are printed', (tester) async {
      await pump(
        tester,
        const InvoiceSettings(
          language: 'en',
          shopName: 'Abu Ahmad Market',
          headerText: 'Main street\nTel 011 222 333',
          footerText: 'Thank you',
        ),
      );
      expect(find.text('Abu Ahmad Market'), findsOneWidget);
      // The phone number is wrapped in invisible isolates so its groups keep
      // their order on an Arabic invoice; the visible text is unchanged.
      expect(
        find.text(isolateSpacedNumbers('Main street\nTel 011 222 333')),
        findsOneWidget,
      );
      expect(find.text('Thank you'), findsOneWidget);
    });

    testWidgets('fits 58 mm paper without overflowing', (tester) async {
      await pump(
        tester,
        const InvoiceSettings(
          language: 'ar',
          paperWidthMm: 58,
          sideMarginMm: 5,
          showItemCode: true,
          shopName: 'دكان أبو أحمد',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
