import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
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

  test('counts the invoices in the archive', () async {
    expect(await repository.invoiceCount(), 0);
    await insertInvoice(database.db, invoiceNo: 1);
    await insertInvoice(database.db, invoiceNo: 2);
    expect(await repository.invoiceCount(), 2);
  });

  /// Deleting lives in ArchiveRepository now; these cases check the file
  /// measurements and the VACUUM around it.
  Future<int> deleteAll(DatabaseExecutor db) async {
    final archive = ArchiveRepository(db);
    var deleted = 0;
    while (true) {
      final gone = await archive.deleteMatchingChunk(const ArchiveFilter());
      if (gone == 0) return deleted;
      deleted += gone;
    }
  }

  test('deletes a date range, bounds inclusive then exclusive', () async {
    final day = DateTime(2026, 5, 10);
    for (var i = 0; i < 4; i++) {
      await insertInvoice(
        database.db,
        invoiceNo: i + 1,
        createdAt: day.add(Duration(days: i)),
      );
    }

    final deleted = await ArchiveRepository(database.db).deleteMatchingChunk(
      ArchiveFilter(
        from: day.add(const Duration(days: 1)),
        to: day.add(const Duration(days: 3)),
      ),
    );

    expect(deleted, 2);
    final left = await database.db.query('invoices', columns: ['invoice_no']);
    expect(left.map((row) => row['invoice_no']), [1, 4]);
  });

  test('a deleted invoice takes its items with it', () async {
    final id = await insertInvoice(database.db, invoiceNo: 1);
    await insertInvoiceItem(database.db, invoiceId: id);
    expect(await deleteAll(database.db), 1);
    expect(await database.db.query('invoice_items'), isEmpty);
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
    expect(await deleteAll(onDisk.db), 2000);
    await file.vacuum();
    expect(await file.databaseSizeBytes(), lessThan(full));
  });
}
