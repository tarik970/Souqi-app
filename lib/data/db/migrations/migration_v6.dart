import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Schema version 6: the record behind "undo last bulk price change".
///
/// - `price_changes`: one row per bulk change — the percentage in basis
///   points (+7.5 % = 750), the rounding step in minor units, what it was
///   applied to, how many products it changed, and when it was undone.
/// - `price_change_items`: each product's price before and after.
///
/// Only the LAST change is kept (the repository clears older ones when a new
/// change is applied): the undo is one step, and the audit log is the
/// history. A product that is hard-deleted takes its line with it.
///
/// Nothing existing is touched; no data moves.
class MigrationV6 implements Migration {
  const MigrationV6();

  @override
  int get version => 6;

  static const _statements = [
    '''
    CREATE TABLE price_changes (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at     INTEGER NOT NULL,
      percent_bp     INTEGER NOT NULL CHECK (percent_bp != 0),
      rounding_step  INTEGER NOT NULL CHECK (rounding_step > 0),
      scope          TEXT NOT NULL
                     CHECK (scope IN ('ALL', 'CURRENCY', 'SELECTED')),
      scope_currency TEXT,
      product_count  INTEGER NOT NULL CHECK (product_count >= 0),
      undone_at      INTEGER
    )''',
    '''
    CREATE TABLE price_change_items (
      change_id       INTEGER NOT NULL
                      REFERENCES price_changes(id) ON DELETE CASCADE,
      product_id      INTEGER NOT NULL
                      REFERENCES products(id) ON DELETE CASCADE,
      currency_code   TEXT NOT NULL,
      old_price_minor INTEGER NOT NULL,
      new_price_minor INTEGER NOT NULL,
      PRIMARY KEY (change_id, product_id)
    )''',
    // Deleting a product looks for its lines (ON DELETE CASCADE).
    'CREATE INDEX idx_price_change_product ON price_change_items(product_id)',
  ];

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final sql in _statements) {
      await db.execute(sql);
    }
  }
}
