import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/features/invoice/invoice_text.dart';

import 'invoice_test_utils.dart';

void main() {
  InvoiceMoney money({
    CurrencyDisplay display = CurrencyDisplay.code,
    String locale = 'en',
  }) =>
      InvoiceMoney(currencies: testCurrencies, display: display, locale: locale);

  group('describeInvoiceLine', () {
    test('a cross-currency line prints the ORIGINAL price and currency', () {
      final invoice = crossCurrencyInvoice();
      final sugar = invoice.items[0];
      // The stored numbers: 5,000 SYP is 0.38 USD when rounded on its own,
      // but 10 of them are 3.85 USD — so "10 × 0.38" must never be printed.
      expect(sugar.unitPriceMinor, 38);
      expect(sugar.lineTotalMinor, 385);

      final line = describeInvoiceLine(
        sugar,
        invoiceCurrencyCode: invoice.currencyCode,
        money: money(),
        showUnit: false,
      );
      expect(line.isCrossCurrency, isTrue);
      expect(line.plain, '10 × 5,000 SYP  3.85 USD');
      expect(line.plain, isNot(contains('0.38')));
      // No "=" anywhere: the total simply sits at the end of the line.
      expect(line.plain, isNot(contains('=')));
    });

    test('a same-currency line is "qty × unit price" then the total', () {
      final invoice = crossCurrencyInvoice();
      final line = describeInvoiceLine(
        invoice.items[1],
        invoiceCurrencyCode: invoice.currencyCode,
        money: money(),
      );
      expect(line.isCrossCurrency, isFalse);
      expect(line.plain, '2 × 2.50  5.00');
    });

    test('currencies follow the symbol / code setting', () {
      final invoice = crossCurrencyInvoice();
      final line = describeInvoiceLine(
        invoice.items[0],
        invoiceCurrencyCode: invoice.currencyCode,
        money: money(display: CurrencyDisplay.symbol),
        showUnit: false,
      );
      expect(line.plain, r'10 × 5,000 ل.س  3.85 $');
    });

    test('the unit is part of the quantity when units are shown', () {
      final invoice = crossCurrencyInvoice();
      expect(
        describeInvoiceLine(
          invoice.items[0],
          invoiceCurrencyCode: invoice.currencyCode,
          money: money(),
        ).plain,
        '10 kg × 5,000 SYP  3.85 USD',
      );
    });

    test('hiding unit prices leaves quantity and total', () {
      final invoice = crossCurrencyInvoice();
      final line = describeInvoiceLine(
        invoice.items[0],
        invoiceCurrencyCode: invoice.currencyCode,
        money: money(),
        showUnitPrice: false,
      );
      expect(line.unitPrice, isNull);
      expect(line.quantity, '10 kg');
      expect(line.total, '3.85');
    });

    test('a currency missing from the table falls back to its code', () {
      final invoice = crossCurrencyInvoice();
      final line = describeInvoiceLine(
        invoice.items[0],
        invoiceCurrencyCode: invoice.currencyCode,
        money: InvoiceMoney(
          currencies: {'USD': usd},
          display: CurrencyDisplay.symbol,
          locale: 'en',
        ),
        showUnit: false,
      );
      expect(line.plain, r'10 × 5,000 SYP  3.85 $');
    });
  });

  group('invoiceRatesUsed', () {
    test('a cross-currency invoice lists the rate that explains it', () {
      final rates = invoiceRatesUsed(crossCurrencyInvoice());
      expect(rates, hasLength(1));
      expect(rates.single.code, 'USD');
      expect(rates.single.rate, const RateFraction(13000, 1));
    });

    test('an invoice in one currency prints no rate', () {
      expect(invoiceRatesUsed(sypInvoice()), isEmpty);
    });

    test('an extra total brings its rate', () {
      final ctxInvoice = sypInvoice();
      expect(ctxInvoice.extraTotals, isEmpty);
      final withExtra = crossCurrencyInvoice(extraCodes: ['SYP']);
      // Invoice in USD, total also shown in SYP (the base): one rate line.
      expect(withExtra.extraTotals.single.currencyCode, 'SYP');
      final rates = invoiceRatesUsed(withExtra);
      expect(rates.map((r) => r.code), ['USD']);
    });
  });

  group('formatting helpers', () {
    test('date and time are numeric and the same in every language', () {
      final moment = DateTime(2026, 3, 5, 9, 7);
      expect(formatInvoiceDateTime(moment, locale: 'en'), '2026/03/05 09:07');
      expect(formatInvoiceDateTime(moment, locale: 'ar'), '2026/03/05 09:07');
    });

    test('spaced phone numbers are pinned left-to-right, nothing else', () {
      final lri = String.fromCharCode(0x2066);
      final pdi = String.fromCharCode(0x2069);
      expect(
        isolateSpacedNumbers('هاتف 011 222 3333'),
        'هاتف ${lri}011 222 3333$pdi',
      );
      expect(
        isolateSpacedNumbers('Tel +963 944 123 456 / (011) 222 3333'),
        'Tel $lri+963 944 123 456$pdi / $lri(011) 222 3333$pdi',
      );
      expect(
        isolateSpacedNumbers('٠٩٤٤ ١٢٣ ٤٥٦'),
        '$lri٠٩٤٤ ١٢٣ ٤٥٦$pdi',
      );
      // No spaces inside the number, a range, plain text: untouched.
      expect(isolateSpacedNumbers('هاتف 0944123456'), 'هاتف 0944123456');
      expect(isolateSpacedNumbers('9:00 - 17:00'), '9:00 - 17:00');
      expect(isolateSpacedNumbers('شكراً لزيارتكم'), 'شكراً لزيارتكم');
      expect(isolateSpacedNumbers(''), '');
    });

    test('basis points read as a percentage', () {
      expect(formatBasisPoints(1000, locale: 'en'), '10');
      expect(formatBasisPoints(1250, locale: 'en'), '12.5');
      expect(formatBasisPoints(5, locale: 'en'), '0.05');
    });
  });

  group('InvoiceSettings storage', () {
    test('an empty table gives the documented defaults', () {
      final s = InvoiceSettings.fromMap(const {});
      expect(s.paperWidthMm, 80);
      expect(s.printerDpi, 203);
      expect(s.sideMarginMm, 3.5);
      expect(s.printableDotsOverride, isNull);
      expect(s.printableDots, 576);
      expect(s.language, 'ar');
      expect(s.outputMode, OutputMode.print);
      expect(s.currencyDisplay, CurrencyDisplay.symbol);
      expect(s.defaultCountryCode, '963');
      expect(s.shareWidthMm, isNull);
      expect(s.cutPaper, isFalse);
      expect(s.feedLines, 3);
      expect(s.hasPrinter, isFalse);
      expect(s.logoPng, isNull);
    });

    test('every field survives a round trip through the settings table', () {
      const original = InvoiceSettings(
        paperWidthMm: 57.5,
        printerDpi: 180,
        sideMarginMm: 4.25,
        printableDotsOverride: 360,
        feedLines: 5,
        cutPaper: true,
        printerAddress: 'AA:BB:CC:DD:EE:FF',
        printerName: 'XP-P323B',
        baseFontSize: 26,
        shopName: 'دكان أبو أحمد',
        headerText: 'line 1\nline 2',
        footerText: 'شكراً لزيارتكم',
        language: 'en',
        showItemCode: true,
        showUnit: false,
        showUnitPrice: false,
        showDateTime: false,
        showInvoiceNumber: false,
        showCustomerName: false,
        showCustomerPhone: false,
        showAccountNumber: false,
        maskAccountNumber: true,
        showPoweredBy: false,
        currencyDisplay: CurrencyDisplay.code,
        extraCurrencies: ['USD', 'TRY'],
        outputMode: OutputMode.both,
        shareWidthMm: 80,
        defaultCountryCode: '90',
      );
      final restored = InvoiceSettings.fromMap(original.toMap());
      expect(restored.toMap(), original.toMap());
      expect(restored.paperWidthMm, 57.5);
      expect(restored.sideMarginMm, 4.25);
      expect(restored.printableDotsOverride, 360);
      expect(restored.extraCurrencies, ['USD', 'TRY']);
      expect(restored.outputMode, OutputMode.both);
      expect(restored.shareWidthMm, 80);
      expect(restored.printerAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('garbage in the table falls back instead of crashing', () {
      final s = InvoiceSettings.fromMap(const {
        SettingsKeys.paperWidthMm: 'wide',
        SettingsKeys.printerDpi: '-3',
        SettingsKeys.sideMarginMm: 'x',
        SettingsKeys.extraTotalCurrencies: '{not json',
        SettingsKeys.shopLogoBase64: '!!!',
        SettingsKeys.outputMode: 'FAX',
        SettingsKeys.baseFontSize: '900',
        SettingsKeys.invoiceLanguage: 'fr',
      });
      expect(s.paperWidthMm, 80);
      expect(s.printerDpi, 100);
      expect(s.sideMarginMm, 3.5);
      expect(s.extraCurrencies, isEmpty);
      expect(s.logoPng, isNull);
      expect(s.outputMode, OutputMode.print);
      expect(s.baseFontSize, InvoiceSettings.maxFontSize);
      expect(s.language, 'ar');
    });

    test('at most two extra currencies are kept', () {
      final s = InvoiceSettings.fromMap(const {
        SettingsKeys.extraTotalCurrencies: '["USD","TRY","EUR","USD"]',
      });
      expect(s.extraCurrencies, ['USD', 'TRY']);
    });
  });
}
