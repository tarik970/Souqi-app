import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/settings/storage_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The rule the seller feels: a big cleanup rewrites the file (and says so),
/// a small one does not make them wait for it.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late ProviderContainer container;

  /// Whether the "optimizing…" indicator was ever raised, in order.
  late List<bool> optimizing;

  setUp(() async {
    database = await openTestDb();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    optimizing = [];
    container.listen(
      housekeepingProvider,
      (_, next) => optimizing.add(next),
      fireImmediately: true,
    );
  });
  tearDown(() async {
    container.dispose();
    await database.close();
  });

  HousekeepingController controller() =>
      container.read(housekeepingProvider.notifier);

  Future<void> seed(int count, {required DateTime createdAt}) async {
    final batch = database.db.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('invoices', {
        'invoice_no': i + 1,
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

  test('a small date-range delete does not VACUUM', () async {
    await seed(10, createdAt: DateTime(2026, 3, 1));

    expect(await controller().deleteRange(), 10);
    expect(optimizing, [false]);
  });

  test('a delete past the threshold VACUUMs with the indicator up', () async {
    await seed(vacuumInvoiceThreshold + 1, createdAt: DateTime(2026, 3, 1));

    expect(await controller().deleteRange(), vacuumInvoiceThreshold + 1);
    expect(optimizing, [false, true, false]);
    expect(container.read(housekeepingProvider), isFalse);
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
    expect(optimizing, [false]);
  });

  test('the stats are re-read after a cleanup', () async {
    await seed(4, createdAt: DateTime(2026, 3, 1));
    expect((await container.read(storageStatsProvider.future)).invoiceCount, 4);

    await controller().deleteRange();

    expect((await container.read(storageStatsProvider.future)).invoiceCount, 0);
  });
}
