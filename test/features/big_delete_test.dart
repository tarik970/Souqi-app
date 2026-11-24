import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/invoice_seeder.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/counter_repository.dart';
import 'package:souqi/features/settings/storage_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// Clearing a real archive, at the size the bug was found at: several chunks,
/// one lock, one outcome, and every guarantee the brief makes about what a
/// deletion may NOT take with it.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = await openTestDb();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
  });
  tearDown(() async {
    container.dispose();
    await database.close();
  });

  HousekeepingController controller() =>
      container.read(housekeepingProvider.notifier);

  Future<int> invoiceCount() =>
      container.read(maintenanceRepositoryProvider).invoiceCount();

  group('clearing 5,000 seeded invoices', () {
    const count = 5000;

    setUp(() async {
      await database.db.update(
        'currencies',
        {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );
      await insertProduct(database.db, name: 'سكر');
      expect(await seedTestInvoices(database.db, count: count), count);
    });

    test('every single one goes, and the archive is empty after', () async {
      final outcome = await controller().deleteMatching(const ArchiveFilter());

      expect(outcome.deleted, count);
      expect(outcome.remaining, 0, reason: 'no partial stop');
      expect(outcome.complete, isTrue);
      expect(await invoiceCount(), 0);
      // The chunk size does not divide 5,000 evenly: the last short chunk
      // has to be taken too.
      expect(count % ArchiveRepository.deleteChunkSize, isNot(0));
    });

    test('the items go with them and nothing is orphaned', () async {
      expect(await database.db.query('invoice_items'), isNotEmpty);
      await controller().deleteMatching(const ArchiveFilter());
      expect(await database.db.query('invoice_items'), isEmpty);
    });

    test('the products survive, type-to-sell ones included', () async {
      final before = await database.db.query('products');
      expect(before, isNotEmpty);
      await controller().deleteMatching(const ArchiveFilter());
      expect(await database.db.query('products'), hasLength(before.length));
    });

    test('the invoice counter is never touched', () async {
      final before = (await database.db.query(
        'counters',
        where: 'name = ?',
        whereArgs: [CounterRepository.invoiceNo],
      )).single['value'];
      expect(before, count);

      await controller().deleteMatching(const ArchiveFilter());

      final after = (await database.db.query(
        'counters',
        where: 'name = ?',
        whereArgs: [CounterRepository.invoiceNo],
      )).single['value'];
      expect(after, before);
      // The next sale carries on from where the shop left off.
      expect(
        await const CounterRepository()
            .next(database.db, CounterRepository.invoiceNo),
        count + 1,
      );
    });

    test('a sold voucher code keeps its sale snapshot', () async {
      final productId = await insertProduct(
        database.db,
        name: 'بطاقة',
        kind: 'SERVICE',
        soldFromCodeStock: 1,
      );
      final batchId =
          await insertVoucherBatch(database.db, productId: productId);
      final codeId = await insertVoucherCode(
        database.db,
        productId: productId,
        batchId: batchId,
        codeHash: 'H1',
      );
      final invoiceId =
          (await database.db.query('invoices', limit: 1)).single['id'] as int;
      await database.db.update(
        'voucher_codes',
        {
          'status': 'SOLD',
          'invoice_id': invoiceId,
          'sold_invoice_no': 1,
          'sold_customer_name': 'أحمد',
          'sold_account_number': '001234',
        },
        where: 'id = ?',
        whereArgs: [codeId],
      );

      await controller().deleteMatching(const ArchiveFilter());

      final code = (await database.db.query(
        'voucher_codes',
        where: 'id = ?',
        whereArgs: [codeId],
      )).single;
      expect(code['status'], 'SOLD');
      expect(code['sold_invoice_no'], 1);
      expect(code['sold_customer_name'], 'أحمد');
      expect(code['sold_account_number'], '001234');
      expect(code['invoice_id'], isNull, reason: 'only the link is dropped');
    });

    test('exactly one outcome for one delete, and the lock refuses the rest',
        () async {
      final outcomes = <DeleteOutcome>[];
      // Three taps in the same frame, as happens when the app looks stuck.
      final first = controller().deleteMatching(const ArchiveFilter());
      outcomes.add(await controller().deleteMatching(const ArchiveFilter()));
      outcomes.add(await controller().deleteMatching(const ArchiveFilter()));
      outcomes.add(await first);

      expect(outcomes.where((o) => o.refused), hasLength(2));
      final done = outcomes.singleWhere((o) => !o.refused);
      expect(done.deleted, count);
      expect(await invoiceCount(), 0);
    });

    test('only the range asked for goes', () async {
      // Everything the seeder wrote is within the last year; add one older.
      await insertInvoice(
        database.db,
        invoiceNo: count + 1,
        createdAt: DateTime(2015, 1, 1),
      );

      final outcome = await controller().deleteMatching(
        ArchiveFilter(from: DateTime.now().subtract(const Duration(days: 400))),
      );

      expect(outcome.deleted, count);
      expect(await invoiceCount(), 1);
    });

    test('the progress never goes backwards and ends on the total', () async {
      final seen = <int>[];
      container.listen(housekeepingProvider, (_, next) {
        if (next.deleting) seen.add(next.done);
      });

      await controller().deleteMatching(const ArchiveFilter());

      expect(seen, isNotEmpty);
      expect(seen.last, count);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });
  });

  group('retention at the same size', () {
    test('clears everything older than the window, in chunks', () async {
      final now = DateTime(2026, 11, 25, 12);
      // 3,000 invoices spread over two years: the older half must go.
      await seedTestInvoices(database.db, count: 3000, days: 730, now: now);
      await container
          .read(settingsRepositoryProvider)
          .setInt(SettingsKeys.autoDeleteDays, 365);

      final deleted = await controller().applyRetention(now: now);

      expect(deleted, greaterThan(1000));
      expect(await invoiceCount(), 3000 - deleted);
      // Nothing inside the window went.
      final oldest = await database.db.rawQuery(
        'SELECT MIN(created_at) AS at FROM invoices',
      );
      expect(
        oldest.first['at'] as int,
        greaterThanOrEqualTo(
          now.subtract(const Duration(days: 365)).millisecondsSinceEpoch,
        ),
      );
      expect(container.read(retentionNoticeProvider), isNull,
          reason: 'applyRetention reports nothing; the daily sweep does');
    });

    test('the daily sweep reports its count exactly once', () async {
      final now = DateTime(2026, 11, 25, 12);
      await seedTestInvoices(database.db, count: 2000, days: 730, now: now);
      await container
          .read(settingsRepositoryProvider)
          .setInt(SettingsKeys.autoDeleteDays, 365);

      final notices = <int?>[];
      container.listen(
        retentionNoticeProvider,
        (_, next) => notices.add(next),
      );

      final deleted = await controller().applyRetentionDaily(now: now);

      expect(deleted, greaterThan(0));
      expect(notices, [deleted], reason: 'one notice, at the end');
    });
  });
}
