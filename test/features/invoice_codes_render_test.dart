import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/printing/escpos.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// How a sold card code gets onto the paper: the block of digits, the
/// options (QR, separate slips), and the pipeline that decrypts the codes of
/// a saved invoice for the printer and the shared file — and for nothing
/// else.
void main() {
  setUpAll(sqfliteFfiInit);

  const codeA = '1111222233334444';

  InvoiceCode printed({
    String? code = codeA,
    String? serial = 'SN-001',
    DateTime? expiry,
    bool unreadable = false,
  }) =>
      InvoiceCode(
        id: 1,
        productName: 'Card 5000',
        code: code,
        masked: '•••• •••• 4444',
        serial: serial,
        expiryAt: expiry,
        unreadable: unreadable,
      );

  Future<void> pumpView(
    WidgetTester tester, {
    required List<InvoiceCode> codes,
    InvoiceSettings settings = const InvoiceSettings(language: 'en'),
    int dots = 576,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(dots.toDouble(), 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: SizedBox(
            width: dots.toDouble(),
            child: InvoiceView(
              invoice: sypInvoice(lines: 1),
              settings: settings,
              currencies: testCurrencies,
              codes: codes,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  /// The characters of the code block, in paint order from the left: what a
  /// customer reads off the paper.
  List<String> digitsOf(WidgetTester tester) {
    final block = find.byType(InvoiceCodeBlock);
    // Every character of the code sits in its own fixed-width cell.
    final cells = find.descendant(
      of: block,
      matching: find.byWidgetPredicate(
        (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
      ),
    );
    final texts = [
      for (final element in cells.evaluate())
        (
          tester.getTopLeft(find.byWidget(element.widget)),
          tester
              .widget<Text>(find.descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(Text),
              ))
              .data!,
        ),
    ]..sort((a, b) {
        final line = a.$1.dy.compareTo(b.$1.dy);
        return line != 0 ? line : a.$1.dx.compareTo(b.$1.dx);
      });
    return [for (final entry in texts) entry.$2];
  }

  group('the code block', () {
    testWidgets('prints the code large, in fours, with name and serial',
        (tester) async {
      await pumpView(tester, codes: [printed()]);
      final block = find.byType(InvoiceCodeBlock);
      expect(block, findsOneWidget);
      expect(digitsOf(tester).join(), codeA);
      expect(
        find.descendant(of: block, matching: find.text('Card 5000')),
        findsOneWidget,
      );
      expect(find.descendant(of: block, matching: find.text('S/N:')),
          findsOneWidget);
      expect(find.descendant(of: block, matching: find.text('SN-001')),
          findsOneWidget);

      // Four groups on one line at 80 mm, each cell the same width, and the
      // gap between groups wider than the pitch inside one.
      final cells = find.descendant(
        of: block,
        matching: find.byWidgetPredicate(
          (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
        ),
      );
      final lefts = [
        for (final element in cells.evaluate())
          tester.getTopLeft(find.byWidget(element.widget)).dx,
      ]..sort();
      final pitch = lefts[1] - lefts[0];
      expect(lefts[2] - lefts[1], pitch);
      expect(lefts[3] - lefts[2], pitch);
      expect(lefts[4] - lefts[3], greaterThan(pitch),
          reason: 'a gap after every fourth character');
      expect(
        {
          for (final element in cells.evaluate())
            tester.getTopLeft(find.byWidget(element.widget)).dy,
        },
        hasLength(1),
        reason: 'one line',
      );
      // Larger than the body text.
      final digit = tester.widget<Text>(find.descendant(
        of: find.byWidget(cells.evaluate().first.widget),
        matching: find.byType(Text),
      ));
      expect(digit.style!.fontSize, greaterThan(22));
      expect(digit.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('a code typed with dashes prints the same way', (tester) async {
      await pumpView(tester, codes: [printed(code: '1111-2222-3333-4444')]);
      expect(digitsOf(tester).join(), codeA);
    });

    testWidgets('on narrow paper the groups wrap between each other',
        (tester) async {
      await pumpView(
        tester,
        codes: [printed()],
        settings: const InvoiceSettings(language: 'en', paperWidthMm: 58),
        dots: 280,
      );
      expect(digitsOf(tester).join(), codeA,
          reason: 'still in reading order, line by line');
      final cells = find.descendant(
        of: find.byType(InvoiceCodeBlock),
        matching: find.byWidgetPredicate(
          (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
        ),
      );
      final rows = <double, int>{};
      for (final element in cells.evaluate()) {
        final y = tester.getTopLeft(find.byWidget(element.widget)).dy;
        rows[y] = (rows[y] ?? 0) + 1;
      }
      expect(rows.length, greaterThan(1));
      // Whole groups per line: never a group cut in two.
      expect(rows.values.every((count) => count % 4 == 0), isTrue,
          reason: '$rows');
    });

    testWidgets('stays left-to-right on an Arabic invoice', (tester) async {
      await pumpView(
        tester,
        codes: [printed()],
        settings: const InvoiceSettings(language: 'ar'),
      );
      expect(digitsOf(tester).join(), codeA);
      expect(find.text('التسلسلي:'), findsOneWidget);
    });

    testWidgets('the expiry is printed as the last valid day', (tester) async {
      await pumpView(
        tester,
        codes: [printed(expiry: expiryFromDate(DateTime(2026, 12, 31)))],
      );
      expect(find.text('Valid until 2026/12/31'), findsOneWidget);
    });

    testWidgets('the QR code is optional', (tester) async {
      Finder qr() => find.descendant(
            of: find.byType(InvoiceCodeBlock),
            matching: find.byType(CustomPaint),
          );
      await pumpView(tester, codes: [printed()]);
      expect(qr(), findsNothing);

      await pumpView(
        tester,
        codes: [printed()],
        settings: const InvoiceSettings(language: 'en', printCodeQr: true),
      );
      expect(qr(), findsOneWidget);
      // Drawn on whole dots: a square whose side is a whole number of
      // modules of a whole number of dots.
      final size = tester.getSize(qr());
      expect(size.width, size.height);
      // 16 characters in byte mode at level M: a version-2 symbol.
      expect(size.width % 25, 0, reason: 'a 25-module symbol');
      expect(size.width / 25, greaterThanOrEqualTo(3));
    });

    testWidgets('on screen: masked, and no QR to scan', (tester) async {
      await pumpView(
        tester,
        codes: [printed().hidden],
        settings: const InvoiceSettings(language: 'en', printCodeQr: true),
      );
      expect(digitsOf(tester).join(), '••••••••4444');
      expect(
        find.descendant(
          of: find.byType(InvoiceCodeBlock),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('a code this device cannot read says so on the paper',
        (tester) async {
      await pumpView(tester, codes: [printed(code: null, unreadable: true)]);
      expect(find.text('Code unavailable on this device'), findsOneWidget);
    });

    testWidgets('an invoice without codes has no block at all', (tester) async {
      await pumpView(tester, codes: const []);
      expect(find.byType(InvoiceCodeBlock), findsNothing);
    });
  });

  group('the print and share pipeline', () {
    late AppDatabase database;
    late ProviderContainer container;
    late CodeCipher cipher;

    Future<T> real<T extends Object>(
      WidgetTester tester,
      Future<T> Function() action,
    ) async {
      final result = await tester.runAsync(action);
      if (result == null) throw StateError('runAsync returned no result');
      return result;
    }

    /// A database with one card product holding two codes, and a saved
    /// invoice that sold both.
    Future<Invoice> open(
      WidgetTester tester, [
      Map<String, String> settings = const {},
    ]) async {
      final keyStore = InMemoryKeyStore();
      cipher = CodeCipher(keyStore);
      database = await real(tester, openTestDb);
      final invoice = await real(tester, () async {
        for (final entry in settings.entries) {
          await database.db.insert('settings', {
            'key': entry.key,
            'value': entry.value,
            'updated_at': 0,
          });
        }
        final cardId = await insertProduct(
          database.db,
          name: 'Card 5000',
          kind: 'SERVICE',
          soldFromCodeStock: 1,
        );
        await VoucherRepository(database.db, cipher).addBatch(
          productId: cardId,
          parsed: parseCodeList(
            '$codeA\n5555666677778888',
            columns: CodeColumns.codeOnly,
          ),
        );
        final syp = Currency(
          code: 'SYP',
          nameAr: 'SYP',
          nameEn: 'SYP',
          decimalPlaces: 0,
          rate: RateFraction.one,
          rateUpdatedAt: DateTime.utc(2026),
        );
        container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(database),
            secretKeyStoreProvider.overrideWithValue(keyStore),
          ],
        );
        return container.read(invoiceRepositoryProvider).save(
              Invoice.fromCart(
                cart: const Cart().add(CartLine(
                  productId: cardId,
                  name: 'Card 5000',
                  kind: ProductKind.service,
                  unitPriceMinor: 5000,
                  priceCurrencyCode: 'SYP',
                  qtyThousandths: 2000,
                  codeStock: true,
                )),
                ctx: CurrencyContext.of([syp], baseCode: 'SYP'),
                createdAt: DateTime(2026, 11, 25, 12).toUtc(),
              ),
            );
      });
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
      return invoice;
    }

    testWidgets('the codes of a saved invoice reach the printer and the share',
        (tester) async {
      final invoice = await open(tester);
      final output = container.read(invoiceOutputProvider);

      final codes = await real(tester, () => output.codesOf(invoice));
      expect([for (final c in codes) c.code], [codeA, '5555666677778888']);
      expect([for (final c in codes) c.productName], ['Card 5000', 'Card 5000']);

      // With its codes the print is taller than the same invoice without.
      final withCodes =
          await real(tester, () => output.renderForPrinter(invoice));
      final without = await real(
          tester, () => output.renderForPrinter(invoice, codes: const []));
      expect(withCodes.height, greaterThan(without.height + 100));

      // The shared image and the PDF carry them too.
      final shared = await real(tester, () => output.renderForShare(invoice));
      final sharedWithout = await real(
          tester, () => output.renderForShare(invoice, codes: const []));
      expect(shared.height, greaterThan(sharedWithout.height + 200));
      final pdf = await real(tester, () => output.sharePdf(invoice));
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });

    testWidgets('a draft invoice (the settings preview) has no codes',
        (tester) async {
      await open(tester);
      final output = container.read(invoiceOutputProvider);
      expect(await real(tester, () => output.codesOf(sypInvoice())), isEmpty);
    });

    testWidgets('a voided code is not printed again', (tester) async {
      final invoice = await open(tester);
      final output = container.read(invoiceOutputProvider);
      await real(tester, () async {
        final vouchers = container.read(voucherRepositoryProvider);
        final sold = await vouchers.codesOfInvoice(invoice.id!);
        return vouchers.voidCode(sold.first.id, reason: 'defective');
      });
      final codes = await real(tester, () => output.codesOf(invoice));
      expect([for (final c in codes) c.code], ['5555666677778888']);
    });

    testWidgets('separate slips: the invoice, then one job per card',
        (tester) async {
      final invoice = await open(tester, {
        SettingsKeys.codesOnSeparateSlips: '1',
        SettingsKeys.cutPaper: '1',
        SettingsKeys.feedLines: '0',
      });
      final output = container.read(invoiceOutputProvider);
      final codes = await real(tester, () => output.codesOf(invoice));

      Future<Uint8List> job(RgbaImage image, {required int feed}) async =>
          buildRasterJob(toMonochrome(image), feedLines: feed, cut: true);

      final expected = BytesBuilder();
      // The invoice itself, WITHOUT its codes, with the invoice's own feed.
      expected.add(await real(
        tester,
        () async => job(
          await output.renderForPrinter(invoice, codes: const []),
          feed: 0,
        ),
      ));
      // Then each card as a job of its own: its own feed (never none — there
      // must be somewhere to tear) and its own cut.
      for (final code in codes) {
        expected.add(await real(
          tester,
          () async => job(
            await output.renderSlip(invoice, code),
            feed: InvoiceOutput.minSlipFeedLines,
          ),
        ));
      }
      final actual = await real(tester, () => output.printJob(invoice));
      expect(actual, expected.toBytes());

      // A slip is one card, not the invoice: far shorter than the receipt
      // that holds both cards.
      final slip =
          await real(tester, () => output.renderSlip(invoice, codes.first));
      final whole = await real(tester, () => output.renderForPrinter(invoice));
      expect(slip.height, lessThan(whole.height));
      expect(slip.width, whole.width);
    });

    testWidgets('one receipt (the default): the codes are on the invoice',
        (tester) async {
      final invoice = await open(tester);
      final output = container.read(invoiceOutputProvider);
      final whole = await real(tester, () => output.renderForPrinter(invoice));
      final expected = buildRasterJob(toMonochrome(whole), feedLines: 3);
      expect(await real(tester, () => output.printJob(invoice)), expected);
    });

    testWidgets('sharing never splits into slips', (tester) async {
      final invoice = await open(tester, {
        SettingsKeys.codesOnSeparateSlips: '1',
      });
      final output = container.read(invoiceOutputProvider);
      final shared = await real(tester, () => output.renderForShare(invoice));
      final without = await real(
          tester, () => output.renderForShare(invoice, codes: const []));
      expect(shared.height, greaterThan(without.height + 200));
    });
  });
}
