import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Schema version 8: VOIDING an invoice and RETURNS — a shop must never have
/// to delete an invoice to fix a mistake.
///
/// THE INVOICE
/// - `voided_at` / `void_reason`: a voided invoice is NOT deleted. It keeps
///   its number, its items and its place in the archive, and only says that
///   it no longer counts. NULL on every live invoice.
/// - `renewal_prev_stored`, `prev_last_renewal_at`, `prev_next_due_at`: what
///   the attached account's dates were just BEFORE this sale renewed it, so
///   a void (or the return of the package) can put them back. Stored from
///   this version on; an older invoice has `renewal_prev_stored = 0` and its
///   previous dates are worked out from the account's earlier invoices.
/// - `renewal_undone`: the renewal of this invoice was taken back by a
///   return (a voided invoice says so by `voided_at`).
///
/// THE RETURN DOCUMENT
/// - `invoice_returns`: one row per return, with its own number from the
///   counter `return_no` (never reused), the invoice it returns from (id,
///   and the number as a snapshot), the invoice's currency and rate, the
///   refund in that currency and in base, how it was given back (cash / off
///   the debt / kept as credit — three amounts that add up to the refund),
///   the reason and the customer snapshot. It goes with its invoice (ON
///   DELETE CASCADE): deleting old invoices deletes their returns.
/// - `invoice_return_items`: the returned lines, as snapshots, each with
///   the invoice line it returns from, the quantity, the returned share of
///   the line total before the discount (`gross_minor`, what "top products"
///   takes off) and what was given back for it (`refund_minor`).
///
/// THE LEDGER, REBUILT ONCE MORE
/// A refund kept on the customer's account is a ledger entry of a new type,
/// RETURN, linked to its document (`return_id`, and `return_no` as the
/// snapshot that stays when the document is deleted with its invoice).
/// sqlite cannot change a CHECK in place, so — exactly as version 5 did —
/// the table is renamed aside, created anew, every row copied across with
/// its id, and the old one dropped. Nothing is lost and no id changes.
///
/// The two triggers that make the ledger append-only are recreated. The one
/// change an entry may still see is a LINK being cleared: `invoice_id` when
/// its invoice is deleted and now also `return_id` when its return document
/// goes with that invoice. Every other column of every entry is frozen.
///
/// HOW THE OLD TABLE IS DROPPED. Foreign keys are on, and the old table
/// references itself (`reverses_id … ON DELETE RESTRICT`): dropping it while
/// it holds a reversal and the entry it reverses would be refused. So it is
/// emptied first, leaves before roots — the rows nothing points at, then the
/// rest — and dropped empty. This needs nothing newer than sqlite 3.9.
///
/// THE INDEXES
/// - the six of version 5, unchanged;
/// - `idx_debt_return`: deleting a return document makes sqlite look for
///   the ledger entry pointing at it (ON DELETE SET NULL);
/// - `idx_returns_invoice`, `idx_return_items_return`,
///   `idx_return_items_item`: the same trap on the way down from a deleted
///   invoice — every deleted invoice and every deleted item is looked up in
///   the returns. Without them a 50,000-invoice clear scans the returns
///   once per row;
/// - `idx_returns_created`: returns of a period, for the statistics and the
///   archive's "Returns" filter;
/// - `idx_invoices_voided`: the archive's "Voided" filter;
/// - `idx_invoices_account`: the earlier renewals of an account.
class MigrationV8 implements Migration {
  const MigrationV8();

  @override
  int get version => 8;

  /// The name the version-7 ledger carries while it is being copied.
  static const String _oldLedger = 'debt_transactions_v7';

  static const String createLedger = '''
    CREATE TABLE debt_transactions (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id        INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
      type               TEXT NOT NULL CHECK (type IN
                           ('DEBT','MANUAL_DEBT','PAYMENT','OPENING_BALANCE','ADJUSTMENT','REVERSAL','RETURN')),
      direction          INTEGER NOT NULL CHECK (direction IN (1,-1)),
      amount_base_minor  INTEGER NOT NULL CHECK (amount_base_minor > 0),
      orig_amount_minor  INTEGER CHECK (orig_amount_minor IS NULL OR orig_amount_minor > 0),
      orig_currency_code TEXT,
      orig_rate_num      INTEGER CHECK (orig_rate_num IS NULL OR orig_rate_num > 0),
      orig_rate_den      INTEGER CHECK (orig_rate_den IS NULL OR orig_rate_den > 0),
      payment_method     TEXT CHECK (payment_method IS NULL
                           OR payment_method IN ('CASH','TRANSFER','OTHER')),
      due_at             INTEGER,
      receipt_no         INTEGER,
      balance_before_base_minor INTEGER,
      invoice_id         INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
      invoice_no         INTEGER,
      return_id          INTEGER REFERENCES invoice_returns(id) ON DELETE SET NULL,
      return_no          INTEGER,
      reverses_id        INTEGER REFERENCES debt_transactions(id) ON DELETE RESTRICT,
      note               TEXT,
      created_at         INTEGER NOT NULL,
      recorded_at        INTEGER NOT NULL,
      CHECK (type NOT IN ('DEBT','MANUAL_DEBT') OR direction = 1),
      CHECK (type NOT IN ('PAYMENT','RETURN') OR direction = -1),
      CHECK ((type = 'REVERSAL') = (reverses_id IS NOT NULL)),
      CHECK (receipt_no IS NULL OR type = 'PAYMENT'),
      CHECK (return_no IS NULL OR type = 'RETURN')
    )''';

  /// The columns the version-7 ledger has, all carried over as they are.
  static const List<String> _carried = [
    'id',
    'customer_id',
    'type',
    'direction',
    'amount_base_minor',
    'orig_amount_minor',
    'orig_currency_code',
    'orig_rate_num',
    'orig_rate_den',
    'payment_method',
    'due_at',
    'receipt_no',
    'balance_before_base_minor',
    'invoice_id',
    'invoice_no',
    'reverses_id',
    'note',
    'created_at',
    'recorded_at',
  ];

  /// Every column but the two links, compared NULL-safely.
  static const List<String> _frozenColumns = [
    'id',
    'customer_id',
    'type',
    'direction',
    'amount_base_minor',
    'orig_amount_minor',
    'orig_currency_code',
    'orig_rate_num',
    'orig_rate_den',
    'payment_method',
    'due_at',
    'receipt_no',
    'balance_before_base_minor',
    'invoice_no',
    'return_no',
    'reverses_id',
    'note',
    'created_at',
    'recorded_at',
  ];

  /// A link may be CLEARED (its invoice or its return document was
  /// deleted), never pointed anywhere else; nothing else may change at all.
  static final String _noUpdateTrigger = '''
    CREATE TRIGGER trg_debt_no_update BEFORE UPDATE ON debt_transactions
    WHEN NOT ((NEW.invoice_id IS NULL OR NEW.invoice_id IS OLD.invoice_id)
      AND (NEW.return_id IS NULL OR NEW.return_id IS OLD.return_id)
      AND ${_frozenColumns.map((c) => 'NEW.$c IS OLD.$c').join(' AND ')})
    BEGIN
      SELECT RAISE(ABORT, 'ledger entries are never edited');
    END''';

  static const String _noDeleteTrigger = '''
    CREATE TRIGGER trg_debt_no_delete BEFORE DELETE ON debt_transactions
    BEGIN
      SELECT RAISE(ABORT, 'ledger entries are never deleted');
    END''';

  static const List<String> _invoiceDdl = [
    'ALTER TABLE invoices ADD COLUMN voided_at INTEGER',
    'ALTER TABLE invoices ADD COLUMN void_reason TEXT',
    'ALTER TABLE invoices ADD COLUMN renewal_prev_stored INTEGER NOT NULL '
        'DEFAULT 0 CHECK (renewal_prev_stored IN (0,1))',
    'ALTER TABLE invoices ADD COLUMN prev_last_renewal_at INTEGER',
    'ALTER TABLE invoices ADD COLUMN prev_next_due_at INTEGER',
    'ALTER TABLE invoices ADD COLUMN renewal_undone INTEGER NOT NULL '
        'DEFAULT 0 CHECK (renewal_undone IN (0,1))',
    'CREATE INDEX idx_invoices_voided ON invoices(voided_at) '
        'WHERE voided_at IS NOT NULL',
    'CREATE INDEX idx_invoices_account ON invoices(account_id, created_at) '
        'WHERE account_id IS NOT NULL',
  ];

  static const List<String> _returnDdl = [
    '''
    CREATE TABLE invoice_returns (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      return_no          INTEGER NOT NULL UNIQUE,
      invoice_id         INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      invoice_no         INTEGER NOT NULL,
      created_at         INTEGER NOT NULL,
      currency_code      TEXT NOT NULL,
      base_currency_code TEXT NOT NULL,
      rate_num           INTEGER NOT NULL CHECK (rate_num > 0),
      rate_den           INTEGER NOT NULL CHECK (rate_den > 0),
      refund_minor       INTEGER NOT NULL CHECK (refund_minor >= 0),
      refund_base_minor  INTEGER NOT NULL CHECK (refund_base_minor >= 0),
      refund_method      TEXT NOT NULL CHECK (refund_method IN ('CASH','DEBT','CREDIT')),
      cash_minor         INTEGER NOT NULL DEFAULT 0 CHECK (cash_minor >= 0),
      debt_minor         INTEGER NOT NULL DEFAULT 0 CHECK (debt_minor >= 0),
      credit_minor       INTEGER NOT NULL DEFAULT 0 CHECK (credit_minor >= 0),
      reason             TEXT,
      customer_id        INTEGER REFERENCES customers(id) ON DELETE SET NULL,
      customer_name      TEXT,
      customer_name_norm TEXT,
      customer_phone     TEXT,
      codes_voided       INTEGER NOT NULL DEFAULT 0,
      codes_restocked    INTEGER NOT NULL DEFAULT 0,
      CHECK (cash_minor + debt_minor + credit_minor = refund_minor)
    )''',
    'CREATE INDEX idx_returns_invoice ON invoice_returns(invoice_id)',
    'CREATE INDEX idx_returns_created ON invoice_returns(created_at)',
    '''
    CREATE TABLE invoice_return_items (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id         INTEGER NOT NULL REFERENCES invoice_returns(id) ON DELETE CASCADE,
      invoice_item_id   INTEGER NOT NULL REFERENCES invoice_items(id) ON DELETE CASCADE,
      sort_order        INTEGER NOT NULL DEFAULT 0,
      product_id        INTEGER REFERENCES products(id) ON DELETE SET NULL,
      product_name      TEXT NOT NULL,
      product_name_norm TEXT NOT NULL DEFAULT '',
      product_code      TEXT,
      kind              TEXT NOT NULL CHECK (kind IN ('GOODS','SERVICE')),
      unit_name         TEXT,
      qty_thousandths   INTEGER NOT NULL CHECK (qty_thousandths > 0),
      gross_minor       INTEGER NOT NULL CHECK (gross_minor >= 0),
      refund_minor      INTEGER NOT NULL CHECK (refund_minor >= 0)
    )''',
    'CREATE INDEX idx_return_items_return ON invoice_return_items(return_id)',
    'CREATE INDEX idx_return_items_item ON invoice_return_items(invoice_item_id)',
    'CREATE INDEX idx_return_items_product ON invoice_return_items(product_id) '
        'WHERE product_id IS NOT NULL',
  ];

  static const List<String> _ledgerIndexes = [
    'CREATE INDEX idx_debt_customer '
        'ON debt_transactions(customer_id, created_at, id)',
    'CREATE INDEX idx_debt_fifo ON debt_transactions('
        'customer_id, direction, created_at, id, '
        'amount_base_minor, due_at, type)',
    'CREATE INDEX idx_debt_invoice ON debt_transactions(invoice_id)',
    'CREATE INDEX idx_debt_created ON debt_transactions('
        'created_at, type, direction, amount_base_minor)',
    'CREATE UNIQUE INDEX idx_debt_reverses ON debt_transactions(reverses_id) '
        'WHERE reverses_id IS NOT NULL',
    'CREATE UNIQUE INDEX idx_debt_receipt ON debt_transactions(receipt_no) '
        'WHERE receipt_no IS NOT NULL',
    'CREATE INDEX idx_debt_return ON debt_transactions(return_id) '
        'WHERE return_id IS NOT NULL',
  ];

  static const List<String> _oldLedgerIndexes = [
    'idx_debt_customer',
    'idx_debt_fifo',
    'idx_debt_invoice',
    'idx_debt_created',
    'idx_debt_reverses',
    'idx_debt_receipt',
  ];

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final statement in _invoiceDdl) {
      await db.execute(statement);
    }
    for (final statement in _returnDdl) {
      await db.execute(statement);
    }
    // The counter `return_no` needs no row here: like `receipt_no`, it is
    // created by the first number drawn (`CounterRepository.next`).
    await _rebuildLedger(db);
  }

  static Future<void> _rebuildLedger(DatabaseExecutor db) async {
    // The triggers would refuse the emptying below, and the index names are
    // needed again by the new table.
    await db.execute('DROP TRIGGER IF EXISTS trg_debt_no_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_debt_no_delete');
    for (final index in _oldLedgerIndexes) {
      await db.execute('DROP INDEX IF EXISTS $index');
    }
    await db.execute('ALTER TABLE debt_transactions RENAME TO $_oldLedger');
    await db.execute(createLedger);

    // Every row, ids kept. In id order: an entry is always older than the
    // reversal that points at it.
    final columns = _carried.join(', ');
    await db.execute(
      'INSERT INTO debt_transactions ($columns) '
      'SELECT $columns FROM $_oldLedger ORDER BY id',
    );

    // Copied, and only then emptied: first the rows no other row reverses,
    // then what is left (see the class comment). A pass that removes
    // nothing while rows remain would be a loop of reversals, which the
    // ledger cannot hold; the migration then stops rather than drop rows it
    // could not account for — the upgrade is one transaction and rolls back.
    final copied = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM debt_transactions'),
    );
    var left = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_oldLedger'),
        ) ??
        0;
    if (copied != left) {
      throw StateError('ledger copy: $copied of $left rows');
    }
    while (left > 0) {
      final removed = await db.rawDelete(
        'DELETE FROM $_oldLedger WHERE id NOT IN ('
        'SELECT reverses_id FROM $_oldLedger WHERE reverses_id IS NOT NULL)',
      );
      if (removed == 0) {
        throw StateError('ledger copy: $left rows cannot be released');
      }
      left -= removed;
    }
    await db.execute('DROP TABLE $_oldLedger');

    for (final statement in _ledgerIndexes) {
      await db.execute(statement);
    }
    await db.execute(_noUpdateTrigger);
    await db.execute(_noDeleteTrigger);
  }
}
