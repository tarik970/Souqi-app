/// Correcting a saved sale without ever deleting it: VOIDING a whole invoice
/// ("إلغاء الفاتورة") and RETURNS ("مرتجع"). No Flutter and no database here —
/// the refund math in this file is unit-tested directly.
///
/// A return is its own document with its own number. Its amounts come from
/// the ORIGINAL invoice — the stored line totals, the stored discount, the
/// invoice's own currency — never from today's prices or rates.
library;

import '../../core/money/exchange.dart';
import '../../core/money/rounding.dart';
import 'invoice.dart';
import 'product.dart';
import 'voucher.dart';

/// How the refund of a return is given back.
enum RefundMethod {
  /// Money handed over the counter. Touches no ledger.
  cash('CASH'),

  /// Taken off what the customer owes; whatever is more than the debt goes
  /// back in cash.
  debt('DEBT'),

  /// Kept on the customer's account, in their favour.
  credit('CREDIT');

  const RefundMethod(this.db);

  final String db;

  static RefundMethod fromDb(String? value) {
    for (final method in values) {
      if (method.db == value) return method;
    }
    return RefundMethod.cash;
  }
}

/// What happens to the card codes of a voided invoice (or of a returned
/// card): VOID them — they were printed and handed over — or put them back
/// in stock, for a card the customer never received.
enum CodeDisposal { voidCode, returnToStock }

/// The invoice is voided: it can be neither voided again nor returned.
class InvoiceVoidedException implements Exception {
  const InvoiceVoidedException(this.invoiceNo);

  final int invoiceNo;

  @override
  String toString() => 'InvoiceVoidedException: invoice $invoiceNo is void';
}

/// The invoice has returns: what is left of it is returned, not voided.
class InvoiceHasReturnsException implements Exception {
  const InvoiceHasReturnsException(this.invoiceNo);

  final int invoiceNo;

  @override
  String toString() =>
      'InvoiceHasReturnsException: invoice $invoiceNo has returns';
}

/// The invoice is older than the "void invoices up to N days old" setting.
class InvoiceTooOldException implements Exception {
  const InvoiceTooOldException(this.maxAgeDays);

  final int maxAgeDays;

  @override
  String toString() =>
      'InvoiceTooOldException: older than $maxAgeDays days';
}

class InvoiceNotFoundException implements Exception {
  const InvoiceNotFoundException(this.invoiceId);

  final int invoiceId;

  @override
  String toString() => 'InvoiceNotFoundException: $invoiceId';
}

/// A return asks for nothing, for a line that is not on the invoice, or for
/// more than is still returnable of a line (sold minus already returned).
class ReturnQuantityException implements Exception {
  const ReturnQuantityException(this.invoiceItemId, this.message);

  /// Null when the return as a whole is empty.
  final int? invoiceItemId;
  final String message;

  @override
  String toString() => 'ReturnQuantityException: $message';
}

/// The card codes chosen for a returned line do not fit it: not on that
/// line, no longer sold, not as many as the cards returned — or cards are
/// returned while their codes would stay with the customer.
class ReturnCodesException implements Exception {
  const ReturnCodesException(this.message);

  final String message;

  @override
  String toString() => 'ReturnCodesException: $message';
}

/// "Reduce the debt" or "keep as credit" needs a customer on the invoice.
class ReturnCustomerRequiredException implements Exception {
  const ReturnCustomerRequiredException();

  @override
  String toString() =>
      'ReturnCustomerRequiredException: the invoice has no customer';
}

/// Why an invoice cannot be voided.
enum VoidBlocker { alreadyVoided, hasReturns, tooOld }

/// The dates a voided (or fully returned) renewal puts back on the account.
class RenewalRestore {
  const RenewalRestore({
    required this.accountId,
    required this.accountNumber,
    required this.applies,
    this.lastRenewalAt,
    this.nextDueAt,
  });

  final int accountId;
  final String accountNumber;

  /// False when the account no longer stands where this invoice left it — a
  /// later renewal (or a date set by hand) is in force and stays.
  final bool applies;

  /// What the account goes back to. Null = it had none.
  final DateTime? lastRenewalAt;
  final DateTime? nextDueAt;
}

/// What voiding an invoice will do — shown before it is confirmed.
class VoidPlan {
  const VoidPlan({
    required this.invoice,
    this.blocker,
    required this.maxAgeDays,
    this.debtBaseMinor = 0,
    this.soldCodes = 0,
    this.renewal,
  });

  final Invoice invoice;

  /// Not null = the invoice cannot be voided, and why.
  final VoidBlocker? blocker;

  /// The age limit in force; 0 = none.
  final int maxAgeDays;

  /// The sale's own debt entry that a REVERSAL will cancel, in base minor
  /// units. 0 = the sale left nothing on the account.
  final int debtBaseMinor;

  /// Card codes still SOLD on the invoice.
  final int soldCodes;

  /// Null = the invoice renewed no account.
  final RenewalRestore? renewal;

  /// Money received at the sale, in the invoice currency: what goes back to
  /// the customer by hand. An invoice saved without a payment (an old one,
  /// or the ledger off) was paid in full.
  int get paidMinor => invoice.paidMinor ?? invoice.totalMinor;

  bool get canVoid => blocker == null;
}

/// One returned line, as asked for: how much of which invoice line, and —
/// for cards sold from code stock — which codes come back and what becomes
/// of each.
class ReturnLineRequest {
  const ReturnLineRequest({
    required this.invoiceItemId,
    required this.qtyThousandths,
    this.codes = const {},
  });

  final int invoiceItemId;
  final int qtyThousandths;

  /// Code id → what happens to it.
  final Map<int, CodeDisposal> codes;
}

/// A return about to be saved.
class ReturnDraft {
  const ReturnDraft({
    required this.invoiceId,
    required this.lines,
    this.method = RefundMethod.cash,
    this.reason,
  });

  final int invoiceId;
  final List<ReturnLineRequest> lines;
  final RefundMethod method;
  final String? reason;

  /// Line id → thousandths, the form the refund math takes.
  Map<int, int> get quantities => {
        for (final line in lines)
          if (line.qtyThousandths > 0) line.invoiceItemId: line.qtyThousandths,
      };
}

/// A line of the invoice with what is still returnable of it.
class ReturnableLine {
  const ReturnableLine({
    required this.item,
    required this.returnedThousandths,
    this.codes = const [],
  });

  final InvoiceItem item;

  /// Already returned by earlier returns.
  final int returnedThousandths;

  /// The card codes still SOLD on this line, masked.
  final List<VoucherCodeView> codes;

  /// Sold minus already returned. Never negative.
  int get remainingThousandths {
    final left = item.qtyThousandths - returnedThousandths;
    return left < 0 ? 0 : left;
  }

  /// Cards of this line are returned by picking their codes.
  bool get hasCodes => codes.isNotEmpty;
}

/// One line of a refund.
class RefundLine {
  const RefundLine({
    required this.item,
    required this.qtyThousandths,
    required this.grossMinor,
    required this.refundMinor,
  });

  final InvoiceItem item;
  final int qtyThousandths;

  /// The returned share of the line total, BEFORE the invoice discount —
  /// what "top products" takes off the product's sales.
  final int grossMinor;

  /// What is given back for it: the returned share of the line total less
  /// its pro-rata share of the invoice discount.
  final int refundMinor;
}

/// What a return gives back, in the invoice currency.
class RefundComputation {
  const RefundComputation({
    required this.lines,
    required this.returnedBeforeMinor,
    required this.returnedAfterMinor,
  });

  final List<RefundLine> lines;

  /// What all earlier returns of the invoice gave back together.
  final int returnedBeforeMinor;

  /// The same, with this return.
  final int returnedAfterMinor;

  /// The refund of THIS return.
  int get refundMinor => returnedAfterMinor - returnedBeforeMinor;
}

/// An exact fraction, for adding line shares up before the one rounding.
class _Fraction {
  const _Fraction(this.numerator, this.denominator);

  final BigInt numerator;

  /// Always > 0.
  final BigInt denominator;

  static final zero = _Fraction(BigInt.zero, BigInt.one);

  _Fraction operator +(_Fraction other) {
    final n = numerator * other.denominator + other.numerator * denominator;
    final d = denominator * other.denominator;
    final g = n.gcd(d);
    return g > BigInt.one ? _Fraction(n ~/ g, d ~/ g) : _Fraction(n, d);
  }

  int round() => divRoundHalfUp(numerator, denominator);
}

/// THE REFUND OF A RETURN, from the original invoice.
///
/// The worth of a quantity `q` of a line is exact:
///
///     lineTotal × (total / subtotal) × (q / soldQty)
///
/// — the line total, less its pro-rata share of the invoice discount, for
/// the part returned. [returnedBefore] and [returning] are thousandths by
/// invoice-item id.
///
/// ONE ROUNDING, AND NOTHING LOST BETWEEN RETURNS: the refund of this return
/// is `round(everything returned so far, this return included)` minus
/// `round(everything returned before)`, each an exact BigInt fraction
/// rounded half-up once. So however an invoice is returned — all at once, or
/// a line and a half today and the rest next week — the refunds add up to
/// exactly what a single full return gives: the invoice total. They can
/// never add up to more than was paid.
///
/// The lines of one return share its total the same way (a running sum,
/// rounded as it goes), so the amounts printed on the document add up to
/// the total printed under them.
///
/// Throws [ReturnQuantityException] for an empty return, a line that is not
/// on the invoice, or more than is still returnable of a line.
RefundComputation computeRefund({
  required Invoice invoice,
  required Map<int, int> returnedBefore,
  required Map<int, int> returning,
}) {
  final asked = {
    for (final entry in returning.entries)
      if (entry.value != 0) entry.key: entry.value,
  };
  if (asked.isEmpty) {
    throw const ReturnQuantityException(null, 'nothing is returned');
  }
  final ids = {for (final item in invoice.items) item.id};
  for (final entry in asked.entries) {
    if (!ids.contains(entry.key)) {
      throw ReturnQuantityException(entry.key, 'not a line of this invoice');
    }
    if (entry.value < 0) {
      throw ReturnQuantityException(entry.key, 'a negative quantity');
    }
  }

  final subtotal = BigInt.from(invoice.subtotalMinor);
  final total = BigInt.from(invoice.totalMinor);

  // What `qty` of `item` is worth, discount share taken off — exactly.
  _Fraction worth(InvoiceItem item, int qty) {
    if (qty == 0 || invoice.subtotalMinor <= 0 || item.qtyThousandths <= 0) {
      return _Fraction.zero;
    }
    return _Fraction(
      BigInt.from(item.lineTotalMinor) * total * BigInt.from(qty),
      subtotal * BigInt.from(item.qtyThousandths),
    );
  }

  // The returned share of the line total, discount left in.
  int gross(InvoiceItem item, int qty) => item.qtyThousandths <= 0
      ? 0
      : divRoundHalfUp(
          BigInt.from(item.lineTotalMinor) * BigInt.from(qty),
          BigInt.from(item.qtyThousandths),
        );

  var running = _Fraction.zero;
  for (final item in invoice.items) {
    final before = returnedBefore[item.id] ?? 0;
    if (before > 0) running += worth(item, before);
  }
  final returnedBeforeMinor = running.round();

  var last = returnedBeforeMinor;
  final lines = <RefundLine>[];
  for (final item in invoice.items) {
    final qty = asked[item.id] ?? 0;
    if (qty == 0) continue;
    final before = returnedBefore[item.id] ?? 0;
    if (before + qty > item.qtyThousandths) {
      throw ReturnQuantityException(
        item.id,
        'returning $qty of ${item.qtyThousandths - before} returnable',
      );
    }
    running += worth(item, qty);
    final rounded = running.round();
    lines.add(RefundLine(
      item: item,
      qtyThousandths: qty,
      grossMinor: gross(item, before + qty) - gross(item, before),
      refundMinor: rounded - last,
    ));
    last = rounded;
  }
  return RefundComputation(
    lines: lines,
    returnedBeforeMinor: returnedBeforeMinor,
    returnedAfterMinor: last,
  );
}

/// The refund of a return in the BASE currency, at the invoice's own stored
/// rate: `base(returned so far) − base(returned before)`, each converted
/// with one rounding — so the returns of an invoice never take more off the
/// statistics than the sale put in, and a complete return takes off exactly
/// the stored `total_base_minor`.
int refundBaseMinor({
  required Invoice invoice,
  required int returnedBeforeMinor,
  required int returnedAfterMinor,
  required int invoiceDecimals,
  required int baseDecimals,
}) {
  int base(int minor) {
    if (minor <= 0) return 0;
    if (minor >= invoice.totalMinor) return invoice.totalBaseMinor;
    if (invoice.currencyCode == invoice.baseCurrencyCode) return minor;
    final converted = toBaseMinor(
      amountMinor: minor,
      fromDecimals: invoiceDecimals,
      fromRate: invoice.rate,
      baseDecimals: baseDecimals,
    );
    return converted > invoice.totalBaseMinor
        ? invoice.totalBaseMinor
        : converted;
  }

  return base(returnedAfterMinor) - base(returnedBeforeMinor);
}

/// A refund divided between cash and the customer's account, in the invoice
/// currency. The three parts always add up to the refund.
class RefundSplit {
  const RefundSplit({
    this.cashMinor = 0,
    this.debtMinor = 0,
    this.creditMinor = 0,
  });

  /// Handed back over the counter.
  final int cashMinor;

  /// Taken off what the customer owes.
  final int debtMinor;

  /// Kept on the account in the customer's favour.
  final int creditMinor;

  /// What goes onto the ledger (a RETURN entry); the rest is cash.
  int get onAccountMinor => debtMinor + creditMinor;

  int get totalMinor => cashMinor + debtMinor + creditMinor;

  /// The method this split amounts to: a "reduce the debt" that found no
  /// debt to reduce is a cash refund.
  RefundMethod get method => creditMinor > 0
      ? RefundMethod.credit
      : debtMinor > 0
          ? RefundMethod.debt
          : RefundMethod.cash;
}

/// Divides [refundMinor] by [method]. [owedMinor] is what the customer owes
/// right now, in the invoice currency (0 when they owe nothing, or when the
/// invoice has no customer): "reduce the debt" takes off as much as that,
/// and the rest goes back in cash.
RefundSplit splitRefund({
  required int refundMinor,
  required RefundMethod method,
  required int owedMinor,
}) {
  switch (method) {
    case RefundMethod.cash:
      return RefundSplit(cashMinor: refundMinor);
    case RefundMethod.debt:
      final owed = owedMinor < 0 ? 0 : owedMinor;
      final off = refundMinor < owed ? refundMinor : owed;
      return RefundSplit(cashMinor: refundMinor - off, debtMinor: off);
    case RefundMethod.credit:
      return RefundSplit(creditMinor: refundMinor);
  }
}

/// The refund method a return opens on: a sale that was (partly) on credit
/// to a customer who still owes reduces the debt first; everything else is
/// refunded in cash.
RefundMethod defaultRefundMethod({
  required Invoice invoice,
  required int owedMinor,
  required bool ledgerOn,
}) =>
    ledgerOn &&
            invoice.customerId != null &&
            invoice.chargedMinor > 0 &&
            owedMinor > 0
        ? RefundMethod.debt
        : RefundMethod.cash;

/// What the return screen needs before it asks "how is it refunded?".
class ReturnPreview {
  const ReturnPreview({
    required this.invoice,
    required this.refund,
    required this.owedMinor,
    required this.hasCustomer,
  });

  final Invoice invoice;
  final RefundComputation refund;

  /// What the customer owes right now, in the invoice currency; 0 without a
  /// customer or a debt.
  final int owedMinor;

  /// The invoice's customer still exists: the refund may go on the account.
  final bool hasCustomer;

  RefundSplit split(RefundMethod method) => splitRefund(
        refundMinor: refund.refundMinor,
        method: method,
        owedMinor: owedMinor,
      );
}

DateTime? _dateOrNull(Object? epochMs) => epochMs == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(epochMs as int, isUtc: true);

/// One line of a saved return: a SNAPSHOT, like an invoice item.
class InvoiceReturnItem {
  const InvoiceReturnItem({
    this.id,
    required this.invoiceItemId,
    this.productId,
    required this.productName,
    this.productCode,
    required this.kind,
    this.unitName,
    required this.qtyThousandths,
    required this.grossMinor,
    required this.refundMinor,
  });

  final int? id;
  final int invoiceItemId;
  final int? productId;
  final String productName;
  final String? productCode;
  final ProductKind kind;
  final String? unitName;
  final int qtyThousandths;

  /// See [RefundLine.grossMinor] and [RefundLine.refundMinor].
  final int grossMinor;
  final int refundMinor;

  static InvoiceReturnItem fromMap(Map<String, Object?> map) =>
      InvoiceReturnItem(
        id: map['id'] as int?,
        invoiceItemId: map['invoice_item_id'] as int,
        productId: map['product_id'] as int?,
        productName: map['product_name'] as String,
        productCode: map['product_code'] as String?,
        kind: ProductKind.fromDb(map['kind'] as String),
        unitName: map['unit_name'] as String?,
        qtyThousandths: map['qty_thousandths'] as int,
        grossMinor: map['gross_minor'] as int,
        refundMinor: map['refund_minor'] as int,
      );
}

/// A saved return ("مرتجع رقم 12 — من فاتورة 152").
class InvoiceReturn {
  const InvoiceReturn({
    required this.id,
    required this.returnNo,
    required this.invoiceId,
    required this.invoiceNo,
    required this.createdAt,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.rate,
    required this.refundMinor,
    required this.refundBaseMinor,
    required this.method,
    this.cashMinor = 0,
    this.debtMinor = 0,
    this.creditMinor = 0,
    this.reason,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.codesVoided = 0,
    this.codesRestocked = 0,
    this.items = const [],
  });

  final int id;

  /// From its own counter: sequential, never reused.
  final int returnNo;
  final int invoiceId;

  /// The number of the invoice it returns from, as a snapshot.
  final int invoiceNo;
  final DateTime createdAt;

  /// The invoice's currency and stored rate.
  final String currencyCode;
  final String baseCurrencyCode;
  final RateFraction rate;

  /// The refund, in the invoice currency and in the base currency.
  final int refundMinor;
  final int refundBaseMinor;

  final RefundMethod method;
  final int cashMinor;
  final int debtMinor;
  final int creditMinor;
  final String? reason;

  final int? customerId;
  final String? customerName;
  final String? customerPhone;

  /// Card codes this return voided and put back in stock.
  final int codesVoided;
  final int codesRestocked;

  final List<InvoiceReturnItem> items;

  /// What went onto the customer's account (a RETURN ledger entry).
  int get onAccountMinor => debtMinor + creditMinor;

  static InvoiceReturn fromMap(
    Map<String, Object?> map, {
    List<InvoiceReturnItem> items = const [],
  }) =>
      InvoiceReturn(
        id: map['id'] as int,
        returnNo: map['return_no'] as int,
        invoiceId: map['invoice_id'] as int,
        invoiceNo: map['invoice_no'] as int,
        createdAt: _dateOrNull(map['created_at'])!,
        currencyCode: map['currency_code'] as String,
        baseCurrencyCode: map['base_currency_code'] as String,
        rate: RateFraction(map['rate_num'] as int, map['rate_den'] as int),
        refundMinor: map['refund_minor'] as int,
        refundBaseMinor: map['refund_base_minor'] as int,
        method: RefundMethod.fromDb(map['refund_method'] as String?),
        cashMinor: (map['cash_minor'] as int?) ?? 0,
        debtMinor: (map['debt_minor'] as int?) ?? 0,
        creditMinor: (map['credit_minor'] as int?) ?? 0,
        reason: map['reason'] as String?,
        customerId: map['customer_id'] as int?,
        customerName: map['customer_name'] as String?,
        customerPhone: map['customer_phone'] as String?,
        codesVoided: (map['codes_voided'] as int?) ?? 0,
        codesRestocked: (map['codes_restocked'] as int?) ?? 0,
        items: items,
      );
}
