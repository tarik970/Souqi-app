import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Schema version 4: what selling prepaid card codes needs on top of the
/// voucher tables version 1 already created. Columns and indexes are only
/// ADDED; no row is rewritten or removed.
///
/// - `voucher_batches.expiry_at`: the expiry the batch was loaded with, so
///   the batch list can show it without reading the codes.
/// - `voucher_codes.status_note`: the reason typed when a code was voided or
///   returned to stock.
/// - `voucher_codes.sold_price_base_minor` / `sold_cost_base_minor`: what the
///   card was sold for and what it cost, both in base currency AT THE MOMENT
///   OF THE SALE. Like the other `sold_*` snapshots they stay when the
///   invoice is deleted, which is what lets "cards sold" and its profit
///   survive the archive's retention sweep.
/// - `audit_log.product_id` / `product_name`: the product a sensitive action
///   was about, as its own column (the screen lists and filters by it) with
///   the name as a snapshot.
///
/// The indexes:
/// - `idx_codes_item`: deleting an invoice cascades to its items, and every
///   deleted item makes sqlite look for voucher codes pointing at it (ON
///   DELETE SET NULL). Without an index that lookup scans the whole code
///   table once per item — invisible while the table was empty, minutes on a
///   big archive delete once a shop has loaded a few thousand cards.
/// - `idx_codes_hash_lookup`: "was this card sold, and to whom?" looks a code
///   up by its hash across all products; the unique index from version 1
///   leads with `product_id` and cannot serve that.
/// - `idx_codes_sold`: statistics for a period.
/// - `idx_codes_batch`: the counts of one batch, and deleting an unsold one.
/// - `idx_codes_status`: "how many can be sold right now, per product" — the
///   number shown on every card product — touches only the AVAILABLE rows,
///   however many thousand SOLD ones have piled up behind them.
class MigrationV4 implements Migration {
  const MigrationV4();

  @override
  int get version => 4;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final statement in ddl) {
      await db.execute(statement);
    }
  }

  static const List<String> ddl = [
    'ALTER TABLE voucher_batches ADD COLUMN expiry_at INTEGER',
    'ALTER TABLE voucher_codes ADD COLUMN status_note TEXT',
    'ALTER TABLE voucher_codes ADD COLUMN sold_price_base_minor INTEGER',
    'ALTER TABLE voucher_codes ADD COLUMN sold_cost_base_minor INTEGER',
    'ALTER TABLE audit_log ADD COLUMN product_id INTEGER',
    'ALTER TABLE audit_log ADD COLUMN product_name TEXT',
    'CREATE INDEX idx_codes_item ON voucher_codes(invoice_item_id)',
    'CREATE INDEX idx_codes_hash_lookup ON voucher_codes(code_hash)',
    'CREATE INDEX idx_codes_sold ON voucher_codes(sold_at) '
        'WHERE sold_at IS NOT NULL',
    'CREATE INDEX idx_codes_batch ON voucher_codes(batch_id, status)',
    'CREATE INDEX idx_codes_status '
        'ON voucher_codes(status, product_id, expiry_at)',
  ];
}
