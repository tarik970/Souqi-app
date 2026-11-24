import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/features/settings/storage_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The rule the seller feels: a big cleanup rewrites the file (and says so),
/// a small one does not make them wait for it.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late ProviderContainer container;

  /// Every phase the controller passed through, in order.
  late List<HousekeepingPhase> phases;

  setUp(() async {
    database = await openTestDb();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    phases = [];
    container.listen(
      housekeepingProvider,
      (_, next) {
        // Progress ticks are many; only the phase changes are interesting.
        if (phases.isEmpty || phases.last != next.phase) {
          phases.add(next.phase);
        }
      },
      fireImmediately: true,
    );
  });
  tearDown(() async {
    container.dispose();
    await database.close();
  });

  HousekeepingController controller() =>
      container.read(housekeepingProvider.notifier);

  Future<void> seed(
    int count, {
    required DateTime createdAt,
    int firstNo = 1,
  }) async {
    final batch = database.db.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('invoices', {
        'invoice_no': firstNo + i,
        'created_at': createdAt.millisecondsSinceEpoch,
        'currency_code': 'SYP',
        'base_currency_code': 'SYP',
        'rate_num': 1,
        'rate_den': 1,
        'subtotal_minor': 1000,
        'total_minor': 1000,
        'total_base_minor': 1000,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Clears the whole archive, the way the archive screen does.
  Future<DeleteOutcome> deleteAll() =>
      controller().deleteMatching(const ArchiveFilter());

  test('a small date-range delete does not VACUUM', () async {
    await seed(10, createdAt: DateTime(2026, 3, 1));

    final outcome = await deleteAll();
    expect(outcome.deleted, 10);
    expect(outcome.remaining, 0);
    expect(outcome.complete, isTrue);
    expect(phases, [
      HousekeepingPhase.idle,
      HousekeepingPhase.deleting,
      HousekeepingPhase.idle,
    ]);
  });

  test('a delete past the threshold VACUUMs with the indicator up', () async {
    await seed(vacuumInvoiceThreshold + 1, createdAt: DateTime(2026, 3, 1));

    expect((await deleteAll()).deleted, vacuumInvoiceThreshold + 1);
    expect(phases, [
      HousekeepingPhase.idle,
      HousekeepingPhase.deleting,
      // The lock is handed from the delete to the VACUUM, so the seller can
      // leave the screen while the file is rewritten.
      HousekeepingPhase.idle,
      HousekeepingPhase.optimizing,
      HousekeepingPhase.idle,
    ]);
    expect(container.read(housekeepingProvider).busy, isFalse);
  });

  group('a big delete goes in chunks and finishes the job', () {
    test('clears every invoice past several chunk boundaries', () async {
      // Two and a half chunks: the loop has to come round more than twice.
      const count = ArchiveRepository.deleteChunkSize * 2 + 500;
      await seed(count, createdAt: DateTime(2026, 3, 1));

      final outcome = await deleteAll();

      expect(outcome.deleted, count);
      expect(outcome.remaining, 0, reason: 'no partial stop');
      expect(outcome.complete, isTrue);
      expect(
        await container.read(maintenanceRepositoryProvider).invoiceCount(),
        0,
      );
    });

    test('reports progress as it goes, never past the total', () async {
      const count = ArchiveRepository.deleteChunkSize * 2;
      await seed(count, createdAt: DateTime(2026, 3, 1));
      final seen = <int>[];
      container.listen(housekeepingProvider, (_, next) {
        if (next.deleting) seen.add(next.done);
      });

      await deleteAll();

      expect(seen, contains(ArchiveRepository.deleteChunkSize));
      expect(seen.last, count);
      expect(seen.every((done) => done <= count), isTrue);
    });

    test('deletes by the criteria, not by any loaded page of ids', () async {
      await seed(50, createdAt: DateTime(2026, 3, 1));
      await seed(10, createdAt: DateTime(2020, 1, 1), firstNo: 51);

      // A page is 30 rows; the delete must still take all 50 of the range.
      final outcome = await controller().deleteMatching(
        ArchiveFilter(from: DateTime(2026, 1, 1)),
      );

      expect(outcome.deleted, 50);
      expect(
        await container.read(maintenanceRepositoryProvider).invoiceCount(),
        10,
      );
    });
  });

  group('the lock', () {
    test('a second delete during the first is refused, not interleaved',
        () async {
      await seed(ArchiveRepository.deleteChunkSize * 2,
          createdAt: DateTime(2026, 3, 1));

      final first = deleteAll();
      // Same frame, before the first has yielded: exactly what an impatient
      // second tap on "Delete" does.
      final second = await deleteAll();

      expect(second.refused, isTrue);
      expect(second.deleted, 0);
      final outcome = await first;
      expect(outcome.deleted, ArchiveRepository.deleteChunkSize * 2);
      expect(outcome.remaining, 0);
    });

    test('retention stands down while a delete is running', () async {
      await seed(ArchiveRepository.deleteChunkSize + 10,
          createdAt: DateTime(2020, 1, 1));
      await container
          .read(settingsRepositoryProvider)
          .setInt(SettingsKeys.autoDeleteDays, 30);

      final delete = deleteAll();
      expect(await controller().applyRetention(), 0);
      // Refused before the day was stamped, so it may still run later.
      expect(
        await container
            .read(settingsRepositoryProvider)
            .getInt(SettingsKeys.autoDeleteLastRunAt),
        0,
      );
      await delete;
    });

    test('a VACUUM during a delete stands down too', () async {
      await seed(10, createdAt: DateTime(2026, 3, 1));
      final delete = deleteAll();
      await controller().vacuum();
      await delete;
      // One delete, one idle: the VACUUM never took the lock.
      expect(phases, [
        HousekeepingPhase.idle,
        HousekeepingPhase.deleting,
        HousekeepingPhase.idle,
      ]);
    });
  });

  test('retention is off until auto_delete_days is set', () async {
    await seed(5, createdAt: DateTime(2020, 1, 1));

    expect(await controller().applyRetention(), 0);
    expect(
      await container.read(maintenanceRepositoryProvider).invoiceCount(),
      5,
    );
  });

  test('retention drops what is older than the setting', () async {
    final now = DateTime(2026, 11, 24);
    await seed(3, createdAt: now.subtract(const Duration(days: 400)));
    await database.db.insert('invoices', {
      'invoice_no': 99,
      'created_at': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      'currency_code': 'SYP',
      'base_currency_code': 'SYP',
      'rate_num': 1,
      'rate_den': 1,
      'subtotal_minor': 1000,
      'total_minor': 1000,
      'total_base_minor': 1000,
    });
    await container
        .read(settingsRepositoryProvider)
        .setInt(SettingsKeys.autoDeleteDays, 365);

    expect(await controller().applyRetention(now: now), 3);
    expect(
      await container.read(maintenanceRepositoryProvider).invoiceCount(),
      1,
    );
    // Three invoices is no reason to rewrite the file.
    expect(phases, isNot(contains(HousekeepingPhase.optimizing)));
  });

  group('retention runs at most once a day', () {
    Future<void> enable(int days) => container
        .read(settingsRepositoryProvider)
        .setInt(SettingsKeys.autoDeleteDays, days);

    Future<int> lastRun() => container
        .read(settingsRepositoryProvider)
        .getInt(SettingsKeys.autoDeleteLastRunAt);

    test('the second launch of the same day does nothing', () async {
      final now = DateTime(2026, 11, 24, 8);
      await seed(3, createdAt: now.subtract(const Duration(days: 400)));
      await enable(365);

      expect(await controller().applyRetentionDaily(now: now), 3);
      expect(container.read(retentionNoticeProvider), 3);

      // Same day, later: three more old invoices arrive (a restore, say)
      // and the sweep still holds off until tomorrow.
      await seed(2, createdAt: now.subtract(const Duration(days: 500)));
      expect(
        await controller()
            .applyRetentionDaily(now: DateTime(2026, 11, 24, 21)),
        0,
      );
      expect(
        await container.read(maintenanceRepositoryProvider).invoiceCount(),
        2,
      );
    });

    test('the next day it runs again', () async {
      await seed(2, createdAt: DateTime(2020, 1, 1));
      await enable(365);
      await controller().applyRetentionDaily(now: DateTime(2026, 11, 24, 23));

      await seed(1, createdAt: DateTime(2020, 1, 2));
      expect(
        await controller()
            .applyRetentionDaily(now: DateTime(2026, 11, 25, 0, 30)),
        1,
      );
    });

    test('while it is off nothing is stamped, so turning it on works today',
        () async {
      await seed(2, createdAt: DateTime(2020, 1, 1));
      final now = DateTime(2026, 11, 24, 8);

      expect(await controller().applyRetentionDaily(now: now), 0);
      expect(await lastRun(), 0, reason: 'nothing ran, nothing to stamp');

      await enable(365);
      expect(await controller().applyRetentionDaily(now: now), 2);
    });

    test('a sweep that deletes nothing says nothing', () async {
      await seed(2, createdAt: DateTime(2026, 11, 20));
      await enable(365);

      expect(
        await controller().applyRetentionDaily(now: DateTime(2026, 11, 24)),
        0,
      );
      expect(container.read(retentionNoticeProvider), isNull);
    });

    test('the day is stamped before the delete', () async {
      await seed(1, createdAt: DateTime(2020, 1, 1));
      await enable(30);
      final now = DateTime(2026, 11, 24, 7, 45);

      await controller().applyRetentionDaily(now: now);

      expect(await lastRun(), now.millisecondsSinceEpoch);
    });
  });

  test('the stats are re-read after a cleanup', () async {
    await seed(4, createdAt: DateTime(2026, 3, 1));
    expect((await container.read(storageStatsProvider.future)).invoiceCount, 4);

    await deleteAll();

    expect((await container.read(storageStatsProvider.future)).invoiceCount, 0);
  });
}
