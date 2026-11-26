import 'package:sqflite/sqflite.dart';

import '../../domain/models/price_change.dart';
import '../../domain/models/voucher.dart';
import 'audit_repository.dart';

/// Bulk price changes and their one-step undo (schema version 6).
///
/// Takes a [Database] because applying and undoing must each be ONE
/// transaction: every price, the undo record and the audit line land
/// together, or none of them does.
class PriceChangeRepository {
  PriceChangeRepository(this._db);

  final Database _db;

  /// The products a change is about, as the preview lists them: active and
  /// inactive alike (an inactive product keeps a price and may come back),
  /// by name. [currencyCode] limits it to products priced in that currency;
  /// [productIds] to a chosen set.
  Future<PriceChangePlan> preview({
    required int basisPoints,
    required PriceRounding rounding,
    required PriceChangeScope scope,
    String? currencyCode,
    Set<int> productIds = const {},
  }) async {
    final rows = await _db.query(
      'products',
      columns: ['id', 'name', 'currency_code', 'price_minor'],
      where: switch (scope) {
        PriceChangeScope.all => null,
        PriceChangeScope.currency => 'currency_code = ?',
        // Chosen in Dart below, not with "id IN (?, ?, …)": SQLite before
        // 3.32 (Android 11 and older) takes at most 999 parameters, and
        // "select all shown" in a big shop passes that.
        PriceChangeScope.selected => productIds.isEmpty ? '0' : null,
      },
      whereArgs: switch (scope) {
        PriceChangeScope.all => null,
        PriceChangeScope.currency => [currencyCode],
        PriceChangeScope.selected => null,
      },
      orderBy: 'is_active DESC, name_norm ASC, id ASC',
    );
    return planBulkPriceChange(
      products: [
        for (final row in rows)
          if (scope != PriceChangeScope.selected ||
              productIds.contains(row['id']))
          (
            id: row['id'] as int,
            name: row['name'] as String,
            currencyCode: row['currency_code'] as String,
            priceMinor: row['price_minor'] as int,
          ),
      ],
      basisPoints: basisPoints,
      rounding: rounding,
      scope: scope,
      scopeCurrency: scope == PriceChangeScope.currency ? currencyCode : null,
    );
  }

  /// Writes [plan] in one transaction: the new prices, the undo record
  /// (replacing the previous one — the undo is one step) and the audit line.
  ///
  /// A product whose price changed since the preview was made is written
  /// from its CURRENT price, not from the stale one on screen: the percentage
  /// is what the seller chose, the preview only showed it. Returns how many
  /// prices changed.
  Future<int> apply(PriceChangePlan plan, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return _db.transaction((txn) async {
      await txn.delete('price_change_items');
      await txn.delete('price_changes');
      final changeId = await txn.insert('price_changes', {
        'created_at': at,
        'percent_bp': plan.basisPoints,
        'rounding_step': plan.rounding.step,
        'scope': plan.scope.db,
        'scope_currency': plan.scopeCurrency,
        'product_count': 0,
      });
      var changed = 0;
      for (final line in plan.lines) {
        final rows = await txn.query(
          'products',
          columns: ['price_minor', 'currency_code'],
          where: 'id = ?',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (rows.isEmpty) continue; // deleted meanwhile
        final old = rows.first['price_minor'] as int;
        final currency = rows.first['currency_code'] as String;
        // Still in scope? A product moved to another currency meanwhile is
        // no longer one of "the products priced in USD".
        if (plan.scope == PriceChangeScope.currency &&
            currency != plan.scopeCurrency) {
          continue;
        }
        final next = bulkNewPrice(old, plan.basisPoints, plan.rounding);
        if (next == old) continue;
        await txn.update(
          'products',
          {'price_minor': next, 'updated_at': at},
          where: 'id = ?',
          whereArgs: [line.productId],
        );
        await txn.insert('price_change_items', {
          'change_id': changeId,
          'product_id': line.productId,
          'currency_code': currency,
          'old_price_minor': old,
          'new_price_minor': next,
        });
        changed++;
      }
      await txn.update(
        'price_changes',
        {'product_count': changed},
        where: 'id = ?',
        whereArgs: [changeId],
      );
      await AuditRepository(txn).log(
        AuditAction.priceBulkChange,
        entityType: 'price_change',
        entityId: changeId,
        details: {
          'percent': formatBasisPoints(plan.basisPoints),
          'rounding': plan.rounding.step == 1 ? null : plan.rounding.step,
          'scope': plan.scope.db,
          'currency': plan.scopeCurrency,
          'products': changed,
        },
        at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      );
      return changed;
    });
  }

  /// The change "undo" would take back: the last one, if it has not been
  /// undone yet.
  Future<PriceChangeRecord?> lastUndoable() async {
    final rows = await _db.query(
      'price_changes',
      where: 'undone_at IS NULL AND product_count > 0',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PriceChangeRecord(
      id: row['id'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      basisPoints: row['percent_bp'] as int,
      rounding: PriceRounding.fromStep(row['rounding_step'] as int),
      scope: PriceChangeScope.fromDb(row['scope'] as String?),
      scopeCurrency: row['scope_currency'] as String?,
      productCount: row['product_count'] as int,
    );
  }

  /// Puts back the prices of the last change, in one transaction, and logs
  /// it. A product whose price is no longer what the change set (edited by
  /// hand or by a sale since, or moved to another currency) is left alone:
  /// undo must never overwrite a newer decision. Null when there is nothing
  /// to undo.
  Future<PriceUndoResult?> undoLast({DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return _db.transaction((txn) async {
      final changes = await txn.query(
        'price_changes',
        where: 'undone_at IS NULL AND product_count > 0',
        orderBy: 'id DESC',
        limit: 1,
      );
      if (changes.isEmpty) return null;
      final changeId = changes.first['id'] as int;
      final items = await txn.query(
        'price_change_items',
        where: 'change_id = ?',
        whereArgs: [changeId],
      );
      var restored = 0;
      for (final item in items) {
        final count = await txn.rawUpdate(
          'UPDATE products SET price_minor = ?, updated_at = ? '
          'WHERE id = ? AND price_minor = ? AND currency_code = ?',
          [
            item['old_price_minor'],
            at,
            item['product_id'],
            item['new_price_minor'],
            item['currency_code'],
          ],
        );
        restored += count;
      }
      // Products deleted since are not in `items` any more (cascade).
      final skipped = (changes.first['product_count'] as int) - restored;
      await txn.update(
        'price_changes',
        {'undone_at': at},
        where: 'id = ?',
        whereArgs: [changeId],
      );
      await AuditRepository(txn).log(
        AuditAction.priceBulkUndo,
        entityType: 'price_change',
        entityId: changeId,
        details: {
          'percent': formatBasisPoints(changes.first['percent_bp'] as int),
          'products': restored,
          'skipped': skipped > 0 ? skipped : null,
        },
        at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      );
      return PriceUndoResult(
        restored: restored,
        skipped: skipped < 0 ? 0 : skipped,
      );
    });
  }
}
