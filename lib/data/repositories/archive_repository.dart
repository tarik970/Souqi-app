import 'package:sqflite/sqflite.dart';

import '../../core/utils/normalize.dart';
import '../../domain/models/invoice.dart';

/// What the archive list shows for one invoice. Deliberately NOT a whole
/// [Invoice]: a page of 30 rows must not drag 300 item rows with it.
class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    required this.currencyCode,
    required this.totalMinor,
    required this.totalBaseMinor,
    this.customerName,
    required this.itemCount,
  });

  final int id;
  final int invoiceNo;
  final DateTime createdAt;
  final String currencyCode;
  final int totalMinor;
  final int totalBaseMinor;
  final String? customerName;
  final int itemCount;

  static ArchiveEntry fromRow(Map<String, Object?> row) => ArchiveEntry(
        id: row['id'] as int,
        invoiceNo: row['invoice_no'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
          isUtc: true,
        ),
        currencyCode: row['currency_code'] as String,
        totalMinor: row['total_minor'] as int,
        totalBaseMinor: row['total_base_minor'] as int,
        customerName: row['customer_name'] as String?,
        itemCount: (row['item_count'] as int?) ?? 0,
      );

  /// Where the next page starts. Paging by this pair instead of an OFFSET
  /// keeps page 500 as fast as page 1.
  ArchiveCursor get cursor => ArchiveCursor(createdAt: createdAt, id: id);
}

class ArchiveCursor {
  const ArchiveCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final int id;
}

/// The date-range buttons of the archive and the statistics screen.
enum ArchivePeriod { all, today, yesterday, thisWeek, thisMonth, custom }

/// The archive's filters. Every field is optional and they combine with AND.
class ArchiveFilter {
  const ArchiveFilter({
    this.from,
    this.to,
    this.invoiceNo,
    this.productQuery = '',
    this.customerQuery = '',
    this.preset = ArchivePeriod.all,
  });

  /// Inclusive lower bound / exclusive upper bound on `created_at`.
  final DateTime? from;
  final DateTime? to;

  final int? invoiceNo;

  /// Matched against the invoice items' normalized name snapshots.
  final String productQuery;

  /// Matched against the invoice's customer name, phone and account-number
  /// snapshots — one box for all three, as on the sale screen.
  final String customerQuery;

  /// Which button of the date-range selector is lit. The resolved dates live
  /// in [from] / [to]; this only remembers the user's choice.
  final ArchivePeriod preset;

  bool get isEmpty =>
      from == null &&
      to == null &&
      invoiceNo == null &&
      productQuery.trim().isEmpty &&
      customerQuery.trim().isEmpty;

  ArchiveFilter copyWith({
    DateTime? Function()? from,
    DateTime? Function()? to,
    int? Function()? invoiceNo,
    String? productQuery,
    String? customerQuery,
    ArchivePeriod? preset,
  }) =>
      ArchiveFilter(
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        invoiceNo: invoiceNo != null ? invoiceNo() : this.invoiceNo,
        productQuery: productQuery ?? this.productQuery,
        customerQuery: customerQuery ?? this.customerQuery,
        preset: preset ?? this.preset,
      );

  @override
  bool operator ==(Object other) =>
      other is ArchiveFilter &&
      other.from == from &&
      other.to == to &&
      other.invoiceNo == invoiceNo &&
      other.productQuery == productQuery &&
      other.customerQuery == customerQuery &&
      other.preset == preset;

  @override
  int get hashCode => Object.hash(
        from,
        to,
        invoiceNo,
        productQuery,
        customerQuery,
        preset,
      );
}

/// How many invoices a range holds and what they came to, for the
/// confirmation of a range delete.
class ArchiveRangeSummary {
  const ArchiveRangeSummary({
    required this.count,
    required this.totalBaseMinor,
  });

  final int count;

  /// In the BASE currency, summed from each invoice's stored
  /// `total_base_minor` — the rate that was in force at the sale, not today's.
  final int totalBaseMinor;
}

/// Reads the invoice archive: filtered, paged lists and single invoices.
///
/// Every list query is bounded by LIMIT and ordered newest first on
/// `idx_invoices_created`, and nothing is filtered in Dart — this has to stay
/// smooth on a phone holding 50,000 invoices.
class ArchiveRepository {
  ArchiveRepository(this._db);

  final DatabaseExecutor _db;

  /// Rows per page. One screen plus a little, so scrolling reaches the next
  /// page before the list runs out.
  static const int pageSize = 30;

  /// One page of the archive, newest first. Pass the previous page's last
  /// [ArchiveEntry.cursor] as [after] to get the page below it.
  Future<List<ArchiveEntry>> page({
    ArchiveFilter filter = const ArchiveFilter(),
    ArchiveCursor? after,
    int limit = pageSize,
  }) async {
    final (where, args) = _where(filter);
    if (after != null) {
      // Strictly "older than the last row shown": created_at alone is not
      // unique (two sales in the same millisecond), so the id breaks the tie
      // and no invoice is ever shown twice or skipped.
      where.add('(i.created_at < ? OR (i.created_at = ? AND i.id < ?))');
      final at = after.createdAt.toUtc().millisecondsSinceEpoch;
      args.addAll([at, at, after.id]);
    }
    final rows = await _db.rawQuery(
      'SELECT i.id, i.invoice_no, i.created_at, i.currency_code, '
      'i.total_minor, i.total_base_minor, i.customer_name, '
      '(SELECT COUNT(*) FROM invoice_items it WHERE it.invoice_id = i.id) '
      'AS item_count '
      'FROM invoices i '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
      'ORDER BY i.created_at DESC, i.id DESC LIMIT ?',
      [...args, limit],
    );
    return rows.map(ArchiveEntry.fromRow).toList();
  }

  /// How many invoices match [filter] and what they total in base currency.
  Future<ArchiveRangeSummary> summary(ArchiveFilter filter) async {
    final (where, args) = _where(filter);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(i.total_base_minor), 0) AS total '
      'FROM invoices i '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}',
      args,
    );
    final row = rows.first;
    return ArchiveRangeSummary(
      count: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
    );
  }

  /// The whole invoice with its items, for the detail / reprint screen.
  Future<Invoice?> getById(int id) async {
    final rows = await _db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final items = await _db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC, id ASC',
    );
    return Invoice.fromMap(
      rows.first,
      items: items.map(InvoiceItem.fromMap).toList(),
    );
  }

  /// Deletes one invoice and returns whether it was there.
  ///
  /// Its items go with it (ON DELETE CASCADE). The invoice counter, the
  /// products it sold — including the ones type-to-sell created — and the
  /// voucher codes it sold all stay: the voucher rows keep their own sale
  /// snapshots and only lose the `invoice_id` link (ON DELETE SET NULL).
  Future<bool> deleteInvoice(int id) async {
    final deleted =
        await _db.delete('invoices', where: 'id = ?', whereArgs: [id]);
    return deleted > 0;
  }

  (List<String>, List<Object?>) _where(ArchiveFilter filter) {
    final where = <String>[];
    final args = <Object?>[];

    final from = filter.from;
    if (from != null) {
      where.add('i.created_at >= ?');
      args.add(from.toUtc().millisecondsSinceEpoch);
    }
    final to = filter.to;
    if (to != null) {
      where.add('i.created_at < ?');
      args.add(to.toUtc().millisecondsSinceEpoch);
    }
    final invoiceNo = filter.invoiceNo;
    if (invoiceNo != null) {
      where.add('i.invoice_no = ?');
      args.add(invoiceNo);
    }

    // Products are searched through the ITEMS' normalized snapshots, so an
    // invoice is found by what it sold even after that product was renamed,
    // deactivated or deleted — and an item that never became a product is
    // found just the same.
    final product = normalizeName(filter.productQuery);
    if (product.isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM invoice_items it WHERE it.invoice_id = i.id '
        "AND it.product_name_norm LIKE ? ESCAPE '!')",
      );
      args.add('%${escapeLike(product)}%');
    }

    // One box, three snapshots: a name, a phone, or a card/account number.
    // Each goes through its own column's normalizer, so Arabic-Indic digits
    // find a phone and "0011-2233" finds an account number.
    final customer = filter.customerQuery.trim();
    if (customer.isNotEmpty) {
      final clauses = <String>[];
      final name = normalizeName(customer);
      if (name.isNotEmpty) {
        clauses.add("i.customer_name_norm LIKE ? ESCAPE '!'");
        args.add('%${escapeLike(name)}%');
      }
      final phone = normalizePhone(customer);
      if (phone.isNotEmpty) {
        clauses.add("i.customer_phone_norm LIKE ? ESCAPE '!'");
        args.add('%${escapeLike(phone)}%');
      }
      final account = normalizeCode(customer);
      if (account.isNotEmpty) {
        clauses.add("i.account_number_norm LIKE ? ESCAPE '!'");
        args.add('%${escapeLike(account)}%');
      }
      if (clauses.isNotEmpty) where.add('(${clauses.join(' OR ')})');
    }

    return (where, args);
  }

  /// Makes a user-typed string safe inside a LIKE pattern: `%`, `_` and the
  /// escape character itself are literal text, not wildcards. Paired with
  /// `ESCAPE '!'` in every LIKE above.
  static String escapeLike(String value) => value
      .replaceAll('!', '!!')
      .replaceAll('%', '!%')
      .replaceAll('_', '!_');
}
