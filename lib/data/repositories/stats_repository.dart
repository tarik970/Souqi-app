import 'package:sqflite/sqflite.dart';

/// The headline figures of one period, all in the BASE currency.
class PeriodStats {
  const PeriodStats({
    required this.from,
    required this.to,
    required this.invoiceCount,
    required this.totalBaseMinor,
    required this.discountBaseMinor,
  });

  /// The period: [from] inclusive, [to] exclusive.
  final DateTime from;
  final DateTime to;

  final int invoiceCount;

  /// Sum of each invoice's stored `total_base_minor` — the base-currency
  /// amount computed at the moment of the sale with that day's rate.
  final int totalBaseMinor;

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
      'WHERE i.created_at >= ? AND i.created_at < ?',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
    );
    final row = rows.first;
    return PeriodStats(
      from: from,
      to: to,
      invoiceCount: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
      discountBaseMinor: (row['discount'] as int?) ?? 0,
    );
  }

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
      'WHERE i.created_at >= ? AND i.created_at < ? '
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
  Future<List<ProductStat>> topProducts({
    required DateTime from,
    required DateTime to,
    required int baseDecimals,
    ProductRanking ranking = ProductRanking.amount,
    int limit = topProductsLimit,
  }) async {
    final amount = _toBaseSql('it.line_total_minor', _pow10(baseDecimals));
    final order = ranking == ProductRanking.sales
        ? 'sales DESC, amount DESC'
        : 'amount DESC, sales DESC';
    final rows = await _db.rawQuery(
      "SELECT CASE WHEN it.product_id IS NOT NULL THEN 'p' || it.product_id "
      "ELSE 'n' || it.product_name_norm END AS gkey, "
      'it.product_id AS product_id, '
      // sqlite guarantees that the bare columns of a group containing a
      // MAX() aggregate come from the row that produced that maximum, so the
      // name shown is the one from the most recent sale in the period.
      'MAX(i.created_at) AS last_at, it.product_name AS name, '
      'COUNT(*) AS sales, '
      'COALESCE(SUM(it.qty_thousandths), 0) AS qty, '
      'COALESCE(SUM($amount), 0) AS amount '
      'FROM invoice_items it '
      'JOIN invoices i ON i.id = it.invoice_id '
      'LEFT JOIN currencies c ON c.code = i.currency_code '
      'WHERE i.created_at >= ? AND i.created_at < ? '
      'GROUP BY gkey ORDER BY $order LIMIT ?',
      [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
        limit,
      ],
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
