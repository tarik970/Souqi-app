import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/utils/normalize.dart';
import 'migration.dart';

/// Schema version 7: ONE BARCODE, ONE PRODUCT — kept by the database itself.
///
/// Until now the rule lived in code only (`ProductRepository.isBarcodeTaken`)
/// and `idx_products_barcode` was an ordinary index. It becomes a UNIQUE
/// partial index (`WHERE barcode IS NOT NULL`: products without a barcode
/// stay as many as they like), so a scan can never have two answers.
///
/// (The same step rewrites the SHORT CODES into the form the lookups
/// compare, see [_normalizeCodes].)
///
/// A database that already holds the same barcode on several products is
/// cleaned first, and nothing but the barcode itself is touched:
///
/// - the barcode STAYS on the product a scan finds today — an active product
///   before a deactivated one, then the oldest (lowest id);
/// - every other product with that barcode has its barcode cleared (the
///   product, its price and its sales stay exactly as they are);
/// - a barcode stored with spaces, dashes or Arabic-Indic digits is rewritten
///   the way the lookups compare it ([normalizeCode]), and a blank one
///   becomes "no barcode".
///
/// How many were cleared, and on which products, is written to the audit log
/// (`BARCODE_DEDUP`) in the same transaction, so the shop can give those
/// products a barcode again. A database with no duplicates gets no line.
class MigrationV7 implements Migration {
  const MigrationV7();

  @override
  int get version => 7;

  /// The audit line of a clean-up (`AuditAction.barcodeDedup`).
  static const String auditAction = 'BARCODE_DEDUP';

  /// Product names listed in the audit line; the count is always complete.
  static const int _namesLogged = 20;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    final rows = await db.query(
      'products',
      columns: ['id', 'name', 'barcode'],
      where: 'barcode IS NOT NULL',
      // The order a scan resolves a barcode in: the first row of each
      // barcode is the one that keeps it.
      orderBy: 'is_active DESC, id ASC',
    );

    final kept = <String>{};
    final clearedNames = <String>[];
    var cleared = 0;
    for (final row in rows) {
      final id = row['id'] as int;
      final stored = '${row['barcode']}';
      final normalized = normalizeCode(stored);
      if (normalized.isEmpty) {
        // Blank: never was a barcode.
        await _setBarcode(db, id, null);
      } else if (!kept.add(normalized)) {
        await _setBarcode(db, id, null);
        cleared++;
        if (clearedNames.length < _namesLogged) {
          clearedNames.add('${row['name']}');
        }
      } else if (normalized != stored) {
        await _setBarcode(db, id, normalized);
      }
    }

    await _normalizeCodes(db);

    await db.execute('DROP INDEX IF EXISTS idx_products_barcode');
    await db.execute(
      'CREATE UNIQUE INDEX idx_products_barcode '
      'ON products(barcode) WHERE barcode IS NOT NULL',
    );

    if (cleared > 0) {
      await db.insert('audit_log', {
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'action': auditAction,
        'details': jsonEncode({
          'products': cleared,
          'names': clearedNames.join(', '),
        }),
      });
    }
  }

  /// SHORT CODES are rewritten the way every lookup compares them
  /// ([normalizeCode]): a code typed as "١٠١" or "a-5" was stored as typed
  /// and could never be found by typing it on the sale screen. A code whose
  /// normal form already belongs to another product is LEFT AS IT IS — no
  /// worse than before, and nothing is lost; a blank one becomes "no code".
  static Future<void> _normalizeCodes(DatabaseExecutor db) async {
    final rows = await db.query(
      'products',
      columns: ['id', 'code'],
      where: 'code IS NOT NULL',
      orderBy: 'id ASC',
    );
    // The codes that are already in their normal form keep it.
    final taken = <String>{
      for (final row in rows)
        if (normalizeCode('${row['code']}') == '${row['code']}')
          '${row['code']}',
    };
    for (final row in rows) {
      final stored = '${row['code']}';
      final normalized = normalizeCode(stored);
      if (normalized == stored) continue;
      if (normalized.isEmpty) {
        await db.update(
          'products',
          {'code': null},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } else if (taken.add(normalized)) {
        await db.update(
          'products',
          {'code': normalized},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<void> _setBarcode(
    DatabaseExecutor db,
    int id,
    String? barcode,
  ) =>
      db.update(
        'products',
        {'barcode': barcode},
        where: 'id = ?',
        whereArgs: [id],
      );
}
