import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/money/exchange.dart';
import '../../core/security/code_cipher.dart';
import '../../core/utils/voucher_format.dart';
import '../../core/vouchers/code_import.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/product.dart';
import '../../domain/models/voucher.dart';
import 'audit_repository.dart';

/// The stock of prepaid card codes: loading batches, counting, selling inside
/// the invoice transaction, voiding, returning, looking a card up.
///
/// Three rules hold for every method here:
///
/// 1. A code is only ever written encrypted (see [CodeCipher]) and only ever
///    read back in the clear by the few methods that say so in their name.
/// 2. Every change of status and its audit line share one transaction.
/// 3. Nothing here puts a code into an exception, a log line or a `toString`.
class VoucherRepository {
  VoucherRepository(this._db, this._cipher);

  final Database _db;
  final CodeCipher _cipher;

  /// Rows per `IN (…)` list — well under sqlite's bound-parameter limit.
  static const int _chunk = 400;

  /// Codes a list screen loads at once.
  static const int listLimit = 500;

  static int _ms(DateTime moment) => moment.toUtc().millisecondsSinceEpoch;

  static DateTime? _date(Object? ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

  /// "Can be sold now": AVAILABLE and not past its expiry. One bound
  /// argument, the current time.
  static const String _sellable =
      "status = 'AVAILABLE' AND (expiry_at IS NULL OR expiry_at > ?)";

  static const String _countsSql = '''
    SUM(CASE WHEN c.status = 'AVAILABLE'
              AND (c.expiry_at IS NULL OR c.expiry_at > ?) THEN 1 ELSE 0 END)
      AS n_available,
    SUM(CASE WHEN c.status = 'AVAILABLE'
              AND c.expiry_at IS NOT NULL AND c.expiry_at <= ? THEN 1 ELSE 0 END)
      AS n_expired,
    SUM(CASE WHEN c.status = 'SOLD' THEN 1 ELSE 0 END) AS n_sold,
    SUM(CASE WHEN c.status = 'VOID' THEN 1 ELSE 0 END) AS n_void''';

  // ---- Counting ---------------------------------------------------------

  /// How many codes each product can sell right now. Products with none are
  /// absent from the map.
  Future<Map<int, int>> availableByProduct({DateTime? now}) async {
    final rows = await _db.rawQuery(
      'SELECT product_id, COUNT(*) AS n FROM voucher_codes '
      'WHERE $_sellable GROUP BY product_id',
      [_ms(now ?? DateTime.now())],
    );
    return {
      for (final row in rows) row['product_id'] as int: row['n'] as int,
    };
  }

  /// Every "sold from code stock" product with its counts — and any other
  /// product that still holds codes, so stock never becomes unreachable
  /// because somebody flipped the switch off.
  Future<List<ProductStock>> stockOverview({DateTime? now}) async {
    final at = _ms(now ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, s.n_available, s.n_expired, s.n_sold, s.n_void
        FROM products p
        LEFT JOIN (
          SELECT c.product_id AS pid, $_countsSql
            FROM voucher_codes c GROUP BY c.product_id
        ) s ON s.pid = p.id
       WHERE (p.kind = 'SERVICE' AND p.sold_from_code_stock = 1)
          OR s.pid IS NOT NULL
       ORDER BY p.is_active DESC, p.name_norm ASC''',
      [at, at],
    );
    return [
      for (final row in rows)
        ProductStock(
          product: Product.fromMap(row),
          available: (row['n_available'] as int?) ?? 0,
          expired: (row['n_expired'] as int?) ?? 0,
          sold: (row['n_sold'] as int?) ?? 0,
          voided: (row['n_void'] as int?) ?? 0,
        ),
    ];
  }

  /// Active card products that are out of stock or at their threshold: the
  /// number on the home screen badge.
  Future<int> lowStockCount({DateTime? now}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS n
        FROM products p
        LEFT JOIN (
          SELECT product_id AS pid, COUNT(*) AS n_available
            FROM voucher_codes WHERE $_sellable GROUP BY product_id
        ) s ON s.pid = p.id
       WHERE p.kind = 'SERVICE' AND p.is_active = 1
         AND p.sold_from_code_stock = 1
         AND COALESCE(s.n_available, 0) <= COALESCE(p.low_stock_threshold, 0)''',
      [_ms(now ?? DateTime.now())],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// The batches of one product, newest first, with what is left of each.
  Future<List<VoucherBatch>> batches(int productId, {DateTime? now}) async {
    final at = _ms(now ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT b.*, $_countsSql
        FROM voucher_batches b
        LEFT JOIN voucher_codes c ON c.batch_id = b.id
       WHERE b.product_id = ?
       GROUP BY b.id
       ORDER BY b.id DESC''',
      [at, at, productId],
    );
    return [
      for (final row in rows)
        VoucherBatch(
          id: row['id'] as int,
          productId: row['product_id'] as int,
          createdAt: _date(row['created_at'])!,
          codeCount: row['code_count'] as int,
          costPerCardMinor: row['cost_per_card_minor'] as int?,
          costCurrencyCode: row['cost_currency_code'] as String?,
          expiryAt: _date(row['expiry_at']),
          note: row['note'] as String?,
          available: (row['n_available'] as int?) ?? 0,
          expired: (row['n_expired'] as int?) ?? 0,
          sold: (row['n_sold'] as int?) ?? 0,
          voided: (row['n_void'] as int?) ?? 0,
        ),
    ];
  }

  // ---- Loading ----------------------------------------------------------

  /// How many of [codes] this product already holds, in any status — for the
  /// report shown BEFORE saving. Uses the hashes; nothing is decrypted.
  Future<int> countExisting(int productId, List<ParsedCode> codes) async {
    if (codes.isEmpty) return 0;
    final hash = await _cipher.hasher();
    final existing = await _existingHashes(
      _db,
      productId,
      [for (final code in codes) hash(code.code)],
    );
    return existing.length;
  }

  static Future<Set<String>> _existingHashes(
    DatabaseExecutor db,
    int productId,
    List<String> hashes,
  ) async {
    final found = <String>{};
    for (var i = 0; i < hashes.length; i += _chunk) {
      final part = hashes.sublist(
        i,
        i + _chunk > hashes.length ? hashes.length : i + _chunk,
      );
      final rows = await db.rawQuery(
        'SELECT code_hash FROM voucher_codes WHERE product_id = ? '
        'AND code_hash IN (${List.filled(part.length, '?').join(',')})',
        [productId, ...part],
      );
      found.addAll(rows.map((row) => row['code_hash'] as String));
    }
    return found;
  }

  /// Loads [parsed] as ONE new batch of [productId], in one transaction.
  ///
  /// Codes the product already has (found by hash, whatever their status —
  /// a card that was sold last month must not come back as stock) are left
  /// out and counted. When nothing is left to add, no batch is created.
  ///
  /// [source] is only a word for the audit log: "paste", "file" or "scan".
  Future<ImportReport> addBatch({
    required int productId,
    required CodeParseResult parsed,
    DateTime? expiryAt,
    int? costPerCardMinor,
    String? costCurrencyCode,
    String? note,
    String source = 'paste',
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final hash = await _cipher.hasher();

    // Hash and encrypt BEFORE the transaction: the database is not held
    // locked while a thousand cards are being encrypted.
    final rows = <({String hash, Uint8List cipher, String? serial})>[];
    final seen = <String>{};
    var repeated = 0;
    for (final entry in parsed.codes) {
      final h = hash(entry.code);
      if (!seen.add(h)) {
        repeated++;
        continue;
      }
      rows.add((
        hash: h,
        cipher: await _cipher.encrypt(entry.code),
        serial: entry.serial,
      ));
    }

    return _db.transaction((txn) async {
      final product = await txn.query(
        'products',
        columns: ['name', 'kind'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (product.isEmpty || product.first['kind'] != ProductKind.service.db) {
        throw ArgumentError.value(productId, 'productId', 'not a card product');
      }
      final existing = await _existingHashes(
        txn,
        productId,
        [for (final row in rows) row.hash],
      );
      final fresh = [
        for (final row in rows)
          if (!existing.contains(row.hash)) row,
      ];
      final report = ImportReport(
        added: fresh.length,
        duplicatesInBatch: parsed.duplicateLines + repeated,
        duplicatesExisting: existing.length,
        emptyLines: parsed.emptyLines,
        invalidLines: parsed.invalidLines,
      );
      if (fresh.isEmpty) return report;

      final hasCost = costPerCardMinor != null && costCurrencyCode != null;
      final batchId = await txn.insert('voucher_batches', {
        'product_id': productId,
        'created_at': _ms(at),
        'code_count': fresh.length,
        'cost_per_card_minor': hasCost ? costPerCardMinor : null,
        'cost_currency_code': hasCost ? costCurrencyCode : null,
        'expiry_at': expiryAt == null ? null : _ms(expiryAt),
        'note': note == null || note.trim().isEmpty ? null : note.trim(),
      });
      final batch = txn.batch();
      for (final row in fresh) {
        batch.insert('voucher_codes', {
          'product_id': productId,
          'batch_id': batchId,
          'code_cipher': row.cipher,
          'code_hash': row.hash,
          'serial': row.serial,
          'expiry_at': expiryAt == null ? null : _ms(expiryAt),
          'status': VoucherStatus.available.db,
          'created_at': _ms(at),
        });
      }
      await batch.commit(noResult: true);
      await AuditRepository(txn).log(
        AuditAction.codeImport,
        productId: productId,
        productName: product.first['name'] as String,
        entityType: 'batch',
        entityId: batchId,
        details: {
          'count': fresh.length,
          'duplicates': report.duplicates,
          'source': source,
        },
        at: at,
      );
      return ImportReport(
        added: report.added,
        duplicatesInBatch: report.duplicatesInBatch,
        duplicatesExisting: report.duplicatesExisting,
        emptyLines: report.emptyLines,
        invalidLines: report.invalidLines,
        batchId: batchId,
      );
    });
  }

  // ---- Selling ----------------------------------------------------------

  /// Takes the codes one invoice line sells. Called by
  /// `InvoiceRepository.save` INSIDE the invoice's transaction, after the
  /// item row exists.
  ///
  /// Does nothing unless the product is a SERVICE marked "sold from code
  /// stock". Otherwise it picks as many sellable codes as the line's
  /// quantity — earliest expiry first (codes with no expiry last), then the
  /// oldest batch, then the lowest id — and marks each SOLD with the time,
  /// the invoice and item ids and the sale snapshots that outlive the
  /// invoice.
  ///
  /// Throws [InsufficientCodeStockException] when there are not enough,
  /// [CodeQuantityException] for a fractional quantity, and
  /// [CodeUnreadableException] when a picked code cannot be decrypted on
  /// this device — each of which rolls the whole invoice back. A card that
  /// could not be printed is never marked sold.
  static Future<int> sellForItem(
    Transaction txn, {
    required CodeCipher cipher,
    required Invoice invoice,
    required int invoiceId,
    required int invoiceNo,
    required InvoiceItem item,
    required int itemId,
    required int productId,
  }) async {
    final product = await txn.query(
      'products',
      columns: ['name', 'kind', 'sold_from_code_stock'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (product.isEmpty ||
        product.first['kind'] != ProductKind.service.db ||
        product.first['sold_from_code_stock'] != 1) {
      return 0;
    }
    if (item.qtyThousandths % 1000 != 0) {
      throw CodeQuantityException(item.productName);
    }
    final wanted = item.qtyThousandths ~/ 1000;
    final at = _ms(invoice.createdAt);

    final picked = await txn.rawQuery(
      '''
      SELECT c.id, c.code_cipher, b.cost_per_card_minor, b.cost_currency_code
        FROM voucher_codes c
        JOIN voucher_batches b ON b.id = c.batch_id
       WHERE c.product_id = ?
         AND c.status = 'AVAILABLE'
         AND (c.expiry_at IS NULL OR c.expiry_at > ?)
       ORDER BY c.expiry_at IS NULL, c.expiry_at, c.batch_id, c.id
       LIMIT ?''',
      [productId, at, wanted],
    );
    if (picked.length < wanted) {
      throw InsufficientCodeStockException(
        productName: item.productName,
        requested: wanted,
        available: picked.length,
      );
    }

    // What the card went for and what it cost, in base currency, as of now.
    final currencies = {
      for (final row in await txn.query('currencies'))
        row['code'] as String: (
          decimals: row['decimal_places'] as int,
          rate: RateFraction(row['rate_num'] as int, row['rate_den'] as int),
        ),
    };
    final baseDecimals = currencies[invoice.baseCurrencyCode]?.decimals ?? 0;
    final priceBase = convertMinor(
      amountMinor: item.origUnitPriceMinor,
      fromDecimals: currencies[item.origCurrencyCode]?.decimals ?? 0,
      fromRate: item.origRate,
      toDecimals: baseDecimals,
      toRate: RateFraction.one,
    );

    for (final row in picked) {
      // Proves the card can be printed before it is taken out of stock.
      await cipher.decrypt(row['code_cipher'] as Uint8List);

      int? costBase;
      final cost = row['cost_per_card_minor'] as int?;
      final costCurrency = currencies[row['cost_currency_code']];
      if (cost != null && costCurrency != null) {
        costBase = convertMinor(
          amountMinor: cost,
          fromDecimals: costCurrency.decimals,
          fromRate: costCurrency.rate,
          toDecimals: baseDecimals,
          toRate: RateFraction.one,
        );
      }
      final changed = await txn.update(
        'voucher_codes',
        {
          'status': VoucherStatus.sold.db,
          'status_changed_at': at,
          'status_note': null,
          'sold_at': at,
          'invoice_id': invoiceId,
          'invoice_item_id': itemId,
          'sold_invoice_no': invoiceNo,
          'sold_customer_id': invoice.customerId,
          'sold_customer_name': invoice.customerName,
          'sold_account_number': invoice.accountNumber,
          'sold_price_base_minor': priceBase,
          'sold_cost_base_minor': costBase,
        },
        where: "id = ? AND status = 'AVAILABLE'",
        whereArgs: [row['id']],
      );
      if (changed != 1) {
        throw StateError('a card code changed hands during the sale');
      }
    }
    return wanted;
  }

  // ---- Reading codes ----------------------------------------------------

  static const String _viewColumns = '''
    c.id, c.product_id, c.batch_id, c.code_cipher, c.serial, c.expiry_at,
    c.status, c.status_changed_at, c.status_note, c.sold_at, c.invoice_id,
    c.invoice_item_id, c.sold_invoice_no, c.sold_customer_name,
    c.sold_account_number, p.name AS product_name''';

  static const String _viewFrom =
      'FROM voucher_codes c JOIN products p ON p.id = c.product_id';

  /// The stored code, or null when it cannot be decrypted here.
  Future<String?> _plain(Object? blob) async {
    try {
      return await _cipher.decrypt(blob as Uint8List);
    } on CodeUnreadableException {
      return null;
    }
  }

  Future<VoucherCodeView> _view(Map<String, Object?> row) async {
    final plain = await _plain(row['code_cipher']);
    return VoucherCodeView(
      id: row['id'] as int,
      productId: row['product_id'] as int,
      productName: row['product_name'] as String,
      batchId: row['batch_id'] as int,
      masked: plain == null ? codeFullyMasked : maskCode(plain),
      unreadable: plain == null,
      serial: row['serial'] as String?,
      expiryAt: _date(row['expiry_at']),
      status: VoucherStatus.fromDb(row['status'] as String),
      statusChangedAt: _date(row['status_changed_at']),
      statusNote: row['status_note'] as String?,
      soldAt: _date(row['sold_at']),
      invoiceId: row['invoice_id'] as int?,
      invoiceItemId: row['invoice_item_id'] as int?,
      soldInvoiceNo: row['sold_invoice_no'] as int?,
      soldCustomerName: row['sold_customer_name'] as String?,
      soldAccountNumber: row['sold_account_number'] as String?,
    );
  }

  Future<List<VoucherCodeView>> _views(
    String where,
    List<Object?> args, {
    String orderBy = 'c.id ASC',
    int limit = listLimit,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT $_viewColumns $_viewFrom WHERE $where ORDER BY $orderBy LIMIT ?',
      [...args, limit],
    );
    return [for (final row in rows) await _view(row)];
  }

  /// Every code an invoice sold, masked — including the ones voided since.
  Future<List<VoucherCodeView>> codesOfInvoice(int invoiceId) =>
      _views('c.invoice_id = ?', [invoiceId]);

  /// The codes of one batch, masked.
  Future<List<VoucherCodeView>> codesOfBatch(int batchId) =>
      _views('c.batch_id = ?', [batchId]);

  /// AVAILABLE codes past their expiry, the longest expired first: never
  /// sold automatically, listed for the owner to decide.
  Future<List<VoucherCodeView>> expiredCodes({int? productId, DateTime? now}) =>
      _views(
        "c.status = 'AVAILABLE' AND c.expiry_at IS NOT NULL "
        'AND c.expiry_at <= ?'
        '${productId == null ? '' : ' AND c.product_id = ?'}',
        [_ms(now ?? DateTime.now()), ?productId],
        orderBy: 'c.expiry_at ASC, c.id ASC',
      );

  /// The codes an invoice prints: the ones still SOLD on it, IN THE CLEAR.
  ///
  /// Only for the printer / share pipeline. A voided code is not printed
  /// again, and one returned to stock is no longer on the invoice at all.
  Future<List<InvoiceCode>> printableCodes(int invoiceId) async {
    final rows = await _db.rawQuery(
      'SELECT c.id, c.invoice_item_id, c.code_cipher, c.serial, c.expiry_at, '
      'COALESCE(it.product_name, p.name) AS product_name '
      'FROM voucher_codes c '
      'JOIN products p ON p.id = c.product_id '
      'LEFT JOIN invoice_items it ON it.id = c.invoice_item_id '
      "WHERE c.invoice_id = ? AND c.status = 'SOLD' "
      'ORDER BY COALESCE(it.sort_order, 0), c.invoice_item_id, c.id',
      [invoiceId],
    );
    final codes = <InvoiceCode>[];
    for (final row in rows) {
      final plain = await _plain(row['code_cipher']);
      codes.add(InvoiceCode(
        id: row['id'] as int,
        invoiceItemId: row['invoice_item_id'] as int?,
        productName: row['product_name'] as String,
        code: plain,
        masked: plain == null ? codeFullyMasked : maskCode(plain),
        unreadable: plain == null,
        serial: row['serial'] as String?,
        expiryAt: _date(row['expiry_at']),
      ));
    }
    return codes;
  }

  /// One code IN THE CLEAR, for showing on screen after the PIN. Logged.
  ///
  /// Throws [CodeUnreadableException] when this device cannot decrypt it.
  Future<String> reveal(int codeId) async {
    final rows = await _db.rawQuery(
      'SELECT $_viewColumns $_viewFrom WHERE c.id = ? LIMIT 1',
      [codeId],
    );
    if (rows.isEmpty) throw StateError('no such code');
    final row = rows.first;
    final plain = await _cipher.decrypt(row['code_cipher'] as Uint8List);
    await AuditRepository(_db).log(
      AuditAction.codeReveal,
      productId: row['product_id'] as int,
      productName: row['product_name'] as String,
      entityType: 'code',
      entityId: codeId,
      details: {
        'tail': codeTail(plain),
        'serial': row['serial'],
        'status': row['status'],
        'invoice_no': row['sold_invoice_no'],
      },
    );
    return plain;
  }

  /// "Was this card sold, and to whom?" — finds [code] by its hash in every
  /// product. Logged, with how many rows matched and never the code.
  Future<List<CodeLookupResult>> lookup(String code) async {
    final hash = await _cipher.hash(code);
    final found = await _views('c.code_hash = ?', [hash]);
    await AuditRepository(_db).log(
      AuditAction.codeLookup,
      productId: found.length == 1 ? found.single.productId : null,
      productName: found.length == 1 ? found.single.productName : null,
      details: {
        'found': found.length,
        if (found.isNotEmpty) 'status': found.first.status.db,
        if (found.isNotEmpty) 'invoice_no': found.first.soldInvoiceNo,
      },
    );
    return found;
  }

  // ---- Returns and mistakes ---------------------------------------------

  /// Marks [codeId] VOID: the card is gone for good (defective, refunded,
  /// given away, expired and written off). Works on a SOLD code and on one
  /// still in stock. The sale snapshots of a sold code are kept — the card
  /// WAS sold, to that customer, on that invoice — only its status says it
  /// no longer counts. Returns false when the code was already void.
  Future<bool> voidCode(int codeId, {required String reason, DateTime? now}) =>
      _changeStatus(
        codeId,
        to: VoucherStatus.voided,
        action: AuditAction.codeVoid,
        reason: reason,
        now: now,
      );

  /// "Return to stock": a SOLD (or voided) code becomes AVAILABLE again and
  /// forgets its sale. For the card sold by mistake and handed back unused.
  /// Returns false when the code was already in stock.
  Future<bool> returnToStock(
    int codeId, {
    required String reason,
    DateTime? now,
  }) =>
      _changeStatus(
        codeId,
        to: VoucherStatus.available,
        action: AuditAction.codeRestore,
        reason: reason,
        now: now,
      );

  Future<bool> _changeStatus(
    int codeId, {
    required VoucherStatus to,
    required AuditAction action,
    required String reason,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    return _db.transaction(
      (txn) => changeStatusIn(
        txn,
        cipher: _cipher,
        codeId: codeId,
        to: to,
        action: action,
        reason: reason,
        at: at,
      ),
    );
  }

  /// The SOLD codes of [invoiceId] — the ones a void or a return still has
  /// to decide about — as (code id, invoice item id).
  static Future<List<({int id, int? invoiceItemId})>> soldCodesOf(
    DatabaseExecutor db,
    int invoiceId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT id, invoice_item_id FROM voucher_codes '
      "WHERE invoice_id = ? AND status = 'SOLD' ORDER BY id",
      [invoiceId],
    );
    return [
      for (final row in rows)
        (id: row['id'] as int, invoiceItemId: row['invoice_item_id'] as int?),
    ];
  }

  /// Changes the status of one code and writes its audit line, INSIDE the
  /// caller's transaction — the way a voided invoice or a return takes its
  /// cards back together with everything else it undoes, or not at all.
  ///
  /// [cipher] is only used for the last digits in the audit line; without
  /// it (or when the code cannot be read on this device) the line simply
  /// has none. [details] adds facts to the line (a return number).
  /// Returns false when the code is gone or already has that status.
  static Future<bool> changeStatusIn(
    Transaction txn, {
    required CodeCipher? cipher,
    required int codeId,
    required VoucherStatus to,
    required AuditAction action,
    required String reason,
    required DateTime at,
    Map<String, Object?> details = const {},
  }) async {
    final rows = await txn.rawQuery(
      'SELECT $_viewColumns $_viewFrom WHERE c.id = ? LIMIT 1',
      [codeId],
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final from = VoucherStatus.fromDb(row['status'] as String);
    if (from == to) return false;
    var tail = '';
    if (cipher != null) {
      try {
        tail = codeTail(await cipher.decrypt(row['code_cipher'] as Uint8List));
      } on CodeUnreadableException {
        // Logged without its last digits.
      }
    }

    final values = <String, Object?>{
      'status': to.db,
      'status_changed_at': _ms(at),
      'status_note': reason.trim().isEmpty ? null : reason.trim(),
    };
    if (to == VoucherStatus.available) {
      // Back on the shelf as if it had never left.
      values.addAll(const {
        'sold_at': null,
        'invoice_id': null,
        'invoice_item_id': null,
        'sold_invoice_no': null,
        'sold_customer_id': null,
        'sold_customer_name': null,
        'sold_account_number': null,
        'sold_price_base_minor': null,
        'sold_cost_base_minor': null,
      });
    }
    await txn.update(
      'voucher_codes',
      values,
      where: 'id = ? AND status = ?',
      whereArgs: [codeId, from.db],
    );
    await AuditRepository(txn).log(
      action,
      productId: row['product_id'] as int,
      productName: row['product_name'] as String,
      entityType: 'code',
      entityId: codeId,
      details: {
        'from': from.db,
        'tail': tail,
        'serial': row['serial'],
        'invoice_no': row['sold_invoice_no'],
        'reason': reason.trim(),
        ...details,
      },
      at: at,
    );
    return true;
  }

  /// Voids every expired, unsold code of [productId] (or of one batch) in
  /// one transaction. Returns how many went.
  Future<int> voidExpired({
    required int productId,
    int? batchId,
    required String reason,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    return _db.transaction((txn) async {
      final changed = await txn.rawUpdate(
        'UPDATE voucher_codes SET status = ?, status_changed_at = ?, '
        'status_note = ? '
        "WHERE product_id = ? AND status = 'AVAILABLE' "
        'AND expiry_at IS NOT NULL AND expiry_at <= ?'
        '${batchId == null ? '' : ' AND batch_id = ?'}',
        [
          VoucherStatus.voided.db,
          _ms(at),
          reason.trim().isEmpty ? null : reason.trim(),
          productId,
          _ms(at),
          ?batchId,
        ],
      );
      if (changed == 0) return 0;
      await AuditRepository(txn).log(
        AuditAction.codeVoid,
        productId: productId,
        productName: await _productName(txn, productId),
        entityType: batchId == null ? 'product' : 'batch',
        entityId: batchId ?? productId,
        details: {'count': changed, 'expired': true, 'reason': reason.trim()},
        at: at,
      );
      return changed;
    });
  }

  /// Gives the unsold codes of a batch a new expiry (or none): the date was
  /// typed wrong, or the provider extended the cards. Logged, because it can
  /// put expired cards back on sale.
  Future<int> setBatchExpiry(int batchId, DateTime? expiryAt) async {
    return _db.transaction((txn) async {
      final batch = await txn.query(
        'voucher_batches',
        where: 'id = ?',
        whereArgs: [batchId],
        limit: 1,
      );
      if (batch.isEmpty) return 0;
      final productId = batch.first['product_id'] as int;
      final value = expiryAt == null ? null : _ms(expiryAt);
      await txn.update(
        'voucher_batches',
        {'expiry_at': value},
        where: 'id = ?',
        whereArgs: [batchId],
      );
      final changed = await txn.update(
        'voucher_codes',
        {'expiry_at': value},
        where: "batch_id = ? AND status = 'AVAILABLE'",
        whereArgs: [batchId],
      );
      await AuditRepository(txn).log(
        AuditAction.codeExpiryChange,
        productId: productId,
        productName: await _productName(txn, productId),
        entityType: 'batch',
        entityId: batchId,
        details: {'count': changed, 'expiry_at': value},
      );
      return changed;
    });
  }

  static Future<String?> _productName(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'products',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  /// Deletes a batch nothing was sold from, with its codes. Returns how many
  /// codes went, or null when the batch has a SOLD code — sold codes are the
  /// record of who got which card and are never deleted. (A code voided
  /// after a sale keeps its sale snapshot and blocks the delete the same
  /// way.)
  Future<int?> deleteUnsoldBatch(int batchId) async {
    return _db.transaction((txn) async {
      final batch = await txn.query(
        'voucher_batches',
        where: 'id = ?',
        whereArgs: [batchId],
        limit: 1,
      );
      if (batch.isEmpty) return 0;
      final sold = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM voucher_codes '
        "WHERE batch_id = ? AND (status = 'SOLD' OR sold_at IS NOT NULL)",
        [batchId],
      ));
      if ((sold ?? 0) > 0) return null;
      final productId = batch.first['product_id'] as int;
      final deleted = await txn.delete(
        'voucher_codes',
        where: 'batch_id = ?',
        whereArgs: [batchId],
      );
      await txn.delete('voucher_batches', where: 'id = ?', whereArgs: [batchId]);
      await AuditRepository(txn).log(
        AuditAction.batchDelete,
        productId: productId,
        productName: await _productName(txn, productId),
        entityType: 'batch',
        entityId: batchId,
        details: {'count': deleted},
      );
      return deleted;
    });
  }

  // ---- Export -----------------------------------------------------------

  /// The unsold codes of [productId] (or of one batch) IN THE CLEAR, as the
  /// lines of a text file: `serial,code` when a card has a serial, the code
  /// alone otherwise — the same shapes the import reads. Logged with the
  /// count. Codes this device cannot decrypt are left out and counted in
  /// [CodeExport.unreadable].
  Future<CodeExport> exportAvailable({
    required int productId,
    int? batchId,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT c.code_cipher, c.serial FROM voucher_codes c '
      "WHERE c.product_id = ? AND c.status = 'AVAILABLE'"
      '${batchId == null ? '' : ' AND c.batch_id = ?'} '
      'ORDER BY c.batch_id, c.id',
      [productId, ?batchId],
    );
    final lines = <String>[];
    var unreadable = 0;
    for (final row in rows) {
      final plain = await _plain(row['code_cipher']);
      if (plain == null) {
        unreadable++;
        continue;
      }
      final serial = row['serial'] as String?;
      lines.add(serial == null || serial.isEmpty ? plain : '$serial,$plain');
    }
    await AuditRepository(_db).log(
      AuditAction.codeExport,
      productId: productId,
      productName: await _productName(_db, productId),
      entityType: batchId == null ? 'product' : 'batch',
      entityId: batchId ?? productId,
      details: {'count': lines.length},
    );
    return CodeExport(lines: lines, unreadable: unreadable);
  }

  /// Notes that an invoice carrying codes was printed or shared again.
  Future<void> logReprint({
    required int invoiceNo,
    required int codeCount,
    required String output,
    String? productName,
    int? productId,
  }) =>
      AuditRepository(_db).log(
        AuditAction.invoiceReprint,
        productId: productId,
        productName: productName,
        entityType: 'invoice',
        details: {'invoice_no': invoiceNo, 'count': codeCount, 'output': output},
      );
}

/// The result of [VoucherRepository.exportAvailable]. Deliberately without a
/// `toString`: the lines are codes.
class CodeExport {
  const CodeExport({required this.lines, required this.unreadable});

  final List<String> lines;
  final int unreadable;
}
