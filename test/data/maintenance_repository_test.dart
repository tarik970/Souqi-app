import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/maintenance_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late MaintenanceRepository repository;

  setUp(() async {
    database = await openTestDb();
    repository = MaintenanceRepository(database.db, filePath: database.path);
  });
  tearDown(() async => database.close());

  /// Invoices one day apart, the first [count] days back from [now].
  Future<void> seed(int count, {required DateTime now}) async {
    final batch = database.db.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('invoices', {
        'invoice_no': i + 1,
        'created_at':
            now.subtract(Duration(days: count - i)).millisecondsSinceEpoch,
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

  test('counts the invoices in the archive', () async {
    expect(await repository.invoiceCount(), 0);
    await insertInvoice(database.db, invoiceNo: 1);
    await insertInvoice(database.db, invoiceNo: 2);
    expect(await repository.invoiceCount(), 2);
  });

  test('deletes a date range, bounds inclusive then exclusive', () async {
    final day = DateTime(2026, 5, 10);
    for (var i = 0; i < 4; i++) {
      await insertInvoice(
        database.db,
        invoiceNo: i + 1,
        createdAt: day.add(Duration(days: i)),
      );
    }

    final deleted = await repository.deleteInvoicesCreatedBetween(
      from: day.add(const Duration(days: 1)),
      to: day.add(const Duration(days: 3)),
    );

    expect(deleted, 2);
    final left = await database.db.query('invoices', columns: ['invoice_no']);
    expect(left.map((row) => row['invoice_no']), [1, 4]);
  });

  test('a deleted invoice takes its items with it', () async {
    final id = await insertInvoice(database.db, invoiceNo: 1);
    await insertInvoiceItem(database.db, invoiceId: id);
    expect(await repository.deleteInvoicesCreatedBetween(), 1);
    expect(await database.db.query('invoice_items'), isEmpty);
  });

  test('retention keeps the invoices inside the window', () async {
    final now = DateTime(2026, 11, 24);
    await seed(10, now: now); // 10 days back, one a day.

    expect(await repository.deleteOlderThan(4, now: now), 6);
    expect(await repository.invoiceCount(), 4);
  });

  test('retention of 0 days keeps everything', () async {
    await insertInvoice(database.db, invoiceNo: 1);
    expect(await repository.deleteOlderThan(0), 0);
    expect(await repository.deleteOlderThan(-5), 0);
    expect(await repository.invoiceCount(), 1);
  });

  test('an in-memory database measures as no file', () async {
    expect(await repository.databaseSizeBytes(), 0);
  });

  test('VACUUM shrinks the file a big delete left behind', () async {
    final directory = await Directory.systemTemp.createTemp('souqi-vacuum');
    addTearDown(() => directory.delete(recursive: true));
    final onDisk = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/souqi.db',
    );
    addTearDown(onDisk.close);
    final file = MaintenanceRepository(onDisk.db, filePath: onDisk.path);

    final batch = onDisk.db.batch();
    for (var i = 0; i < 2000; i++) {
      batch.insert('invoices', {
        'invoice_no': i + 1,
        'created_at': DateTime(2020, 1, 1).millisecondsSinceEpoch,
        'currency_code': 'SYP',
        'base_currency_code': 'SYP',
        'rate_num': 1,
        'rate_den': 1,
        'subtotal_minor': 1000,
        'total_minor': 1000,
        'total_base_minor': 1000,
        'note': 'x' * 400,
      });
    }
    await batch.commit(noResult: true);

    final full = await file.databaseSizeBytes();
    expect(full, greaterThan(0));
    expect(await file.deleteInvoicesCreatedBetween(), 2000);
    await file.vacuum();
    expect(await file.databaseSizeBytes(), lessThan(full));
  });
}
