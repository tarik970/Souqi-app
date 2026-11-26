import 'package:sqflite/sqflite.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/licensing/license_status.dart';
import '../../core/money/exchange.dart';
import '../../core/security/code_cipher.dart';
import '../../core/utils/due_dates.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_return.dart';
import '../../domain/models/product.dart';
import '../../domain/models/voucher.dart';
import 'archive_repository.dart';
import 'audit_repository.dart';
import 'counter_repository.dart';
import 'debt_repository.dart';
import 'voucher_repository.dart';

/// What is known about the renewal an invoice made, and what taking it back
/// puts on the account.
class _RenewalUndo {
  const _RenewalUndo({
    required this.accountId,
    required this.accountNumber,
    required this.applies,
    required this.soldAtMs,
    this.prevLastMs,
    this.prevNextMs,
  });

  final int accountId;
  final String accountNumber;

  /// The account still stands where this invoice left it.
  final bool applies;

  /// `created_at` of the invoice — what it wrote as the last renewal.
  final int soldAtMs;
  final int? prevLastMs;
  final int? prevNextMs;

  static DateTime? _date(int? ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  RenewalRestore get restore => RenewalRestore(
        accountId: accountId,
        accountNumber: accountNumber,
        applies: applies,
        lastRenewalAt: _date(prevLastMs),
        nextDueAt: _date(prevNextMs),
      );
}

/// CORRECTING A SAVED SALE WITHOUT DELETING IT: voiding a whole invoice and
/// returns.
///
/// THE RULES THIS CLASS KEEPS
/// - An invoice is never deleted to fix a mistake, and its number never
///   changes: a void marks it (`voided_at`, the reason), a return is its own
///   document with its own number from the counter `return_no`.
/// - Everything a correction undoes lands in ONE transaction, or none of it
///   does: the ledger, the card codes, the renewal dates, the document and
///   its audit line.
/// - The ledger is only ever ADDED to: a void posts a REVERSAL of the sale's
///   debt entry (which also gives back a credit balance the sale used — that
///   was the same entry), a return posts a RETURN entry for what stays on
///   the account. A cash refund touches no ledger.
/// - Products the sale created and prices it wrote back stay as they are.
/// - The license is asked first ([LicenseGuard.ensureCanSell]): a void or a
///   return is refused exactly where a sale is.
///
/// The screens ask for the PIN before they call this; the age limit of a
/// void and every other refusal are decided here, in the data layer.
class InvoiceCorrectionRepository {
  InvoiceCorrectionRepository(this._db, {this.codeCipher, this.guard});

  final Database _db;

  /// For the masked codes of a line and the last digits in the audit log.
  /// Null = the card codes feature is off.
  final CodeCipher? codeCipher;

  /// Null = no licensing (a repository built by a test).
  final LicenseGuard? guard;

  static const _counters = CounterRepository();

  /// Return documents the archive loads at a time.
  static const int returnsPageSize = 50;

  static int _ms(DateTime moment) => moment.toUtc().millisecondsSinceEpoch;

  static String? _blankToNull(String? text) {
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static BigInt _pow10(int exp) => BigInt.from(10).pow(exp);

  // ---- Reading -------------------------------------------------------------

  /// The invoice with its items, and its raw row (the renewal columns are
  /// bookkeeping the model does not carry).
  static Future<({Map<String, Object?> row, Invoice invoice})?> _load(
    DatabaseExecutor db,
    int invoiceId,
  ) async {
    final rows = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final items = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return (
      row: rows.first,
      invoice: Invoice.fromMap(
        rows.first,
        items: items.map(InvoiceItem.fromMap).toList(),
      ),
    );
  }

  static Future<int> _maxAgeDays(DatabaseExecutor db) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [SettingsKeys.voidMaxAgeDays],
      limit: 1,
    );
    final raw = rows.isEmpty
        ? SettingsKeys.defaults[SettingsKeys.voidMaxAgeDays]
        : rows.first['value'] as String?;
    final days = int.tryParse(raw ?? '') ?? 30;
    return days < 0 ? 0 : days;
  }

  /// The "void invoices up to N days old" setting; 0 = no limit.
  Future<int> voidMaxAgeDays() => _maxAgeDays(_db);

  /// Thousandths already returned of each line of [invoiceId].
  static Future<Map<int, int>> _returnedBefore(
    DatabaseExecutor db,
    int invoiceId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT it.invoice_item_id AS item, SUM(it.qty_thousandths) AS qty '
      'FROM invoice_return_items it '
      'JOIN invoice_returns r ON r.id = it.return_id '
      'WHERE r.invoice_id = ? GROUP BY it.invoice_item_id',
      [invoiceId],
    );
    return {
      for (final row in rows) row['item'] as int: (row['qty'] as int?) ?? 0,
    };
  }

  static Future<int> _returnCount(DatabaseExecutor db, int invoiceId) async =>
      Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM invoice_returns WHERE invoice_id = ?',
        [invoiceId],
      )) ??
      0;

  static Future<({int invoice, int base})> _decimals(
    DatabaseExecutor db,
    Invoice invoice,
  ) async {
    final places = {
      for (final row in await db.query(
        'currencies',
        columns: ['code', 'decimal_places'],
        where: 'code IN (?, ?)',
        whereArgs: [invoice.currencyCode, invoice.baseCurrencyCode],
      ))
        row['code'] as String: row['decimal_places'] as int,
    };
    return (
      invoice: places[invoice.currencyCode] ?? 0,
      base: places[invoice.baseCurrencyCode] ?? 0,
    );
  }

  /// What [customerId] owes right now: in base minor units, and in the
  /// invoice's currency at the invoice's stored rate — rounded DOWN, so
  /// "reduce the debt" can never take off more than is owed.
  static Future<({int base, int invoice})> _owed(
    DatabaseExecutor db,
    Invoice invoice,
    int customerId,
    ({int invoice, int base}) decimals,
  ) async {
    final balance = await DebtRepository.balanceIn(db, customerId);
    if (balance <= 0) return (base: 0, invoice: 0);
    if (invoice.currencyCode == invoice.baseCurrencyCode) {
      return (base: balance, invoice: balance);
    }
    final numerator = BigInt.from(balance) *
        BigInt.from(invoice.rate.denominator) *
        _pow10(decimals.invoice);
    final denominator =
        BigInt.from(invoice.rate.numerator) * _pow10(decimals.base);
    return (base: balance, invoice: (numerator ~/ denominator).toInt());
  }

  // ---- Renewals ------------------------------------------------------------

  /// What taking back the renewal of this invoice means, or null when it
  /// renewed nothing (no account, no SERVICE item) or was already taken
  /// back.
  ///
  /// THE PREVIOUS DATES are the ones the sale stored (schema version 8 on);
  /// for an older invoice they are worked out from the account's earlier
  /// renewals that still stand — the newest of them is the last renewal, and
  /// the due day follows from the account's period.
  ///
  /// THE ACCOUNT IS ONLY MOVED BACK WHEN IT STILL STANDS WHERE THIS INVOICE
  /// LEFT IT. A later renewal — or dates someone set by hand since — is in
  /// force and stays.
  static Future<_RenewalUndo?> _renewalUndo(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Invoice invoice,
  ) async {
    final accountId = row['account_id'] as int?;
    if (accountId == null || ((row['renewal_undone'] as int?) ?? 0) != 0) {
      return null;
    }
    if (!invoice.items.any((item) => item.kind == ProductKind.service)) {
      return null;
    }
    final accounts = await db.query(
      'customer_accounts',
      columns: [
        'account_number',
        'renewal_days',
        'last_renewal_at',
      ],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (accounts.isEmpty) return null;
    final account = accounts.first;
    final soldAt = row['created_at'] as int;

    int? prevLast;
    int? prevNext;
    if (((row['renewal_prev_stored'] as int?) ?? 0) == 1) {
      prevLast = row['prev_last_renewal_at'] as int?;
      prevNext = row['prev_next_due_at'] as int?;
    } else {
      final earlier = await db.rawQuery(
        'SELECT i.created_at FROM invoices i '
        'WHERE i.account_id = ? AND i.id != ? '
        'AND i.voided_at IS NULL AND i.renewal_undone = 0 '
        'AND (i.created_at < ? OR (i.created_at = ? AND i.id < ?)) '
        'AND EXISTS (SELECT 1 FROM invoice_items it '
        "WHERE it.invoice_id = i.id AND it.kind = 'SERVICE') "
        'ORDER BY i.created_at DESC, i.id DESC LIMIT 1',
        [accountId, invoice.id, soldAt, soldAt, invoice.id],
      );
      if (earlier.isNotEmpty) {
        prevLast = earlier.first['created_at'] as int;
        final days = account['renewal_days'] as int?;
        prevNext = days == null
            ? null
            : _ms(nextDueAfter(
                DateTime.fromMillisecondsSinceEpoch(prevLast, isUtc: true),
                days,
              ));
      }
    }
    return _RenewalUndo(
      accountId: accountId,
      accountNumber: account['account_number'] as String,
      applies: account['last_renewal_at'] == soldAt,
      soldAtMs: soldAt,
      prevLastMs: prevLast,
      prevNextMs: prevNext,
    );
  }

  static Future<void> _applyRenewalUndo(
    Transaction txn,
    _RenewalUndo undo,
    int invoiceId,
  ) async {
    if (undo.applies) {
      await txn.update(
        'customer_accounts',
        {
          'last_renewal_at': undo.prevLastMs,
          'next_due_at': undo.prevNextMs,
        },
        where: 'id = ?',
        whereArgs: [undo.accountId],
      );
    }
    // A later renewal recorded THIS one as what came before it. This one no
    // longer counts, so that record steps back to what came before this:
    // voiding the later invoice afterwards then lands on the right dates.
    await txn.update(
      'invoices',
      {
        'prev_last_renewal_at': undo.prevLastMs,
        'prev_next_due_at': undo.prevNextMs,
      },
      where: 'account_id = ? AND id != ? AND renewal_prev_stored = 1 '
          'AND prev_last_renewal_at = ?',
      whereArgs: [undo.accountId, invoiceId, undo.soldAtMs],
    );
    await txn.update(
      'invoices',
      {'renewal_undone': 1},
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  // ---- Void ----------------------------------------------------------------

  static Future<VoidBlocker?> _blocker(
    DatabaseExecutor db,
    Invoice invoice, {
    required DateTime now,
    required int maxAgeDays,
  }) async {
    if (invoice.isVoided) return VoidBlocker.alreadyVoided;
    if (await _returnCount(db, invoice.id!) > 0) return VoidBlocker.hasReturns;
    // Whole calendar days, in the shop's own time: an invoice of this
    // morning is 0 days old all day.
    if (maxAgeDays > 0 &&
        calendarDaysBetween(invoice.createdAt, now) > maxAgeDays) {
      return VoidBlocker.tooOld;
    }
    return null;
  }

  /// What voiding [invoiceId] will do — for the confirmation — and whether
  /// it can be voided at all. Writes nothing.
  Future<VoidPlan> voidPlan(int invoiceId, {DateTime? now}) async {
    final loaded = await _load(_db, invoiceId);
    if (loaded == null) throw InvoiceNotFoundException(invoiceId);
    final maxAge = await _maxAgeDays(_db);
    final entry = await DebtRepository.saleEntryOf(_db, invoiceId);
    final sold = await VoucherRepository.soldCodesOf(_db, invoiceId);
    final undo = await _renewalUndo(_db, loaded.row, loaded.invoice);
    return VoidPlan(
      invoice: loaded.invoice,
      blocker: await _blocker(
        _db,
        loaded.invoice,
        now: now ?? DateTime.now(),
        maxAgeDays: maxAge,
      ),
      maxAgeDays: maxAge,
      debtBaseMinor: entry?.amountBaseMinor ?? 0,
      soldCodes: sold.length,
      renewal: undo?.restore,
    );
  }

  /// VOIDS invoice [invoiceId] and returns it as it now is.
  ///
  /// The invoice stays in the archive with its number, marked void with the
  /// time and the [reason]. In the same transaction everything the sale did
  /// is undone:
  /// - its debt entry is cancelled by a REVERSAL (never edited, never
  ///   deleted) — which also gives back a credit balance the sale used;
  /// - every card code still sold on it is voided or, with
  ///   [CodeDisposal.returnToStock], put back in stock — each with its own
  ///   audit line;
  /// - an account it renewed gets its previous dates back.
  ///
  /// Throws [InvoiceVoidedException] (a second void), [InvoiceHasReturnsException],
  /// [InvoiceTooOldException] and [LicenseRequiredException]; nothing at all
  /// is written then.
  Future<Invoice> voidInvoice(
    int invoiceId, {
    required String reason,
    CodeDisposal codes = CodeDisposal.voidCode,
    DateTime? now,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a reason is required');
    }
    // Blocked like a sale: no license, no void.
    await guard?.ensureCanSell();
    final at = now ?? DateTime.now();
    await _db.transaction((txn) async {
      final loaded = await _load(txn, invoiceId);
      if (loaded == null) throw InvoiceNotFoundException(invoiceId);
      final invoice = loaded.invoice;
      final maxAge = await _maxAgeDays(txn);
      switch (await _blocker(txn, invoice, now: at, maxAgeDays: maxAge)) {
        case VoidBlocker.alreadyVoided:
          throw InvoiceVoidedException(invoice.invoiceNo);
        case VoidBlocker.hasReturns:
          throw InvoiceHasReturnsException(invoice.invoiceNo);
        case VoidBlocker.tooOld:
          throw InvoiceTooOldException(maxAge);
        case null:
          break;
      }

      final entry = await DebtRepository.saleEntryOf(txn, invoiceId);
      if (entry != null) {
        await DebtRepository.postReversal(txn, entry, reason: why, at: at);
      }

      final sold = await VoucherRepository.soldCodesOf(txn, invoiceId);
      for (final code in sold) {
        await VoucherRepository.changeStatusIn(
          txn,
          cipher: codeCipher,
          codeId: code.id,
          to: codes == CodeDisposal.voidCode
              ? VoucherStatus.voided
              : VoucherStatus.available,
          action: codes == CodeDisposal.voidCode
              ? AuditAction.codeVoid
              : AuditAction.codeRestore,
          reason: why,
          at: at,
        );
      }

      final undo = await _renewalUndo(txn, loaded.row, invoice);
      if (undo != null) await _applyRenewalUndo(txn, undo, invoiceId);

      final marked = await txn.update(
        'invoices',
        {'voided_at': _ms(at), 'void_reason': why},
        where: 'id = ? AND voided_at IS NULL',
        whereArgs: [invoiceId],
      );
      if (marked != 1) throw InvoiceVoidedException(invoice.invoiceNo);

      await AuditRepository(txn).log(
        AuditAction.invoiceVoid,
        entityType: 'invoice',
        entityId: invoiceId,
        details: {
          'invoice_no': invoice.invoiceNo,
          'amount': invoice.totalBaseMinor,
          'customer': invoice.customerName,
          'debt_reversed': entry?.amountBaseMinor,
          if (sold.isNotEmpty) 'count': sold.length,
          if (sold.isNotEmpty)
            'codes': codes == CodeDisposal.voidCode ? 'VOID' : 'STOCK',
          if (undo != null && undo.applies) 'account': undo.accountNumber,
          'reason': why,
        },
        at: at,
      );
    });
    return (await _load(_db, invoiceId))!.invoice;
  }

  // ---- Returns -------------------------------------------------------------

  /// The lines of [invoiceId] with what is still returnable of each (sold
  /// minus already returned) and the card codes still sold on them, masked.
  Future<List<ReturnableLine>> returnableLines(int invoiceId) async {
    final loaded = await _load(_db, invoiceId);
    if (loaded == null) return const [];
    final before = await _returnedBefore(_db, invoiceId);
    final cipher = codeCipher;
    final codes = cipher == null
        ? const <VoucherCodeView>[]
        : await VoucherRepository(_db, cipher).codesOfInvoice(invoiceId);
    return [
      for (final item in loaded.invoice.items)
        ReturnableLine(
          item: item,
          returnedThousandths: before[item.id] ?? 0,
          codes: [
            for (final code in codes)
              if (code.invoiceItemId == item.id &&
                  code.status == VoucherStatus.sold)
                code,
          ],
        ),
    ];
  }

  /// The refund of returning [quantities] (thousandths by line id) from
  /// [invoiceId], and what its customer owes — everything the "how is it
  /// refunded?" question needs. Writes nothing.
  Future<ReturnPreview> previewReturn(
    int invoiceId,
    Map<int, int> quantities,
  ) async {
    final loaded = await _load(_db, invoiceId);
    if (loaded == null) throw InvoiceNotFoundException(invoiceId);
    final invoice = loaded.invoice;
    if (invoice.isVoided) throw InvoiceVoidedException(invoice.invoiceNo);
    final refund = computeRefund(
      invoice: invoice,
      returnedBefore: await _returnedBefore(_db, invoiceId),
      returning: quantities,
    );
    final customerId = invoice.customerId;
    final hasCustomer = customerId != null &&
        (await _db.query(
          'customers',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [customerId],
          limit: 1,
        ))
            .isNotEmpty;
    final owed = hasCustomer
        ? await _owed(
            _db,
            invoice,
            customerId,
            await _decimals(_db, invoice),
          )
        : (base: 0, invoice: 0);
    return ReturnPreview(
      invoice: invoice,
      refund: refund,
      owedMinor: owed.invoice,
      hasCustomer: hasCustomer,
    );
  }

  /// SAVES A RETURN and gives back its document.
  ///
  /// In one transaction: the quantities are checked against what is still
  /// returnable (several returns of one invoice can never take a line below
  /// zero — the check and the write share the transaction), the refund is
  /// worked out from the original invoice ([computeRefund]), the return gets
  /// its number, its lines are written, the part of the refund that stays
  /// on the customer's account becomes a RETURN ledger entry, the chosen
  /// card codes are voided or put back in stock, and an account whose
  /// package came back gets its previous dates. Then the audit line.
  ///
  /// Throws [InvoiceVoidedException], [ReturnQuantityException],
  /// [ReturnCodesException], [ReturnCustomerRequiredException] and
  /// [LicenseRequiredException]; nothing at all is written then.
  Future<InvoiceReturn> saveReturn(ReturnDraft draft, {DateTime? now}) async {
    // Blocked like a sale: no license, no return.
    await guard?.ensureCanSell();
    final at = now ?? DateTime.now();
    final returnId = await _db.transaction((txn) async {
      final loaded = await _load(txn, draft.invoiceId);
      if (loaded == null) throw InvoiceNotFoundException(draft.invoiceId);
      final invoice = loaded.invoice;
      final invoiceId = invoice.id!;
      if (invoice.isVoided) throw InvoiceVoidedException(invoice.invoiceNo);

      final requests = <int, ReturnLineRequest>{};
      for (final line in draft.lines) {
        if (line.qtyThousandths == 0) continue;
        if (requests.containsKey(line.invoiceItemId)) {
          throw ReturnQuantityException(
            line.invoiceItemId,
            'the same line twice in one return',
          );
        }
        requests[line.invoiceItemId] = line;
      }
      final before = await _returnedBefore(txn, invoiceId);
      final refund = computeRefund(
        invoice: invoice,
        returnedBefore: before,
        returning: {
          for (final line in requests.values)
            line.invoiceItemId: line.qtyThousandths,
        },
      );

      // The cards: each returned card of a line that still has codes is
      // one of THOSE codes, and no card is refunded while its code stays
      // with the customer.
      final soldByLine = <int, Set<int>>{};
      for (final code in await VoucherRepository.soldCodesOf(txn, invoiceId)) {
        final line = code.invoiceItemId;
        if (line != null) soldByLine.putIfAbsent(line, () => {}).add(code.id);
      }
      final disposals = <int, CodeDisposal>{};
      for (final line in refund.lines) {
        final lineId = line.item.id!;
        final chosen = requests[lineId]!.codes;
        final attached = soldByLine[lineId] ?? const <int>{};
        if (!attached.containsAll(chosen.keys)) {
          throw const ReturnCodesException('a code that is not on this line');
        }
        if (chosen.isNotEmpty && chosen.length * 1000 != line.qtyThousandths) {
          throw const ReturnCodesException(
            'as many codes as cards are returned',
          );
        }
        final left = line.item.qtyThousandths -
            (before[lineId] ?? 0) -
            line.qtyThousandths;
        if ((attached.length - chosen.length) * 1000 > left) {
          throw const ReturnCodesException(
            'cards are returned but their codes are not',
          );
        }
        disposals.addAll(chosen);
      }

      final decimals = await _decimals(txn, invoice);
      final customerId = invoice.customerId;
      final hasCustomer = customerId != null &&
          (await txn.query(
            'customers',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [customerId],
            limit: 1,
          ))
              .isNotEmpty;
      if (draft.method != RefundMethod.cash && !hasCustomer) {
        throw const ReturnCustomerRequiredException();
      }
      final owed = hasCustomer
          ? await _owed(txn, invoice, customerId, decimals)
          : (base: 0, invoice: 0);
      var split = splitRefund(
        refundMinor: refund.refundMinor,
        method: draft.method,
        owedMinor: owed.invoice,
      );

      // What stays on the account, in base — the invoice's own rate, one
      // rounding, exactly as the sale's debt was converted. Taking it off a
      // debt never takes off more than the debt.
      var ledgerBase = 0;
      if (split.onAccountMinor > 0) {
        ledgerBase = invoice.currencyCode == invoice.baseCurrencyCode
            ? split.onAccountMinor
            : toBaseMinor(
                amountMinor: split.onAccountMinor,
                fromDecimals: decimals.invoice,
                fromRate: invoice.rate,
                baseDecimals: decimals.base,
              );
        if (split.debtMinor > 0 && ledgerBase > owed.base) {
          ledgerBase = owed.base;
        }
        // Worth nothing in the base currency: it is handed back instead.
        if (ledgerBase <= 0) {
          split = RefundSplit(cashMinor: refund.refundMinor);
        }
      }

      final returnNo = await _counters.next(txn, CounterRepository.returnNo);
      final refundBase = refundBaseMinor(
        invoice: invoice,
        returnedBeforeMinor: refund.returnedBeforeMinor,
        returnedAfterMinor: refund.returnedAfterMinor,
        invoiceDecimals: decimals.invoice,
        baseDecimals: decimals.base,
      );
      final reason = _blankToNull(draft.reason);
      final voided =
          disposals.values.where((d) => d == CodeDisposal.voidCode).length;
      final customerName = invoice.customerName;
      final id = await txn.insert('invoice_returns', {
        'return_no': returnNo,
        'invoice_id': invoiceId,
        'invoice_no': invoice.invoiceNo,
        'created_at': _ms(at),
        'currency_code': invoice.currencyCode,
        'base_currency_code': invoice.baseCurrencyCode,
        'rate_num': invoice.rate.numerator,
        'rate_den': invoice.rate.denominator,
        'refund_minor': refund.refundMinor,
        'refund_base_minor': refundBase,
        'refund_method': split.method.db,
        'cash_minor': split.cashMinor,
        'debt_minor': split.debtMinor,
        'credit_minor': split.creditMinor,
        'reason': reason,
        'customer_id': hasCustomer ? customerId : null,
        'customer_name': customerName,
        'customer_name_norm':
            customerName == null ? null : normalizeName(customerName),
        'customer_phone': invoice.customerPhone,
        'codes_voided': voided,
        'codes_restocked': disposals.length - voided,
      });
      for (var i = 0; i < refund.lines.length; i++) {
        final line = refund.lines[i];
        await txn.insert('invoice_return_items', {
          'return_id': id,
          'invoice_item_id': line.item.id,
          'sort_order': i,
          'product_id': line.item.productId,
          'product_name': line.item.productName,
          'product_name_norm': normalizeName(line.item.productName),
          'product_code': line.item.productCode,
          'kind': line.item.kind.db,
          'unit_name': line.item.unitName,
          'qty_thousandths': line.qtyThousandths,
          'gross_minor': line.grossMinor,
          'refund_minor': line.refundMinor,
        });
      }

      if (ledgerBase > 0) {
        final foreign = invoice.currencyCode != invoice.baseCurrencyCode;
        await DebtRepository.postReturn(
          txn,
          customerId: customerId!,
          amountBaseMinor: ledgerBase,
          origAmountMinor: foreign ? split.onAccountMinor : null,
          origCurrencyCode: foreign ? invoice.currencyCode : null,
          origRate: foreign ? invoice.rate : null,
          invoiceId: invoiceId,
          invoiceNo: invoice.invoiceNo,
          returnId: id,
          returnNo: returnNo,
          note: reason,
          at: at,
        );
      }

      for (final entry in disposals.entries) {
        final toStock = entry.value == CodeDisposal.returnToStock;
        await VoucherRepository.changeStatusIn(
          txn,
          cipher: codeCipher,
          codeId: entry.key,
          to: toStock ? VoucherStatus.available : VoucherStatus.voided,
          action: toStock ? AuditAction.codeRestore : AuditAction.codeVoid,
          reason: reason ?? '',
          at: at,
          details: {'return_no': returnNo},
        );
      }

      // The package itself came back: no SERVICE quantity is left on the
      // invoice, so the renewal it made is taken back with it.
      var serviceLeft = 0;
      var hasService = false;
      for (final item in invoice.items) {
        if (item.kind != ProductKind.service) continue;
        hasService = true;
        serviceLeft += item.qtyThousandths -
            (before[item.id] ?? 0) -
            (requests[item.id]?.qtyThousandths ?? 0);
      }
      _RenewalUndo? undo;
      if (hasService && serviceLeft <= 0) {
        undo = await _renewalUndo(txn, loaded.row, invoice);
        if (undo != null) await _applyRenewalUndo(txn, undo, invoiceId);
      }

      await AuditRepository(txn).log(
        AuditAction.invoiceReturn,
        entityType: 'return',
        entityId: id,
        details: {
          'invoice_no': invoice.invoiceNo,
          'return_no': returnNo,
          'amount': refundBase,
          'customer': customerName,
          'method': split.method.db,
          if (ledgerBase > 0) 'on_account': ledgerBase,
          if (disposals.isNotEmpty) 'count': disposals.length,
          if (undo != null && undo.applies) 'account': undo.accountNumber,
          'reason': reason,
        },
        at: at,
      );
      return id;
    });
    return (await returnById(returnId))!;
  }

  static Future<List<InvoiceReturnItem>> _itemsOf(
    DatabaseExecutor db,
    int returnId,
  ) async {
    final rows = await db.query(
      'invoice_return_items',
      where: 'return_id = ?',
      whereArgs: [returnId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(InvoiceReturnItem.fromMap).toList();
  }

  /// One return document with its lines, or null.
  Future<InvoiceReturn?> returnById(int id) async {
    final rows = await _db.query(
      'invoice_returns',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InvoiceReturn.fromMap(rows.first, items: await _itemsOf(_db, id));
  }

  /// The return documents made from [invoiceId], oldest first, each with
  /// its lines.
  Future<List<InvoiceReturn>> returnsOf(int invoiceId) async {
    final rows = await _db.query(
      'invoice_returns',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    return [
      for (final row in rows)
        InvoiceReturn.fromMap(
          row,
          items: await _itemsOf(_db, row['id'] as int),
        ),
    ];
  }

  (List<String>, List<Object?>) _returnsWhere(ArchiveFilter filter) {
    final where = <String>[];
    final args = <Object?>[];
    final from = filter.from;
    if (from != null) {
      where.add('r.created_at >= ?');
      args.add(_ms(from));
    }
    final to = filter.to;
    if (to != null) {
      where.add('r.created_at < ?');
      args.add(_ms(to));
    }
    // The number box finds a return by its own number or by its invoice's.
    final number = filter.invoiceNo;
    if (number != null) {
      where.add('(r.invoice_no = ? OR r.return_no = ?)');
      args
        ..add(number)
        ..add(number);
    }
    final product = normalizeName(filter.productQuery);
    if (product.isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM invoice_return_items it '
        "WHERE it.return_id = r.id AND it.product_name_norm LIKE ? ESCAPE '!')",
      );
      args.add('%${ArchiveRepository.escapeLike(product)}%');
    }
    final customer = normalizeName(filter.customerQuery);
    if (customer.isNotEmpty) {
      where.add("r.customer_name_norm LIKE ? ESCAPE '!'");
      args.add('%${ArchiveRepository.escapeLike(customer)}%');
    }
    return (where, args);
  }

  /// The archive's "Returns" list: the return documents DATED in the
  /// filter's period, newest first, narrowed by its search box (a number
  /// finds the return or its invoice). Without their lines — a list row
  /// does not show them.
  Future<List<InvoiceReturn>> returnsPage(
    ArchiveFilter filter, {
    int limit = returnsPageSize,
  }) async {
    final (where, args) = _returnsWhere(filter);
    final rows = await _db.rawQuery(
      'SELECT r.* FROM invoice_returns r '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
      'ORDER BY r.created_at DESC, r.id DESC LIMIT ?',
      [...args, limit],
    );
    return rows.map(InvoiceReturn.fromMap).toList();
  }

  /// How many return documents [filter] matches and what they gave back, in
  /// base currency — the line above the "Returns" list.
  Future<ArchiveRangeSummary> returnsSummary(ArchiveFilter filter) async {
    final (where, args) = _returnsWhere(filter);
    final row = (await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(r.refund_base_minor), 0) AS total '
      'FROM invoice_returns r '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}',
      args,
    ))
        .first;
    return ArchiveRangeSummary(
      count: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
    );
  }
}
