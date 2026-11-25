import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/customer_seeder.dart';
import 'package:souqi/data/dev/debt_seeder.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The debug seeder writes a ledger the real code agrees with, and the
/// queries behind the debtors list, the statistics and invoice deletion run
/// on the indexes they were written for.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late DebtRepository debts;

  final now = DateTime(2026, 11, 25, 12);

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    debts = DebtRepository(db);
  });

  tearDown(() => appDb.close());

  Future<int> count(String sql) async =>
      (await db.rawQuery(sql)).first.values.first! as int;

  group('the seeder', () {
    test('writes nothing without customers', () async {
      expect(await seedTestDebts(db, entries: 100, now: now), 0);
      expect(await debts.hasEntries(), isFalse);
    });

    test('writes the entries asked for, plus a few reversals', () async {
      await seedTestCustomers(db, customers: 60, accountsPerCustomer: 0, now: now);
      final progress = <int>[];
      final written = await seedTestDebts(
        db,
        entries: 6000,
        now: now,
        onProgress: progress.add,
      );
      expect(written, 6000);
      expect(progress, [5000, 6000]);
      final reversals = await count(
          "SELECT COUNT(*) FROM debt_transactions WHERE type = 'REVERSAL'");
      expect(reversals, greaterThan(0));
      expect(await count('SELECT COUNT(*) FROM debt_transactions'),
          6000 + reversals);
      // Every type the screens show is there.
      for (final type in ['DEBT', 'MANUAL_DEBT', 'PAYMENT', 'OPENING_BALANCE']) {
        expect(
          await count("SELECT COUNT(*) FROM debt_transactions "
              "WHERE type = '$type'"),
          greaterThan(0),
          reason: type,
        );
      }
    });

    test('receipt numbers are unique and the counter carries on after them',
        () async {
      await seedTestCustomers(db, customers: 20, accountsPerCustomer: 0, now: now);
      await seedTestDebts(db, entries: 800, now: now);
      final payments = await count(
          "SELECT COUNT(*) FROM debt_transactions WHERE type = 'PAYMENT'");
      expect(await count('SELECT MAX(receipt_no) FROM debt_transactions'),
          payments);
      final customer = (await db.query('customers', limit: 1)).single['id'] as int;
      final next = await debts.recordPayment(
        customerId: customer,
        amountMinor: 100,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
      );
      expect(next.receiptNo, payments + 1);
      // Seeding again continues, it does not collide.
      await seedTestDebts(db, entries: 800, now: now);
      expect(
        await count('SELECT COUNT(DISTINCT receipt_no) FROM debt_transactions '
            'WHERE receipt_no IS NOT NULL'),
        await count("SELECT COUNT(*) FROM debt_transactions "
            "WHERE type = 'PAYMENT'"),
      );
    });

    test('produces every kind of account, and the SQL aging agrees with the '
        'Dart FIFO on it', () async {
      await seedTestCustomers(db, customers: 50, accountsPerCustomer: 0, now: now);
      await seedTestDebts(db, entries: 2000, now: now);
      final snapshot = await debts.debtors(now: now);
      expect(snapshot.owingCount, greaterThan(10));
      expect(snapshot.totalCreditBaseMinor, greaterThan(0),
          reason: 'someone has a credit balance');
      expect(snapshot.debtors.length, lessThan(50),
          reason: 'someone is settled');
      expect(snapshot.overdueCount, greaterThan(0));
      final aging = snapshot.aging;
      expect(aging.total, snapshot.totalOutstandingBaseMinor);
      expect(aging.amounts.where((a) => a > 0).length, greaterThanOrEqualTo(3),
          reason: 'aging: $aging');
      for (final debtor in snapshot.debtors) {
        final expected = await debts.accountSummary(debtor.customerId, now: now);
        expect(debtor.account.balanceBaseMinor, expected.balanceBaseMinor);
        expect(debtor.account.aging, expected.aging, reason: debtor.name);
        expect(debtor.account.oldestUnpaidAt, expected.oldestUnpaidAt);
        expect(debtor.account.overdueBaseMinor, expected.overdueBaseMinor);
        expect(debtor.account.lastPaymentAt, expected.lastPaymentAt);
      }
    });
  });

  group('the query plans', () {
    setUp(() async {
      await seedTestCustomers(db, customers: 40, accountsPerCustomer: 0, now: now);
      await seedTestDebts(db, entries: 1500, now: now);
    });

    /// What sqlite says it will do.
    Future<String> plan(String sql, [List<Object?> args = const []]) async {
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return rows.map((r) => r['detail']).join(' | ');
    }

    test('the accounts of every customer: ONE forward pass over the covering '
        'index, customers by primary key', () async {
      final detail = await plan(DebtRepository.accountsQuery);
      expect(detail, contains('SCAN t USING COVERING INDEX idx_debt_fifo'),
          reason: detail);
      // The "was it reversed?" probe is a search of the tiny partial index.
      expect(detail, contains('idx_debt_reverses'), reason: detail);
      expect(detail, isNot(contains('SCAN rv')), reason: detail);
      expect(detail, isNot(contains('SCAN c')), reason: detail);
      // Grouped in index order: nothing is sorted, nothing is read twice.
      expect(detail, isNot(contains('TEMP B-TREE')), reason: detail);
      expect('SCAN t'.allMatches(detail), hasLength(1), reason: detail);
    });

    test('the packed debits unpack into ledger order', () {
      expect(DebtRepository.unpackDebits(null), isEmpty);
      expect(DebtRepository.unpackDebits(''), isEmpty);
      final debits = DebtRepository.unpackDebits(
          '3000 7 250 9000,1000 2 100 ,1000 1 75 4000');
      expect(debits.map((d) => d.amountBaseMinor), [75, 100, 250]);
      expect(debits.map((d) => d.createdAt.millisecondsSinceEpoch),
          [1000, 1000, 3000]);
      expect(debits.map((d) => d.dueAt?.millisecondsSinceEpoch),
          [4000, null, 9000]);
    });

    test('period statistics: a range read of the created-at index', () async {
      final detail = await plan(DebtRepository.periodQuery, [0, 1]);
      expect(detail, contains('idx_debt_created'), reason: detail);
      expect(detail, contains('created_at>? AND created_at<?'), reason: detail);
      expect(detail, isNot(contains('SCAN t')), reason: detail);
    });

    test('one customer\'s ledger and balance come through their own index',
        () async {
      final ledger = await plan(
        'SELECT * FROM debt_transactions t WHERE t.customer_id = ? '
        'ORDER BY t.created_at DESC, t.id DESC LIMIT 200',
        [1],
      );
      expect(ledger, contains('idx_debt_customer'), reason: ledger);
      expect(ledger, isNot(contains('TEMP B-TREE')), reason: ledger);
      final balance = await plan(
        'SELECT SUM(amount_base_minor * direction) FROM debt_transactions '
        'WHERE customer_id = ?',
        [1],
      );
      expect(balance, contains('COVERING INDEX'), reason: balance);
    });

    test('deleting an invoice finds its ledger entries by index', () async {
      // What the foreign key's ON DELETE SET NULL runs for every deleted
      // invoice. Without idx_debt_invoice this is a scan of the whole
      // ledger, once per invoice.
      final detail = await plan(
        'UPDATE debt_transactions SET invoice_id = NULL WHERE invoice_id = ?',
        [1],
      );
      expect(detail, contains('idx_debt_invoice'), reason: detail);
      final carrying = await plan(
        'SELECT COUNT(*) FROM invoices i WHERE EXISTS ('
        'SELECT 1 FROM debt_transactions dt WHERE dt.invoice_id = i.id)',
      );
      expect(carrying, contains('idx_debt_invoice'), reason: carrying);
    });

    test('deleting invoices that carry debts leaves the seeded ledger whole',
        () async {
      final customer = (await db.query('customers', limit: 1)).single['id'] as int;
      final invoiceId = await insertInvoice(db, invoiceNo: 1);
      await db.insert('debt_transactions', {
        'customer_id': customer,
        'type': 'DEBT',
        'direction': 1,
        'amount_base_minor': 123,
        'invoice_id': invoiceId,
        'invoice_no': 1,
        'created_at': 1,
        'recorded_at': 1,
      });
      final before = await count('SELECT COUNT(*) FROM debt_transactions');
      final total = await count(
          'SELECT SUM(amount_base_minor * direction) FROM debt_transactions');
      final archive = ArchiveRepository(db);
      expect(await archive.countCarryingDebt(const ArchiveFilter()), 1);
      await archive.deleteMatchingChunk(const ArchiveFilter());
      expect(await count('SELECT COUNT(*) FROM invoices'), 0);
      expect(await count('SELECT COUNT(*) FROM debt_transactions'), before);
      expect(
        await count(
            'SELECT SUM(amount_base_minor * direction) FROM debt_transactions'),
        total,
      );
    });
  });
}
