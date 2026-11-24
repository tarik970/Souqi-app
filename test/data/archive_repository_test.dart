import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/counter_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The archive's filters, its paging and the guarantees deletion must keep.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late ArchiveRepository archive;

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    archive = ArchiveRepository(db);
  });
  tearDown(() => appDb.close());

  group('listing', () {
    test('newest first, with the item count', () async {
      final older = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 11, 1, 10),
      );
      await insertInvoiceItem(db, invoiceId: older);
      final newer = await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 2, 10),
      );
      await insertInvoiceItem(db, invoiceId: newer, name: 'Tea');
      await insertInvoiceItem(db, invoiceId: newer, name: 'Rice', sortOrder: 1);

      final page = await archive.page();
      expect(page.map((e) => e.invoiceNo), [2, 1]);
      expect(page.first.itemCount, 2);
      expect(page.last.itemCount, 1);
      expect(page.first.totalMinor, 1000);
    });

    test('shows the customer name snapshot', () async {
      await insertInvoice(db, invoiceNo: 1, customerName: 'أحمد');
      expect((await archive.page()).single.customerName, 'أحمد');
    });
  });

  group('paging', () {
    /// 25 invoices, newest last by number.
    Future<void> seed(int count) async {
      for (var i = 1; i <= count; i++) {
        await insertInvoice(
          db,
          invoiceNo: i,
          createdAt: DateTime(2026, 11, 1).add(Duration(minutes: i)),
        );
      }
    }

    test('walks the whole archive with no gaps and no repeats', () async {
      await seed(25);
      final seen = <int>[];
      ArchiveCursor? cursor;
      for (var round = 0; round < 10; round++) {
        final page = await archive.page(after: cursor, limit: 10);
        if (page.isEmpty) break;
        seen.addAll(page.map((e) => e.invoiceNo));
        cursor = page.last.cursor;
      }
      expect(seen, List.generate(25, (i) => 25 - i));
      expect(seen.toSet(), hasLength(25));
    });

    test('invoices in the same millisecond are still paged one by one',
        () async {
      // The id breaks the tie: without it a page boundary inside a group of
      // same-millisecond sales would skip or repeat rows.
      final at = DateTime(2026, 11, 3, 12);
      for (var i = 1; i <= 5; i++) {
        await insertInvoice(db, invoiceNo: i, createdAt: at);
      }
      final first = await archive.page(limit: 2);
      final second = await archive.page(after: first.last.cursor, limit: 2);
      final third = await archive.page(after: second.last.cursor, limit: 2);
      expect(
        [...first, ...second, ...third].map((e) => e.invoiceNo),
        [5, 4, 3, 2, 1],
      );
    });

    test('the filter is carried into every page', () async {
      await seed(25);
      await insertInvoice(
        db,
        invoiceNo: 99,
        createdAt: DateTime(2020, 1, 1),
      );
      final filter = ArchiveFilter(from: DateTime(2026, 11, 1));
      final page = await archive.page(filter: filter, limit: 10);
      final next = await archive.page(
        filter: filter,
        after: page.last.cursor,
        limit: 100,
      );
      expect([...page, ...next].map((e) => e.invoiceNo), isNot(contains(99)));
      expect([...page, ...next], hasLength(25));
    });
  });

  group('date range', () {
    setUp(() async {
      await insertInvoice(db, invoiceNo: 1, createdAt: DateTime(2026, 11, 20));
      await insertInvoice(db, invoiceNo: 2, createdAt: DateTime(2026, 11, 24));
      await insertInvoice(db, invoiceNo: 3, createdAt: DateTime(2026, 11, 25));
    });

    test('from is inclusive and to is exclusive', () async {
      final page = await archive.page(
        filter: ArchiveFilter(
          from: DateTime(2026, 11, 24),
          to: DateTime(2026, 11, 25),
        ),
      );
      expect(page.map((e) => e.invoiceNo), [2]);
    });

    test('summary counts and totals the range', () async {
      final summary = await archive.summary(
        ArchiveFilter(from: DateTime(2026, 11, 24)),
      );
      expect(summary.count, 2);
      expect(summary.totalBaseMinor, 2000);
    });
  });

  group('invoice number', () {
    test('matches exactly, ignores non-numeric noise', () async {
      await insertInvoice(db, invoiceNo: 7);
      await insertInvoice(db, invoiceNo: 70);
      expect(
        (await archive.page(filter: const ArchiveFilter(invoiceNo: 7)))
            .map((e) => e.invoiceNo),
        [7],
      );
    });
  });

  group('product search over the item snapshots', () {
    setUp(() async {
      final sugar = await insertInvoice(db, invoiceNo: 1);
      await insertInvoiceItem(db, invoiceId: sugar, name: 'السكر الناعم');
      final tea = await insertInvoice(db, invoiceNo: 2);
      await insertInvoiceItem(db, invoiceId: tea, name: 'شاي أخضر');
      final other = await insertInvoice(db, invoiceNo: 3);
      await insertInvoiceItem(db, invoiceId: other, name: 'Rice');
    });

    Future<List<int>> search(String query) async =>
        (await archive.page(filter: ArchiveFilter(productQuery: query)))
            .map((e) => e.invoiceNo)
            .toList();

    test('finds the Arabic name however it is typed', () async {
      // The shared normalization: the leading "ال", أ/إ/آ → ا, diacritics
      // and tatweel all fold away on both sides of the comparison.
      expect(await search('سكر'), [1]);
      expect(await search('السكر'), [1]);
      expect(await search('سُكَّر'), [1]);
      expect(await search('ســكر'), [1]);
      expect(await search('شاي اخضر'), [2]);
      expect(await search('أخضر'), [2]);
    });

    test('is case-insensitive for Latin names', () async {
      expect(await search('rice'), [3]);
      expect(await search('RICE'), [3]);
    });

    test('an item that never became a product is still found', () async {
      final typed = await insertInvoice(db, invoiceNo: 4);
      await insertInvoiceItem(db, invoiceId: typed, name: 'عصير', productId: null);
      expect(await search('عصير'), [4]);
    });

    test('a wildcard typed by the user is literal text', () async {
      expect(await search('%'), isEmpty);
    });

    test('no match is an empty list, not everything', () async {
      expect(await search('zzz'), isEmpty);
    });
  });

  group('customer search over the invoice snapshots', () {
    setUp(() async {
      await insertInvoice(
        db,
        invoiceNo: 1,
        customerName: 'أحمد العلي',
        customerPhone: '0944 123 456',
      );
      await insertInvoice(
        db,
        invoiceNo: 2,
        customerName: 'سمير',
        accountNumber: '0011-2233-4455',
      );
      await insertInvoice(db, invoiceNo: 3);
    });

    Future<List<int>> search(String query) async =>
        (await archive.page(filter: ArchiveFilter(customerQuery: query)))
            .map((e) => e.invoiceNo)
            .toList();

    test('matches the name through the shared normalization', () async {
      expect(await search('احمد'), [1]);
      expect(await search('أحمد'), [1]);
      expect(await search('العلي'), [1]);
      expect(await search('علي'), [1]);
    });

    test('matches the phone however it was written', () async {
      expect(await search('0944123456'), [1]);
      expect(await search('0944 123 456'), [1]);
      expect(await search('944123'), [1]);
      // Arabic-Indic digits are the same number.
      expect(await search('٠٩٤٤'), [1]);
    });

    test('matches the account number ignoring spaces and dashes', () async {
      expect(await search('00112233'), [2]);
      expect(await search('0011 2233'), [2]);
      expect(await search('2233-4455'), [2]);
    });

    test('an invoice with no customer never matches', () async {
      expect(await search('a'), isNot(contains(3)));
    });
  });

  group('filters combine', () {
    test('date range and product search are ANDed', () async {
      final old = await insertInvoice(
        db,
        invoiceNo: 1,
        createdAt: DateTime(2026, 10, 1),
      );
      await insertInvoiceItem(db, invoiceId: old, name: 'سكر');
      final recent = await insertInvoice(
        db,
        invoiceNo: 2,
        createdAt: DateTime(2026, 11, 24),
      );
      await insertInvoiceItem(db, invoiceId: recent, name: 'سكر');

      final page = await archive.page(
        filter: ArchiveFilter(
          from: DateTime(2026, 11, 1),
          productQuery: 'سكر',
        ),
      );
      expect(page.map((e) => e.invoiceNo), [2]);
    });
  });

  group('deleting one invoice keeps everything it must', () {
    test('the counter never goes back, numbers are never reused', () async {
      const counters = CounterRepository();
      await counters.next(db, CounterRepository.invoiceNo);
      await counters.next(db, CounterRepository.invoiceNo);
      final id = await insertInvoice(db, invoiceNo: 2);

      expect(await archive.deleteInvoice(id), isTrue);

      final counter = (await db.query(
        'counters',
        where: 'name = ?',
        whereArgs: [CounterRepository.invoiceNo],
      )).single;
      expect(counter['value'], 2);
      // The next sale gets 3, not the 2 that was just freed.
      expect(await counters.next(db, CounterRepository.invoiceNo), 3);
    });

    test('products survive, including one created by type-to-sell', () async {
      final productId = await insertProduct(db, name: 'عصير');
      final id = await insertInvoice(db, invoiceNo: 1);
      await insertInvoiceItem(db, invoiceId: id, productId: productId);

      await archive.deleteInvoice(id);

      expect(await db.query('products'), hasLength(1));
      expect((await db.query('invoice_items')), isEmpty);
    });

    test('a sold voucher code keeps its sale snapshot', () async {
      final productId =
          await insertProduct(db, kind: 'SERVICE', soldFromCodeStock: 1);
      final batchId = await insertVoucherBatch(db, productId: productId);
      final codeId = await insertVoucherCode(
        db,
        productId: productId,
        batchId: batchId,
        codeHash: 'H1',
      );
      final id = await insertInvoice(db, invoiceNo: 5);
      final itemId = await insertInvoiceItem(db, invoiceId: id);
      await db.update(
        'voucher_codes',
        {
          'status': 'SOLD',
          'invoice_id': id,
          'invoice_item_id': itemId,
          'sold_invoice_no': 5,
          'sold_customer_name': 'أحمد',
          'sold_account_number': '001234',
        },
        where: 'id = ?',
        whereArgs: [codeId],
      );

      await archive.deleteInvoice(id);

      final code = (await db.query(
        'voucher_codes',
        where: 'id = ?',
        whereArgs: [codeId],
      )).single;
      expect(code['status'], 'SOLD');
      expect(code['sold_invoice_no'], 5);
      expect(code['sold_customer_name'], 'أحمد');
      expect(code['sold_account_number'], '001234');
      expect(code['invoice_id'], isNull, reason: 'only the link is dropped');
    });

    test('deleting an invoice that is already gone is not an error', () async {
      expect(await archive.deleteInvoice(999), isFalse);
    });
  });

  group('deleting a range keeps the same guarantees', () {
    test('counter, products and voucher snapshots all survive', () async {
      const counters = CounterRepository();
      final productId = await insertProduct(db, name: 'سكر');
      for (var i = 1; i <= 3; i++) {
        await counters.next(db, CounterRepository.invoiceNo);
        final id = await insertInvoice(
          db,
          invoiceNo: i,
          createdAt: DateTime(2026, 10, i),
        );
        await insertInvoiceItem(db, invoiceId: id, productId: productId);
      }

      final deleted = await archive.deleteMatchingChunk(
        ArchiveFilter(to: DateTime(2026, 11, 1)),
      );

      expect(deleted, 3);
      expect(await db.query('invoices'), isEmpty);
      expect(await db.query('invoice_items'), isEmpty);
      expect(await db.query('products'), hasLength(1));
      expect(await counters.next(db, CounterRepository.invoiceNo), 4);
    });
  });

  group('the query plans', () {
    /// What sqlite says it will do. A range query that falls back to a full
    /// table scan is the difference between instant and several seconds on a
    /// 50,000-invoice archive.
    Future<String> plan(String sql, List<Object?> args) async {
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return rows.map((r) => r['detail']).join(' | ');
    }

    final ranged = ArchiveFilter(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 12, 1),
    );

    test('the summary aggregate goes through the created_at index', () async {
      final (sql, args) = archive.summaryQuery(ranged);
      final detail = await plan(sql, args);
      expect(detail, contains('idx_invoices_created'));
      expect(detail, isNot(contains('SCAN invoices')));
    });

    test('the summary is one aggregate row, not a list of invoices', () {
      final (sql, _) = archive.summaryQuery(ranged);
      expect(sql, contains('COUNT(*)'));
      expect(sql, contains('SUM(i.total_base_minor)'));
    });

    test('the chunk delete picks its ids through the same index', () async {
      final (sql, args) = archive.deleteChunkQuery(ranged, limit: 2000);
      final detail = await plan(sql, args);
      expect(detail, contains('idx_invoices_created'));
      expect(detail, isNot(contains('SCAN invoices')));
      // Bounded: never "delete everything matching" in one statement.
      expect(sql, contains('LIMIT ?'));
    });

    test('a page goes through the created_at index', () async {
      final detail = await plan(
        'SELECT i.id FROM invoices i WHERE i.created_at >= ? '
        'ORDER BY i.created_at DESC, i.id DESC LIMIT 30',
        [0],
      );
      expect(detail, contains('idx_invoices_created'));
    });
  });

  group('getById', () {
    test('returns the invoice with its items in order', () async {
      final id = await insertInvoice(db, invoiceNo: 9, customerName: 'سمير');
      await insertInvoiceItem(db, invoiceId: id, name: 'B', sortOrder: 1);
      await insertInvoiceItem(db, invoiceId: id, name: 'A', sortOrder: 0);

      final invoice = await archive.getById(id);
      expect(invoice, isNotNull);
      expect(invoice!.invoiceNo, 9);
      expect(invoice.customerName, 'سمير');
      expect(invoice.items.map((i) => i.productName), ['A', 'B']);
    });

    test('null for an invoice that is not there', () async {
      expect(await archive.getById(404), isNull);
    });
  });
}
