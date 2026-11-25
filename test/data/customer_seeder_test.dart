import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/due_dates.dart';
import 'package:souqi/core/utils/normalize.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/customer_seeder.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The debug-only customer seeder, and — on what it writes — the quick
/// search and the due list at the size the brief asks them to stay instant
/// with: 5,000 customers and 10,000 accounts.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late CustomerRepository customers;

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    customers = CustomerRepository(db);
  });
  tearDown(() => appDb.close());

  group('seedTestCustomers', () {
    test('writes the asked-for customers, each with two accounts', () async {
      expect(await seedTestCustomers(db, customers: 40), 40);
      expect(await db.query('customers'), hasLength(40));
      expect(await db.query('customer_accounts'), hasLength(80));
    });

    test('nothing to do for a count of zero', () async {
      expect(await seedTestCustomers(db, customers: 0), 0);
      expect(await db.query('customers'), isEmpty);
      expect(await db.query('products'), isEmpty);
    });

    test('reports progress chunk by chunk', () async {
      final progress = <int>[];
      await seedTestCustomers(db, customers: 1200, onProgress: progress.add);
      expect(progress, [500, 1000, 1200]);
    });

    test('fills the search columns through the shared normalizers', () async {
      await seedTestCustomers(db, customers: 60);
      for (final row in await db.query('customers')) {
        expect(row['name_norm'], normalizeName(row['name'] as String));
        final phone = row['phone'] as String?;
        expect(
          row['phone_norm'],
          phone == null ? isNull : normalizePhone(phone),
        );
      }
      for (final row in await db.query('customer_accounts')) {
        expect(
          row['account_number_norm'],
          normalizeCode(row['account_number'] as String),
        );
      }
    });

    test('writes phones the ways shops really type them', () async {
      await seedTestCustomers(db, customers: 40);
      final phones = (await db.query('customers', columns: ['phone']))
          .map((r) => r['phone'] as String?)
          .toList();
      expect(phones.any((p) => p == null), isTrue, reason: 'optional');
      expect(phones.any((p) => p != null && p.contains(' ')), isTrue);
      expect(phones.any((p) => p != null && p.startsWith('+963')), isTrue);
      expect(
        phones.any((p) => p != null && p.contains(RegExp('[٠-٩]'))),
        isTrue,
        reason: 'Arabic-Indic digits',
      );
    });

    test('writes account numbers with leading zeros and with letters',
        () async {
      await seedTestCustomers(db, customers: 20);
      final numbers =
          (await db.query('customer_accounts', columns: ['account_number']))
              .map((r) => r['account_number'] as String)
              .toList();
      expect(numbers.any((n) => n.startsWith('00')), isTrue);
      expect(numbers.any((n) => n.startsWith('AB-')), isTrue);
      expect(numbers.toSet(), hasLength(numbers.length), reason: 'unique');
    });

    test('creates packages to renew when the catalog has none', () async {
      await seedTestCustomers(db, customers: 10);
      final packages = await db.query('products', where: "kind = 'SERVICE'");
      expect(packages, hasLength(seedPackages.length));
      final linked = await db.query(
        'customer_accounts',
        where: 'default_product_id IS NOT NULL',
      );
      expect(linked, hasLength(20));
    });

    test('uses the shop\'s own packages when it has some', () async {
      final own = await insertProduct(db, name: 'My package', kind: 'SERVICE');
      await seedTestCustomers(db, customers: 10);
      expect(await db.query('products'), hasLength(1));
      final ids = (await db.query('customer_accounts',
              columns: ['default_product_id']))
          .map((r) => r['default_product_id'])
          .toSet();
      expect(ids, {own});
    });

    test('puts accounts in every bucket of the due list', () async {
      final now = DateTime(2026, 11, 25, 12);
      await seedTestCustomers(db, customers: 200, now: now);
      final counts = await customers.dueCounts(now: now, soonDays: 3);
      expect(counts.overdue, greaterThan(0));
      expect(counts.today, greaterThan(0));
      expect(counts.soon, greaterThan(0));
      // And some that are not due yet, and some with no schedule at all.
      final all = await db.query('customer_accounts');
      expect(counts.total, lessThan(all.length));
      expect(all.any((r) => r['next_due_at'] == null), isTrue);
    });

    test('every due date is last renewal + period, as a day', () async {
      await seedTestCustomers(db, customers: 30,
          now: DateTime(2026, 11, 25, 12));
      for (final row in await db.query('customer_accounts')) {
        final days = row['renewal_days'] as int?;
        if (days == null) {
          expect(row['next_due_at'], isNull);
          continue;
        }
        final last = DateTime.fromMillisecondsSinceEpoch(
          row['last_renewal_at'] as int,
          isUtc: true,
        );
        expect(
          row['next_due_at'],
          nextDueAfter(last, days).toUtc().millisecondsSinceEpoch,
        );
      }
    });

    test('seeding twice makes new customers, not the same ones again',
        () async {
      await seedTestCustomers(db, customers: 15);
      await seedTestCustomers(db, customers: 15);
      expect(await db.query('customers'), hasLength(30));
      final numbers =
          (await db.query('customer_accounts', columns: ['account_number']))
              .map((r) => r['account_number'])
              .toList();
      expect(numbers.toSet(), hasLength(60));
    });

    test('what it writes is found by the quick search', () async {
      await seedTestCustomers(db, customers: 50);
      final account = (await db.query('customer_accounts', limit: 1)).single;
      final hits = await customers
          .quickSearch(normalizeCode(account['account_number'] as String));
      expect(hits, isNotEmpty);
      expect(hits.first.account!.id, account['id']);
      expect(hits.first.packageName, isNotNull);
    });
  });

  group('at 5,000 customers and 10,000 accounts', () {
    // Generous on purpose: this guards against a quadratic plan (seconds),
    // not against a slow test machine. Typical is a few milliseconds.
    const budget = Duration(milliseconds: 400);
    final now = DateTime(2026, 11, 25, 12);

    Future<Duration> timed(Future<void> Function() action) async {
      // One warm-up run, so the first query's statement compilation is not
      // what gets measured.
      await action();
      final watch = Stopwatch()..start();
      await action();
      return watch.elapsed;
    }

    setUp(() async {
      await seedTestCustomers(db, customers: 5000, now: now);
    });

    test('the seed really is that size', () async {
      final customerCount =
          await db.rawQuery('SELECT COUNT(*) AS n FROM customers');
      final accountCount =
          await db.rawQuery('SELECT COUNT(*) AS n FROM customer_accounts');
      expect(customerCount.single['n'], 5000);
      expect(accountCount.single['n'], 10000);
    });

    test('the quick search stays instant, whatever is typed', () async {
      final sample = (await db.query(
        'customer_accounts',
        where: 'id = ?',
        whereArgs: [7777],
      ))
          .single;
      final number = sample['account_number'] as String;
      final queries = <String>[
        'احمد', // a name thousands of rows match
        'Haddad 12',
        '0944', // the start of a phone
        '٠٩٤٤ ١٢', // the same, in Arabic-Indic digits
        '+963 94',
        number, // one exact account
        number.substring(number.length - 5), // the tail of a number
        'AB-00', // letters and a dash
        'zzzz-nothing', // no match: the whole table is read
      ];
      for (final query in queries) {
        late int found;
        final elapsed = await timed(() async {
          found = (await customers.quickSearch(query)).length;
        });
        // ignore: avoid_print
        print('quick search "$query": ${elapsed.inMilliseconds} ms, '
            '$found rows');
        expect(elapsed, lessThan(budget), reason: query);
        expect(found, lessThanOrEqualTo(CustomerRepository.quickSearchLimit));
      }
      expect(await customers.quickSearch(number), isNotEmpty);
      expect(await customers.quickSearch('zzzz-nothing'), isEmpty);
    });

    test('its plan at this size is still one indexed pass', () async {
      final (sql, args) = customers.quickSearchQuery('0011 22')!;
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      final detail = rows.map((r) => r['detail']).join(' | ');
      expect(detail, contains('idx_accounts_customer'));
      expect(detail, isNot(contains('SCAN a')), reason: detail);
      expect(detail, isNot(contains('SCAN p')), reason: detail);
    });

    test('the due list and its counts stay instant', () async {
      final list = await timed(() async {
        await customers.dueList(now: now, soonDays: 3);
      });
      final counts = await timed(() async {
        await customers.dueCounts(now: now, soonDays: 3);
      });
      // ignore: avoid_print
      print('due list: ${list.inMilliseconds} ms, '
          'due counts: ${counts.inMilliseconds} ms');
      expect(list, lessThan(budget));
      expect(counts, lessThan(budget));

      final (sql, args) = customers.dueListQuery(now: now, soonDays: 3);
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      final detail = rows.map((r) => r['detail']).join(' | ');
      expect(detail, contains('idx_accounts_due'));
      expect(detail, isNot(contains('TEMP B-TREE')), reason: detail);
    });

    test('the customers list pages stay instant', () async {
      final first = await timed(() async {
        await customers.list();
      });
      final searched = await timed(() async {
        await customers.list(query: '0944 12');
      });
      // ignore: avoid_print
      print('customers page: ${first.inMilliseconds} ms, '
          'searched: ${searched.inMilliseconds} ms');
      expect(first, lessThan(budget));
      expect(searched, lessThan(budget));
    });

    test('the duplicate check stays instant', () async {
      final elapsed = await timed(() async {
        await customers.findDuplicateAccounts('0000007777', provider: 'MTN');
      });
      expect(elapsed, lessThan(budget));
    });
  });
}
