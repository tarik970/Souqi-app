/// A saved sale. Every row here is a SNAPSHOT: product names, codes, units,
/// prices, the invoice currency and every exchange rate used. Changing a
/// product's price or a currency's rate later never alters a saved invoice.
library;

import '../../core/money/exchange.dart';
import '../../core/utils/normalize.dart';
import 'cart.dart';
import 'product.dart';

/// The cart holds a product marked "requires customer account" and the sale
/// has no account attached. The sale screen blocks Save before it gets this
/// far; this is the rule itself, so nothing else can save such a sale either.
class AccountRequiredException implements Exception {
  const AccountRequiredException(this.productName);

  /// The first product that needs the account.
  final String productName;

  @override
  String toString() =>
      'AccountRequiredException: "$productName" requires a customer account';
}

/// The invoice total in one extra currency, with the rate used.
class InvoiceExtraTotal {
  const InvoiceExtraTotal({
    required this.currencyCode,
    required this.rate,
    required this.totalMinor,
  });

  final String currencyCode;
  final RateFraction rate;
  final int totalMinor;
}

class InvoiceItem {
  const InvoiceItem({
    this.id,
    this.productId,
    required this.productName,
    this.productCode,
    required this.kind,
    this.unitName,
    required this.qtyThousandths,
    required this.origUnitPriceMinor,
    required this.origCurrencyCode,
    required this.origRate,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    this.saveAsProduct = false,
    this.unitId,
    this.updateProductPrice = false,
    this.newProductBarcode,
  });

  final int? id;

  /// Null for an item sold without saving a product, or once the product is
  /// hard-deleted.
  final int? productId;

  // --- Catalog instructions --------------------------------------------
  // What saving the invoice should do to the product catalog for this line.
  // They only travel from the cart to InvoiceRepository.save, which carries
  // them out in the invoice's own transaction; they are never stored and are
  // always false / null on an invoice read back from the database.

  /// [productId] is null and the item should become a product: on save it is
  /// linked to an existing product with the same normalized name, or a new
  /// product is created from this line.
  final bool saveAsProduct;

  /// Unit of the product to create (GOODS only).
  final int? unitId;

  /// Set the product's saved price to [origUnitPriceMinor] on save, provided
  /// the product is priced in [origCurrencyCode].
  final bool updateProductPrice;

  /// The barcode the product made from this line gets (an item started
  /// from an unknown barcode).
  final String? newProductBarcode;

  final String productName;
  final String? productCode;
  final ProductKind kind;
  final String? unitName;
  final int qtyThousandths;

  /// The price as entered, in its own currency, with that currency's rate to
  /// base at sale time.
  final int origUnitPriceMinor;
  final String origCurrencyCode;
  final RateFraction origRate;

  /// The same price converted into the invoice currency and rounded on its
  /// own — for display and printing only.
  final int unitPriceMinor;

  /// The line total in the invoice currency: price × quantity × rate with a
  /// single rounding step, NOT [unitPriceMinor] × quantity. Across currencies
  /// the two differ, and this one is the honest amount owed.
  final int lineTotalMinor;

  /// The stored form of this item: its database [id] and the product it ended
  /// up linked to. The catalog instructions are dropped — they are done.
  InvoiceItem saved({required int id, required int? productId}) => InvoiceItem(
        id: id,
        productId: productId,
        productName: productName,
        productCode: productCode,
        kind: kind,
        unitName: unitName,
        qtyThousandths: qtyThousandths,
        origUnitPriceMinor: origUnitPriceMinor,
        origCurrencyCode: origCurrencyCode,
        origRate: origRate,
        unitPriceMinor: unitPriceMinor,
        lineTotalMinor: lineTotalMinor,
      );

  Map<String, Object?> toRow({required int invoiceId, required int sortOrder}) =>
      {
        'invoice_id': invoiceId,
        'product_id': productId,
        'sort_order': sortOrder,
        'product_name': productName,
        // The search/grouping index beside the snapshot, never instead of it.
        'product_name_norm': normalizeName(productName),
        'product_code': productCode,
        'kind': kind.db,
        'unit_name': unitName,
        'qty_thousandths': qtyThousandths,
        'orig_unit_price_minor': origUnitPriceMinor,
        'orig_currency_code': origCurrencyCode,
        'orig_rate_num': origRate.numerator,
        'orig_rate_den': origRate.denominator,
        'unit_price_minor': unitPriceMinor,
        'line_total_minor': lineTotalMinor,
      };

  static InvoiceItem fromMap(Map<String, Object?> map) => InvoiceItem(
        id: map['id'] as int?,
        productId: map['product_id'] as int?,
        productName: map['product_name'] as String,
        productCode: map['product_code'] as String?,
        kind: ProductKind.fromDb(map['kind'] as String),
        unitName: map['unit_name'] as String?,
        qtyThousandths: map['qty_thousandths'] as int,
        origUnitPriceMinor: map['orig_unit_price_minor'] as int,
        origCurrencyCode: map['orig_currency_code'] as String,
        origRate: RateFraction(
          map['orig_rate_num'] as int,
          map['orig_rate_den'] as int,
        ),
        unitPriceMinor: map['unit_price_minor'] as int,
        lineTotalMinor: map['line_total_minor'] as int,
      );
}

class Invoice {
  const Invoice({
    this.id,
    this.invoiceNo = 0,
    required this.createdAt,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.rate,
    required this.subtotalMinor,
    this.discountType,
    this.discountValue,
    this.discountMinor = 0,
    required this.totalMinor,
    required this.totalBaseMinor,
    this.extraTotals = const [],
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.accountId,
    this.accountNumber,
    this.accountProvider,
    this.note,
    this.items = const [],
    this.paidMinor,
    this.creditUsedMinor,
    this.prevBalanceBaseMinor,
    this.newBalanceBaseMinor,
    this.voidedAt,
    this.voidReason,
  });

  final int? id;

  // --- Void ----------------------------------------------------------------
  // A voided invoice is never deleted: it keeps its number and its items and
  // only says that it no longer counts (statistics, reports and totals leave
  // it out). Written by `InvoiceCorrectionRepository.voidInvoice` alone.

  /// When the invoice was voided; null on a live invoice.
  final DateTime? voidedAt;

  /// Why, as it was chosen or typed.
  final String? voidReason;

  bool get isVoided => voidedAt != null;

  /// 0 in a draft; the repository assigns the sequential number on save.
  final int invoiceNo;

  final DateTime createdAt;

  /// The invoice currency and its rate to base, snapshotted.
  final String currencyCode;
  final String baseCurrencyCode;
  final RateFraction rate;

  final int subtotalMinor;
  final DiscountType? discountType;

  /// What the user entered: minor units for an amount, basis points for a
  /// percentage. Kept next to the resolved [discountMinor].
  final int? discountValue;
  final int discountMinor;

  final int totalMinor;
  final int totalBaseMinor;
  final List<InvoiceExtraTotal> extraTotals;

  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final int? accountId;
  final String? accountNumber;
  final String? accountProvider;
  final String? note;

  final List<InvoiceItem> items;

  // --- Payment (debt ledger) ---------------------------------------------
  // Written by InvoiceRepository.save when the sale went through the
  // payment sheet. All null on an invoice saved without it (the debt
  // feature off, or any invoice from before schema version 5), which then
  // prints exactly as it always did.

  /// Money received at the sale, in the invoice currency.
  final int? paidMinor;

  /// How much of the unpaid rest was covered by the customer's credit
  /// balance, in the invoice currency.
  final int? creditUsedMinor;

  /// The customer's balance before and after this sale, in the BASE
  /// currency. Snapshots of what the invoice printed; null without a
  /// customer.
  final int? prevBalanceBaseMinor;
  final int? newBalanceBaseMinor;

  /// What the sale charged to the customer's account: the total less the
  /// money received. 0 for a sale paid in full (and for an old invoice).
  int get chargedMinor => paidMinor == null ? 0 : totalMinor - paidMinor!;

  /// What is still owed for THIS invoice after the money received and the
  /// credit balance used.
  int get remainingMinor => chargedMinor - (creditUsedMinor ?? 0);

  /// The sale was not simply paid in full: the invoice has a payment story
  /// to print (paid / from credit / remaining).
  bool get hasDebtLines => chargedMinor > 0;

  /// Saving this invoice renews the attached account: it is linked to one
  /// and sells at least one SERVICE/CARD item. A customer's account attached
  /// to a sale of goods only (sugar for the man who also has an ADSL line)
  /// is a snapshot on the invoice, not a renewal — it leaves the account's
  /// dates alone.
  bool get renewsAccount =>
      accountId != null &&
      items.any((item) => item.kind == ProductKind.service);

  /// Builds a draft invoice from a cart. Computes the totals itself so the
  /// saved numbers can never drift from what the sale screen showed.
  ///
  /// [updateProductPrices] is the "update product price from sales" setting:
  /// when on, a line whose price the seller changed (and a typed item that
  /// turns out to match an existing product) carries the instruction to
  /// update that product's saved price.
  ///
  /// Throws [StateError] for an empty cart or when a currency in the cart has
  /// no rate yet, and [AccountRequiredException] when the cart holds a
  /// product marked "requires customer account" and no [accountId] is given.
  factory Invoice.fromCart({
    required Cart cart,
    required CurrencyContext ctx,
    required DateTime createdAt,
    bool updateProductPrices = false,
    int? customerId,
    String? customerName,
    String? customerPhone,
    int? accountId,
    String? accountNumber,
    String? accountProvider,
    String? note,
  }) {
    if (cart.isEmpty) {
      throw StateError('cannot save an empty cart');
    }
    if (accountId == null) {
      final needing = cart.linesRequiringAccount;
      if (needing.isNotEmpty) {
        throw AccountRequiredException(needing.first.name);
      }
    }
    final totals = computeCartTotals(cart, ctx);
    if (totals.currenciesNeedingRate.isNotEmpty) {
      final codes = totals.currenciesNeedingRate.map((c) => c.code).join(', ');
      throw StateError('missing exchange rate for $codes');
    }
    return Invoice(
      createdAt: createdAt,
      currencyCode: totals.currency.code,
      baseCurrencyCode: totals.baseCurrency.code,
      rate: totals.currency.rate,
      subtotalMinor: totals.subtotalMinor,
      discountType: cart.discount?.type,
      discountValue: cart.discount?.value,
      discountMinor: totals.discountMinor,
      totalMinor: totals.totalMinor,
      totalBaseMinor: totals.totalBaseMinor,
      extraTotals: [
        for (final extra in totals.extraTotals)
          InvoiceExtraTotal(
            currencyCode: extra.currency.code,
            rate: extra.currency.rate,
            totalMinor: extra.totalMinor,
          ),
      ],
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      accountId: accountId,
      accountNumber: accountNumber,
      accountProvider: accountProvider,
      note: note,
      items: [
        for (final line in totals.lines)
          InvoiceItem(
            productId: line.line.productId,
            productName: line.line.name,
            productCode: line.line.code,
            kind: line.line.kind,
            unitName: line.line.unitName,
            qtyThousandths: line.line.qtyThousandths,
            origUnitPriceMinor: line.line.unitPriceMinor,
            origCurrencyCode: line.line.priceCurrencyCode,
            origRate: line.origRate,
            unitPriceMinor: line.unitPriceMinor,
            lineTotalMinor: line.lineTotalMinor,
            saveAsProduct: line.line.createsProduct,
            unitId: line.line.unitId,
            newProductBarcode:
                line.line.createsProduct ? line.line.barcode : null,
            updateProductPrice: updateProductPrices &&
                (line.line.hasPriceOverride ||
                    (line.line.createsProduct && line.line.unitPriceMinor > 0)),
          ),
      ],
    );
  }

  Invoice copyWith({
    int? id,
    int? invoiceNo,
    List<InvoiceItem>? items,
    int? paidMinor,
    int? creditUsedMinor,
    int? prevBalanceBaseMinor,
    int? newBalanceBaseMinor,
    DateTime? voidedAt,
    String? voidReason,
  }) =>
      Invoice(
        id: id ?? this.id,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        createdAt: createdAt,
        currencyCode: currencyCode,
        baseCurrencyCode: baseCurrencyCode,
        rate: rate,
        subtotalMinor: subtotalMinor,
        discountType: discountType,
        discountValue: discountValue,
        discountMinor: discountMinor,
        totalMinor: totalMinor,
        totalBaseMinor: totalBaseMinor,
        extraTotals: extraTotals,
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        accountId: accountId,
        accountNumber: accountNumber,
        accountProvider: accountProvider,
        note: note,
        items: items ?? this.items,
        paidMinor: paidMinor ?? this.paidMinor,
        creditUsedMinor: creditUsedMinor ?? this.creditUsedMinor,
        prevBalanceBaseMinor: prevBalanceBaseMinor ?? this.prevBalanceBaseMinor,
        newBalanceBaseMinor: newBalanceBaseMinor ?? this.newBalanceBaseMinor,
        voidedAt: voidedAt ?? this.voidedAt,
        voidReason: voidReason ?? this.voidReason,
      );

  /// Row for the `invoices` table. [invoiceNo] is passed separately because
  /// the repository draws it from the counter inside the save transaction.
  Map<String, Object?> toRow({required int invoiceNo}) {
    final extra1 = extraTotals.isNotEmpty ? extraTotals[0] : null;
    final extra2 = extraTotals.length > 1 ? extraTotals[1] : null;
    return {
      'invoice_no': invoiceNo,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch,
      'currency_code': currencyCode,
      'base_currency_code': baseCurrencyCode,
      'rate_num': rate.numerator,
      'rate_den': rate.denominator,
      'subtotal_minor': subtotalMinor,
      'discount_type': discountType?.db,
      'discount_value': discountValue,
      'discount_minor': discountMinor,
      'total_minor': totalMinor,
      'total_base_minor': totalBaseMinor,
      'extra1_currency_code': extra1?.currencyCode,
      'extra1_rate_num': extra1?.rate.numerator,
      'extra1_rate_den': extra1?.rate.denominator,
      'extra1_total_minor': extra1?.totalMinor,
      'extra2_currency_code': extra2?.currencyCode,
      'extra2_rate_num': extra2?.rate.numerator,
      'extra2_rate_den': extra2?.rate.denominator,
      'extra2_total_minor': extra2?.totalMinor,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'account_id': accountId,
      'account_number': accountNumber,
      'account_provider': accountProvider,
      // Search indexes for the archive; the snapshots above stay verbatim.
      'customer_name_norm':
          customerName == null ? null : normalizeName(customerName!),
      'customer_phone_norm':
          customerPhone == null ? null : normalizePhone(customerPhone!),
      'account_number_norm':
          accountNumber == null ? null : normalizeCode(accountNumber!),
      'note': note,
      'paid_minor': paidMinor,
      'credit_used_minor': creditUsedMinor,
      'prev_balance_base_minor': prevBalanceBaseMinor,
      'new_balance_base_minor': newBalanceBaseMinor,
    };
  }

  static Invoice fromMap(
    Map<String, Object?> map, {
    List<InvoiceItem> items = const [],
  }) {
    final discountType = map['discount_type'] as String?;
    final extras = <InvoiceExtraTotal>[];
    for (final prefix in ['extra1', 'extra2']) {
      final code = map['${prefix}_currency_code'] as String?;
      if (code == null) continue;
      extras.add(InvoiceExtraTotal(
        currencyCode: code,
        rate: RateFraction(
          map['${prefix}_rate_num'] as int,
          map['${prefix}_rate_den'] as int,
        ),
        totalMinor: map['${prefix}_total_minor'] as int,
      ));
    }
    return Invoice(
      id: map['id'] as int?,
      invoiceNo: map['invoice_no'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
        isUtc: true,
      ),
      currencyCode: map['currency_code'] as String,
      baseCurrencyCode: map['base_currency_code'] as String,
      rate: RateFraction(map['rate_num'] as int, map['rate_den'] as int),
      subtotalMinor: map['subtotal_minor'] as int,
      discountType:
          discountType == null ? null : DiscountType.fromDb(discountType),
      discountValue: map['discount_value'] as int?,
      discountMinor: (map['discount_minor'] as int?) ?? 0,
      totalMinor: map['total_minor'] as int,
      totalBaseMinor: map['total_base_minor'] as int,
      extraTotals: extras,
      customerId: map['customer_id'] as int?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      accountId: map['account_id'] as int?,
      accountNumber: map['account_number'] as String?,
      accountProvider: map['account_provider'] as String?,
      note: map['note'] as String?,
      items: items,
      paidMinor: map['paid_minor'] as int?,
      creditUsedMinor: map['credit_used_minor'] as int?,
      prevBalanceBaseMinor: map['prev_balance_base_minor'] as int?,
      newBalanceBaseMinor: map['new_balance_base_minor'] as int?,
      voidedAt: map['voided_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['voided_at'] as int,
              isUtc: true,
            ),
      voidReason: map['void_reason'] as String?,
    );
  }
}
