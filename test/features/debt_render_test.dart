import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/features/debts/debt_output.dart';
import 'package:souqi/features/debts/debt_papers.dart';
import 'package:souqi/features/debts/receipt_screen.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The papers of the debt ledger — the payment receipt, the account
/// statement and the debt lines of the invoice — in Arabic and in English:
/// what they say, and that they go through the same print / share pipeline
/// as the invoice (exact printer width, 2× share image, PDF).
void main() {
  setUpAll(sqfliteFfiInit);

  const english = InvoiceSettings(language: 'en', shopName: 'Al-Baraka');
  const arabic = InvoiceSettings(language: 'ar', shopName: 'بقالة البركة');

  DebtEntry payment({
    int amount = 4000,
    int before = 10000,
    int receiptNo = 37,
    PaymentMethod method = PaymentMethod.cash,
    int? origAmount,
    String? origCurrency,
    RateFraction? origRate,
    String? note,
    int? reversedById,
  }) =>
      DebtEntry(
        id: 9,
        customerId: 1,
        type: DebtEntryType.payment,
        direction: -1,
        amountBaseMinor: amount,
        origAmountMinor: origAmount,
        origCurrencyCode: origCurrency,
        origRate: origRate,
        paymentMethod: method,
        receiptNo: receiptNo,
        balanceBeforeBaseMinor: before,
        note: note,
        createdAt: DateTime(2026, 11, 25, 14, 35),
        recordedAt: DateTime(2026, 11, 25, 14, 35),
        reversedById: reversedById,
      );

  ReceiptData receipt(DebtEntry entry, {String name = 'Ahmad Hasan'}) =>
      ReceiptData(
        payment: entry,
        customerName: name,
        customerPhone: '0944 123 456',
        baseCurrencyCode: 'SYP',
      );

  DebtEntry line(
    int id,
    DebtEntryType type,
    int direction,
    int amount,
    DateTime at, {
    int? invoiceNo,
    int? receiptNo,
    int? reversedById,
    DebtEntryType? reversedType,
    int? reversedReceiptNo,
  }) =>
      DebtEntry(
        id: id,
        customerId: 1,
        type: type,
        direction: direction,
        amountBaseMinor: amount,
        invoiceNo: invoiceNo,
        receiptNo: receiptNo,
        reversesId: type == DebtEntryType.reversal ? 1 : null,
        reversedById: reversedById,
        reversedType: reversedType,
        reversedReceiptNo: reversedReceiptNo,
        createdAt: at,
        recordedAt: at,
      );

  /// Brought forward 15,000; invoice 152 +8,000; receipt 37 −3,000;
  /// closing 20,000.
  StatementData statement({String name = 'Ahmad Hasan', int entries = 2}) {
    var running = 15000;
    final lines = <LedgerLine>[];
    for (var i = 0; i < entries; i++) {
      final entry = i.isEven
          ? line(i + 1, DebtEntryType.debt, 1, 8000, DateTime(2026, 11, 5 + i),
              invoiceNo: 152 + i)
          : line(i + 1, DebtEntryType.payment, -1, 3000,
              DateTime(2026, 11, 5 + i),
              receiptNo: 37 + i);
      running += entry.signedBaseMinor;
      lines.add(LedgerLine(entry: entry, balanceAfterBaseMinor: running));
    }
    return StatementData(
      statement: AccountStatement(
        from: DateTime(2026, 11),
        to: DateTime(2026, 12),
        openingBalanceBaseMinor: 15000,
        lines: lines,
      ),
      customerName: name,
      customerPhone: '0944 123 456',
      baseCurrencyCode: 'SYP',
      printedAt: DateTime(2026, 11, 25, 16),
    );
  }

  Future<void> pump(WidgetTester tester, Widget paper, InvoiceSettings s) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // A long paper is taller than the test window.
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: s.printableDots.toDouble(), child: paper),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  group('the payment receipt', () {
    testWidgets('English: number, date, customer, balances, amount',
        (tester) async {
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(note: 'for November')),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Al-Baraka'), findsOneWidget);
      expect(find.text('Payment receipt'), findsOneWidget);
      expect(find.text('Receipt no. 37'), findsOneWidget);
      expect(find.text('2026/11/25 14:35'), findsOneWidget);
      expect(find.text('Received from:'), findsOneWidget);
      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.text('0944 123 456'), findsOneWidget);
      expect(find.text('Previous balance'), findsOneWidget);
      expect(find.text('10,000 ل.س'), findsOneWidget);
      expect(find.text('Amount paid'), findsOneWidget);
      expect(find.text('4,000 ل.س'), findsOneWidget);
      expect(find.text('New balance'), findsOneWidget);
      expect(find.text('6,000 ل.س'), findsOneWidget);
      expect(find.text('owes'), findsNWidgets(2));
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('for November'), findsOneWidget);
      expect(find.text('COPY'), findsNothing);
      expect(find.text('CANCELLED'), findsNothing);
    });

    testWidgets('Arabic: the same receipt, right to left, Arabic words',
        (tester) async {
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(), name: 'أحمد الحسن'),
          settings: arabic,
          currencies: testCurrencies,
        ),
        arabic,
      );
      expect(find.text('بقالة البركة'), findsOneWidget);
      expect(find.text('سند قبض'), findsOneWidget);
      expect(find.text('سند قبض رقم 37'), findsOneWidget);
      expect(find.text('استلمنا من:'), findsOneWidget);
      expect(find.text('أحمد الحسن'), findsOneWidget);
      expect(find.text('الرصيد السابق'), findsOneWidget);
      expect(find.text('المبلغ المدفوع'), findsOneWidget);
      expect(find.text('الرصيد الجديد'), findsOneWidget);
      expect(find.text('عليه'), findsNWidgets(2));
      expect(find.text('نقداً'), findsOneWidget);
      // The paper sets its own direction from the invoice language.
      final direction = tester.widget<Directionality>(
        find
            .descendant(
              of: find.byType(ReceiptView),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(direction.textDirection, TextDirection.rtl);
    });

    testWidgets('a payment that leaves a credit: "owes" before, "credit" '
        'after', (tester) async {
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(amount: 5000, before: 3000)),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('owes'), findsOneWidget);
      expect(find.text('credit'), findsOneWidget);
      expect(find.text('3,000 ل.س'), findsOneWidget);
      expect(find.text('2,000 ل.س'), findsOneWidget);
    });

    testWidgets('paid in another currency: what was handed over and the '
        'rate', (tester) async {
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(
            amount: 136500,
            before: 200000,
            origAmount: 1050,
            origCurrency: 'USD',
            origRate: const RateFraction(13000, 1),
            method: PaymentMethod.transfer,
          )),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('136,500 ل.س'), findsOneWidget);
      expect(find.text('Received as:'), findsOneWidget);
      expect(find.text(r'10.50 $'), findsOneWidget);
      expect(find.text(r'1 $'), findsOneWidget);
      expect(find.text('13,000 ل.س'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });

    testWidgets('a reprint is marked COPY; a reversed payment is marked '
        'cancelled', (tester) async {
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(reversedById: 12)),
          settings: english,
          currencies: testCurrencies,
          isCopy: true,
        ),
        english,
      );
      expect(find.text('COPY'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(payment(reversedById: 12)),
          settings: arabic,
          currencies: testCurrencies,
          isCopy: true,
        ),
        arabic,
      );
      expect(find.text('نسخة'), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
    });

    testWidgets('fits the narrowest paper at the largest font', (tester) async {
      const narrow = InvoiceSettings(
        language: 'ar',
        paperWidthMm: 58,
        baseFontSize: 40,
        shopName: 'بقالة البركة للمواد الغذائية',
      );
      await pump(
        tester,
        ReceiptView(
          receipt: receipt(
            payment(
              amount: 123456789,
              before: 987654321,
              origAmount: 1050000,
              origCurrency: 'USD',
              origRate: const RateFraction(24691, 2),
              note: 'ملاحظة طويلة جداً عن هذه الدفعة وما يتعلق بها',
            ),
            name: 'عبد الرحمن عبد اللطيف الخطيب الدمشقي',
          ),
          settings: narrow,
          currencies: testCurrencies,
          isCopy: true,
        ),
        narrow,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the account statement', () {
    testWidgets('English: brought forward, entries with running balances, '
        'totals, closing', (tester) async {
      await pump(
        tester,
        StatementView(
          data: statement(),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Account statement'), findsOneWidget);
      expect(find.text('Customer:'), findsOneWidget);
      expect(find.text('Ahmad Hasan'), findsOneWidget);
      // The period: first day and LAST day (the end is exclusive).
      expect(find.text('2026/11/01'), findsOneWidget);
      expect(find.text('2026/11/30'), findsOneWidget);
      expect(find.text('Balance brought forward'), findsOneWidget);
      expect(find.text('15,000 ل.س'), findsOneWidget);
      expect(find.text('Invoice 152'), findsOneWidget);
      expect(find.text('Receipt 38'), findsOneWidget);
      expect(find.text('Debit'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);
      expect(find.text('23,000'), findsOneWidget);
      expect(find.text('20,000'), findsOneWidget);
      expect(find.text('Total debits'), findsOneWidget);
      expect(find.text('8,000 ل.س'), findsOneWidget);
      expect(find.text('Total credits'), findsOneWidget);
      expect(find.text('3,000 ل.س'), findsOneWidget);
      expect(find.text('Closing balance'), findsOneWidget);
      expect(find.text('20,000 ل.س'), findsOneWidget);
    });

    testWidgets('Arabic', (tester) async {
      await pump(
        tester,
        StatementView(
          data: statement(name: 'أحمد الحسن'),
          settings: arabic,
          currencies: testCurrencies,
        ),
        arabic,
      );
      expect(find.text('كشف حساب'), findsOneWidget);
      expect(find.text('أحمد الحسن'), findsOneWidget);
      expect(find.text('رصيد سابق'), findsOneWidget);
      expect(find.text('فاتورة 152'), findsOneWidget);
      expect(find.text('سند قبض 38'), findsOneWidget);
      expect(find.text('مدين'), findsOneWidget);
      expect(find.text('دائن'), findsOneWidget);
      expect(find.text('مجموع المدين'), findsOneWidget);
      expect(find.text('مجموع الدائن'), findsOneWidget);
      expect(find.text('الرصيد الختامي'), findsOneWidget);
    });

    testWidgets('an empty period and the whole account', (tester) async {
      await pump(
        tester,
        StatementView(
          data: StatementData(
            statement: const AccountStatement(
              from: null,
              to: null,
              openingBalanceBaseMinor: 0,
              lines: [],
            ),
            customerName: 'Sara',
            baseCurrencyCode: 'SYP',
            printedAt: DateTime(2026, 11, 25),
          ),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Whole account'), findsOneWidget);
      expect(find.text('No entries in this period'), findsOneWidget);
      expect(find.text('0 ل.س'), findsNWidgets(4));
    });

    testWidgets('a cancelled entry and its reversal both stay, the first '
        'one marked', (tester) async {
      final at = DateTime(2026, 11, 10);
      final data = StatementData(
        statement: AccountStatement(
          from: null,
          to: null,
          openingBalanceBaseMinor: 0,
          lines: [
            LedgerLine(
              entry: line(1, DebtEntryType.payment, -1, 500, at,
                  receiptNo: 4, reversedById: 2),
              balanceAfterBaseMinor: -500,
            ),
            LedgerLine(
              entry: line(2, DebtEntryType.reversal, 1, 500, at,
                  reversedType: DebtEntryType.payment, reversedReceiptNo: 4),
              balanceAfterBaseMinor: 0,
            ),
          ],
        ),
        customerName: 'Sara',
        baseCurrencyCode: 'SYP',
        printedAt: DateTime(2026, 11, 25),
      );
      await pump(
        tester,
        StatementView(
          data: data,
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Receipt 4 (Reversed)'), findsOneWidget);
      expect(find.text('Reversal: Receipt 4'), findsOneWidget);
    });

    testWidgets('fits the narrowest paper at the largest font', (tester) async {
      const narrow = InvoiceSettings(
        language: 'ar',
        paperWidthMm: 58,
        baseFontSize: 40,
      );
      await pump(
        tester,
        StatementView(
          data: statement(
            name: 'عبد الرحمن عبد اللطيف الخطيب الدمشقي',
            entries: 6,
          ),
          settings: narrow,
          currencies: testCurrencies,
        ),
        narrow,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the debt lines of the invoice', () {
    Invoice partial({int? prev = 2000, int? next = 7000}) =>
        sypInvoice().copyWith(
          paidMinor: 1003,
          creditUsedMinor: 0,
          prevBalanceBaseMinor: prev,
          newBalanceBaseMinor: next,
        );

    Future<void> pumpInvoice(
      WidgetTester tester,
      Invoice invoice,
      InvoiceSettings s,
    ) =>
        pump(
          tester,
          InvoiceView(invoice: invoice, settings: s, currencies: testCurrencies),
          s,
        );

    testWidgets('by default: paid and remaining, no balances', (tester) async {
      // Two lines of 2 × 1,500 and 2 × 1,501 = 6,002.
      await pumpInvoice(tester, partial(), english);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('1,003 ل.س'), findsOneWidget);
      expect(find.text('Remaining (debt)'), findsOneWidget);
      expect(find.text('4,999 ل.س'), findsOneWidget);
      expect(find.text('Previous balance'), findsNothing);
      expect(find.text('New balance'), findsNothing);
    });

    testWidgets('all four toggles on, in Arabic', (tester) async {
      const s = InvoiceSettings(
        language: 'ar',
        showPreviousBalance: true,
        showNewBalance: true,
      );
      await pumpInvoice(tester, partial(), s);
      expect(find.text('المدفوع'), findsOneWidget);
      expect(find.text('الباقي (دين)'), findsOneWidget);
      expect(find.text('الرصيد السابق'), findsOneWidget);
      expect(find.text('الرصيد الجديد'), findsOneWidget);
      expect(find.text('2,000 ل.س'), findsOneWidget);
      expect(find.text('7,000 ل.س'), findsOneWidget);
      expect(find.text('عليه'), findsNWidgets(2));
    });

    testWidgets('each toggle hides its own line', (tester) async {
      await pumpInvoice(
        tester,
        partial(),
        const InvoiceSettings(
          language: 'en',
          showPaidAmount: false,
          showPreviousBalance: true,
        ),
      );
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Remaining (debt)'), findsOneWidget);
      expect(find.text('Previous balance'), findsOneWidget);
      expect(find.text('New balance'), findsNothing);

      await pumpInvoice(
        tester,
        partial(),
        const InvoiceSettings(
          language: 'en',
          showRemainingAmount: false,
          showNewBalance: true,
        ),
      );
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Remaining (debt)'), findsNothing);
      expect(find.text('Previous balance'), findsNothing);
      expect(find.text('New balance'), findsOneWidget);
    });

    testWidgets('a credit balance used is its own line', (tester) async {
      final invoice = sypInvoice().copyWith(
        paidMinor: 1002,
        creditUsedMinor: 5000,
        prevBalanceBaseMinor: -5000,
        newBalanceBaseMinor: 0,
      );
      await pumpInvoice(
        tester,
        invoice,
        const InvoiceSettings(
          language: 'en',
          showPreviousBalance: true,
          showNewBalance: true,
        ),
      );
      expect(find.text('From credit balance'), findsOneWidget);
      expect(find.text('5,000 ل.س'), findsNWidgets(2));
      expect(find.text('0 ل.س'), findsNWidgets(2), reason: 'remaining + new');
      expect(find.text('credit'), findsOneWidget);
    });

    testWidgets('a sale paid in full prints no debt lines; with the balances '
        'on it still shows what the customer owes', (tester) async {
      final paid = sypInvoice().copyWith(
        paidMinor: 6002,
        creditUsedMinor: 0,
        prevBalanceBaseMinor: 3000,
        newBalanceBaseMinor: 3000,
      );
      await pumpInvoice(tester, paid, english);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Remaining (debt)'), findsNothing);
      await pumpInvoice(
        tester,
        paid,
        const InvoiceSettings(
          language: 'en',
          showPreviousBalance: true,
          showNewBalance: true,
        ),
      );
      expect(find.text('Previous balance'), findsOneWidget);
      expect(find.text('New balance'), findsOneWidget);
      // A customer with no balance at all: nothing to say.
      await pumpInvoice(
        tester,
        sypInvoice().copyWith(
          paidMinor: 6002,
          creditUsedMinor: 0,
          prevBalanceBaseMinor: 0,
          newBalanceBaseMinor: 0,
        ),
        const InvoiceSettings(
          language: 'en',
          showPreviousBalance: true,
          showNewBalance: true,
        ),
      );
      expect(find.text('Previous balance'), findsNothing);
      expect(find.text('New balance'), findsNothing);
    });

    testWidgets('an invoice from before the ledger prints as it always did',
        (tester) async {
      await pumpInvoice(
        tester,
        sypInvoice(),
        const InvoiceSettings(
          language: 'en',
          showPreviousBalance: true,
          showNewBalance: true,
        ),
      );
      for (final label in [
        'Paid',
        'Remaining (debt)',
        'Previous balance',
        'New balance',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    test('with the debt ledger off, the render settings carry no debt line',
        () async {
      final database = await openTestDb();
      for (final key in [
        SettingsKeys.showPreviousBalance,
        SettingsKeys.showNewBalance,
      ]) {
        await database.db.insert('settings', {
          'key': key,
          'value': '1',
          'updated_at': 0,
        });
      }
      addTearDown(FeatureGate.reset);
      for (final on in [true, false]) {
        FeatureGate.applyWithout([if (!on) Feature.debt]);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(database),
          ],
        );
        final settings =
            (await container.read(invoiceRenderContextProvider.future)).settings;
        expect(settings.showPaidAmount, on);
        expect(settings.showRemainingAmount, on);
        expect(settings.showPreviousBalance, on);
        expect(settings.showNewBalance, on);
        container.dispose();
      }
      await database.close();
    });
  });

  group('through the print / share pipeline', () {
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

    Future<void> open(WidgetTester tester, String language) async {
      database = await real(tester, openTestDb);
      await tester.runAsync(() async {
        await database.db.insert(
          'settings',
          {
            'key': SettingsKeys.invoiceLanguage,
            'value': language,
            'updated_at': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
    }

    bool hasInk(RgbaImage image) {
      for (var i = 0; i < image.rgba.length; i += 4) {
        if (image.rgba[i] < 128) return true;
      }
      return false;
    }

    for (final language in ['ar', 'en']) {
      testWidgets('receipt ($language): exact printer width, 2× share image, '
          'PDF, ESC/POS job', (tester) async {
        await open(tester, language);
        final output = container.read(ledgerPaperOutputProvider);
        final paper = receiptPaper(receipt(payment()));

        final printed = await real(tester, () => output.renderForPrinter(paper));
        expect(printed.width, 512);
        expect(printed.height, greaterThan(200));
        expect(hasInk(printed), isTrue);

        final png = await real(tester, () => output.sharePng(paper));
        expect(readPngSize(png)!.width, 2 * 512);

        final pdf = await real(tester, () => output.sharePdf(paper));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

        final job = await real(tester, () => output.printJob(paper));
        expect(job.length, greaterThan(printed.height * 512 ~/ 8));

        // A copy is a taller paper: the COPY box is on it.
        final copy =
            await real(tester, () => output.renderForPrinter(paper, copy: true));
        expect(copy.height, greaterThan(printed.height));
      });

      testWidgets('statement ($language): a long one is one long strip',
          (tester) async {
        await open(tester, language);
        final output = container.read(ledgerPaperOutputProvider);
        final short = statementPaper(statement(), customerId: 1);
        final long = statementPaper(statement(entries: 120), customerId: 1);

        final small = await real(tester, () => output.renderForPrinter(short));
        final big = await real(tester, () => output.renderForPrinter(long));
        expect(small.width, 512);
        expect(big.width, 512);
        // Far taller than one GPU slice (1,024 rows): the capture stitched
        // several, and every one of them has ink.
        expect(big.height, greaterThan(4000));
        expect(big.height, greaterThan(small.height * 10));
        for (var slice = 0; slice < big.height ~/ 1024; slice++) {
          var ink = false;
          final from = slice * 1024 * big.width * 4;
          for (var i = from; i < from + 1024 * big.width * 4; i += 4) {
            if (big.rgba[i] < 128) {
              ink = true;
              break;
            }
          }
          expect(ink, isTrue, reason: 'slice $slice is blank');
        }

        final png = await real(tester, () => output.sharePng(short));
        expect(readPngSize(png)!.width, 2 * 512);
        final pdf = await real(tester, () => output.sharePdf(long));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      });
    }

    testWidgets('file names: the receipt number, a copy apart from the '
        'original', (tester) async {
      await open(tester, 'en');
      final paper = receiptPaper(receipt(payment(receiptNo: 37)));
      expect(paper.fileName, 'receipt-37');
      final statementFile = statementPaper(statement(), customerId: 12).fileName;
      expect(statementFile, 'statement-12-20261125');
      final caption =
          paper.caption(lookupAppLocalizations(const Locale('en')));
      expect(caption, 'Receipt no. 37');
    });
  });
}
