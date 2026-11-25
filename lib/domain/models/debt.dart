/// The customer debt ledger ("دفتر الديون"): entries, balances, FIFO aging,
/// statements. No Flutter and no database here — the math in this file is
/// unit-tested directly, and the repository's SQL is tested against it.
///
/// A balance is always `SUM(amount × direction)` over a customer's entries:
/// POSITIVE = the customer owes the shop ("عليه"), NEGATIVE = the shop owes
/// the customer ("له", a credit / advance). Every amount is base-currency
/// minor units.
library;

import '../../core/money/exchange.dart';

enum DebtEntryType {
  /// The unpaid part of a sale.
  debt('DEBT'),

  /// A debt with no invoice behind it (a cash loan, an old item).
  manualDebt('MANUAL_DEBT'),
  payment('PAYMENT'),

  /// What the customer owed (or was owed) when the shop moved from its paper
  /// notebook.
  openingBalance('OPENING_BALANCE'),

  /// A manual correction, in either direction.
  adjustment('ADJUSTMENT'),

  /// Cancels another entry. Entries are never edited or deleted.
  reversal('REVERSAL');

  const DebtEntryType(this.db);

  final String db;

  static DebtEntryType fromDb(String value) =>
      values.firstWhere((t) => t.db == value);
}

enum PaymentMethod {
  cash('CASH'),
  transfer('TRANSFER'),
  other('OTHER');

  const PaymentMethod(this.db);

  final String db;

  static PaymentMethod? fromDb(String? value) {
    for (final method in values) {
      if (method.db == value) return method;
    }
    return null;
  }
}

DateTime? _dateOrNull(Object? epochMs) => epochMs == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(epochMs as int, isUtc: true);

/// One line of the ledger.
class DebtEntry {
  const DebtEntry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.direction,
    required this.amountBaseMinor,
    this.origAmountMinor,
    this.origCurrencyCode,
    this.origRate,
    this.paymentMethod,
    this.dueAt,
    this.receiptNo,
    this.balanceBeforeBaseMinor,
    this.invoiceId,
    this.invoiceNo,
    this.reversesId,
    this.note,
    required this.createdAt,
    required this.recordedAt,
    this.reversedById,
    this.reversedType,
    this.reversedReceiptNo,
    this.reversedInvoiceNo,
  });

  final int id;
  final int customerId;
  final DebtEntryType type;

  /// +1: the customer owes more (a debit). -1: the customer owes less.
  final int direction;

  /// Always > 0; the sign is [direction].
  final int amountBaseMinor;

  /// What was handed over when it was not the base currency, with the rate
  /// used — snapshots.
  final int? origAmountMinor;
  final String? origCurrencyCode;
  final RateFraction? origRate;

  final PaymentMethod? paymentMethod;

  /// The day a debit is due (the local midnight that starts it).
  final DateTime? dueAt;

  /// The receipt ("سند قبض") number of a payment.
  final int? receiptNo;

  /// What the receipt printed as the previous balance. A document snapshot.
  final int? balanceBeforeBaseMinor;

  /// The live invoice, while it is still in the archive.
  final int? invoiceId;

  /// Its number, kept after the invoice itself is deleted.
  final int? invoiceNo;

  /// The entry this REVERSAL cancels.
  final int? reversesId;
  final String? note;

  /// The date the entry counts from in the account.
  final DateTime createdAt;

  /// When the row was written.
  final DateTime recordedAt;

  /// The REVERSAL that cancelled this entry, if any (joined, not stored).
  final int? reversedById;

  /// For a REVERSAL: what the cancelled entry was (joined, not stored).
  final DebtEntryType? reversedType;
  final int? reversedReceiptNo;
  final int? reversedInvoiceNo;

  int get signedBaseMinor => direction * amountBaseMinor;

  bool get isDebit => direction > 0;

  bool get isReversal => type == DebtEntryType.reversal;

  /// Cancelled by a reversal: shown struck through.
  bool get isReversed => reversedById != null;

  /// Counts as a debt or as a payment: neither cancelled nor a cancellation.
  /// (Both still count towards the BALANCE, where the pair nets to zero.)
  bool get isEffective => !isReversal && !isReversed;

  /// A reversal cannot itself be reversed, and nothing is reversed twice.
  bool get canBeReversed => isEffective;

  /// The balance right after a payment — what its receipt prints.
  int? get balanceAfterBaseMinor => balanceBeforeBaseMinor == null
      ? null
      : balanceBeforeBaseMinor! + signedBaseMinor;

  /// From a `debt_transactions` row, optionally joined with the reversal
  /// that cancelled it (`reversed_by_id`) and the entry it cancels
  /// (`rv_type`, `rv_receipt_no`, `rv_invoice_no`).
  static DebtEntry fromMap(Map<String, Object?> map) {
    final rateNum = map['orig_rate_num'] as int?;
    final rateDen = map['orig_rate_den'] as int?;
    final reversedType = map['rv_type'] as String?;
    return DebtEntry(
      id: map['id'] as int,
      customerId: map['customer_id'] as int,
      type: DebtEntryType.fromDb(map['type'] as String),
      direction: map['direction'] as int,
      amountBaseMinor: map['amount_base_minor'] as int,
      origAmountMinor: map['orig_amount_minor'] as int?,
      origCurrencyCode: map['orig_currency_code'] as String?,
      origRate: rateNum == null || rateDen == null
          ? null
          : RateFraction(rateNum, rateDen),
      paymentMethod: PaymentMethod.fromDb(map['payment_method'] as String?),
      dueAt: _dateOrNull(map['due_at']),
      receiptNo: map['receipt_no'] as int?,
      balanceBeforeBaseMinor: map['balance_before_base_minor'] as int?,
      invoiceId: map['invoice_id'] as int?,
      invoiceNo: map['invoice_no'] as int?,
      reversesId: map['reverses_id'] as int?,
      note: map['note'] as String?,
      createdAt: _dateOrNull(map['created_at'])!,
      recordedAt: _dateOrNull(map['recorded_at'])!,
      reversedById: map['reversed_by_id'] as int?,
      reversedType:
          reversedType == null ? null : DebtEntryType.fromDb(reversedType),
      reversedReceiptNo: map['rv_receipt_no'] as int?,
      reversedInvoiceNo: map['rv_invoice_no'] as int?,
    );
  }
}

/// A ledger entry with the customer's balance right after it.
class LedgerLine {
  const LedgerLine({required this.entry, required this.balanceAfterBaseMinor});

  final DebtEntry entry;
  final int balanceAfterBaseMinor;
}

/// How a sale was paid, as chosen in the payment sheet. Travels with the
/// draft invoice into `InvoiceRepository.save`, which writes the invoice and
/// the ledger entry in one transaction.
class SalePayment {
  const SalePayment({
    required this.paidMinor,
    this.creditUsedMinor = 0,
    this.dueAt,
    this.overrideCreditLimit = false,
  });

  /// Money received now, in the INVOICE currency. The rest of the total is
  /// charged to the customer's account.
  final int paidMinor;

  /// How much of that rest is covered by the customer's credit balance
  /// (invoice currency). Informational: the ledger entry is the same — it is
  /// what the invoice prints as "from credit balance".
  final int creditUsedMinor;

  /// When the new debt is due. Null = the customer's (or the shop's) default
  /// number of days from the sale.
  final DateTime? dueAt;

  /// The seller confirmed the sale although it takes the customer over their
  /// credit limit (with the PIN when one is set). Logged.
  final bool overrideCreditLimit;
}

/// A sale that leaves a debt (or uses a credit balance) needs a customer.
class DebtCustomerRequiredException implements Exception {
  const DebtCustomerRequiredException();

  @override
  String toString() =>
      'DebtCustomerRequiredException: a sale on credit needs a customer';
}

/// The payment does not fit the invoice (negative, or more than the total).
class InvalidSalePaymentException implements Exception {
  const InvalidSalePaymentException(this.message);

  final String message;

  @override
  String toString() => 'InvalidSalePaymentException: $message';
}

/// The new debt would take the customer over their credit limit and the
/// seller has not overridden it. Thrown inside the invoice transaction,
/// which is then rolled back: nothing is saved.
class CreditLimitExceededException implements Exception {
  const CreditLimitExceededException({
    required this.balanceBaseMinor,
    required this.newBalanceBaseMinor,
    required this.limitBaseMinor,
  });

  final int balanceBaseMinor;
  final int newBalanceBaseMinor;
  final int limitBaseMinor;

  @override
  String toString() => 'CreditLimitExceededException: '
      '$newBalanceBaseMinor would exceed the limit of $limitBaseMinor';
}

/// The entry cannot be reversed: it is a reversal itself, or it was already
/// reversed.
class NotReversibleException implements Exception {
  const NotReversibleException(this.entryId);

  final int entryId;

  @override
  String toString() => 'NotReversibleException: entry $entryId';
}

/// The four aging buckets, by the age of a debt in days.
enum AgingBucket {
  /// 0–30 days.
  current,

  /// 31–60 days.
  days31to60,

  /// 61–90 days.
  days61to90,

  /// More than 90 days.
  over90;

  static AgingBucket forAgeDays(int days) {
    if (days <= 30) return AgingBucket.current;
    if (days <= 60) return AgingBucket.days31to60;
    if (days <= 90) return AgingBucket.days61to90;
    return AgingBucket.over90;
  }
}

/// Unpaid amounts by bucket, in base minor units.
class AgingSummary {
  const AgingSummary([this.amounts = const [0, 0, 0, 0]]);

  /// Indexed by [AgingBucket.index].
  final List<int> amounts;

  int operator [](AgingBucket bucket) => amounts[bucket.index];

  int get total => amounts.fold(0, (sum, amount) => sum + amount);

  AgingSummary operator +(AgingSummary other) => AgingSummary([
        for (var i = 0; i < amounts.length; i++) amounts[i] + other.amounts[i],
      ]);

  @override
  bool operator ==(Object other) =>
      other is AgingSummary &&
      other.amounts.length == amounts.length &&
      [for (var i = 0; i < amounts.length; i++) amounts[i] == other.amounts[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hashAll(amounts);

  @override
  String toString() => 'AgingSummary($amounts)';
}

/// A debit as the FIFO allocation sees it.
class FifoDebit {
  const FifoDebit({
    required this.amountBaseMinor,
    required this.createdAt,
    this.dueAt,
  });

  final int amountBaseMinor;
  final DateTime createdAt;
  final DateTime? dueAt;
}

/// What is still unpaid of one debit after the FIFO allocation.
class UnpaidDebit {
  const UnpaidDebit({required this.debit, required this.unpaidBaseMinor});

  final FifoDebit debit;
  final int unpaidBaseMinor;
}

/// Whole days from the local day of [since] to the local day of [now].
int ageInDays(DateTime since, DateTime now) {
  final a = since.toLocal();
  final b = now.toLocal();
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// The local midnight that starts the day of [moment].
DateTime startOfLocalDay(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// FIFO: every credit (payment, credit adjustment…) pays off the OLDEST
/// debits first. Returns what is left unpaid of each debit, oldest first.
///
/// [debits] must be in ledger order (oldest first). [creditsBaseMinor] is
/// the sum of all effective credits. When the credits exceed the debits the
/// customer has a credit balance and nothing is unpaid.
///
/// This is the reference the SQL in `DebtRepository` is tested against.
List<UnpaidDebit> fifoUnpaid(List<FifoDebit> debits, int creditsBaseMinor) {
  var credit = creditsBaseMinor;
  final unpaid = <UnpaidDebit>[];
  for (final debit in debits) {
    if (credit >= debit.amountBaseMinor) {
      credit -= debit.amountBaseMinor;
      continue;
    }
    unpaid.add(UnpaidDebit(
      debit: debit,
      unpaidBaseMinor: debit.amountBaseMinor - credit,
    ));
    credit = 0;
  }
  return unpaid;
}

/// Buckets [unpaid] by the age of each debit at [now].
AgingSummary agingOf(List<UnpaidDebit> unpaid, DateTime now) =>
    AgingClock(now).aging(unpaid);

/// "Today" for ages and due dates, worked out ONCE: the local midnights
/// that start today and the days 30, 60 and 90 days ago.
///
/// A debit's bucket is then a comparison of two integers. Asking the system
/// for the local date of every debit instead (what [ageInDays] does, and
/// what this agrees with to the day) costs a time-zone lookup each time —
/// at a hundred thousand debits that was most of the debtors list.
class AgingClock {
  AgingClock(this.now) {
    final local = now.toLocal();
    int startOf(int daysAgo) =>
        DateTime(local.year, local.month, local.day - daysAgo)
            .millisecondsSinceEpoch;
    _today = startOf(0);
    _day30 = startOf(30);
    _day60 = startOf(60);
    _day90 = startOf(90);
  }

  final DateTime now;
  late final int _today;
  late final int _day30;
  late final int _day60;
  late final int _day90;

  /// The bucket of a debt dated [createdAt]: 0–30 days old means dated on
  /// or after the day 30 days ago, and so on.
  AgingBucket bucketOf(DateTime createdAt) {
    final at = createdAt.millisecondsSinceEpoch;
    if (at >= _day30) return AgingBucket.current;
    if (at >= _day60) return AgingBucket.days31to60;
    if (at >= _day90) return AgingBucket.days61to90;
    return AgingBucket.over90;
  }

  /// Past its due day: the due day is before today. A debt due today is not
  /// late yet, and one without a due day never is.
  bool isOverdue(DateTime? dueAt) =>
      dueAt != null && dueAt.millisecondsSinceEpoch < _today;

  AgingSummary aging(List<UnpaidDebit> unpaid) {
    final amounts = [0, 0, 0, 0];
    for (final item in unpaid) {
      amounts[bucketOf(item.debit.createdAt).index] += item.unpaidBaseMinor;
    }
    return AgingSummary(amounts);
  }
}

/// The summary of one account from its balance and its EFFECTIVE debits in
/// ledger order (oldest first): FIFO decides what is unpaid, and from that
/// come the oldest unpaid debt, the overdue amount and the aging.
///
/// The credits are not passed in: they are whatever separates the debits
/// from the balance. Pass [clock] when summarizing many accounts at the
/// same moment.
AccountSummary summarizeAccount({
  required int balanceBaseMinor,
  required List<FifoDebit> debits,
  required DateTime now,
  DateTime? lastPaymentAt,
  AgingClock? clock,
}) {
  if (balanceBaseMinor <= 0) {
    return AccountSummary(
      balanceBaseMinor: balanceBaseMinor,
      lastPaymentAt: lastPaymentAt,
    );
  }
  var total = 0;
  for (final debit in debits) {
    total += debit.amountBaseMinor;
  }
  final credits = total - balanceBaseMinor;
  final unpaid = fifoUnpaid(debits, credits < 0 ? 0 : credits);
  final at = clock ?? AgingClock(now);
  var overdue = 0;
  for (final item in unpaid) {
    if (at.isOverdue(item.debit.dueAt)) overdue += item.unpaidBaseMinor;
  }
  return AccountSummary(
    balanceBaseMinor: balanceBaseMinor,
    lastPaymentAt: lastPaymentAt,
    oldestUnpaidAt: unpaid.isEmpty ? null : unpaid.first.debit.createdAt,
    overdueBaseMinor: overdue,
    aging: at.aging(unpaid),
  );
}

/// Where one customer's account stands.
class AccountSummary {
  const AccountSummary({
    required this.balanceBaseMinor,
    this.lastPaymentAt,
    this.oldestUnpaidAt,
    this.overdueBaseMinor = 0,
    this.aging = const AgingSummary(),
  });

  /// Positive: the customer owes. Negative: the shop owes the customer.
  final int balanceBaseMinor;
  final DateTime? lastPaymentAt;

  /// The date of the oldest debit that is not fully paid (FIFO).
  final DateTime? oldestUnpaidAt;

  /// The part of the balance that is past its due day.
  final int overdueBaseMinor;
  final AgingSummary aging;

  bool get owes => balanceBaseMinor > 0;

  bool get hasCredit => balanceBaseMinor < 0;

  bool get isOverdue => overdueBaseMinor > 0;

  /// What the shop owes the customer, as a positive number (0 when none).
  int get creditBaseMinor => balanceBaseMinor < 0 ? -balanceBaseMinor : 0;
}

/// One row of the debtors list.
class Debtor {
  const Debtor({
    required this.customerId,
    required this.name,
    required this.nameNorm,
    this.phone,
    this.phoneNorm,
    required this.isActive,
    this.creditLimitBaseMinor,
    required this.account,
  });

  final int customerId;
  final String name;
  final String nameNorm;
  final String? phone;
  final String? phoneNorm;
  final bool isActive;
  final int? creditLimitBaseMinor;
  final AccountSummary account;

  int get balanceBaseMinor => account.balanceBaseMinor;

  bool get isOverLimit =>
      creditLimitBaseMinor != null &&
      account.balanceBaseMinor > creditLimitBaseMinor!;
}

/// Every customer with a non-zero balance, with the totals over them.
class DebtorsSnapshot {
  const DebtorsSnapshot({required this.debtors, required this.at});

  const DebtorsSnapshot.empty(this.at) : debtors = const [];

  final List<Debtor> debtors;

  /// The moment ages and "overdue" were measured at.
  final DateTime at;

  /// The sum of what customers owe (credit balances are not netted off: the
  /// money the shop owes one customer does not reduce what another owes).
  int get totalOutstandingBaseMinor => debtors.fold(
        0,
        (sum, d) => d.balanceBaseMinor > 0 ? sum + d.balanceBaseMinor : sum,
      );

  /// The sum of what the shop owes customers, as a positive number.
  int get totalCreditBaseMinor => debtors.fold(
        0,
        (sum, d) => d.balanceBaseMinor < 0 ? sum - d.balanceBaseMinor : sum,
      );

  int get owingCount => debtors.where((d) => d.balanceBaseMinor > 0).length;

  int get overdueCount => debtors.where((d) => d.account.isOverdue).length;

  AgingSummary get aging => debtors.fold(
        const AgingSummary(),
        (sum, d) => sum + d.account.aging,
      );
}

/// An account statement ("كشف حساب") for a date range.
class AccountStatement {
  const AccountStatement({
    required this.from,
    required this.to,
    required this.openingBalanceBaseMinor,
    required this.lines,
  });

  /// Inclusive start, exclusive end. Null = unbounded on that side.
  final DateTime? from;
  final DateTime? to;

  /// The balance of everything before [from].
  final int openingBalanceBaseMinor;

  /// Every entry in the range, oldest first, with its running balance.
  final List<LedgerLine> lines;

  int get totalDebitsBaseMinor => lines.fold(
        0,
        (sum, l) => l.entry.isDebit ? sum + l.entry.amountBaseMinor : sum,
      );

  int get totalCreditsBaseMinor => lines.fold(
        0,
        (sum, l) => l.entry.isDebit ? sum : sum + l.entry.amountBaseMinor,
      );

  int get closingBalanceBaseMinor =>
      lines.isEmpty ? openingBalanceBaseMinor : lines.last.balanceAfterBaseMinor;
}

/// The debt figures of the statistics screen.
class DebtStats {
  const DebtStats({
    required this.outstandingBaseMinor,
    required this.owedAtStartBaseMinor,
    required this.newDebtBaseMinor,
    required this.debitsBaseMinor,
    required this.collectedBaseMinor,
    required this.topDebtors,
    required this.aging,
  });

  /// What customers owe right now (not tied to the period).
  final int outstandingBaseMinor;

  /// What customers owed when the period began.
  final int owedAtStartBaseMinor;

  /// Debt MADE in the period: sales on credit, manual debts and debit
  /// adjustments that were not reversed. Opening balances are not new debt —
  /// they are old debt being written down.
  final int newDebtBaseMinor;

  /// Every debit dated in the period, opening balances included.
  final int debitsBaseMinor;

  /// Payments received in the period that were not reversed.
  final int collectedBaseMinor;

  /// The ten largest balances.
  final List<Debtor> topDebtors;
  final AgingSummary aging;

  /// Collected in the period ÷ what there was to collect in it (what was
  /// owed when it began + every debit dated in it), in basis points
  /// (10000 = 100%), never above 100%. Null when there was nothing to
  /// collect.
  int? get collectionRateBasisPoints {
    final collectable = owedAtStartBaseMinor + debitsBaseMinor;
    if (collectable <= 0) return null;
    final rate = (collectedBaseMinor * 10000 + collectable ~/ 2) ~/ collectable;
    return rate > 10000 ? 10000 : rate;
  }
}

/// What recording a sale did to the customer's account.
class SaleLedgerResult {
  const SaleLedgerResult({
    required this.prevBalanceBaseMinor,
    required this.newBalanceBaseMinor,
    required this.debtBaseMinor,
  });

  final int prevBalanceBaseMinor;
  final int newBalanceBaseMinor;

  /// The debit written to the ledger (0 = none).
  final int debtBaseMinor;
}

/// One row typed into the bulk "opening balances" screen.
class OpeningBalanceDraft {
  const OpeningBalanceDraft({
    this.customerId,
    required this.name,
    this.phone,
    required this.amountBaseMinor,
    this.customerOwes = true,
    this.date,
  });

  /// An existing customer picked from the search; null = by [name].
  final int? customerId;
  final String name;
  final String? phone;
  final int amountBaseMinor;

  /// False = the shop owes the customer (a credit balance).
  final bool customerOwes;
  final DateTime? date;
}

/// What saving an [OpeningBalanceDraft] did.
class OpeningBalanceResult {
  const OpeningBalanceResult({
    required this.entry,
    required this.customerId,
    required this.customerName,
    required this.createdCustomer,
  });

  final DebtEntry entry;
  final int customerId;
  final String customerName;

  /// False when the name matched an existing customer (the duplicate guard).
  final bool createdCustomer;
}
