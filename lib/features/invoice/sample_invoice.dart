import 'dart:ui' show Locale;

import '../../config/features.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';

int _pow10(int exp) {
  var v = 1;
  for (var i = 0; i < exp; i++) {
    v *= 10;
  }
  return v;
}

/// A believable price in [currency]: [whole] for a currency without decimals
/// (SYP: 8,500), or a hundredth of that scale for one with decimals
/// (USD: 0.85), so the sample never shows absurd amounts.
int _samplePrice(Currency currency, int whole) => currency.decimalPlaces == 0
    ? whole
    : whole * _pow10(currency.decimalPlaces) ~/ 10000;

/// A made-up invoice for the settings preview and the test print.
///
/// It goes through the REAL cart math with the shop's own currencies, so the
/// preview shows exactly how amounts, extra totals and exchange rates will
/// look — including a cross-currency line when the shop has a second
/// currency with a rate. Item and customer names come from the ARB files in
/// the INVOICE language.
Invoice buildSampleInvoice({
  required InvoiceSettings settings,
  required List<Currency> currencies,
  required String baseCode,
  DateTime? now,
}) {
  final l10n = lookupAppLocalizations(Locale(settings.language));
  final ctx = CurrencyContext.of(
    currencies,
    baseCode: baseCode,
    extraCodes: settings.extraCurrencies,
  );
  final base = ctx.base;
  Currency? other;
  for (final currency in currencies) {
    if (currency.code != baseCode &&
        currency.isActive &&
        ctx.hasUsableRate(currency.code)) {
      other = currency;
      break;
    }
  }
  final teaCurrency = other ?? base;

  var cart = const Cart()
      .add(CartLine(
        name: l10n.sampleItemSugar,
        code: '101',
        unitName: l10n.sampleUnitKg,
        unitPriceMinor: _samplePrice(base, 8500),
        priceCurrencyCode: base.code,
        qtyThousandths: 2500,
      ))
      .add(CartLine(
        name: l10n.sampleItemTea,
        code: '102',
        unitName: l10n.sampleUnitBox,
        unitPriceMinor: _samplePrice(teaCurrency, 23000),
        priceCurrencyCode: teaCurrency.code,
        qtyThousandths: 2000,
      ))
      .add(CartLine(
        name: l10n.sampleItemPackage,
        code: '201',
        kind: ProductKind.service,
        unitPriceMinor: _samplePrice(base, 50000),
        priceCurrencyCode: base.code,
        qtyThousandths: 1000,
      ));
  if (discountEnabled) {
    cart = cart.withDiscount(const Discount.percent(500));
  }

  return Invoice.fromCart(
    cart: cart,
    ctx: ctx,
    createdAt: now ?? DateTime.now(),
    customerName: customersEnabled ? l10n.sampleCustomerName : null,
    customerPhone: customersEnabled ? '0944 123 456' : null,
    accountNumber: accountsEnabled ? '0011223344' : null,
  ).copyWith(invoiceNo: 125);
}
