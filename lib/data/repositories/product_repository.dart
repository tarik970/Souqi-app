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

  /// "Most sold" everywhere in the app means the last 30 days.
  static const salesWindow = Duration(days: 30);

  /// The favorites bar never grows past this by itself (stars can exceed it).
  static const favoritesBarLimit = 12;

  /// How often each product was sold since `?` (one bound argument: the
  /// window start in epoch ms). `times` counts invoice lines — the number of
  /// sales — rather than adding quantities up, because quantities of
  /// different units cannot be compared (0.25 kg of coffee, 24 bottles).
  /// The quantity only breaks ties.
  static const _salesSubquery = '''
    SELECT ii.product_id AS pid,
           COUNT(*) AS times,
           SUM(ii.qty_thousandths) AS qty
      FROM invoice_items ii
      JOIN invoices i ON i.id = ii.invoice_id
     WHERE ii.product_id IS NOT NULL AND i.created_at >= ?
     GROUP BY ii.product_id''';

  int _windowStart(DateTime? now) => (now ?? DateTime.now())
      .toUtc()
      .subtract(salesWindow)
      .millisecondsSinceEpoch;

  /// `%` and `_` typed by the user must match themselves.
  static String _escapeLike(String text) => text
      .replaceAll('!', '!!')
      .replaceAll('%', '!%')
      .replaceAll('_', '!_');

  /// Active products matching [query] (name or code) and [kind].
  /// [includeInactive] additionally returns deactivated products.
  ///
  /// Without a query: favorites first, then by name. With a query the best
  /// match comes first — exact code or barcode, then exact name, then names
  /// (or codes) starting with the text, then names containing it — and within
  /// each group the most-sold products of the last 30 days lead. The name is
  /// compared in its normalized form (see [normalizeName]), so "السكر" finds
  /// "سكر". [now] exists for tests.
  Future<List<Product>> list({
    String query = '',
    ProductKind? kind,
    bool includeInactive = false,
    bool favoritesOnly = false,
    DateTime? now,
  }) async {
    final where = StringBuffer('1 = 1');
    final whereArgs = <Object?>[];
    if (!includeInactive) {
      where.write(' AND p.is_active = 1');
    }
    if (kind != null) {
      where.write(' AND p.kind = ?');
      whereArgs.add(kind.db);
    }
    if (favoritesOnly) {
      where.write(' AND p.is_favorite = 1');
    }
    final q = query.trim();
    if (q.isEmpty) {
      final rows = await _db.rawQuery(
        'SELECT p.* FROM products p WHERE $where '
        'ORDER BY p.is_active DESC, p.is_favorite DESC, p.name_norm ASC',
        whereArgs,
      );
      return rows.map(Product.fromMap).toList();
    }

    final name = normalizeName(q);
    final exactCode = normalizeCode(q);
    final codePrefix = '${_escapeLike(normalizeDigits(q))}%';
    // A query that normalizes to nothing (only diacritics, say) must not turn
    // into LIKE '%%' and match every product: '' never equals a name.
    final namePrefix = name.isEmpty ? '' : '${_escapeLike(name)}%';
    final nameAnywhere = name.isEmpty ? '' : '%${_escapeLike(name)}%';

    final rows = await _db.rawQuery(
      '''
      SELECT p.*,
             CASE
               WHEN p.code = ? OR p.barcode = ? THEN 0
               WHEN p.name_norm = ? THEN 1
               WHEN p.name_norm LIKE ? ESCAPE '!'
                    OR p.code LIKE ? ESCAPE '!' THEN 2
               ELSE 3
             END AS match_rank
        FROM products p
        LEFT JOIN ($_salesSubquery) s ON s.pid = p.id
       WHERE $where
         AND (p.name_norm LIKE ? ESCAPE '!'
              OR p.code LIKE ? ESCAPE '!'
              OR p.code = ?
              OR p.barcode = ?)
       ORDER BY p.is_active DESC,
                match_rank ASC,
                COALESCE(s.times, 0) DESC,
                COALESCE(s.qty, 0) DESC,
                p.is_favorite DESC,
                p.name_norm ASC''',
      [
        exactCode, exactCode, name, namePrefix, codePrefix, // CASE
        _windowStart(now), // sales subquery
        ...whereArgs,
        nameAnywhere, codePrefix, exactCode, exactCode,
      ],
    );
    return rows.map(Product.fromMap).toList();
  }

  /// The sale screen's favorites bar: every starred product first (by name),
  /// then — when [includeAuto] — the most-sold products of the last 30 days
  /// that are not starred, until the bar holds [limit] buttons. Stars are
  /// never cut off: a shop that starred 15 products sees all 15.
  Future<List<Product>> favoritesBar({
    bool includeAuto = true,
    int limit = favoritesBarLimit,
    DateTime? now,
  }) async {
    final starred = await list(favoritesOnly: true);
    final room = limit - starred.length;
    if (!includeAuto || room <= 0) return starred;
    final rows = await _db.rawQuery(
      '''
      SELECT p.*
        FROM products p
        JOIN ($_salesSubquery) s ON s.pid = p.id
       WHERE p.is_active = 1 AND p.is_favorite = 0
       ORDER BY s.times DESC, s.qty DESC, p.name_norm ASC
       LIMIT ?''',
      [_windowStart(now), room],
    );
    return [...starred, ...rows.map(Product.fromMap)];
  }

  /// The product whose normalized name equals that of [name], if any — the
  /// duplicate guard. Inactive products count too (an active one wins), so a
  /// product the shop once deactivated is reused instead of duplicated.
  Future<Product?> findByName(String name) async {
    final normalized = normalizeName(name);
    if (normalized.isEmpty) return null;
    final rows = await _db.query(
      'products',
      where: 'name_norm = ?',
      whereArgs: [normalized],
      orderBy: 'is_active DESC, id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// "Remember last price": sets the saved price to what the product was just
  /// sold for. Only when the product is priced in [currencyCode] — a price in
  /// another currency is a different number, not a new price — and never to
  /// zero. Returns whether the price changed.
  Future<bool> updatePriceFromSale(
    int id, {
    required int priceMinor,
    required String currencyCode,
  }) async {
    if (priceMinor <= 0) return false;
    final changed = await _db.update(
      'products',
      {
        'price_minor': priceMinor,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ? AND currency_code = ? AND price_minor != ?',
      whereArgs: [id, currencyCode, priceMinor],
    );
    return changed > 0;
  }

  /// Exact lookup for the sale screen's "type a code and press Enter" flow:
  /// matches the short code first, then the barcode. Active products only.
  Future<Product?> getByExactCode(String code) async {
    final normalized = normalizeCode(code);
    if (normalized.isEmpty) return null;
    for (final column in ['code', 'barcode']) {
      final rows = await _db.query(
        'products',
        where: 'is_active = 1 AND $column = ?',
        whereArgs: [normalized],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    return null;
  }

  /// Whether a product with this id still exists.
  Future<bool> exists(int id) async {
    final rows = await _db.query(
      'products',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Product?> getById(int id) async {
    final rows =
        await _db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// A barcode as it is stored and looked up: [normalizeCode] (no spaces or
  /// dashes, Western digits, upper case). Null for nothing at all.
  static String? normalizeBarcode(String? barcode) {
    if (barcode == null) return null;
    final normalized = normalizeCode(barcode);
    return normalized.isEmpty ? null : normalized;
  }

  /// The product carrying [barcode] — active or not, the active one first.
  Future<Product?> findByBarcode(String barcode) async {
    final normalized = normalizeBarcode(barcode);
    if (normalized == null) return null;
    final rows = await _db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [normalized],
      orderBy: 'is_active DESC, id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// True when [barcode] is already on a different product (one barcode,
  /// one product: a scan must never have to choose).
  Future<bool> isBarcodeTaken(String barcode, {int? excludeId}) async {
    final normalized = normalizeBarcode(barcode);
    if (normalized == null) return false;
    final rows = await _db.query(
      'products',
      columns: ['id'],
      where: excludeId == null ? 'barcode = ?' : 'barcode = ? AND id != ?',
      whereArgs: excludeId == null ? [normalized] : [normalized, excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Gives a product the barcode it was first sold under, unless it has one
  /// or another product does.
  Future<void> adoptBarcode(int id, String barcode) async {
    final normalized = normalizeBarcode(barcode);
    if (normalized == null || await isBarcodeTaken(normalized, excludeId: id)) {
      return;
    }
    await _db.update(
      'products',
      {
        'barcode': normalized,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ? AND barcode IS NULL',
      whereArgs: [id],
    );
  }

  /// A short code as it is stored and looked up: [normalizeCode] (Western
  /// digits, no spaces or dashes, upper case) — the form every lookup
  /// compares with. Stored as typed, "١٠١" from an Arabic keyboard could
  /// never be found by typing 101, or ١٠١. Null for nothing at all.
  static String? normalizeProductCode(String? code) {
    if (code == null) return null;
    final normalized = normalizeCode(code);
    return normalized.isEmpty ? null : normalized;
  }

  /// True when [code] is already used by a different product.
  Future<bool> isCodeTaken(String code, {int? excludeId}) async {
    code = normalizeCode(code);
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
  /// voucher stock, or is the default package of a customer's account; then
  /// it is deactivated so history — and the account's package — stay intact.
  ///
  /// The schema alone would let the delete through and quietly clear the
  /// account's package (ON DELETE SET NULL); a renewal would then open with
  /// an empty cart and nobody would know why.
  Future<ProductDeleteResult> delete(int id) async {
    final used = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT EXISTS('
          '  SELECT 1 FROM invoice_items WHERE product_id = ?'
          '  UNION ALL'
          '  SELECT 1 FROM voucher_batches WHERE product_id = ?'
          '  UNION ALL'
          '  SELECT 1 FROM customer_accounts WHERE default_product_id = ?'
          ')',
          [id, id, id],
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
      'code': normalizeProductCode(p.code),
      'barcode': normalizeBarcode(p.barcode),
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
