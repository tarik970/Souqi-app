import 'package:sqflite/sqflite.dart';

import '../../core/utils/normalize.dart';
import '../../domain/models/product.dart';

enum ProductDeleteResult {
  /// The product had no invoice/voucher history and was removed.
  deleted,

  /// The product is referenced by history and was deactivated instead.
  deactivated,
}

class ProductRepository {
  ProductRepository(this._db);

  final DatabaseExecutor _db;

  /// Active products matching [query] (name or code) and [kind].
  /// [includeInactive] additionally returns deactivated products.
  Future<List<Product>> list({
    String query = '',
    ProductKind? kind,
    bool includeInactive = false,
    bool favoritesOnly = false,
  }) async {
    final where = StringBuffer('1 = 1');
    final args = <Object?>[];
    if (!includeInactive) {
      where.write(' AND is_active = 1');
    }
    if (kind != null) {
      where.write(' AND kind = ?');
      args.add(kind.db);
    }
    if (favoritesOnly) {
      where.write(' AND is_favorite = 1');
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(' AND (name_norm LIKE ? OR code LIKE ? OR barcode = ?)');
      final nameLike = '%${normalizeName(q)}%';
      final codeLike = '${normalizeDigits(q)}%';
      args.addAll([nameLike, codeLike, normalizeCode(q)]);
    }
    final rows = await _db.query(
      'products',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'is_active DESC, is_favorite DESC, name_norm ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getById(int id) async {
    final rows =
        await _db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// True when [code] is already used by a different product.
  Future<bool> isCodeTaken(String code, {int? excludeId}) async {
    final rows = await _db.query(
      'products',
      columns: ['id'],
      where: excludeId == null ? 'code = ?' : 'code = ? AND id != ?',
      whereArgs: excludeId == null ? [code] : [code, excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insert(Product product) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.insert('products', {
      ..._toRow(product),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> update(Product product) async {
    await _db.update(
      'products',
      {
        ..._toRow(product),
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> setFavorite(int id, bool favorite) async {
    await _db.update(
      'products',
      {
        'is_favorite': favorite ? 1 : 0,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setActive(int id, bool active) async {
    await _db.update(
      'products',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-deletes the product unless it is referenced by invoice items or
  /// voucher stock; then it is deactivated so history stays intact.
  Future<ProductDeleteResult> delete(int id) async {
    final used = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT EXISTS('
          '  SELECT 1 FROM invoice_items WHERE product_id = ?'
          '  UNION ALL'
          '  SELECT 1 FROM voucher_batches WHERE product_id = ?'
          ')',
          [id, id],
        )) ==
        1;
    if (used) {
      await setActive(id, false);
      return ProductDeleteResult.deactivated;
    }
    await _db.delete('products', where: 'id = ?', whereArgs: [id]);
    return ProductDeleteResult.deleted;
  }

  Map<String, Object?> _toRow(Product p) {
    final isService = p.kind == ProductKind.service;
    return {
      'name': p.name.trim(),
      'name_norm': normalizeName(p.name),
      'code': p.code,
      'barcode': p.barcode,
      'kind': p.kind.db,
      'unit_id': isService ? null : p.unitId,
      'price_minor': p.priceMinor,
      'currency_code': p.currencyCode,
      'is_favorite': p.isFavorite ? 1 : 0,
      'is_active': p.isActive ? 1 : 0,
      'requires_account': isService && p.requiresAccount ? 1 : 0,
      'sold_from_code_stock': isService && p.soldFromCodeStock ? 1 : 0,
      'low_stock_threshold': p.lowStockThreshold,
    };
  }
}
