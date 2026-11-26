import 'package:sqflite/sqflite.dart';

/// The headline figures of one period, all in the BASE currency.
class PeriodStats {
  const PeriodStats({
    required this.from,
    required this.to,
    required this.invoiceCount,
    required this.totalBaseMinor,
    required this.discountBaseMinor,
    this.returnCount = 0,
    this.returnsBaseMinor = 0,
  });

  /// The period: [from] inclusive, [to] exclusive.
  final DateTime from;
  final DateTime to;

  /// Invoices of the period that were not voided.
  final int invoiceCount;

  /// Sum of each invoice's stored `total_base_minor` — the base-currency
  /// amount computed at the moment of the sale with that day's rate. Voided
  /// invoices are not in it; returns are NOT taken off (see
  /// [netBaseMinor]).
  final int totalBaseMinor;

  /// Return documents DATED in the period — whatever the date of the
  /// invoice they return from — and what they gave back, in base currency.
  final int returnCount;
  final int returnsBaseMinor;

  /// NET SALES: what was sold in the period less what was returned in it.
  int get netBaseMinor => totalBaseMinor - returnsBaseMinor;

  /// Sum of the invoice discounts, each converted with the invoice's OWN
  /// stored rate snapshot.
  final int discountBaseMinor;

  /// The average invoice, rounded half-up. Zero for a period with no sales.
  int get averageBaseMinor => invoiceCount == 0
      ? 0
      : (2 * totalBaseMinor + invoiceCount) ~/ (2 * invoiceCount);

  Duration get length => to.difference(from);
}

/// Sales in one invoice currency, for the optional breakdown.
class CurrencyTotal {
  const CurrencyTotal({
    required this.currencyCode,
    required this.invoiceCount,
    required this.totalMinor,
    required this.totalBaseMinor,
  });

  final String currencyCode;
  final int invoiceCount;

  /// In that currency's own minor units.
  final int totalMinor;

  /// The same sales in base currency, from the stored snapshots.
  final int totalBaseMinor;
}

/// One row of the "top products" tables.
class ProductStat {
  const ProductStat({
    required this.groupKey,
    required this.name,
    required this.productId,
    required this.salesCount,
    required this.qtyThousandths,
    required this.amountBaseMinor,
  });

  /// `p<id>` for a saved product, `n<normalized name>` for items that were
  /// sold without ever becoming products.
  final String groupKey;

  /// The name from the most recent sale — what the shop last called it.
  final String name;

  /// Null for a group of unsaved items (or a product deleted since).
  final int? productId;

  /// How many invoice lines sold it in the period.
  final int salesCount;

  /// Summed quantity in thousandths. Only meaningful within one unit, so the
  /// screens lead with [salesCount] and [amountBaseMinor].
  final int qtyThousandths;

  final int amountBaseMinor;
}

/// How the top-products table is ordered.
enum ProductRanking { sales, amount }

/// Sales statistics, computed by SQL aggregates over indexed columns.
///
/// Two rules run through every query here:
///
/// 1. Amounts are BASE currency from the invoice's own snapshots — the stored
///    `total_base_minor`, or the stored `rate_num`/`rate_den` of that sale.
///    Today's exchange rate never touches a past period.
/// 2. Nothing is summed in Dart. A shop with 50,000 invoices gets counts and
///    sums out of sqlite, over `idx_invoices_created`.
class StatsRepository {
  StatsRepository(this._db);

  final DatabaseExecutor _db;

  /// Rows in each top-products table.
  static const int topProductsLimit = 10;

  /// 10^decimal_places of the invoice's own currency, as SQL. The currency
  /// table is joined in as `c`; a currency deleted since the sale falls back
  /// to 0 decimals, which is what an unknown currency is stored as.
  static const String _currencyPow10 =
      'CASE COALESCE(c.decimal_places, 0) '
      'WHEN 0 THEN 1 WHEN 1 THEN 10 WHEN 2 THEN 100 WHEN 3 THEN 1000 '
      'ELSE 10000 END';

  /// An amount in the invoice's currency, converted to base minor units in
  /// SQL with integer arithmetic and half-up rounding:
  ///
  ///     base = amount * rate_num * 10^baseDecimals / (rate_den * 10^curDecimals)
  ///
  /// `(2x + y) / (2y)` is `round(x / y)` half-up for non-negative x, and
  /// sqlite's integer division truncates towards zero. Every amount here
  /// (totals, discounts, line totals) is non-negative.
  ///
  /// Used only for discounts and line totals; invoice totals have their
  /// base-currency value stored outright.
  static String _toBaseSql(String amount, int basePow10) =>
      '(($amount) * i.rate_num * $basePow10 * 2 + i.rate_den * ($_currencyPow10)) '
      '/ (i.rate_den * ($_currencyPow10) * 2)';

  static int _pow10(int exp) {
    var v = 1;
    for (var i = 0; i < exp; i++) {
      v *= 10;
    }
    return v;
  }

  /// Count, total, discounts for [from] (inclusive) to [to] (exclusive).
  ///
  /// [baseDecimals] is the base currency's `decimal_places`.
  Future<PeriodStats> summary({
    required DateTime from,
    required DateTime to,
    required int baseDecimals,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, '
      'COALESCE(SUM(i.total_base_minor), 0) AS total, '
      'COALESCE(SUM(${_toBaseSql('i.discount_minor', _pow10(baseDecimals))}), 0) '
      'AS discount '
      'FROM invoices i LEFT JOIN currencies c ON c.code = i.currency_code '
      'WHERE i.created_at >= ? AND i.created_at < ? AND $_live',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    );
    final row = rows.first;
    // Returns count on the day of the RETURN: a sale of last month returned
    // today is money that left the till today. A range read of
    // `idx_returns_created`.
    final returns = (await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(r.refund_base_minor), 0) AS total '
      'FROM invoice_returns r WHERE r.created_at >= ? AND r.created_at < ?',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    ))
        .first;
    return PeriodStats(
      from: from,
      to: to,
      invoiceCount: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
      discountBaseMinor: (row['discount'] as int?) ?? 0,
      returnCount: (returns['n'] as int?) ?? 0,
      returnsBaseMinor: (returns['total'] as int?) ?? 0,
    );
  }

  /// "This invoice counts": it was not voided. `i` is the invoice. A voided
  /// invoice stays in the archive and is left out of every figure here.
  static const String _live = 'i.voided_at IS NULL';

  /// The same period as [summary], split by the invoice currency.
  Future<List<CurrencyTotal>> byCurrency({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT i.currency_code AS code, COUNT(*) AS n, '
      'COALESCE(SUM(i.total_minor), 0) AS total, '
      'COALESCE(SUM(i.total_base_minor), 0) AS total_base '
      'FROM invoices i '
      'WHERE i.created_at >= ? AND i.created_at < ? AND $_live '
      'GROUP BY i.currency_code ORDER BY total_base DESC',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    );
    return [
      for (final row in rows)
        CurrencyTotal(
          currencyCode: row['code'] as String,
          invoiceCount: (row['n'] as int?) ?? 0,
          totalMinor: (row['total'] as int?) ?? 0,
          totalBaseMinor: (row['total_base'] as int?) ?? 0,
        ),
    ];
  }

  /// The best-selling products of the period, by number of sales or by
  /// amount sold.
  ///
  /// Lines are grouped by `product_id` when the line is linked to a product,
  /// and otherwise by the normalized name snapshot — so an item typed into
  /// three sales without ever being saved as a product is still one row, and
  /// "السكر" and "سكر" are the same row. [ProductStat.salesCount] counts
  /// invoice LINES, which is how the favorites bar ranks best sellers too.
  ///
  /// With [renewalsOnly] the table is the "top packages" one: only the
  /// SERVICE/CARD lines of invoices that carry an account snapshot.
  Future<List<ProductStat>> topProducts({
    required DateTime from,
    required DateTime to,
    required int baseDecimals,
    ProductRanking ranking = ProductRanking.amount,
    int limit = topProductsLimit,
    bool renewalsOnly = false,
  }) async {
    final pow = _pow10(baseDecimals);
    final amount = _toBaseSql('it.line_total_minor', pow);
    // The returned share of a line total, with the return's own stored rate
    // (the invoice's). In the second half below the return is aliased `i`,
    // so the same conversion reads its rate and currency.
    final returned = _toBaseSql('it.gross_minor', pow);
    final order = ranking == ProductRanking.sales
        ? 'sales DESC, amount DESC'
        : 'amount DESC, sales DESC';
    final fromMs = from.toUtc().millisecondsSinceEpoch;
    final toMs = to.toUtc().millisecondsSinceEpoch;
    // NET quantities and amounts: the lines sold in the period (by the date
    // of the sale, voided invoices left out) less the lines returned in it
    // (by the date of the RETURN). One row per line on either side, then
    // one GROUP BY — nothing newer than sqlite 3.9.
    final rows = await _db.rawQuery(
      'SELECT gkey, product_id, '
      // sqlite guarantees that the bare columns of a group containing a
      // MAX() aggregate come from the row that produced that maximum, so the
      // name shown is the one from the most recent sale in the period (a
      // returned line carries 0 and never wins).
      'MAX(last_at) AS last_at, name, '
      'SUM(sales) AS sales, SUM(qty) AS qty, SUM(amount) AS amount '
      'FROM ('
      "SELECT CASE WHEN it.product_id IS NOT NULL THEN 'p' || it.product_id "
      "ELSE 'n' || it.product_name_norm END AS gkey, "
      'it.product_id AS product_id, i.created_at AS last_at, '
      'it.product_name AS name, 1 AS sales, it.qty_thousandths AS qty, '
      '$amount AS amount '
      'FROM invoice_items it '
      'JOIN invoices i ON i.id = it.invoice_id '
      'LEFT JOIN currencies c ON c.code = i.currency_code '
      'WHERE i.created_at >= ? AND i.created_at < ? AND $_live '
      '${renewalsOnly ? "AND it.kind = 'SERVICE' AND $_hasAccount " : ''}'
      'UNION ALL '
      "SELECT CASE WHEN it.product_id IS NOT NULL THEN 'p' || it.product_id "
      "ELSE 'n' || it.product_name_norm END, "
      'it.product_id, 0, it.product_name, 0, -it.qty_thousandths, '
      '-($returned) '
      'FROM invoice_return_items it '
      'JOIN invoice_returns i ON i.id = it.return_id '
      'LEFT JOIN currencies c ON c.code = i.currency_code '
      '${renewalsOnly ? 'JOIN invoices sold ON sold.id = i.invoice_id ' : ''}'
      'WHERE i.created_at >= ? AND i.created_at < ? '
      '${renewalsOnly ? "AND it.kind = 'SERVICE' "
          'AND sold.account_number IS NOT NULL ' : ''}'
      ') GROUP BY gkey '
      // What was only RETURNED in the period (and sold before it) is not a
      // best seller of it; the Returns figure is where that shows.
      'HAVING SUM(sales) > 0 '
      'ORDER BY $order LIMIT ?',
      [fromMs, toMs, fromMs, toMs, limit],
    );
    return [
      for (final row in rows)
        ProductStat(
          groupKey: row['gkey'] as String,
          name: row['name'] as String,
          productId: row['product_id'] as int?,
          salesCount: (row['sales'] as int?) ?? 0,
          qtyThousandths: (row['qty'] as int?) ?? 0,
          amountBaseMinor: (row['amount'] as int?) ?? 0,
        ),
    ];
  }

  /// An invoice linked to a customer's card / account, told by the account
  /// number SNAPSHOT — it survives the account being edited or deactivated.
  static const String _hasAccount = 'i.account_number IS NOT NULL';

  /// Renewals in the period: invoices that carry an account snapshot and
  /// sold at least one SERVICE/CARD item — the same rule that moves an
  /// account's due date when the invoice is saved.
  Future<RenewalStats> renewals({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(i.total_base_minor), 0) AS total '
      'FROM invoices i '
      'WHERE i.created_at >= ? AND i.created_at < ? AND $_hasAccount '
      // Neither voided nor taken back by the return of its package.
      'AND $_live AND i.renewal_undone = 0 '
      'AND EXISTS (SELECT 1 FROM invoice_items it '
      "WHERE it.invoice_id = i.id AND it.kind = 'SERVICE')",
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    );
    final row = rows.first;
    return RenewalStats(
      count: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
    );
  }

  /// Sales per customer in the period, the biggest first, from the invoice
  /// SNAPSHOTS: grouped by the linked customer when there still is one, and
  /// otherwise by the normalized name snapshot. The name shown is the one on
  /// the customer's most recent invoice in the period.
  Future<List<CustomerStat>> topCustomers({
    required DateTime from,
    required DateTime to,
    int limit = topProductsLimit,
  }) async {
    final rows = await _db.rawQuery(
      "SELECT CASE WHEN i.customer_id IS NOT NULL THEN 'c' || i.customer_id "
      "ELSE 'n' || COALESCE(i.customer_name_norm, '') END AS gkey, "
      'i.customer_id AS customer_id, '
      'MAX(i.created_at) AS last_at, i.customer_name AS name, '
      'COUNT(*) AS n, COALESCE(SUM(i.total_base_minor), 0) AS total '
      'FROM invoices i '
      'WHERE i.created_at >= ? AND i.created_at < ? AND $_live '
      'AND i.customer_name IS NOT NULL '
      'GROUP BY gkey ORDER BY total DESC, n DESC LIMIT ?',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
        limit,
      ],
    );
    return [
      for (final row in rows)
        CustomerStat(
          groupKey: row['gkey'] as String,
          name: row['name'] as String,
          customerId: row['customer_id'] as int?,
          invoiceCount: (row['n'] as int?) ?? 0,
          totalBaseMinor: (row['total'] as int?) ?? 0,
        ),
    ];
  }

  /// Prepaid cards sold in the period, per product, the best seller first.
  ///
  /// Counted from the CODES, not from the invoices: every sold code carries
  /// its own sale time and its price and cost in base currency as they were
  /// at the sale. So the figures survive the invoice being deleted by the
  /// archive's retention sweep, and a card voided or returned to stock since
  /// is no longer counted.
  ///
  /// The price is the line's unit price — before any discount on the whole
  /// invoice, which belongs to no single card.
  Future<List<CardSaleStat>> cardSales({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT c.product_id AS product_id, p.name AS name, COUNT(*) AS n, '
      'COALESCE(SUM(c.sold_price_base_minor), 0) AS revenue, '
      'SUM(CASE WHEN c.sold_cost_base_minor IS NOT NULL THEN 1 ELSE 0 END) '
      'AS n_cost, '
      'COALESCE(SUM(CASE WHEN c.sold_cost_base_minor IS NOT NULL '
      'THEN COALESCE(c.sold_price_base_minor, 0) - c.sold_cost_base_minor '
      'END), 0) AS profit '
      'FROM voucher_codes c JOIN products p ON p.id = c.product_id '
      "WHERE c.status = 'SOLD' AND c.sold_at >= ? AND c.sold_at < ? "
      'GROUP BY c.product_id ORDER BY n DESC, revenue DESC',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    );
    return [
      for (final row in rows)
        CardSaleStat(
          productId: row['product_id'] as int,
          name: row['name'] as String,
          count: (row['n'] as int?) ?? 0,
          revenueBaseMinor: (row['revenue'] as int?) ?? 0,
          costKnownCount: (row['n_cost'] as int?) ?? 0,
          profitBaseMinor: (row['profit'] as int?) ?? 0,
        ),
    ];
  }
}

/// Cards of one product sold in a period, in the BASE currency.
class CardSaleStat {
  const CardSaleStat({
    required this.productId,
    required this.name,
    required this.count,
    required this.revenueBaseMinor,
    required this.costKnownCount,
    required this.profitBaseMinor,
  });

  final int productId;
  final String name;
  final int count;
  final int revenueBaseMinor;

  /// How many of the [count] cards came from a batch with a cost entered.
  /// Profit is only known for those.
  final int costKnownCount;

  /// Sale price − cost, over the [costKnownCount] cards. Can be negative.
  final int profitBaseMinor;

  bool get hasProfit => costKnownCount > 0;

  /// Some of the cards had no cost entered: the profit covers only a part.
  bool get profitIsPartial => costKnownCount < count;
}

/// Renewals in a period, in the BASE currency.
class RenewalStats {
  const RenewalStats({required this.count, required this.totalBaseMinor});

  final int count;
  final int totalBaseMinor;
}

/// One row of the "sales per customer" table.
class CustomerStat {
  const CustomerStat({
    required this.groupKey,
    required this.name,
    required this.customerId,
    required this.invoiceCount,
    required this.totalBaseMinor,
  });

  /// `c<id>` for a linked customer, `n<normalized name>` for a snapshot
  /// whose customer link is gone.
  final String groupKey;
  final String name;
  final int? customerId;
  final int invoiceCount;
  final int totalBaseMinor;
}

/// Where a figure went against the period before it.
enum TrendDirection { up, down, flat }

/// One figure this period against the same figure last period.
///
/// The percentage is for DISPLAY only — a label next to the two exact
/// integer amounts, never something the app computes with.
class Comparison {
  const Comparison({required this.current, required this.previous});

  final int current;
  final int previous;

  int get difference => current - previous;

  TrendDirection get direction => switch (difference) {
        > 0 => TrendDirection.up,
        < 0 => TrendDirection.down,
        _ => TrendDirection.flat,
      };

  /// Percent change, or null when there is nothing to compare against
  /// (the previous period had none of this at all).
  double? get percent =>
      previous == 0 ? null : (difference * 100) / previous.abs();
}
