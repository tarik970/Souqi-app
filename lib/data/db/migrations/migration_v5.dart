import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Schema version 5: the customer debt ledger ("دفتر الديون").
///
/// `debt_transactions` has existed since version 1 but could not hold what a
/// real ledger needs, and sqlite cannot change a CHECK constraint in place —
/// so the table is REBUILT: the old one is renamed aside, the new one is
/// created, every old row is copied across with its id, and only then is the
/// old table dropped. No row is lost (the app never wrote any before this
/// version, but a database is carried over whatever it holds).
///
/// THE LEDGER
/// - `type`: DEBT (the unpaid part of a sale), MANUAL_DEBT, PAYMENT,
///   OPENING_BALANCE, ADJUSTMENT, REVERSAL.
/// - `direction`: +1 = the customer owes more (a debit), -1 = the customer
///   owes less (a credit). Fixed by the type where the type has only one
///   meaning; explicit for opening balances and adjustments; the opposite of
///   the reversed entry for a reversal. The balance of a customer is
///   `SUM(amount_base_minor * direction)` — positive: the customer owes the
///   shop; negative: the shop owes the customer. There is no stored balance
///   anywhere that could drift from that sum.
/// - `amount_base_minor`: always > 0, in base-currency minor units.
/// - `orig_*`: what was actually handed over when it was not the base
///   currency, with the exact rate fraction used — a snapshot, like every
///   other rate in the database.
/// - `payment_method`, `receipt_no` (payments), `due_at` (debits).
/// - `balance_before_base_minor`: what the RECEIPT of a payment printed as
///   the previous balance. A snapshot of a document, so a reprint says what
///   the original said; no calculation ever reads it.
/// - `invoice_id` + `invoice_no`: the link to the live invoice, and the
///   number that stays when the invoice is deleted.
/// - `reverses_id`: the entry a REVERSAL cancels (at most one reversal per
///   entry — the unique index).
/// - `created_at` is the date the entry counts from in the account (an
///   opening balance may be dated in the past); `recorded_at` is when the row
///   was written.
///
/// ENTRIES ARE NEVER EDITED OR DELETED. Two triggers make that a property of
/// the database, not a habit of the code: a delete always aborts, and an
/// update aborts unless it only clears `invoice_id` (the ON DELETE SET NULL
/// of a deleted invoice). A mistake is corrected by a REVERSAL entry.
///
/// THE INDEXES
/// - `idx_debt_customer`: one customer's ledger in order.
/// - `idx_debt_fifo`: covers the balance of every customer and the FIFO
///   aging (payments are allocated to the oldest debits) without touching
///   the table.
/// - `idx_debt_invoice`: deleting an invoice makes sqlite look for ledger
///   entries pointing at it (ON DELETE SET NULL). Without an index that is a
///   scan of the whole ledger per deleted invoice — the same trap
///   `idx_codes_item` closed in version 4.
/// - `idx_debt_created`: statistics for a period.
/// - `idx_debt_reverses`, `idx_debt_receipt`: unique, and tiny.
///
/// ALSO
/// - `customers.credit_limit_base_minor`, `customers.default_due_days`.
/// - `invoices.paid_minor`, `credit_used_minor` (invoice currency) and
///   `prev_balance_base_minor`, `new_balance_base_minor`: what the invoice
///   prints about its payment. NULL on every invoice saved before this
///   version, which therefore prints exactly as it always did.
class MigrationV5 implements Migration {
  const MigrationV5();

  @override
  int get version => 5;

  /// Days a debit carried over from the old table is given before it counts
  /// as overdue — the default of the new "due days" setting.
  static const int legacyDueDays = 30;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final statement in ddl) {
      await db.execute(statement);
    }
  }

  static const String createLedger = '''
    CREATE TABLE debt_transactions (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id        INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
      type               TEXT NOT NULL CHECK (type IN
                           ('DEBT','MANUAL_DEBT','PAYMENT','OPENING_BALANCE','ADJUSTMENT','REVERSAL')),
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
      reverses_id        INTEGER REFERENCES debt_transactions(id) ON DELETE RESTRICT,
      note               TEXT,
      created_at         INTEGER NOT NULL,
      recorded_at        INTEGER NOT NULL,
      CHECK (type NOT IN ('DEBT','MANUAL_DEBT') OR direction = 1),
      CHECK (type != 'PAYMENT' OR direction = -1),
      CHECK ((type = 'REVERSAL') = (reverses_id IS NOT NULL)),
      CHECK (receipt_no IS NULL OR type = 'PAYMENT')
    )''';

  /// Every column but `invoice_id`, compared NULL-safely: the one change an
  /// existing entry may ever see is its invoice link being cleared.
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
    'reverses_id',
    'note',
    'created_at',
    'recorded_at',
  ];

  static final String _noUpdateTrigger = '''
    CREATE TRIGGER trg_debt_no_update BEFORE UPDATE ON debt_transactions
    WHEN NOT (NEW.invoice_id IS NULL
      AND ${_frozenColumns.map((c) => 'NEW.$c IS OLD.$c').join(' AND ')})
    BEGIN
      SELECT RAISE(ABORT, 'ledger entries are never edited');
    END''';

  static const String _noDeleteTrigger = '''
    CREATE TRIGGER trg_debt_no_delete BEFORE DELETE ON debt_transactions
    BEGIN
      SELECT RAISE(ABORT, 'ledger entries are never deleted');
    END''';

  static final List<String> ddl = [
    'ALTER TABLE customers ADD COLUMN credit_limit_base_minor INTEGER '
        'CHECK (credit_limit_base_minor IS NULL OR credit_limit_base_minor >= 0)',
    'ALTER TABLE customers ADD COLUMN default_due_days INTEGER '
        'CHECK (default_due_days IS NULL OR default_due_days >= 0)',
    'ALTER TABLE invoices ADD COLUMN paid_minor INTEGER',
    'ALTER TABLE invoices ADD COLUMN credit_used_minor INTEGER',
    'ALTER TABLE invoices ADD COLUMN prev_balance_base_minor INTEGER',
    'ALTER TABLE invoices ADD COLUMN new_balance_base_minor INTEGER',

    // The rebuild. Nothing references the old table (no foreign key, view or
    // trigger), so renaming it aside is safe on every sqlite version.
    'ALTER TABLE debt_transactions RENAME TO debt_transactions_v1',
    createLedger,
    // The old rows, ids kept. Version 1 had no direction: a DEBT is a debit,
    // a PAYMENT a credit, and its sign-less ADJUSTMENT is carried as a debit.
    // The invoice number is snapshotted from the invoice while it is still
    // there.
    '''
    INSERT INTO debt_transactions (
      id, customer_id, type, direction, amount_base_minor,
      orig_amount_minor, orig_currency_code, orig_rate_num, orig_rate_den,
      due_at, invoice_id, invoice_no, note, created_at, recorded_at)
    SELECT o.id, o.customer_id, o.type,
      CASE o.type WHEN 'PAYMENT' THEN -1 ELSE 1 END,
      o.amount_base_minor,
      o.orig_amount_minor, o.orig_currency_code, o.orig_rate_num, o.orig_rate_den,
      CASE WHEN o.type = 'PAYMENT' THEN NULL
           ELSE o.created_at + ${legacyDueDays * Duration.millisecondsPerDay} END,
      o.invoice_id,
      (SELECT i.invoice_no FROM invoices i WHERE i.id = o.invoice_id),
      o.note, o.created_at, o.created_at
    FROM debt_transactions_v1 o''',
    'DROP TABLE debt_transactions_v1',

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
    _noUpdateTrigger,
    _noDeleteTrigger,
  ];
}
