import 'package:sqflite/sqflite.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/money/exchange.dart';
import '../../core/utils/due_dates.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/voucher.dart';
import 'audit_repository.dart';
import 'counter_repository.dart';
import 'customer_repository.dart';

/// What [DebtRepository.planSale] worked out for a sale, before anything is
/// written: the balances the invoice row snapshots and the debit to post
/// once the invoice has its id.
class SaleLedgerPlan {
  const SaleLedgerPlan({
    required this.customerId,
    required this.customerName,
    required this.prevBalanceBaseMinor,
    required this.debtBaseMinor,
    required this.origAmountMinor,
    required this.dueAt,
    required this.limitBaseMinor,
    required this.overLimit,
  });

  final int customerId;
  final String customerName;
  final int prevBalanceBaseMinor;

  /// The debit to post, in base minor units. 0 = nothing goes on the account.
  final int debtBaseMinor;

  /// The same amount in the invoice currency, when that is not the base.
  final int? origAmountMinor;
  final DateTime? dueAt;
  final int? limitBaseMinor;

  /// The sale goes over the credit limit and the seller overrode it.
  final bool overLimit;

  int get newBalanceBaseMinor => prevBalanceBaseMinor + debtBaseMinor;
}

/// The customer debt ledger.
///
/// THE RULES THIS CLASS KEEPS
/// - An entry is written once and never changed or removed (the database
///   itself refuses, see `MigrationV5`). A mistake is corrected with
///   [reverse], which writes a REVERSAL entry and a line in the audit log.
/// - A balance is never stored: it is `SUM(amount × direction)` every time.
/// - Everything that writes more than one row runs in one transaction.
///
/// SQL here sticks to what sqlite 3.9 (Android 7) understands: no window
/// functions, no row values, no FILTER. The running balance is accumulated
/// in Dart over one customer's rows; the accounts of ALL customers come out
/// of one grouped pass over the covering `idx_debt_fifo`, and the FIFO
/// allocation itself is [fifoUnpaid] — one definition for the single
/// account and for the whole list.
class DebtRepository {
  DebtRepository(this._db);

  final Database _db;

  static const _counters = CounterRepository();

  /// Rows of a customer's ledger loaded at a time.
  static const int ledgerPageSize = 200;

  /// The list of largest balances on the statistics screen.
  static const int topDebtorsLimit = 10;

  /// "This entry was not cancelled by a reversal." [alias] is the entry.
  static String _notReversed(String alias) =>
      'NOT EXISTS (SELECT 1 FROM debt_transactions rv '
      'WHERE rv.reverses_id = $alias.id)';

  static int _ms(DateTime moment) => moment.toUtc().millisecondsSinceEpoch;

  static String? _blankToNull(String? text) {
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---- Balances ----------------------------------------------------------

  static Future<int> _balance(
    DatabaseExecutor db,
    int customerId, {
    DateTime? before,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_base_minor * direction), 0) AS balance '
      'FROM debt_transactions WHERE customer_id = ?'
      '${before == null ? '' : ' AND created_at < ?'}',
      [customerId, if (before != null) _ms(before)],
    );
    return (rows.first['balance'] as int?) ?? 0;
  }

  /// What [customerId] owes (positive) or is owed (negative), in base minor
  /// units. With [before], the balance of the entries dated earlier.
  Future<int> balanceOf(int customerId, {DateTime? before}) =>
      _balance(_db, customerId, before: before);

  /// Days a new debt of [customerId] is given: the customer's own, else the
  /// shop's default.
  static Future<int> _dueDays(DatabaseExecutor db, int customerId) async {
    final rows = await db.query(
      'customers',
      columns: ['default_due_days'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    final own = rows.isEmpty ? null : rows.first['default_due_days'] as int?;
    if (own != null) return own;
    final setting = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [SettingsKeys.debtDefaultDueDays],
      limit: 1,
    );
    final raw = setting.isEmpty
        ? SettingsKeys.defaults[SettingsKeys.debtDefaultDueDays]
        : setting.first['value'] as String?;
    return int.tryParse(raw ?? '') ?? 30;
  }

  /// The due day [customerId] gets for a debt dated [at].
  Future<DateTime> defaultDueDate(int customerId, DateTime at) async =>
      nextDueAfter(at, await _dueDays(_db, customerId));

  // ---- Writing -----------------------------------------------------------

  static Future<int> _insert(
    DatabaseExecutor db, {
    required int customerId,
    required DebtEntryType type,
    required int direction,
    required int amountBaseMinor,
    int? origAmountMinor,
    String? origCurrencyCode,
    RateFraction? origRate,
    PaymentMethod? paymentMethod,
    DateTime? dueAt,
    int? receiptNo,
    int? balanceBeforeBaseMinor,
    int? invoiceId,
    int? invoiceNo,
    int? reversesId,
    String? note,
    required DateTime createdAt,
    required DateTime recordedAt,
  }) {
    if (amountBaseMinor <= 0) {
      throw ArgumentError.value(
          amountBaseMinor, 'amountBaseMinor', 'must be > 0');
    }
    return db.insert('debt_transactions', {
      'customer_id': customerId,
      'type': type.db,
      'direction': direction,
      'amount_base_minor': amountBaseMinor,
      'orig_amount_minor': origAmountMinor,
      'orig_currency_code': origCurrencyCode,
      'orig_rate_num': origRate?.numerator,
      'orig_rate_den': origRate?.denominator,
      'payment_method': paymentMethod?.db,
      'due_at': dueAt == null ? null : _ms(dueAt),
      'receipt_no': receiptNo,
      'balance_before_base_minor': balanceBeforeBaseMinor,
      'invoice_id': invoiceId,
      'invoice_no': invoiceNo,
      'reverses_id': reversesId,
      'note': _blankToNull(note),
      'created_at': _ms(createdAt),
      'recorded_at': _ms(recordedAt),
    });
  }

  /// An amount handed over in [currencyCode], in base minor units — one
  /// BigInt conversion, rounded half-up once. Throws when it rounds to
  /// nothing: an entry of zero is not an entry.
  static int _toBase({
    required int amountMinor,
    required String currencyCode,
    required int currencyDecimals,
    required RateFraction rate,
    required String baseCode,
    required int baseDecimals,
  }) {
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountMinor, 'amountMinor', 'must be > 0');
    }
    final base = currencyCode == baseCode
        ? amountMinor
        : toBaseMinor(
            amountMinor: amountMinor,
            fromDecimals: currencyDecimals,
            fromRate: rate,
            baseDecimals: baseDecimals,
          );
    if (base <= 0) {
      throw ArgumentError.value(
          amountMinor, 'amountMinor', 'is worth nothing in the base currency');
    }
    return base;
  }

  /// Records a payment and returns it — with its receipt number, drawn from
  /// the persisted counter in the same transaction, so receipt numbers are
  /// sequential and never reused, and with the balance its receipt prints.
  ///
  /// [amountMinor] is in [currencyCode]. When that is not the base currency
  /// the amount is converted with [rate] (base units per 1 unit, exactly as
  /// entered) and both the original amount and the rate are stored.
  ///
  /// A payment larger than the debt is allowed: the customer then has a
  /// credit balance.
  Future<DebtEntry> recordPayment({
    required int customerId,
    required int amountMinor,
    required String currencyCode,
    required int currencyDecimals,
    RateFraction rate = RateFraction.one,
    required String baseCode,
    required int baseDecimals,
    PaymentMethod method = PaymentMethod.cash,
    String? note,
    DateTime? at,
  }) async {
    final amountBase = _toBase(
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      currencyDecimals: currencyDecimals,
      rate: rate,
      baseCode: baseCode,
      baseDecimals: baseDecimals,
    );
    final foreign = currencyCode != baseCode;
    final now = DateTime.now();
    final id = await _db.transaction((txn) async {
      final before = await _balance(txn, customerId);
      final receiptNo = await _counters.next(txn, CounterRepository.receiptNo);
      return _insert(
        txn,
        customerId: customerId,
        type: DebtEntryType.payment,
        direction: -1,
        amountBaseMinor: amountBase,
        origAmountMinor: foreign ? amountMinor : null,
        origCurrencyCode: foreign ? currencyCode : null,
        origRate: foreign ? rate : null,
        paymentMethod: method,
        receiptNo: receiptNo,
        balanceBeforeBaseMinor: before,
        note: note,
        createdAt: at ?? now,
        recordedAt: now,
      );
    });
    return (await entryById(id))!;
  }

  /// A debt with no invoice behind it: a cash loan, an item from before the
  /// app. Due on [dueAt], or after the customer's default number of days.
  Future<DebtEntry> addManualDebt({
    required int customerId,
    required int amountBaseMinor,
    DateTime? dueAt,
    String? note,
    DateTime? at,
  }) =>
      _addDebitOrCredit(
        customerId: customerId,
        type: DebtEntryType.manualDebt,
        direction: 1,
        amountBaseMinor: amountBaseMinor,
        dueAt: dueAt,
        note: note,
        at: at,
      );

  /// What an existing customer owed ([customerOwes]) or was owed when the
  /// shop started using the ledger.
  Future<DebtEntry> addOpeningBalance({
    required int customerId,
    required int amountBaseMinor,
    bool customerOwes = true,
    DateTime? dueAt,
    String? note,
    DateTime? at,
  }) =>
      _addDebitOrCredit(
        customerId: customerId,
        type: DebtEntryType.openingBalance,
        direction: customerOwes ? 1 : -1,
        amountBaseMinor: amountBaseMinor,
        dueAt: dueAt,
        note: note,
        at: at,
      );

  Future<DebtEntry> _addDebitOrCredit({
    required int customerId,
    required DebtEntryType type,
    required int direction,
    required int amountBaseMinor,
    DateTime? dueAt,
    String? note,
    DateTime? at,
    Future<void> Function(Transaction txn, int entryId)? alsoInTransaction,
  }) async {
    final now = DateTime.now();
    final date = at ?? now;
    final id = await _db.transaction((txn) async {
      final entryId = await _insert(
        txn,
        customerId: customerId,
        type: type,
        direction: direction,
        amountBaseMinor: amountBaseMinor,
        // Only a debit can be late.
        dueAt: direction > 0
            ? dueAt ?? nextDueAfter(date, await _dueDays(txn, customerId))
            : null,
        note: note,
        createdAt: date,
        recordedAt: now,
      );
      await alsoInTransaction?.call(txn, entryId);
      return entryId;
    });
    return (await entryById(id))!;
  }

  /// A manual correction of the balance: [increasesDebt] true = the customer
  /// owes more. The [reason] is required, and the correction is written to
  /// the audit log in the same transaction. (The screen asks for the PIN
  /// first.)
  Future<DebtEntry> addAdjustment({
    required int customerId,
    required int amountBaseMinor,
    required bool increasesDebt,
    required String reason,
    DateTime? at,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a reason is required');
    }
    return _addDebitOrCredit(
      customerId: customerId,
      type: DebtEntryType.adjustment,
      direction: increasesDebt ? 1 : -1,
      amountBaseMinor: amountBaseMinor,
      note: why,
      at: at,
      alsoInTransaction: (txn, entryId) async {
        await AuditRepository(txn).log(
          AuditAction.debtAdjustment,
          entityType: 'debt_entry',
          entityId: entryId,
          details: {
            'customer': await _customerName(txn, customerId),
            'amount': increasesDebt ? amountBaseMinor : -amountBaseMinor,
            'reason': why,
          },
        );
      },
    );
  }

  static Future<String?> _customerName(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final rows = await db.query(
      'customers',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['name'] as String?;
  }

  /// One row of the bulk "opening balances" screen: finds the customer —
  /// the one picked, or the one the typed name (and phone) already belongs
  /// to — or creates them, and records the opening balance. One
  /// transaction: no customer is left behind without the balance that was
  /// typed for them.
  Future<OpeningBalanceResult> addOpeningBalanceFor(
    OpeningBalanceDraft draft,
  ) async {
    final name = draft.name.trim();
    if (draft.customerId == null && name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'a name is required');
    }
    final now = DateTime.now();
    final date = draft.date ?? now;
    final (entryId, customerId, customerName, created) =
        await _db.transaction((txn) async {
      final customers = CustomerRepository(txn);
      var created = false;
      Customer? customer;
      if (draft.customerId != null) {
        customer = await customers.getById(draft.customerId!);
        if (customer == null) {
          throw ArgumentError.value(
              draft.customerId, 'customerId', 'no such customer');
        }
      } else {
        customer = await customers.findByNameAndPhone(name, phone: draft.phone);
        if (customer == null) {
          final id = await customers
              .insert(Customer(name: name, phone: _blankToNull(draft.phone)));
          customer = (await customers.getById(id))!;
          created = true;
        }
      }
      // An opening balance for someone who was deactivated: they are a
      // customer again.
      if (!customer.isActive) await customers.setActive(customer.id!, true);
      final entryId = await _insert(
        txn,
        customerId: customer.id!,
        type: DebtEntryType.openingBalance,
        direction: draft.customerOwes ? 1 : -1,
        amountBaseMinor: draft.amountBaseMinor,
        dueAt: draft.customerOwes
            ? nextDueAfter(date, await _dueDays(txn, customer.id!))
            : null,
        createdAt: date,
        recordedAt: now,
      );
      return (entryId, customer.id!, customer.name, created);
    });
    return OpeningBalanceResult(
      entry: (await entryById(entryId))!,
      customerId: customerId,
      customerName: customerName,
      createdCustomer: created,
    );
  }

  /// Cancels entry [entryId] with a REVERSAL entry — the same amount in the
  /// opposite direction, pointing at it — and writes the [reason] to the
  /// audit log, all in one transaction. The cancelled entry itself is not
  /// touched. (The screen asks for the PIN first.)
  ///
  /// Throws [NotReversibleException] for a reversal or for an entry that was
  /// already reversed, and [ArgumentError] without a reason.
  Future<DebtEntry> reverse(int entryId, {required String reason}) async {
    final why = reason.trim();
    if (why.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a reason is required');
    }
    final now = DateTime.now();
    final id = await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT t.*, '
        '(SELECT rv.id FROM debt_transactions rv WHERE rv.reverses_id = t.id) '
        'AS reversed_by_id '
        'FROM debt_transactions t WHERE t.id = ?',
        [entryId],
      );
      if (rows.isEmpty) throw NotReversibleException(entryId);
      final entry = DebtEntry.fromMap(rows.first);
      if (!entry.canBeReversed) throw NotReversibleException(entryId);
      final reversalId = await _insert(
        txn,
        customerId: entry.customerId,
        type: DebtEntryType.reversal,
        direction: -entry.direction,
        amountBaseMinor: entry.amountBaseMinor,
        origAmountMinor: entry.origAmountMinor,
        origCurrencyCode: entry.origCurrencyCode,
        origRate: entry.origRate,
        reversesId: entry.id,
        note: why,
        createdAt: now,
        recordedAt: now,
      );
      await AuditRepository(txn).log(
        AuditAction.debtReversal,
        entityType: 'debt_entry',
        entityId: entry.id,
        details: {
          'customer': await _customerName(txn, entry.customerId),
          'entry': entry.type.db,
          'amount': entry.signedBaseMinor,
          'receipt_no': entry.receiptNo,
          'invoice_no': entry.invoiceNo,
          'reason': why,
        },
      );
      return reversalId;
    });
    return (await entryById(id))!;
  }

  // ---- Sales -------------------------------------------------------------

  /// Works out what [payment] means for the account of the customer on
  /// [draft]: validates it, reads the balance, converts the unpaid part to
  /// the base currency and checks the credit limit. Writes nothing.
  ///
  /// Returns null when the sale has no customer (and so no account): it
  /// must then be paid in full.
  ///
  /// Throws [InvalidSalePaymentException], [DebtCustomerRequiredException]
  /// and [CreditLimitExceededException] — inside the invoice transaction,
  /// which rolls the whole sale back.
  static Future<SaleLedgerPlan?> planSale(
    Transaction txn, {
    required Invoice draft,
    required SalePayment payment,
  }) async {
    final total = draft.totalMinor;
    if (payment.paidMinor < 0 || payment.paidMinor > total) {
      throw InvalidSalePaymentException(
          'paid ${payment.paidMinor} of a total of $total');
    }
    final charged = total - payment.paidMinor;
    if (payment.creditUsedMinor < 0 || payment.creditUsedMinor > charged) {
      throw InvalidSalePaymentException(
          'credit used ${payment.creditUsedMinor} of $charged charged');
    }
    final customerId = draft.customerId;
    if (customerId == null) {
      if (charged > 0) throw const DebtCustomerRequiredException();
      return null;
    }
    final customers = await txn.query(
      'customers',
      columns: ['name', 'credit_limit_base_minor'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customers.isEmpty) {
      if (charged > 0) throw const DebtCustomerRequiredException();
      return null;
    }
    final limit = customers.first['credit_limit_base_minor'] as int?;
    final prev = await _balance(txn, customerId);

    var debtBase = 0;
    int? origAmount;
    if (charged > 0) {
      if (draft.currencyCode == draft.baseCurrencyCode) {
        debtBase = charged;
      } else {
        final decimals = {
          for (final row in await txn.query(
            'currencies',
            columns: ['code', 'decimal_places'],
            where: 'code IN (?, ?)',
            whereArgs: [draft.currencyCode, draft.baseCurrencyCode],
          ))
            row['code'] as String: row['decimal_places'] as int,
        };
        debtBase = toBaseMinor(
          amountMinor: charged,
          fromDecimals: decimals[draft.currencyCode] ?? 0,
          fromRate: draft.rate,
          baseDecimals: decimals[draft.baseCurrencyCode] ?? 0,
        );
        origAmount = charged;
      }
    }

    // The limit only stops NEW debt: a customer already over it can still
    // buy for cash.
    final over = limit != null && debtBase > 0 && prev + debtBase > limit;
    if (over && !payment.overrideCreditLimit) {
      throw CreditLimitExceededException(
        balanceBaseMinor: prev,
        newBalanceBaseMinor: prev + debtBase,
        limitBaseMinor: limit,
      );
    }
    return SaleLedgerPlan(
      customerId: customerId,
      customerName: customers.first['name'] as String,
      prevBalanceBaseMinor: prev,
      debtBaseMinor: debtBase,
      origAmountMinor: debtBase > 0 ? origAmount : null,
      dueAt: debtBase > 0
          ? payment.dueAt ??
              nextDueAfter(draft.createdAt, await _dueDays(txn, customerId))
          : null,
      limitBaseMinor: limit,
      overLimit: over,
    );
  }

  /// Posts what [plan] decided, once the invoice has its id and number: the
  /// DEBT entry, and the audit line of a credit-limit override.
  static Future<void> postSale(
    Transaction txn, {
    required SaleLedgerPlan plan,
    required Invoice draft,
    required int invoiceId,
    required int invoiceNo,
  }) async {
    if (plan.debtBaseMinor <= 0) return;
    final entryId = await _insert(
      txn,
      customerId: plan.customerId,
      type: DebtEntryType.debt,
      direction: 1,
      amountBaseMinor: plan.debtBaseMinor,
      origAmountMinor: plan.origAmountMinor,
      origCurrencyCode:
          plan.origAmountMinor == null ? null : draft.currencyCode,
      origRate: plan.origAmountMinor == null ? null : draft.rate,
      dueAt: plan.dueAt,
      invoiceId: invoiceId,
      invoiceNo: invoiceNo,
      createdAt: draft.createdAt,
      recordedAt: DateTime.now(),
    );
    if (plan.overLimit) {
      await AuditRepository(txn).log(
        AuditAction.creditLimitOverride,
        entityType: 'debt_entry',
        entityId: entryId,
        details: {
          'customer': plan.customerName,
          'invoice_no': invoiceNo,
          'balance': plan.prevBalanceBaseMinor,
          'new_balance': plan.newBalanceBaseMinor,
          'limit': plan.limitBaseMinor,
        },
      );
    }
  }

  // ---- Reading one account -----------------------------------------------

  static const String _entrySelect =
      'SELECT t.*, r.id AS reversed_by_id, o.type AS rv_type, '
      'o.receipt_no AS rv_receipt_no, o.invoice_no AS rv_invoice_no '
      'FROM debt_transactions t '
      'LEFT JOIN debt_transactions r ON r.reverses_id = t.id '
      'LEFT JOIN debt_transactions o ON o.id = t.reverses_id ';

  Future<DebtEntry?> entryById(int id) async {
    final rows = await _db.rawQuery('${_entrySelect}WHERE t.id = ?', [id]);
    return rows.isEmpty ? null : DebtEntry.fromMap(rows.first);
  }

  /// One entry with the balance right after it — for following the link
  /// between an entry and its reversal.
  Future<LedgerLine?> lineById(int id) async {
    final entry = await entryById(id);
    if (entry == null) return null;
    final at = _ms(entry.createdAt);
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount_base_minor * direction), 0) AS balance '
      'FROM debt_transactions WHERE customer_id = ? '
      'AND (created_at < ? OR (created_at = ? AND id <= ?))',
      [entry.customerId, at, at, entry.id],
    );
    return LedgerLine(
      entry: entry,
      balanceAfterBaseMinor: (rows.first['balance'] as int?) ?? 0,
    );
  }

  /// The payment with receipt number [receiptNo], or null.
  Future<DebtEntry?> entryByReceiptNo(int receiptNo) async {
    final rows = await _db
        .rawQuery('${_entrySelect}WHERE t.receipt_no = ?', [receiptNo]);
    return rows.isEmpty ? null : DebtEntry.fromMap(rows.first);
  }

  /// The ledger of [customerId], NEWEST FIRST, each entry with the balance
  /// right after it. [from] inclusive, [to] exclusive.
  ///
  /// The running balance is the true balance of the account — it counts
  /// every entry, whatever the caller then chooses to show. Pass [limit] to
  /// read only the newest rows; the balances are still right, because they
  /// are counted back from the balance at the end of the range.
  Future<List<LedgerLine>> ledger(
    int customerId, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final rows = await _db.rawQuery(
      '${_entrySelect}WHERE t.customer_id = ?'
      '${from == null ? '' : ' AND t.created_at >= ?'}'
      '${to == null ? '' : ' AND t.created_at < ?'} '
      'ORDER BY t.created_at DESC, t.id DESC'
      '${limit == null ? '' : ' LIMIT ?'}',
      [
        customerId,
        if (from != null) _ms(from),
        if (to != null) _ms(to),
        ?limit,
      ],
    );
    var running = await _balance(_db, customerId, before: to);
    final lines = <LedgerLine>[];
    for (final row in rows) {
      final entry = DebtEntry.fromMap(row);
      lines.add(LedgerLine(entry: entry, balanceAfterBaseMinor: running));
      running -= entry.signedBaseMinor;
    }
    return lines;
  }

  /// The account statement of [customerId] for a range: the balance brought
  /// forward, every entry OLDEST FIRST with its running balance, and (on the
  /// result) the totals and the closing balance.
  Future<AccountStatement> statement(
    int customerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final opening =
        from == null ? 0 : await _balance(_db, customerId, before: from);
    final rows = await _db.rawQuery(
      '${_entrySelect}WHERE t.customer_id = ?'
      '${from == null ? '' : ' AND t.created_at >= ?'}'
      '${to == null ? '' : ' AND t.created_at < ?'} '
      'ORDER BY t.created_at ASC, t.id ASC',
      [customerId, if (from != null) _ms(from), if (to != null) _ms(to)],
    );
    var running = opening;
    final lines = <LedgerLine>[];
    for (final row in rows) {
      final entry = DebtEntry.fromMap(row);
      running += entry.signedBaseMinor;
      lines.add(LedgerLine(entry: entry, balanceAfterBaseMinor: running));
    }
    return AccountStatement(
      from: from,
      to: to,
      openingBalanceBaseMinor: opening,
      lines: lines,
    );
  }

  /// Where the account of [customerId] stands at [now]: balance, last
  /// payment, and the FIFO view of what is unpaid (oldest unpaid debt,
  /// overdue amount, aging).
  Future<AccountSummary> accountSummary(
    int customerId, {
    required DateTime now,
  }) async {
    final balance = await _balance(_db, customerId);
    final last = await _db.rawQuery(
      'SELECT MAX(t.created_at) AS at FROM debt_transactions t '
      "WHERE t.customer_id = ? AND t.type = 'PAYMENT' "
      'AND ${_notReversed('t')}',
      [customerId],
    );
    final lastAt = last.first['at'] as int?;
    final lastPaymentAt = lastAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastAt, isUtc: true);
    if (balance <= 0) {
      return AccountSummary(
        balanceBaseMinor: balance,
        lastPaymentAt: lastPaymentAt,
      );
    }
    final rows = await _db.rawQuery(
      'SELECT t.amount_base_minor, t.created_at, t.due_at '
      'FROM debt_transactions t '
      "WHERE t.customer_id = ? AND t.direction = 1 AND t.type != 'REVERSAL' "
      'AND ${_notReversed('t')} '
      'ORDER BY t.created_at ASC, t.id ASC',
      [customerId],
    );
    return summarizeAccount(
      balanceBaseMinor: balance,
      lastPaymentAt: lastPaymentAt,
      now: now,
      debits: [
        for (final row in rows)
          FifoDebit(
            amountBaseMinor: row['amount_base_minor'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
              isUtc: true,
            ),
            dueAt: row['due_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    row['due_at'] as int,
                    isUtc: true,
                  ),
          ),
      ],
    );
  }

  // ---- All accounts ------------------------------------------------------

  /// Every customer with a non-zero balance, in ONE pass over the covering
  /// `idx_debt_fifo`, grouped by customer: the balance, the date of the last
  /// payment, and the customer's effective debits packed into one string
  /// (`created_at id amount due_at`, comma separated) for the FIFO
  /// allocation — which is inherently sequential, and which Dart then does
  /// with the same [fifoUnpaid] the single-account view uses.
  ///
  /// Why packed, and why not SQL all the way: the running sum FIFO needs is
  /// a window function (sqlite 3.25, Android 11 — too new), and the two ways
  /// around it were measured on 200,000 entries: a correlated sum per debit
  /// (2.3 s) and a recursive walk over the unpaid debits (0.6 s, one b-tree
  /// seek per step). This pass only ever reads the index forward (0.2 s),
  /// and hands over one row per customer instead of one per debit.
  ///
  /// "Effective": a cancelled entry and the reversal that cancelled it take
  /// no part in the allocation (the balance is unaffected either way — the
  /// pair nets to zero).
  ///
  /// Returned as text so a test can EXPLAIN exactly what runs.
  static const String accountsQuery =
      'SELECT c.id, c.name, c.name_norm, c.phone, c.phone_norm, c.is_active, '
      'c.credit_limit_base_minor, b.balance, b.last_payment_at, b.debits '
      'FROM (SELECT t.customer_id, '
      '  SUM(t.amount_base_minor * t.direction) AS balance, '
      "  MAX(CASE WHEN t.type = 'PAYMENT' AND NOT EXISTS ("
      '    SELECT 1 FROM debt_transactions rv WHERE rv.reverses_id = t.id) '
      '    THEN t.created_at END) AS last_payment_at, '
      "  group_concat(CASE WHEN t.direction = 1 AND t.type != 'REVERSAL' "
      '    AND NOT EXISTS ('
      '    SELECT 1 FROM debt_transactions rv WHERE rv.reverses_id = t.id) '
      "    THEN t.created_at || ' ' || t.id || ' ' || t.amount_base_minor "
      "      || ' ' || COALESCE(t.due_at, '') END) AS debits "
      '  FROM debt_transactions t GROUP BY t.customer_id) b '
      'JOIN customers c ON c.id = b.customer_id '
      'WHERE b.balance != 0';

  /// Unpacks the `debits` column of [accountsQuery] into ledger order.
  ///
  /// A hand-rolled scan rather than `split`: at 100,000 debits the
  /// substrings alone would be most of the work.
  static List<FifoDebit> unpackDebits(String? packed) {
    if (packed == null || packed.isEmpty) return const [];
    final debits = <FifoDebit>[];
    // (created_at, id) of each debit, to check — and if need be restore —
    // ledger order.
    final keys = <int>[];
    var sorted = true;
    final fields = [0, 0, 0, 0];
    var field = 0;
    var digits = 0;
    void flush() {
      final createdAt = fields[0];
      final id = fields[1];
      if (keys.isNotEmpty) {
        final lastAt = keys[keys.length - 2];
        if (createdAt < lastAt || (createdAt == lastAt && id < keys.last)) {
          sorted = false;
        }
      }
      keys
        ..add(createdAt)
        ..add(id);
      debits.add(FifoDebit(
        amountBaseMinor: fields[2],
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
        // An empty last field is "no due date".
        dueAt: field == 3 && digits > 0
            ? DateTime.fromMillisecondsSinceEpoch(fields[3], isUtc: true)
            : null,
      ));
      fields.fillRange(0, 4, 0);
      field = 0;
      digits = 0;
    }

    for (var i = 0; i < packed.length; i++) {
      final unit = packed.codeUnitAt(i);
      if (unit == 0x2C) {
        flush(); // ','
      } else if (unit == 0x20) {
        field++; // ' '
        digits = 0;
      } else if (field < 4) {
        fields[field] = fields[field] * 10 + (unit - 0x30);
        digits++;
      }
    }
    flush();
    // group_concat hands the values over in the order the index was read,
    // which already is ledger order — sqlite does not promise that, so it is
    // checked, and put right in the case it ever is not.
    if (sorted) return debits;
    final order = [for (var i = 0; i < debits.length; i++) i]
      ..sort((a, b) {
        final byDate = keys[a * 2].compareTo(keys[b * 2]);
        return byDate != 0 ? byDate : keys[a * 2 + 1].compareTo(keys[b * 2 + 1]);
      });
    return [for (final index in order) debits[index]];
  }

  /// Every customer with a non-zero balance, each with their FIFO aging at
  /// [now] — the data behind the debtors list, the home card and the debt
  /// statistics. One aggregate ([accountsQuery]); the list is then sorted,
  /// filtered and searched in memory by whoever shows it.
  Future<DebtorsSnapshot> debtors({required DateTime now}) async {
    final rows = await _db.rawQuery(accountsQuery);
    if (rows.isEmpty) return DebtorsSnapshot.empty(now);
    DateTime? date(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
    // "Today" is worked out once for all of them.
    final clock = AgingClock(now);
    return DebtorsSnapshot(
      at: now,
      debtors: [
        for (final row in rows)
          Debtor(
            customerId: row['id'] as int,
            name: row['name'] as String,
            nameNorm: row['name_norm'] as String,
            phone: _blankToNull(row['phone'] as String?),
            phoneNorm: row['phone_norm'] as String?,
            isActive: row['is_active'] != 0,
            creditLimitBaseMinor: row['credit_limit_base_minor'] as int?,
            account: summarizeAccount(
              balanceBaseMinor: row['balance'] as int,
              lastPaymentAt: date(row['last_payment_at']),
              now: now,
              clock: clock,
              // Only a customer who owes has anything to allocate.
              debits: (row['balance'] as int) > 0
                  ? unpackDebits(row['debits'] as String?)
                  : const [],
            ),
          ),
      ],
    );
  }

  /// Debits and payments dated in a period, cancelled ones left out. A range
  /// read of the covering `idx_debt_created`.
  ///
  /// Returned as text so a test can EXPLAIN exactly what runs.
  static const String periodQuery =
      'SELECT '
      "COALESCE(SUM(CASE WHEN t.direction = 1 AND t.type != 'OPENING_BALANCE' "
      'THEN t.amount_base_minor END), 0) AS new_debt, '
      'COALESCE(SUM(CASE WHEN t.direction = 1 THEN t.amount_base_minor END), 0) '
      'AS debits, '
      "COALESCE(SUM(CASE WHEN t.type = 'PAYMENT' THEN t.amount_base_minor END), 0) "
      'AS collected '
      'FROM debt_transactions t '
      'WHERE t.created_at >= ? AND t.created_at < ? '
      "AND t.type != 'REVERSAL' "
      'AND NOT EXISTS (SELECT 1 FROM debt_transactions rv '
      '  WHERE rv.reverses_id = t.id)';

  /// The debt figures for [from]..[to] (inclusive start, exclusive end),
  /// with "now" figures measured at [now].
  Future<DebtStats> stats({
    required DateTime from,
    required DateTime to,
    required DateTime now,
  }) async {
    final snapshot = await debtors(now: now);
    final period = (await _db.rawQuery(periodQuery, [_ms(from), _ms(to)])).first;
    // What customers owed when the period began: the positive balances of
    // everything dated before it.
    final start = await _db.rawQuery(
      'SELECT COALESCE(SUM(b.balance), 0) AS owed FROM ('
      'SELECT SUM(t.amount_base_minor * t.direction) AS balance '
      'FROM debt_transactions t WHERE t.created_at < ? '
      'GROUP BY t.customer_id) b WHERE b.balance > 0',
      [_ms(from)],
    );
    final top = [
      for (final debtor in snapshot.debtors)
        if (debtor.balanceBaseMinor > 0) debtor,
    ]..sort((a, b) {
        final byAmount = b.balanceBaseMinor.compareTo(a.balanceBaseMinor);
        return byAmount != 0 ? byAmount : a.nameNorm.compareTo(b.nameNorm);
      });
    return DebtStats(
      outstandingBaseMinor: snapshot.totalOutstandingBaseMinor,
      owedAtStartBaseMinor: (start.first['owed'] as int?) ?? 0,
      newDebtBaseMinor: (period['new_debt'] as int?) ?? 0,
      debitsBaseMinor: (period['debits'] as int?) ?? 0,
      collectedBaseMinor: (period['collected'] as int?) ?? 0,
      topDebtors: top.take(topDebtorsLimit).toList(),
      aging: snapshot.aging,
    );
  }

  /// True once the ledger holds anything at all.
  Future<bool> hasEntries() async {
    final rows =
        await _db.rawQuery('SELECT 1 FROM debt_transactions LIMIT 1');
    return rows.isNotEmpty;
  }
}
