/// The sale cart: an immutable value object plus the pure math that turns it
/// into totals. No Flutter, no database — everything here is unit-testable.
///
/// Money is INTEGER minor units of its own currency, quantities are INTEGER
/// thousandths. Every line keeps its price in the PRODUCT's currency; the
/// conversion to the invoice currency happens in [computeCartTotals] using the
/// currencies' current exact rates, so updating a rate re-prices the whole
/// cart with no stored state to refresh.
library;

import '../../core/money/exchange.dart';
import '../../core/money/quantity.dart';
import 'currency.dart';
import 'product.dart';

enum DiscountType {
  amount('AMOUNT'),
  percent('PERCENT');

  const DiscountType(this.db);

  final String db;

  static DiscountType fromDb(String value) =>
      values.firstWhere((t) => t.db == value);
}

/// A per-invoice discount: either a fixed amount in the invoice currency's
/// minor units, or a percentage in basis points (1000 = 10.00%).
class Discount {
  const Discount.amount(this.value)
      : type = DiscountType.amount,
        assert(value >= 0, 'discount amount must be >= 0');

  const Discount.percent(this.value)
      : type = DiscountType.percent,
        assert(value >= 0 && value <= 10000, 'basis points must be 0..10000');

  const Discount._(this.type, this.value);

  final DiscountType type;

  /// Minor units for [DiscountType.amount], basis points for
  /// [DiscountType.percent].
  final int value;

  static Discount fromDb(String type, int value) =>
      Discount._(DiscountType.fromDb(type), value);

  bool get isZero => value == 0;

  @override
  bool operator ==(Object other) =>
      other is Discount && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}

/// One cart line. [id] is assigned by [Cart.add]; callers build lines with the
/// default id of 0.
class CartLine {
  const CartLine({
    this.id = 0,
    this.productId,
    required this.name,
    this.code,
    this.kind = ProductKind.goods,
    this.unitId,
    this.unitName,
    required this.unitPriceMinor,
    required this.priceCurrencyCode,
    required this.qtyThousandths,
    this.saveAsProduct = false,
    this.listPriceMinor,
    this.listCurrencyCode,
    this.requiresAccount = false,
    this.codeStock = false,
    this.barcode,
  });

  /// Stable identity inside one cart (not a database id).
  final int id;

  /// Null for an item typed directly into the sale ("type-to-sell") that is
  /// not a saved product yet.
  final int? productId;

  final String name;
  final String? code;
  final ProductKind kind;

  /// The unit behind [unitName]. Only needed for an item typed into the sale,
  /// so the product created from it gets the same unit.
  final int? unitId;
  final String? unitName;

  /// Unit price in minor units of [priceCurrencyCode]. Editable per sale.
  final int unitPriceMinor;
  final String priceCurrencyCode;
  final int qtyThousandths;

  /// For a typed item ([productId] null): save it as a product when the
  /// invoice is saved. False = sold once, nothing is added to the catalog.
  final bool saveAsProduct;

  /// The saved product's price and currency when the line was added. Null for
  /// a typed item. Lets the cart tell a price the seller changed from one
  /// that simply is the product's price.
  final int? listPriceMinor;
  final String? listCurrencyCode;

  /// The product is marked "requires customer account": the sale cannot be
  /// saved until a customer's card / account is attached to it.
  final bool requiresAccount;

  /// The product is "sold from code stock": every unit sold takes one
  /// prepaid card code when the invoice is saved. Such a line is sold in
  /// whole cards and never beyond what is in stock.
  final bool codeStock;

  /// For a typed item started from an unknown barcode ("new product with
  /// this barcode"): the product created on save gets it.
  final String? barcode;

  /// A typed item that becomes a product when the invoice is saved.
  bool get createsProduct => productId == null && saveAsProduct;

  /// The seller changed the unit price of a saved product, still in the
  /// product's own currency. With "update product price from sales" on, this
  /// price replaces the product's saved one when the invoice is saved.
  ///
  /// A price of zero never counts: giving an item away must not wipe the
  /// price the shop normally sells it for.
  bool get hasPriceOverride =>
      productId != null &&
      listPriceMinor != null &&
      listCurrencyCode == priceCurrencyCode &&
      unitPriceMinor != listPriceMinor &&
      unitPriceMinor > 0;

  /// Same saved product, same unit, same unit price, same currency →
  /// quantities merge. Unsaved items (no [productId]) never merge, so each
  /// typed line stays on its own row.
  ///
  /// The unit is part of it because the quantity sheet can change it per line:
  /// 2 bags and 3 kg of the same sugar are two rows, not five of something.
  bool mergesWith(CartLine other) =>
      productId != null &&
      other.productId == productId &&
      other.unitId == unitId &&
      other.unitPriceMinor == unitPriceMinor &&
      other.priceCurrencyCode == priceCurrencyCode;

  CartLine copyWith({
    int? id,
    int? Function()? productId,
    String? name,
    String? Function()? code,
    ProductKind? kind,
    int? Function()? unitId,
    String? Function()? unitName,
    int? unitPriceMinor,
    String? priceCurrencyCode,
    int? qtyThousandths,
    bool? saveAsProduct,
  }) {
    return CartLine(
      id: id ?? this.id,
      productId: productId != null ? productId() : this.productId,
      name: name ?? this.name,
      code: code != null ? code() : this.code,
      kind: kind ?? this.kind,
      unitId: unitId != null ? unitId() : this.unitId,
      unitName: unitName != null ? unitName() : this.unitName,
      unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
      priceCurrencyCode: priceCurrencyCode ?? this.priceCurrencyCode,
      qtyThousandths: qtyThousandths ?? this.qtyThousandths,
      saveAsProduct: saveAsProduct ?? this.saveAsProduct,
      listPriceMinor: listPriceMinor,
      listCurrencyCode: listCurrencyCode,
      requiresAccount: requiresAccount,
      codeStock: codeStock,
      barcode: barcode,
    );
  }
}

/// Everything the cart math needs to know about currencies: the live table,
/// which code is base, and up to two optional extra display currencies.
class CurrencyContext {
  const CurrencyContext({
    required this.byCode,
    required this.baseCode,
    this.extraCodes = const [],
  });

  CurrencyContext.of(
    Iterable<Currency> currencies, {
    required this.baseCode,
    this.extraCodes = const [],
  }) : byCode = {for (final c in currencies) c.code: c};

  final Map<String, Currency> byCode;
  final String baseCode;

  /// Extra currencies shown under the main total (max 2, see invoice settings).
  final List<String> extraCodes;

  Currency get base => require(baseCode);

  Currency? lookup(String code) => byCode[code];

  Currency require(String code) {
    final currency = byCode[code];
    if (currency == null) {
      throw ArgumentError.value(code, 'code', 'unknown currency');
    }
    return currency;
  }

  /// A currency may be used in a sale only once its rate has been entered.
  /// The base currency is always usable (its rate is 1/1 by definition).
  bool hasUsableRate(String code) {
    if (code == baseCode) return true;
    return byCode[code]?.rateUpdatedAt != null;
  }
}

/// The cart. Every mutator returns a new instance.
class Cart {
  const Cart({
    this.lines = const [],
    this.discount,
    this.invoiceCurrencyCode,
    this.nextLineId = 1,
  });

  final List<CartLine> lines;

  /// Null when no discount is set (or the discount feature is off).
  final Discount? discount;

  /// Null means "follow the base currency", which is the default per sale.
  final String? invoiceCurrencyCode;

  final int nextLineId;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  String effectiveCurrencyCode(CurrencyContext ctx) =>
      invoiceCurrencyCode ?? ctx.baseCode;

  /// The lines that cannot be sold without a customer account attached
  /// (products marked "requires customer account"). While this is not empty
  /// and the sale has no account, the sale must not be saved.
  List<CartLine> get linesRequiringAccount =>
      [for (final line in lines) if (line.requiresAccount) line];

  /// Whole cards each "sold from code stock" product has in this cart, by
  /// product id — summed over its lines, because the same card at two
  /// prices is two lines drawing on one stock.
  Map<int, int> get codeStockQuantities {
    final wanted = <int, int>{};
    for (final line in lines) {
      final id = line.productId;
      if (!line.codeStock || id == null) continue;
      // Rounded up: half a card still needs a whole one to exist.
      wanted[id] = (wanted[id] ?? 0) + (line.qtyThousandths + 999) ~/ 1000;
    }
    return wanted;
  }

  CartLine? lineById(int id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }

  /// Adds [line], merging into an existing line when [CartLine.mergesWith]
  /// says they are the same product at the same price.
  Cart add(CartLine line) {
    if (line.qtyThousandths <= 0) {
      throw ArgumentError.value(
          line.qtyThousandths, 'qtyThousandths', 'must be > 0');
    }
    final index = lines.indexWhere((l) => l.mergesWith(line));
    if (index >= 0) {
      final existing = lines[index];
      final merged = existing.copyWith(
        qtyThousandths: existing.qtyThousandths + line.qtyThousandths,
      );
      return _copy(lines: [...lines]..[index] = merged);
    }
    return _copy(
      lines: [...lines, line.copyWith(id: nextLineId)],
      nextLineId: nextLineId + 1,
    );
  }

  /// Replaces the line with the same [CartLine.id]. If the edit makes it
  /// identical to another line, the two fold together at the earlier
  /// position. Unknown ids are ignored.
  Cart replace(CartLine line) {
    if (line.qtyThousandths <= 0) {
      throw ArgumentError.value(
          line.qtyThousandths, 'qtyThousandths', 'must be > 0');
    }
    final index = lines.indexWhere((l) => l.id == line.id);
    if (index < 0) return this;
    final updated = [...lines]..[index] = line;
    final twin = updated.indexWhere(
      (l) => l.id != line.id && l.mergesWith(line),
    );
    if (twin < 0) return _copy(lines: updated);
    final target = updated[twin];
    updated[twin] = target.copyWith(
      qtyThousandths: target.qtyThousandths + line.qtyThousandths,
    );
    updated.removeWhere((l) => l.id == line.id);
    return _copy(lines: updated);
  }

  Cart setQuantity(int lineId, int qtyThousandths) {
    final line = lineById(lineId);
    if (line == null) return this;
    if (qtyThousandths <= 0) return remove(lineId);
    return replace(line.copyWith(qtyThousandths: qtyThousandths));
  }

  Cart remove(int lineId) =>
      _copy(lines: lines.where((l) => l.id != lineId).toList());

  /// Empties the lines and the discount but keeps the chosen invoice currency
  /// and the line-id sequence.
  Cart clear() => Cart(
        invoiceCurrencyCode: invoiceCurrencyCode,
        nextLineId: nextLineId,
      );

  Cart withDiscount(Discount? discount) => Cart(
        lines: lines,
        discount: discount,
        invoiceCurrencyCode: invoiceCurrencyCode,
        nextLineId: nextLineId,
      );

  Cart withInvoiceCurrency(String? code) => Cart(
        lines: lines,
        discount: discount,
        invoiceCurrencyCode: code,
        nextLineId: nextLineId,
      );

  Cart _copy({List<CartLine>? lines, int? nextLineId}) => Cart(
        lines: lines ?? this.lines,
        discount: discount,
        invoiceCurrencyCode: invoiceCurrencyCode,
        nextLineId: nextLineId ?? this.nextLineId,
      );
}

/// One line priced into the invoice currency.
class LineTotals {
  const LineTotals({
    required this.line,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    required this.origDecimals,
    required this.origRate,
  });

  final CartLine line;

  /// Unit price converted into the invoice currency's minor units, rounded on
  /// its own. DISPLAY ONLY — [lineTotalMinor] is not derived from it.
  final int unitPriceMinor;

  /// The line total in the invoice currency: price × quantity × rate with a
  /// single rounding step, so the per-unit rounding error is not multiplied
  /// by the quantity. Equals `round(price * qty / 1000)` when the line's
  /// currency is already the invoice currency.
  final int lineTotalMinor;

  /// Snapshot of the original currency's decimals and rate to base.
  final int origDecimals;
  final RateFraction origRate;
}

/// The invoice total expressed in one extra display currency.
class ExtraTotal {
  const ExtraTotal({required this.currency, required this.totalMinor});

  final Currency currency;
  final int totalMinor;
}

/// The fully computed cart.
class CartTotals {
  const CartTotals({
    required this.currency,
    required this.baseCurrency,
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.totalBaseMinor,
    required this.extraTotals,
    required this.currenciesNeedingRate,
  });

  /// The invoice currency.
  final Currency currency;
  final Currency baseCurrency;
  final List<LineTotals> lines;
  final int subtotalMinor;

  /// Never larger than [subtotalMinor], so [totalMinor] is never negative.
  final int discountMinor;
  final int totalMinor;
  final int totalBaseMinor;
  final List<ExtraTotal> extraTotals;

  /// Currencies used by this cart whose rate has never been entered. While
  /// this is not empty the sale must not be saved.
  final List<Currency> currenciesNeedingRate;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

/// Prices every line into the invoice currency and sums the cart.
///
/// Per line, two independent numbers — the same two the invoice stores and
/// the receipt prints:
/// - the unit price converted into the invoice currency, rounded on its own,
///   shown to the customer;
/// - the line total, where price × quantity × rate run through ONE BigInt
///   fraction with a single half-up rounding step. The total is never
///   `displayedUnitPrice × qty`: that would multiply the per-unit rounding
///   error by the quantity.
///
/// So a receipt can legitimately read "0.38 × 10 = 3.85" when the line was
/// priced in another currency; the total is the honest conversion of
/// 10 × 5000 SYP, and the unit price is the rounded display of one unit.
CartTotals computeCartTotals(Cart cart, CurrencyContext ctx) {
  final invoice = ctx.require(cart.effectiveCurrencyCode(ctx));
  final base = ctx.base;

  final needRate = <String, Currency>{};
  if (!ctx.hasUsableRate(invoice.code)) {
    needRate[invoice.code] = invoice;
  }

  final lineTotals = <LineTotals>[];
  var subtotal = 0;
  for (final line in cart.lines) {
    final from = ctx.require(line.priceCurrencyCode);
    if (!ctx.hasUsableRate(from.code)) {
      needRate[from.code] = from;
    }
    final unitPrice = convertMinor(
      amountMinor: line.unitPriceMinor,
      fromDecimals: from.decimalPlaces,
      fromRate: from.rate,
      toDecimals: invoice.decimalPlaces,
      toRate: invoice.rate,
    );
    final total = convertLineTotalMinor(
      unitPriceMinor: line.unitPriceMinor,
      qtyThousandths: line.qtyThousandths,
      fromDecimals: from.decimalPlaces,
      fromRate: from.rate,
      toDecimals: invoice.decimalPlaces,
      toRate: invoice.rate,
    );
    subtotal += total;
    lineTotals.add(LineTotals(
      line: line,
      unitPriceMinor: unitPrice,
      lineTotalMinor: total,
      origDecimals: from.decimalPlaces,
      origRate: from.rate,
    ));
  }

  var discountMinor = 0;
  final discount = cart.discount;
  if (discount != null) {
    discountMinor = switch (discount.type) {
      DiscountType.amount => discount.value,
      DiscountType.percent => percentDiscountMinor(
          subtotalMinor: subtotal,
          basisPoints: discount.value,
        ),
    };
    if (discountMinor > subtotal) discountMinor = subtotal;
  }
  final total = subtotal - discountMinor;

  final totalBase = convertMinor(
    amountMinor: total,
    fromDecimals: invoice.decimalPlaces,
    fromRate: invoice.rate,
    toDecimals: base.decimalPlaces,
    toRate: base.rate,
  );

  final extras = <ExtraTotal>[];
  for (final code in ctx.extraCodes.take(2)) {
    final extra = ctx.lookup(code);
    if (extra == null || extra.code == invoice.code) continue;
    if (!ctx.hasUsableRate(extra.code)) continue;
    extras.add(ExtraTotal(
      currency: extra,
      totalMinor: convertMinor(
        amountMinor: total,
        fromDecimals: invoice.decimalPlaces,
        fromRate: invoice.rate,
        toDecimals: extra.decimalPlaces,
        toRate: extra.rate,
      ),
    ));
  }

  return CartTotals(
    currency: invoice,
    baseCurrency: base,
    lines: lineTotals,
    subtotalMinor: subtotal,
    discountMinor: discountMinor,
    totalMinor: total,
    totalBaseMinor: totalBase,
    extraTotals: extras,
    currenciesNeedingRate: needRate.values.toList(),
  );
}
