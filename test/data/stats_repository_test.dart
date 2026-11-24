import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The statistics are only worth anything if the money is right: every
/// amount in the BASE currency, taken from what each invoice stored at the
/// time of the sale.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late StatsRepository stats;

  /// SYP is the base currency with 0 decimals; USD has 2 and a stored rate
  /// of 13,000 SYP per dollar.
  const usdRate = RateFraction(13000, 1);

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    stats = StatsRepository(db);
    await db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
  });
  tearDown(() => appDb.close());

  final november = DateTime(2026, 11, 1);
  final december = DateTime(2026, 12, 1);

  Future<PeriodStats> summary({DateTime? from, DateTime? to}) => stats.summary(
        from: from ?? november,
        to: to ?? december,
        baseDecimals: 0,
      );

  group('summary', () {
    test('an empty period is zeros, not an error', () async {
      final result = await summary();
      expect(result.invoiceCount, 0);
      expect(result.totalBaseMinor, 0);
      expect(result.discountBaseMinor, 0);
      expect(result.averageBaseMinor, 0);
    });

    test('counts and totals from the stored base amounts', () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        subtotalMinor: 10000,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 6),
        subtotalMinor: 5000,
      );
      final result = await summary();
      expect(result.invoiceCount, 2);
      expect(result.totalBaseMinor, 15000);
      expect(result.averageBaseMinor, 7500);
    });

    test('ignores invoices outside the period', () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 10, 31, 23, 59),
        subtotalMinor: 999999,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: december,
        subtotalMinor: 999999,
      );
      await insertInvoice(
        db,
        invoiceNo: 3,
        createdAt: november,
        subtotalMinor: 1000,
      );
      final result = await summary();
      expect(result.invoiceCount, 1);
      expect(result.totalBaseMinor, 1000);
    });

    test('the average rounds half-up', () async {
      // 1,000 + 1,001 over two invoices = 1,000.5 → 1,001.
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        subtotalMinor: 1000,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 6),
        subtotalMinor: 1001,
      );
      expect((await summary()).averageBaseMinor, 1001);
    });

    test('a USD invoice contributes its stored base total, not its own',
        () async {
      // 3.85 USD at 13,000 SYP/USD = 50,050 SYP, computed at sale time.
      final base = toBaseMinor(
        amountMinor: 385,
        fromDecimals: 2,
        fromRate: usdRate,
        baseDecimals: 0,
      );
      expect(base, 50050);
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 7),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 385,
        totalBaseMinor: base,
      );
      final result = await summary();
      expect(result.totalBaseMinor, 50050);
    });

    test('a rate change today does not move a past total', () async {
      final base = toBaseMinor(
        amountMinor: 100,
        fromDecimals: 2,
        fromRate: usdRate,
        baseDecimals: 0,
      );
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 7),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 100,
        totalBaseMinor: base,
      );
      final before = (await summary()).totalBaseMinor;

      await db.update(
        'currencies',
        {'rate_num': 25000, 'rate_den': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );

      expect((await summary()).totalBaseMinor, before);
    });

    test('mixed currencies add up in base', () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        subtotalMinor: 10000,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 6),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 100,
        totalBaseMinor: 13000,
      );
      final result = await summary();
      expect(result.invoiceCount, 2);
      expect(result.totalBaseMinor, 23000);
    });
  });

  group('discounts', () {
    test('a base-currency discount is summed as it stands', () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        subtotalMinor: 10000,
        discountMinor: 1500,
      );
      final result = await summary();
      expect(result.discountBaseMinor, 1500);
      expect(result.totalBaseMinor, 8500);
    });

    test('a USD discount is converted with the invoice own rate', () async {
      // 2.50 USD off, at the 13,000 rate stored on that invoice = 32,500 SYP.
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 1000,
        discountMinor: 250,
        totalBaseMinor: 97500,
      );
      expect((await summary()).discountBaseMinor, 32500);
    });

    test('the conversion rounds half-up, per invoice', () async {
      // 1 cent at 13,000/1 is 130 SYP exactly; 1 cent at 101/1 is 1.01 SYP,
      // which must come out as 1, and 1 cent at 150/1 is 1.5 → 2.
      Future<int> discountInBase(int rateNum) async {
        await db.delete('invoices');
        await insertInvoice(
          db,
          invoiceNo: 1,
          createdAt: DateTime(2026, 11, 5),
          currency: 'USD',
          rateNum: rateNum,
          subtotalMinor: 1000,
          discountMinor: 1,
        );
        return (await summary()).discountBaseMinor;
      }

      expect(await discountInBase(13000), 130);
      expect(await discountInBase(101), 1);
      expect(await discountInBase(150), 2);
    });
  });

  group('the previous period', () {
    test('is the same figures over the equal-length range before it',
        () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 10),
        subtotalMinor: 10000,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 3),
        subtotalMinor: 4000,
      );

      final week = await stats.summary(
        from: DateTime(2026, 11, 8),
        to: DateTime(2026, 11, 15),
        baseDecimals: 0,
      );
      final before = await stats.summary(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 8),
        baseDecimals: 0,
      );

      expect(week.totalBaseMinor, 10000);
      expect(before.totalBaseMinor, 4000);

      final comparison = Comparison(
        current: week.totalBaseMinor,
        previous: before.totalBaseMinor,
      );
      expect(comparison.direction, TrendDirection.up);
      expect(comparison.difference, 6000);
      expect(comparison.percent, 150);
    });

    test('nothing last period is a change with no percentage', () async {
      const comparison = Comparison(current: 5000, previous: 0);
      expect(comparison.percent, isNull);
      expect(comparison.direction, TrendDirection.up);
    });

    test('a drop to nothing is down, not flat', () async {
      const comparison = Comparison(current: 0, previous: 5000);
      expect(comparison.direction, TrendDirection.down);
      expect(comparison.percent, -100);
    });

    test('equal periods are flat', () {
      const comparison = Comparison(current: 100, previous: 100);
      expect(comparison.direction, TrendDirection.flat);
      expect(comparison.percent, 0);
    });
  });

  group('top products', () {
    Future<List<ProductStat>> top({
      ProductRanking ranking = ProductRanking.amount,
    }) =>
        stats.topProducts(
          from: november,
          to: december,
          baseDecimals: 0,
          ranking: ranking,
        );

    test('groups by product_id and names it from the latest sale', () async {
      final productId = await insertProduct(db, name: 'سكر');
      final first = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
      );
      await insertInvoiceItem(
        db,
        invoiceId: first,
        productId: productId,
        name: 'سكر',
        unitPriceMinor: 1000,
      );
      final second = await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 20),
      );
      await insertInvoiceItem(
        db,
        invoiceId: second,
        productId: productId,
        // Renamed in the catalog between the two sales; the snapshot of the
        // later sale is what the table shows.
        name: 'سكر ناعم',
        unitPriceMinor: 2000,
      );

      final rows = await top();
      expect(rows, hasLength(1));
      expect(rows.single.productId, productId);
      expect(rows.single.name, 'سكر ناعم');
      expect(rows.single.salesCount, 2);
      expect(rows.single.amountBaseMinor, 3000);
    });

    test('groups unsaved items by their normalized snapshot name', () async {
      // Three sales of an item that never became a product, typed three
      // ways: one row, three sales.
      for (final (i, name) in ['سكر', 'السكر', 'سُكَّر'].indexed) {
        final id = await insertInvoice(
          db,
          invoiceNo: i + 1,
          createdAt: DateTime(2026, 11, 5 + i),
        );
        await insertInvoiceItem(
          db,
          invoiceId: id,
          productId: null,
          name: name,
          unitPriceMinor: 1000,
        );
      }

      final rows = await top();
      expect(rows, hasLength(1));
      expect(rows.single.productId, isNull);
      expect(rows.single.groupKey, 'nسكر');
      expect(rows.single.salesCount, 3);
      expect(rows.single.amountBaseMinor, 3000);
    });

    test('a saved product and an unsaved item are separate rows', () async {
      final productId = await insertProduct(db, name: 'شاي');
      final id = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
      );
      await insertInvoiceItem(
        db,
        invoiceId: id,
        productId: productId,
        name: 'شاي',
      );
      await insertInvoiceItem(
        db,
        invoiceId: id,
        productId: null,
        name: 'عصير',
        sortOrder: 1,
      );
      expect(await top(), hasLength(2));
    });

    test('amounts are converted to base with each invoice own rate',
        () async {
      final syp = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
      );
      await insertInvoiceItem(
        db,
        invoiceId: syp,
        name: 'سكر',
        unitPriceMinor: 5000,
        qtyThousandths: 1000,
      );
      final usd = await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 6),
        currency: 'USD',
        rateNum: 13000,
      );
      await insertInvoiceItem(
        db,
        invoiceId: usd,
        name: 'سكر',
        currency: 'USD',
        rateNum: 13000,
        // 1.00 USD of sugar = 13,000 SYP.
        unitPriceMinor: 100,
        qtyThousandths: 1000,
      );

      final rows = await top();
      expect(rows, hasLength(1));
      expect(rows.single.amountBaseMinor, 18000);
    });

    test('ranks by number of sales or by amount, as asked', () async {
      // Cheap-and-often against dear-and-rarely.
      for (var i = 0; i < 3; i++) {
        final id = await insertInvoice(
          db,
          invoiceNo: i + 1,
          createdAt: DateTime(2026, 11, 5 + i),
        );
        await insertInvoiceItem(
          db,
          invoiceId: id,
          name: 'خبز',
          unitPriceMinor: 100,
        );
      }
      final big = await insertInvoice(
        db,
        invoiceNo: 9,
        createdAt: DateTime(2026, 11, 20),
      );
      await insertInvoiceItem(
        db,
        invoiceId: big,
        name: 'زيت',
        unitPriceMinor: 90000,
      );

      expect(
        (await top(ranking: ProductRanking.sales)).map((p) => p.name),
        ['خبز', 'زيت'],
      );
      expect(
        (await top(ranking: ProductRanking.amount)).map((p) => p.name),
        ['زيت', 'خبز'],
      );
    });

    test('keeps to the limit', () async {
      final id = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
      );
      for (var i = 0; i < 15; i++) {
        await insertInvoiceItem(
          db,
          invoiceId: id,
          name: 'item $i',
          sortOrder: i,
          unitPriceMinor: 100 * (i + 1),
        );
      }
      expect(await top(), hasLength(StatsRepository.topProductsLimit));
    });

    test('only the period is counted', () async {
      final outside = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 10, 1),
      );
      await insertInvoiceItem(db, invoiceId: outside, name: 'سكر');
      expect(await top(), isEmpty);
    });
  });

  group('by currency', () {
    test('splits the period by the invoice currency, keeping both views',
        () async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 5),
        subtotalMinor: 10000,
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 6),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 200,
        totalBaseMinor: 26000,
      );

      final rows = await stats.byCurrency(from: november, to: december);
      expect(rows.map((r) => r.currencyCode), ['USD', 'SYP']);
      final usd = rows.firstWhere((r) => r.currencyCode == 'USD');
      expect(usd.invoiceCount, 1);
      expect(usd.totalMinor, 200, reason: 'in its own minor units');
      expect(usd.totalBaseMinor, 26000);
    });
  });
}
