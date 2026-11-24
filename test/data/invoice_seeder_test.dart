import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/invoice_seeder.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/counter_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The debug-only seeder. It exists so the archive and statistics screens
/// can be tried against a big archive on a real phone — which is only worth
/// anything if what it writes looks like real sales.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    await db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
  });
  tearDown(() => appDb.close());

  test('writes the asked-for number of invoices', () async {
    expect(await seedTestInvoices(db, count: 40), 40);
    expect(await db.query('invoices'), hasLength(40));
    expect(await db.query('invoice_items'), hasLength(120));
  });

  test('nothing to do for a count of zero', () async {
    expect(await seedTestInvoices(db, count: 0), 0);
    expect(await db.query('invoices'), isEmpty);
  });

  test('invoice numbers come from the real counter and stay sequential',
      () async {
    await seedTestInvoices(db, count: 5);
    final numbers = (await db.query('invoices', columns: ['invoice_no']))
        .map((r) => r['invoice_no'])
        .toList()
      ..sort();
    expect(numbers, [1, 2, 3, 4, 5]);
    expect(
      await const CounterRepository().next(db, CounterRepository.invoiceNo),
      6,
    );
  });

  test('carries on from invoices that are already there', () async {
    await insertInvoice(db, invoiceNo: 1);
    await const CounterRepository().next(db, CounterRepository.invoiceNo);
    await seedTestInvoices(db, count: 2);
    final numbers = (await db.query('invoices', columns: ['invoice_no']))
        .map((r) => r['invoice_no'] as int)
        .toList()
      ..sort();
    expect(numbers, [1, 2, 3]);
  });

  test('spreads the invoices back over the asked-for days', () async {
    final now = DateTime(2026, 11, 24, 12);
    await seedTestInvoices(db, count: 10, days: 30, now: now);
    final created = (await db.query('invoices', columns: ['created_at']))
        .map((r) => DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
              isUtc: true,
            ))
        .toList();
    expect(created.every((at) => !at.isAfter(now.toUtc())), isTrue);
    expect(
      created.every(
        (at) => at.isAfter(now.toUtc().subtract(const Duration(days: 31))),
      ),
      isTrue,
    );
  });

  test('the items are searchable: the normalized column is filled', () async {
    await seedTestInvoices(db, count: 10);
    final archive = ArchiveRepository(db);
    // "السكر" and "سكر" are both seeded and both found by either spelling.
    final found =
        await archive.page(filter: const ArchiveFilter(productQuery: 'السكر'));
    expect(found, isNotEmpty);
    final rows = await db.query(
      'invoice_items',
      where: "product_name_norm = ''",
    );
    expect(rows, isEmpty, reason: 'every item must be searchable');
  });

  test('links lines to products that already exist', () async {
    await insertProduct(db, name: 'سكر');
    await seedTestInvoices(db, count: 10);
    final linked = await db.query(
      'invoice_items',
      where: 'product_id IS NOT NULL',
    );
    expect(linked, isNotEmpty);
  });

  test('mixes in a second currency with its own rate snapshot', () async {
    await seedTestInvoices(db, count: 10);
    final codes = (await db.query('invoices', columns: ['currency_code']))
        .map((r) => r['currency_code'])
        .toSet();
    expect(codes, containsAll(['SYP', 'USD']));
    final usd = (await db.query(
      'invoices',
      where: 'currency_code = ?',
      whereArgs: ['USD'],
    )).first;
    expect(usd['rate_num'], 13000);
    expect(usd['rate_den'], 1);
  });

  test('a USD invoice stores a base total above its own total', () async {
    await seedTestInvoices(db, count: 10);
    final usd = (await db.query(
      'invoices',
      where: 'currency_code = ?',
      whereArgs: ['USD'],
    )).first;
    expect(usd['total_base_minor'] as int, greaterThan(usd['total_minor'] as int));
  });

  test('the statistics screen has something to show', () async {
    final now = DateTime(2026, 11, 24, 12);
    await seedTestInvoices(db, count: 30, days: 30, now: now);
    final stats = StatsRepository(db);
    final summary = await stats.summary(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 12, 1),
      baseDecimals: 0,
    );
    expect(summary.invoiceCount, 30);
    expect(summary.totalBaseMinor, greaterThan(0));
    expect(summary.discountBaseMinor, greaterThan(0),
        reason: 'some invoices must carry a discount');

    final top = await stats.topProducts(
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 12, 1),
      baseDecimals: 0,
    );
    expect(top, isNotEmpty);
  });
}
