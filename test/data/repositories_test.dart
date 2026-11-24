import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/counter_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;

  setUp(() async {
    appDb = await openTestDb();
  });

  tearDown(() => appDb.close());

  group('SettingsRepository', () {
    test('seeded values are readable', () async {
      final repo = SettingsRepository(appDb.db);
      expect(await repo.getString(SettingsKeys.baseCurrencyCode), 'SYP');
      expect(await repo.getString(SettingsKeys.appLanguage), 'ar');
      expect(await repo.getString(SettingsKeys.invoiceLanguage), 'ar');
    });

    test('missing keys fall back to code defaults', () async {
      final repo = SettingsRepository(appDb.db);
      expect(await repo.getStringOrNull(SettingsKeys.paperWidthMm), isNull);
      expect(await repo.getInt(SettingsKeys.paperWidthMm), 80);
      expect(await repo.getInt(SettingsKeys.printerDpi), 203);
      expect(await repo.getBool(SettingsKeys.showUnit), isTrue);
      expect(await repo.getBool(SettingsKeys.showItemCode), isFalse);
    });

    test('set then get round-trips, overwrite works', () async {
      final repo = SettingsRepository(appDb.db);
      await repo.setString(SettingsKeys.shopName, 'دكان أبو أحمد');
      expect(await repo.getString(SettingsKeys.shopName), 'دكان أبو أحمد');

      await repo.setInt(SettingsKeys.paperWidthMm, 58);
      expect(await repo.getInt(SettingsKeys.paperWidthMm), 58);

      await repo.setBool(SettingsKeys.maskAccountNumber, true);
      expect(await repo.getBool(SettingsKeys.maskAccountNumber), isTrue);

      await repo.setInt(SettingsKeys.paperWidthMm, 80);
      expect(await repo.getInt(SettingsKeys.paperWidthMm), 80);
    });

    test('remove falls back to default again', () async {
      final repo = SettingsRepository(appDb.db);
      await repo.setInt(SettingsKeys.autoDeleteDays, 30);
      expect(await repo.getInt(SettingsKeys.autoDeleteDays), 30);
      await repo.remove(SettingsKeys.autoDeleteDays);
      expect(await repo.getInt(SettingsKeys.autoDeleteDays), 0);
    });
  });

  group('CounterRepository', () {
    test('invoice numbers are sequential from the seeded counter', () async {
      const counters = CounterRepository();
      final n1 = await appDb.db.transaction(
          (txn) => counters.next(txn, CounterRepository.invoiceNo));
      final n2 = await appDb.db.transaction(
          (txn) => counters.next(txn, CounterRepository.invoiceNo));
      expect(n1, 1);
      expect(n2, 2);
    });

    test('a rolled-back transaction does not consume a number', () async {
      const counters = CounterRepository();
      try {
        await appDb.db.transaction((txn) async {
          await counters.next(txn, CounterRepository.invoiceNo);
          throw StateError('abort');
        });
      } on StateError {
        // expected
      }
      final next = await appDb.db.transaction(
          (txn) => counters.next(txn, CounterRepository.invoiceNo));
      expect(next, 1, reason: 'rollback must release the number');
    });

    test('unknown counter starts at 1', () async {
      const counters = CounterRepository();
      final n = await appDb.db
          .transaction((txn) => counters.next(txn, 'batch_no'));
      expect(n, 1);
    });
  });
}
