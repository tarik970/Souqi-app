@Tags(['performance'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/customer_seeder.dart';
import 'package:souqi/data/dev/debt_seeder.dart';
import 'package:souqi/data/dev/invoice_seeder.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// Times the debt ledger at the size the brief asks it to stay fast at:
/// 5,000 customers and 200,000 ledger entries.
///
/// On a REAL FILE, not in memory, and gated like the archive timings:
///
///     SOUQI_PERF=1 flutter test test/data/debt_performance_test.dart
///
/// The assertions are loose on purpose: they catch a lost index (orders of
/// magnitude), not a slow machine. The printed timings are the point.
void main() {
  if (Platform.environment['SOUQI_PERF'] != '1') {
    test('debt ledger timings', () {}, skip: 'set SOUQI_PERF=1 to run');
    return;
  }

  setUpAll(sqfliteFfiInit);

  const customers = 5000;
  const entries = 200000;
  const invoices = 3000;

  late Directory directory;
  late AppDatabase appDb;
  late DebtRepository debts;
  final now = DateTime.now();

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('souqi-debt-perf');
    appDb = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/souqi.db',
    );
    debts = DebtRepository(appDb.db);
    await insertProduct(appDb.db, name: 'سكر');
    var watch = Stopwatch()..start();
    await seedTestCustomers(appDb.db,
        customers: customers, accountsPerCustomer: 0, now: now);
    _report('seeding $customers customers', watch.elapsed);
    watch = Stopwatch()..start();
    expect(await seedTestDebts(appDb.db, entries: entries, now: now), entries);
    _report('seeding $entries ledger entries', watch.elapsed);
    _note('database file',
        '${File(appDb.path).lengthSync() ~/ 1024} KB');
  });

  tearDownAll(() async {
    await appDb.close();
    await directory.delete(recursive: true);
  });

  Future<Duration> time(String label, Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    await action();
    final elapsed = watch.elapsed;
    _report(label, elapsed);
    return elapsed;
  }

  test('the accounts of every customer (the one grouped pass)', () async {
    final elapsed = await time('accounts query (all customers)', () async {
      final rows = await appDb.db.rawQuery(DebtRepository.accountsQuery);
      expect(rows.length, greaterThan(1000));
      _note(
        'packed debits handed to Dart',
        '${rows.fold<int>(0, (sum, r) => sum + ((r['debits'] as String?)?.length ?? 0)) ~/ 1024} KB',
      );
    });
    expect(elapsed.inMilliseconds, lessThan(3000));
  });

  test('the debtors list, the home card and the statistics', () async {
    late int outstanding;
    var elapsed = await time('debtors snapshot (list + home card)', () async {
      final snapshot = await debts.debtors(now: now);
      outstanding = snapshot.totalOutstandingBaseMinor;
      expect(snapshot.aging.total, outstanding);
      _note('customers with a balance', '${snapshot.debtors.length}');
      _note('overdue customers', '${snapshot.overdueCount}');
    });
    expect(elapsed.inMilliseconds, lessThan(8000));
    elapsed = await time('debt statistics (one month)', () async {
      final stats = await debts.stats(
        from: DateTime(now.year, now.month),
        to: DateTime(now.year, now.month + 1),
        now: now,
      );
      expect(stats.outstandingBaseMinor, outstanding);
      expect(stats.topDebtors, hasLength(DebtRepository.topDebtorsLimit));
    });
    expect(elapsed.inMilliseconds, lessThan(10000));
  });

  test('one customer: balance, summary, ledger page, statement', () async {
    final id = (await appDb.db.query('customers',
            orderBy: 'id ASC', limit: 1, offset: 2500))
        .single['id'] as int;
    var elapsed =
        await time('one balance', () async => debts.balanceOf(id));
    expect(elapsed.inMilliseconds, lessThan(500));
    elapsed = await time('one account summary (FIFO in Dart)',
        () async => debts.accountSummary(id, now: now));
    expect(elapsed.inMilliseconds, lessThan(500));
    elapsed = await time('one ledger page', () async {
      final lines =
          await debts.ledger(id, limit: DebtRepository.ledgerPageSize);
      expect(lines, isNotEmpty);
    });
    expect(elapsed.inMilliseconds, lessThan(500));
    elapsed = await time('one statement (whole account)',
        () async => debts.statement(id));
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('recording a payment and reversing it', () async {
    final id = (await appDb.db.query('customers', limit: 1)).single['id'] as int;
    late int entryId;
    var elapsed = await time('record a payment', () async {
      entryId = (await debts.recordPayment(
        customerId: id,
        amountMinor: 1000,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
      ))
          .id;
    });
    expect(elapsed.inMilliseconds, lessThan(1000));
    elapsed = await time('reverse it',
        () async => debts.reverse(entryId, reason: 'timing'));
    expect(elapsed.inMilliseconds, lessThan(1000));
  });

  test('deleting invoices next to a full ledger', () async {
    // Invoices that each carry a debt, then all of them deleted: every
    // delete makes sqlite look for ledger entries pointing at the invoice.
    // With idx_debt_invoice that is a probe; without it, a scan of 200,000
    // rows per invoice.
    final created = await seedTestInvoices(appDb.db, count: invoices);
    expect(created, invoices);
    final customer =
        (await appDb.db.query('customers', limit: 1)).single['id'] as int;
    final ids = await appDb.db.query('invoices', columns: ['id', 'invoice_no']);
    await appDb.db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in ids) {
        batch.insert('debt_transactions', {
          'customer_id': customer,
          'type': 'DEBT',
          'direction': 1,
          'amount_base_minor': 1000,
          'invoice_id': row['id'],
          'invoice_no': row['invoice_no'],
          'created_at': 1,
          'recorded_at': 1,
        });
      }
      await batch.commit(noResult: true);
    });
    final archive = ArchiveRepository(appDb.db);
    final before = (await appDb.db
            .rawQuery('SELECT COUNT(*) FROM debt_transactions'))
        .first
        .values
        .first;
    var elapsed = await time('count invoices carrying debt', () async {
      expect(await archive.countCarryingDebt(const ArchiveFilter()), invoices);
    });
    expect(elapsed.inMilliseconds, lessThan(2000));
    elapsed = await time('delete $invoices invoices carrying debts', () async {
      while (await archive.deleteMatchingChunk(const ArchiveFilter()) > 0) {}
    });
    expect(elapsed.inMilliseconds, lessThan(15000));
    expect(
      (await appDb.db.rawQuery('SELECT COUNT(*) FROM debt_transactions'))
          .first
          .values
          .first,
      before,
    );
  });
}

void _report(String label, Duration elapsed) =>
    _note(label, '${elapsed.inMilliseconds} ms');

void _note(String label, String value) {
  // ignore: avoid_print
  print('PERF  ${label.padRight(40)} $value');
}
