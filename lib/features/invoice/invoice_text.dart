/// The words and numbers on an invoice, as plain strings. No widgets here, so
/// the wording rules are unit-tested directly and shared by every surface:
/// the thermal print, the shared image/PDF and the on-screen view.
library;

import '../../core/money/exchange.dart';
import '../../core/money/money_format.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';

/// Formats amounts for one invoice: which label a currency gets (symbol or
/// code, per the setting) and how many decimals it has.
class InvoiceMoney {
  const InvoiceMoney({
    required this.currencies,
    required this.display,
    required this.locale,
  });

  /// The live currency table by code. A currency missing from it (deleted
  /// since the sale) falls back to its code and 0 decimals.
  final Map<String, Currency> currencies;
  final CurrencyDisplay display;

  /// The INVOICE language — decides digit shapes and separators.
  final String locale;

  String label(String code) {
    final currency = currencies[code];
    if (display == CurrencyDisplay.code ||
        currency == null ||
        currency.symbol.isEmpty) {
      return code;
    }
    return currency.symbol;
  }

  int decimals(String code) => currencies[code]?.decimalPlaces ?? 0;

  String amount(int minor, String code, {bool withCurrency = true}) =>
      formatMinor(
        minor,
        decimals: decimals(code),
        locale: locale,
        symbol: withCurrency ? label(code) : '',
      );
}

/// The three parts of an item's detail line.
class InvoiceLineText {
  const InvoiceLineText({
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.isCrossCurrency,
  });

  /// "10", or "10 kg" when units are shown.
  final String quantity;

  /// Null when unit prices are hidden.
  final String? unitPrice;
  final String total;

  /// The item was priced in a currency other than the invoice's.
  final bool isCrossCurrency;

  /// The whole line as one string, the way it reads on paper: no "=" — the
  /// quantity and price sit at the start of the line, the total at its end.
  String get plain =>
      unitPrice == null ? '$quantity  $total' : '$quantity × $unitPrice  $total';
}

/// Words one item's detail line.
///
/// Same-currency line: "qty × unit price" then the total, all in the invoice
/// currency (which the Total line names).
///
/// Cross-currency line: the ORIGINAL unit price in its own currency and the
/// converted total, each with its currency — "10 × 5,000 SYP" … "3.85 USD".
/// The converted unit price is deliberately not printed: it is rounded on
/// its own, so "10 × 0.38" → "3.85" would not multiply out, while the original
/// price times the quantity at the printed rate does.
InvoiceLineText describeInvoiceLine(
  InvoiceItem item, {
  required String invoiceCurrencyCode,
  required InvoiceMoney money,
  bool showUnit = true,
  bool showUnitPrice = true,
}) {
  final cross = item.origCurrencyCode != invoiceCurrencyCode;
  final qty = formatQuantity(item.qtyThousandths, locale: money.locale);
  final unit = item.unitName;
  final quantity =
      showUnit && unit != null && unit.isNotEmpty ? '$qty $unit' : qty;

  String? unitPrice;
  if (showUnitPrice) {
    unitPrice = cross
        ? money.amount(item.origUnitPriceMinor, item.origCurrencyCode)
        : money.amount(
            item.unitPriceMinor,
            invoiceCurrencyCode,
            withCurrency: false,
          );
  }
  return InvoiceLineText(
    quantity: quantity,
    unitPrice: unitPrice,
    total: money.amount(
      item.lineTotalMinor,
      invoiceCurrencyCode,
      withCurrency: cross && showUnitPrice,
    ),
    isCrossCurrency: cross,
  );
}

/// One "1 USD = 13,000 SYP" line: [rate] base units per 1 unit of [code].
class InvoiceRateLine {
  const InvoiceRateLine({required this.code, required this.rate});

  final String code;
  final RateFraction rate;
}

/// The exchange rates a reader needs to check the invoice's arithmetic, from
/// the SNAPSHOT stored with the invoice (never today's rates).
///
/// Rates only matter when the invoice shows amounts in more than one
/// currency: a cross-currency item, or the total in an extra currency. Then
/// every non-base currency involved is listed once, the invoice currency
/// first. An invoice entirely in one currency prints no rate at all.
List<InvoiceRateLine> invoiceRatesUsed(Invoice invoice) {
  final rates = <String, RateFraction>{};
  for (final item in invoice.items) {
    if (item.origCurrencyCode != invoice.currencyCode) {
      rates[item.origCurrencyCode] = item.origRate;
    }
  }
  for (final extra in invoice.extraTotals) {
    rates[extra.currencyCode] = extra.rate;
  }
  if (rates.isEmpty) return const [];
  return [
    if (invoice.currencyCode != invoice.baseCurrencyCode)
      InvoiceRateLine(code: invoice.currencyCode, rate: invoice.rate),
    for (final entry in rates.entries)
      if (entry.key != invoice.baseCurrencyCode &&
          entry.key != invoice.currencyCode)
        InvoiceRateLine(code: entry.key, rate: entry.value),
  ];
}

/// "2026/11/24 14:35" — numeric, 24-hour, the same in every language (only
/// the digit shapes follow [locale]). Needs no locale data to be loaded.
String formatInvoiceDateTime(DateTime moment, {required String locale}) {
  final t = moment.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return localizeDigits(
    '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}',
    locale,
  );
}

/// LEFT-TO-RIGHT ISOLATE and POP DIRECTIONAL ISOLATE.
final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

/// One group of a spaced number: digits (Western, Arabic-Indic or Persian),
/// optionally with a leading '+' and/or wrapped in parentheses.
const _numberGroup = r'\(?\+?[0-9٠-٩۰-۹]+\)?';

final _spacedNumber = RegExp('$_numberGroup(?: $_numberGroup)+');

/// Keeps a number typed in space-separated groups — a phone number such as
/// "011 222 3333" — in the order it was typed.
///
/// Next to Arabic text the Unicode bidi algorithm lays digit groups out
/// right to left, so that number would print as "3333 222 011". Wrapping the
/// run in LEFT-TO-RIGHT ISOLATE … POP DIRECTIONAL ISOLATE (invisible control
/// characters) pins its order in both invoice directions. Numbers without
/// spaces, and ranges such as "9:00 - 17:00", are left untouched.
///
/// Used for the free-text header and footer, where shops put their phone.
String isolateSpacedNumbers(String text) => text.replaceAllMapped(
      _spacedNumber,
      (match) => '$_lri${match[0]}$_pdi',
    );

/// A percentage held as basis points (1000 → "10", 1250 → "12.5").
String formatBasisPoints(int basisPoints, {required String locale}) {
  final whole = basisPoints ~/ 100;
  var frac = (basisPoints % 100).toString().padLeft(2, '0');
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  return localizeDigits(frac.isEmpty ? '$whole' : '$whole.$frac', locale);
}
