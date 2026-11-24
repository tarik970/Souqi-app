import 'package:sqflite/sqflite.dart';

import '../../../core/utils/normalize.dart';
import 'migration.dart';

/// Schema version 3: normalized, indexed search columns on the invoice
/// SNAPSHOTS, so the archive can search 50,000 invoices by product name,
/// customer name, phone or account number without reading them into Dart.
///
/// The snapshots themselves (`product_name`, `customer_name`, …) are never
/// touched: an archived invoice must keep showing exactly the text that was
/// sold. The `*_norm` columns are a search index beside them, filled through
/// the same shared normalizers the live tables use — which is what makes
/// "السكر" find an invoice that sold "سكر".
///
/// `invoice_items.product_name_norm` is also the grouping key statistics use
/// for items that never became products.
class MigrationV3 implements Migration {
  const MigrationV3();

  @override
  int get version => 3;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final statement in ddl) {
      await db.execute(statement);
    }
    await backfill(db);
  }

  /// Also used by the v1+v2 → v3 path and by the migration test.
  static const List<String> ddl = [
    // NOT NULL with a default: an ALTER TABLE on a table with rows in it
    // cannot leave existing rows without a value.
    "ALTER TABLE invoice_items ADD COLUMN product_name_norm TEXT NOT NULL DEFAULT ''",
    'CREATE INDEX idx_items_name_norm ON invoice_items(product_name_norm)',
    'ALTER TABLE invoices ADD COLUMN customer_name_norm TEXT',
    'ALTER TABLE invoices ADD COLUMN customer_phone_norm TEXT',
    'ALTER TABLE invoices ADD COLUMN account_number_norm TEXT',
    'CREATE INDEX idx_invoices_customer_norm ON invoices(customer_name_norm) '
        'WHERE customer_name_norm IS NOT NULL',
    'CREATE INDEX idx_invoices_phone_norm ON invoices(customer_phone_norm) '
        'WHERE customer_phone_norm IS NOT NULL',
    'CREATE INDEX idx_invoices_account_norm ON invoices(account_number_norm) '
        'WHERE account_number_norm IS NOT NULL',
  ];

  /// Fills the new columns for invoices saved before this version. Done in
  /// one transaction-sized batch per table; an upgrade runs once, and a shop
  /// with a year of invoices must not wait for 50,000 round trips.
  static Future<void> backfill(DatabaseExecutor db) async {
    final items = await db.query(
      'invoice_items',
      columns: ['id', 'product_name'],
    );
    var batch = db.batch();
    for (final row in items) {
      batch.update(
        'invoice_items',
        {'product_name_norm': normalizeName(row['product_name'] as String)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);

    final invoices = await db.query(
      'invoices',
      columns: ['id', 'customer_name', 'customer_phone', 'account_number'],
    );
    batch = db.batch();
    for (final row in invoices) {
      final name = row['customer_name'] as String?;
      final phone = row['customer_phone'] as String?;
      final account = row['account_number'] as String?;
      if (name == null && phone == null && account == null) continue;
      batch.update(
        'invoices',
        {
          'customer_name_norm': name == null ? null : normalizeName(name),
          'customer_phone_norm': phone == null ? null : normalizePhone(phone),
          'account_number_norm':
              account == null ? null : normalizeCode(account),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }
}
