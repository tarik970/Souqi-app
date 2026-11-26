import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/features/debts/debt_output.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/features/returns/return_paper.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The two papers of phase 7 in Arabic and in English: the RETURN document
/// and the "VOID / ملغاة" stamp of a voided invoice — what they say, which
/// way they read, and that they go through the same print / share pipeline
/// as every other paper (exact printer width, 2× share image, PDF).
void main() {
  setUpAll(sqfliteFfiInit);

  const english = InvoiceSettings(language: 'en', shopName: 'Al-Baraka');
  const arabic = InvoiceSettings(language: 'ar', shopName: 'بقالة البركة');

  /// Return no. 12 from invoice 152: 1.5 kg of sugar and one tea.
  InvoiceReturn document({
    int cash = 12000,
    int debt = 0,
    int credit = 0,
    String? reason = 'damaged bag',
    String? name = 'Ahmad Hasan',
    String currency = 'SYP',
  }) =>
      InvoiceReturn(
        id: 5,
        returnNo: 12,
        invoiceId: 3,
        invoiceNo: 152,
        createdAt: DateTime(2026, 11, 27, 16, 30),
        currencyCode: currency,
        baseCurrencyCode: 'SYP',
        rate: currency == 'SYP'
            ? RateFraction.one
            : const RateFraction(13000, 1),
        refundMinor: cash + debt + credit,
        refundBaseMinor: cash + debt + credit,
        method: credit > 0
            ? RefundMethod.credit
            : debt > 0
                ? RefundMethod.debt
                : RefundMethod.cash,
        cashMinor: cash,
        debtMinor: debt,
        creditMinor: credit,
        reason: reason,
        customerId: name == null ? null : 1,
        customerName: name,
        customerPhone: name == null ? null : '0944 123 456',
        items: [
          InvoiceReturnItem(
            id: 1,
            invoiceItemId: 1,
            productName: 'Sugar',
            productCode: '101',
            kind: ProductKind.goods,
            unitName: 'kg',
            qtyThousandths: 1500,
            grossMinor: 12000,
            refundMinor: cash + debt + credit - 1000,
          ),
          const InvoiceReturnItem(
            id: 2,
            invoiceItemId: 2,
            productName: 'Tea',
            kind: ProductKind.goods,
            qtyThousandths: 1000,
            grossMinor: 1000,
            refundMinor: 1000,
          ),
        ],
      );

  Invoice voided({String reason = 'duplicate'}) => sypInvoice().copyWith(
        voidedAt: DateTime(2026, 11, 26, 10, 5),
        voidReason: reason,
      );

  Future<void> pump(WidgetTester tester, Widget paper, InvoiceSettings s) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
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

  TextDirection directionOf(WidgetTester tester, Type paper) => tester
      .widget<Directionality>(
        find
            .descendant(
              of: find.byType(paper),
              matching: find.byType(Directionality),
            )
            .first,
      )
      .textDirection;

  group('the return document', () {
    testWidgets('English: its number, the invoice it comes from, date, '
        'customer, lines, refund and method, reason', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Al-Baraka'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Return no. 12'), findsOneWidget);
      expect(find.text('From invoice 152'), findsOneWidget);
      expect(find.text('2026/11/27 16:30'), findsOneWidget);
      expect(find.text('Customer:'), findsOneWidget);
      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.text('0944 123 456'), findsOneWidget);
      expect(find.text('Sugar'), findsOneWidget);
      expect(find.text('1.5 kg'), findsOneWidget);
      expect(find.text('11,000'), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('Refund total'), findsOneWidget);
      expect(find.text('12,000 ل.س'), findsOneWidget);
      expect(find.text('Refund method:'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Reason:'), findsOneWidget);
      expect(find.text('damaged bag'), findsOneWidget);
      expect(find.text('COPY'), findsNothing);
      expect(directionOf(tester, ReturnView), TextDirection.ltr);
    });

    testWidgets('Arabic: "مرتجع رقم 12 — من فاتورة 152", right to left, '
        'Arabic words', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(name: 'أحمد الحسن', reason: 'كيس تالف'),
          settings: arabic,
          currencies: testCurrencies,
        ),
        arabic,
      );
      expect(find.text('بقالة البركة'), findsOneWidget);
      expect(find.text('مرتجع'), findsOneWidget);
      expect(find.text('مرتجع رقم 12'), findsOneWidget);
      expect(find.text('من فاتورة 152'), findsOneWidget);
      expect(find.text('الزبون:'), findsOneWidget);
      expect(find.text('أحمد الحسن'), findsOneWidget);
      expect(find.text('المبلغ المردود'), findsOneWidget);
      expect(find.text('طريقة الرد:'), findsOneWidget);
      expect(find.text('نقداً'), findsOneWidget);
      expect(find.text('السبب:'), findsOneWidget);
      expect(find.text('كيس تالف'), findsOneWidget);
      // The paper sets its own direction from the invoice language…
      expect(directionOf(tester, ReturnView), TextDirection.rtl);
      // …and a date stays one left-to-right run inside it.
      final date = tester.widget<Text>(find.text('2026/11/27 16:30'));
      expect(date.textDirection, TextDirection.ltr);
    });

    testWidgets('given back two ways: each amount is said', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(cash: 5000, debt: 3000),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('8,000 ل.س'), findsOneWidget);
      expect(find.text("Off the customer's debt"), findsOneWidget);
      expect(find.text('3,000 ل.س'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('5,000 ل.س'), findsOneWidget);
      expect(find.text('Refund method:'), findsNothing);
    });

    testWidgets('kept as credit; no customer, no reason: nothing printed '
        'for them', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(cash: 0, credit: 12000),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Customer credit'), findsOneWidget);

      await pump(
        tester,
        ReturnView(
          document: document(name: null, reason: null),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('Customer:'), findsNothing);
      expect(find.text('Reason:'), findsNothing);
      expect(find.text('Return no. 12'), findsOneWidget);
    });

    testWidgets('a reprint is marked COPY, in both languages', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(),
          settings: english,
          currencies: testCurrencies,
          isCopy: true,
        ),
        english,
      );
      expect(find.text('COPY'), findsOneWidget);
      await pump(
        tester,
        ReturnView(
          document: document(),
          settings: arabic,
          currencies: testCurrencies,
          isCopy: true,
        ),
        arabic,
      );
      expect(find.text('نسخة'), findsOneWidget);
    });

    testWidgets('a refund in dollars keeps its currency', (tester) async {
      await pump(
        tester,
        ReturnView(
          document: document(cash: 385, currency: 'USD'),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text(r'3.85 $'), findsOneWidget);
    });

    for (final (settings, name) in [(english, 'en'), (arabic, 'ar')]) {
      testWidgets('fits a 58 mm paper at a large font ($name)', (tester) async {
        final narrow = InvoiceSettings(
          language: settings.language,
          shopName: settings.shopName,
          paperWidthMm: 58,
          sideMarginMm: 5,
          baseFontSize: 30,
        );
        await pump(
          tester,
          ReturnView(
            document: document(
              cash: 123456789,
              debt: 987654321,
              name: 'عبد الرحمن محمد الأحمد الحسن الطويل',
              reason: 'الزبون أعاد البضاعة لأنها لا تناسبه وطلب استرداد المبلغ',
            ),
            settings: narrow,
            currencies: testCurrencies,
            isCopy: true,
          ),
          narrow,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the VOID stamp on a voided invoice', () {
    testWidgets('English: "VOID", boxed, above everything, with when',
        (tester) async {
      await pump(
        tester,
        InvoiceView(
          invoice: voided(),
          settings: english,
          currencies: testCurrencies,
        ),
        english,
      );
      expect(find.text('VOID'), findsOneWidget);
      final stamp = find.byKey(const ValueKey('paper-void-mark'));
      expect(stamp, findsOneWidget);
      // Above the shop name.
      expect(
        tester.getTopLeft(stamp).dy,
        lessThan(tester.getTopLeft(find.text('Al-Baraka')).dy),
      );
      expect(find.text('Voided on:'), findsOneWidget);
      expect(find.text('2026/11/26 10:05'), findsOneWidget);
      expect(find.text('COPY'), findsNothing);
      // The invoice under it is all still there.
      expect(find.text('Invoice no. 7'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('Arabic: "ملغاة"', (tester) async {
      await pump(
        tester,
        InvoiceView(
          invoice: voided(),
          settings: arabic,
          currencies: testCurrencies,
        ),
        arabic,
      );
      expect(find.text('ملغاة'), findsOneWidget);
      expect(find.text('أُلغيت في:'), findsOneWidget);
      expect(find.text('VOID'), findsNothing);
      expect(directionOf(tester, InvoiceView), TextDirection.rtl);
    });

    testWidgets('a reprint of a voided invoice carries both marks',
        (tester) async {
      for (final (settings, marks) in [
        (english, ['VOID', 'COPY']),
        (arabic, ['ملغاة', 'نسخة']),
      ]) {
        await pump(
          tester,
          InvoiceView(
            invoice: voided(),
            settings: settings,
            currencies: testCurrencies,
            isCopy: true,
          ),
          settings,
        );
        for (final mark in marks) {
          expect(find.text(mark), findsOneWidget, reason: mark);
        }
        // VOID first.
        expect(
          tester.getTopLeft(find.text(marks.first)).dy,
          lessThan(tester.getTopLeft(find.text(marks.last)).dy),
        );
      }
    });

    testWidgets('an invoice that is not voided has no stamp', (tester) async {
      await pump(
        tester,
        InvoiceView(
          invoice: sypInvoice(),
          settings: english,
          currencies: testCurrencies,
          isCopy: true,
        ),
        english,
      );
      expect(find.text('VOID'), findsNothing);
      expect(find.byKey(const ValueKey('paper-void-mark')), findsNothing);
      expect(find.text('Voided on:'), findsNothing);
    });

    testWidgets('fits a 58 mm paper at a large font, both languages',
        (tester) async {
      for (final language in ['ar', 'en']) {
        final narrow = InvoiceSettings(
          language: language,
          paperWidthMm: 58,
          sideMarginMm: 5,
          baseFontSize: 30,
        );
        await pump(
          tester,
          InvoiceView(
            invoice: voided(),
            settings: narrow,
            currencies: testCurrencies,
            isCopy: true,
          ),
          narrow,
        );
        expect(tester.takeException(), isNull, reason: language);
      }
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
      testWidgets('return ($language): exact printer width, 2× share image, '
          'PDF, print job; a copy is marked', (tester) async {
        await open(tester, language);
        final output = container.read(ledgerPaperOutputProvider);
        final paper = returnPaper(document());

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

      testWidgets('voided invoice ($language): the stamp is on the print and '
          'on the shared image', (tester) async {
        await open(tester, language);
        final output = container.read(invoiceOutputProvider);

        final live =
            await real(tester, () => output.renderForPrinter(sypInvoice()));
        final stamped =
            await real(tester, () => output.renderForPrinter(voided()));
        expect(stamped.width, 512);
        expect(stamped.width, live.width);
        // The same invoice, taller by the stamp and its date line.
        expect(stamped.height, greaterThan(live.height + 40));
        expect(hasInk(stamped), isTrue);

        final liveShare = await real(tester, () => output.sharePng(sypInvoice()));
        final voidShare = await real(tester, () => output.sharePng(voided()));
        expect(readPngSize(voidShare)!.width, 2 * 512);
        expect(
          readPngSize(voidShare)!.height,
          greaterThan(readPngSize(liveShare)!.height),
        );
        final pdf = await real(tester, () => output.sharePdf(voided()));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      });
    }

    testWidgets('file name and caption of a return', (tester) async {
      final paper = returnPaper(document());
      expect(paper.fileName, 'return-12');
      expect(paper.customerPhone, '0944 123 456');
      expect(
        paper.caption(lookupAppLocalizations(const Locale('en'))),
        'Return no. 12 — From invoice 152',
      );
      expect(
        paper.caption(lookupAppLocalizations(const Locale('ar'))),
        'مرتجع رقم 12 — من فاتورة 152',
      );
    });
  });
}
