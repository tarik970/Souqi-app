import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Schema version 1: every table the app will ever need in v1, including
/// feature-flagged ones (debt ledger, vouchers), so enabling a flag later
/// needs no migration.
///
/// Conventions:
/// - Timestamps: INTEGER epoch milliseconds, UTC.
/// - Money: INTEGER minor units, always next to a currency code.
/// - Quantities: INTEGER thousandths (500 = 0.5).
/// - Exchange rates: exact fractions rate_num/rate_den (both > 0), meaning
///   "rate_num/rate_den base units per 1 unit of this currency".
class MigrationV1 implements Migration {
  const MigrationV1();

  @override
  int get version => 1;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final statement in _ddl) {
      await db.execute(statement);
    }
    await _seed(db);
  }

  static const List<String> _ddl = [
    '''
    CREATE TABLE settings (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE counters (
      name  TEXT PRIMARY KEY,
      value INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE currencies (
      code            TEXT PRIMARY KEY,
      name_ar         TEXT NOT NULL,
      name_en         TEXT NOT NULL,
      symbol          TEXT NOT NULL DEFAULT '',
      decimal_places  INTEGER NOT NULL CHECK (decimal_places BETWEEN 0 AND 4),
      rate_num        INTEGER NOT NULL CHECK (rate_num > 0),
      rate_den        INTEGER NOT NULL CHECK (rate_den > 0),
      rate_updated_at INTEGER,
      is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
      sort_order      INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE units (
      id         INTEGER PRIMARY KEY,
      name_ar    TEXT NOT NULL,
      name_en    TEXT NOT NULL,
      is_preset  INTEGER NOT NULL DEFAULT 0 CHECK (is_preset IN (0,1)),
      is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
      sort_order INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE products (
      id                   INTEGER PRIMARY KEY,
      name                 TEXT NOT NULL,
      name_norm            TEXT NOT NULL,
      code                 TEXT,
      barcode              TEXT,
      kind                 TEXT NOT NULL CHECK (kind IN ('GOODS','SERVICE')),
      unit_id              INTEGER REFERENCES units(id) ON DELETE RESTRICT,
      price_minor          INTEGER NOT NULL CHECK (price_minor >= 0),
      currency_code        TEXT NOT NULL REFERENCES currencies(code),
      is_favorite          INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0,1)),
      is_active            INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
      requires_account     INTEGER NOT NULL DEFAULT 0 CHECK (requires_account IN (0,1)),
      sold_from_code_stock INTEGER NOT NULL DEFAULT 0 CHECK (sold_from_code_stock IN (0,1)),
      low_stock_threshold  INTEGER CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0),
      created_at           INTEGER NOT NULL,
      updated_at           INTEGER NOT NULL,
      CHECK (kind = 'GOODS' OR unit_id IS NULL)
    )''',
    'CREATE INDEX idx_products_name_norm ON products(name_norm)',
    'CREATE UNIQUE INDEX idx_products_code ON products(code) WHERE code IS NOT NULL',
    'CREATE INDEX idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL',
    'CREATE INDEX idx_products_fav ON products(is_favorite, is_active)',
    '''
    CREATE TABLE customers (
      id         INTEGER PRIMARY KEY,
      name       TEXT NOT NULL,
      name_norm  TEXT NOT NULL,
      phone      TEXT,
      phone_norm TEXT,
      notes      TEXT,
      is_active  INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_customers_name_norm ON customers(name_norm)',
    'CREATE INDEX idx_customers_phone_norm ON customers(phone_norm) WHERE phone_norm IS NOT NULL',
    '''
    CREATE TABLE customer_accounts (
      id                  INTEGER PRIMARY KEY,
      customer_id         INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
      account_number      TEXT NOT NULL,
      account_number_norm TEXT NOT NULL,
      label               TEXT,
      provider            TEXT,
      default_product_id  INTEGER REFERENCES products(id) ON DELETE SET NULL,
      renewal_days        INTEGER CHECK (renewal_days IS NULL OR renewal_days > 0),
      last_renewal_at     INTEGER,
      next_due_at         INTEGER,
      notes               TEXT,
      is_active           INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
      created_at          INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_accounts_customer ON customer_accounts(customer_id)',
    'CREATE INDEX idx_accounts_number_norm ON customer_accounts(account_number_norm)',
    'CREATE INDEX idx_accounts_due ON customer_accounts(next_due_at) WHERE next_due_at IS NOT NULL',
    '''
    CREATE TABLE invoices (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_no         INTEGER NOT NULL UNIQUE,
      created_at         INTEGER NOT NULL,
      currency_code      TEXT NOT NULL,
      base_currency_code TEXT NOT NULL,
      rate_num           INTEGER NOT NULL CHECK (rate_num > 0),
      rate_den           INTEGER NOT NULL CHECK (rate_den > 0),
      subtotal_minor     INTEGER NOT NULL,
      discount_type      TEXT CHECK (discount_type IN ('AMOUNT','PERCENT')),
      discount_value     INTEGER,
      discount_minor     INTEGER NOT NULL DEFAULT 0,
      total_minor        INTEGER NOT NULL,
      total_base_minor   INTEGER NOT NULL,
      extra1_currency_code TEXT,
      extra1_rate_num      INTEGER CHECK (extra1_rate_num IS NULL OR extra1_rate_num > 0),
      extra1_rate_den      INTEGER CHECK (extra1_rate_den IS NULL OR extra1_rate_den > 0),
      extra1_total_minor   INTEGER,
      extra2_currency_code TEXT,
      extra2_rate_num      INTEGER CHECK (extra2_rate_num IS NULL OR extra2_rate_num > 0),
      extra2_rate_den      INTEGER CHECK (extra2_rate_den IS NULL OR extra2_rate_den > 0),
      extra2_total_minor   INTEGER,
      customer_id      INTEGER REFERENCES customers(id) ON DELETE SET NULL,
      customer_name    TEXT,
      customer_phone   TEXT,
      account_id       INTEGER REFERENCES customer_accounts(id) ON DELETE SET NULL,
      account_number   TEXT,
      account_provider TEXT,
      note             TEXT
    )''',
    'CREATE INDEX idx_invoices_created ON invoices(created_at)',
    'CREATE INDEX idx_invoices_customer ON invoices(customer_id) WHERE customer_id IS NOT NULL',
    '''
    CREATE TABLE invoice_items (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id      INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      product_id      INTEGER REFERENCES products(id) ON DELETE SET NULL,
      sort_order      INTEGER NOT NULL DEFAULT 0,
      product_name    TEXT NOT NULL,
      product_code    TEXT,
      kind            TEXT NOT NULL CHECK (kind IN ('GOODS','SERVICE')),
      unit_name       TEXT,
      qty_thousandths INTEGER NOT NULL CHECK (qty_thousandths > 0),
      orig_unit_price_minor INTEGER NOT NULL,
      orig_currency_code    TEXT NOT NULL,
      orig_rate_num         INTEGER NOT NULL CHECK (orig_rate_num > 0),
      orig_rate_den         INTEGER NOT NULL CHECK (orig_rate_den > 0),
      unit_price_minor      INTEGER NOT NULL,
      line_total_minor      INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_items_invoice ON invoice_items(invoice_id)',
    'CREATE INDEX idx_items_product ON invoice_items(product_id) WHERE product_id IS NOT NULL',
    '''
    CREATE TABLE voucher_batches (
      id                  INTEGER PRIMARY KEY,
      product_id          INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      created_at          INTEGER NOT NULL,
      code_count          INTEGER NOT NULL,
      cost_per_card_minor INTEGER,
      cost_currency_code  TEXT REFERENCES currencies(code),
      note                TEXT
    )''',
    'CREATE INDEX idx_batches_product ON voucher_batches(product_id)',
    '''
    CREATE TABLE voucher_codes (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id      INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      batch_id        INTEGER NOT NULL REFERENCES voucher_batches(id) ON DELETE RESTRICT,
      code_cipher     BLOB NOT NULL,
      code_hash       TEXT NOT NULL,
      serial          TEXT,
      expiry_at       INTEGER,
      status          TEXT NOT NULL DEFAULT 'AVAILABLE'
                        CHECK (status IN ('AVAILABLE','SOLD','VOID')),
      status_changed_at INTEGER,
      sold_at         INTEGER,
      invoice_id      INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
      invoice_item_id INTEGER REFERENCES invoice_items(id) ON DELETE SET NULL,
      sold_invoice_no      INTEGER,
      sold_customer_id     INTEGER,
      sold_customer_name   TEXT,
      sold_account_number  TEXT,
      created_at      INTEGER NOT NULL
    )''',
    'CREATE UNIQUE INDEX idx_codes_hash ON voucher_codes(product_id, code_hash)',
    'CREATE INDEX idx_codes_alloc ON voucher_codes(product_id, status, expiry_at, batch_id, id)',
    'CREATE INDEX idx_codes_invoice ON voucher_codes(invoice_id) WHERE invoice_id IS NOT NULL',
    '''
    CREATE TABLE audit_log (
      id          INTEGER PRIMARY KEY,
      created_at  INTEGER NOT NULL,
      action      TEXT NOT NULL,
      entity_type TEXT,
      entity_id   INTEGER,
      details     TEXT
    )''',
    'CREATE INDEX idx_audit_created ON audit_log(created_at)',
    'CREATE INDEX idx_audit_action ON audit_log(action)',
    '''
    CREATE TABLE debt_transactions (
      id                 INTEGER PRIMARY KEY,
      customer_id        INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
      invoice_id         INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
      created_at         INTEGER NOT NULL,
      type               TEXT NOT NULL CHECK (type IN ('DEBT','PAYMENT','ADJUSTMENT')),
      amount_base_minor  INTEGER NOT NULL CHECK (amount_base_minor > 0),
      orig_amount_minor  INTEGER,
      orig_currency_code TEXT,
      orig_rate_num      INTEGER CHECK (orig_rate_num IS NULL OR orig_rate_num > 0),
      orig_rate_den      INTEGER CHECK (orig_rate_den IS NULL OR orig_rate_den > 0),
      note               TEXT
    )''',
    'CREATE INDEX idx_debt_customer ON debt_transactions(customer_id, created_at)',
  ];

  Future<void> _seed(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await db.insert('counters', {'name': 'invoice_no', 'value': 0});

    await db.insert('currencies', {
      'code': 'SYP',
      'name_ar': 'ليرة سورية',
      'name_en': 'Syrian Pound',
      'symbol': 'ل.س',
      'decimal_places': 0,
      'rate_num': 1,
      'rate_den': 1,
      'rate_updated_at': now,
      'is_active': 1,
      'sort_order': 0,
    });
    // USD is seeded with a placeholder 1/1 rate and NO rate_updated_at;
    // the UI must require a rate update before USD is used in a sale.
    await db.insert('currencies', {
      'code': 'USD',
      'name_ar': 'دولار أمريكي',
      'name_en': 'US Dollar',
      'symbol': r'$',
      'decimal_places': 2,
      'rate_num': 1,
      'rate_den': 1,
      'rate_updated_at': null,
      'is_active': 1,
      'sort_order': 1,
    });

    const presetUnits = [
      ('كغ', 'kg'),
      ('غ', 'g'),
      ('كيس', 'bag'),
      ('قطعة', 'piece'),
      ('علبة', 'box'),
      ('لتر', 'liter'),
    ];
    for (var i = 0; i < presetUnits.length; i++) {
      await db.insert('units', {
        'name_ar': presetUnits[i].$1,
        'name_en': presetUnits[i].$2,
        'is_preset': 1,
        'is_active': 1,
        'sort_order': i,
      });
    }

    const seedSettings = {
      'base_currency_code': 'SYP',
      'app_language': 'ar',
      'invoice_language': 'ar',
    };
    for (final entry in seedSettings.entries) {
      await db.insert('settings', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }
  }
}
