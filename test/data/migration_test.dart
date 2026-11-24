import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/db/migrations/migration_v1.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
  });

  tearDown(() => appDb.close());

  group('schema', () {
    test('user_version is the latest migration', () async {
      final rows = await db.rawQuery('PRAGMA user_version');
      expect(rows.first.values.first, 2);
      expect(AppDatabase.schemaVersion, 2);
    });

    test('foreign keys are enforced', () async {
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.first.values.first, 1);
    });

    test('all tables exist', () async {
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final names = rows.map((r) => r['name']).toSet();
      expect(
        names.containsAll([
          'settings',
          'counters',
          'currencies',
          'units',
          'products',
          'customers',
          'customer_accounts',
          'invoices',
          'invoice_items',
          'voucher_batches',
          'voucher_codes',
          'audit_log',
          'debt_transactions',
        ]),
        isTrue,
        reason: 'missing tables from: $names',
      );
    });

    test('seeds: SYP base + USD, preset units, counter, settings', () async {
      final syp = (await db
              .query('currencies', where: 'code = ?', whereArgs: ['SYP']))
          .single;
      expect(syp['decimal_places'], 0);
      expect(syp['rate_num'], 1);
      expect(syp['rate_den'], 1);
      expect(syp['rate_updated_at'], isNotNull);

      final usd = (await db
              .query('currencies', where: 'code = ?', whereArgs: ['USD']))
          .single;
      expect(usd['decimal_places'], 2);
      expect(usd['rate_updated_at'], isNull,
          reason: 'USD rate must be marked as never updated');

      final units =
          await db.query('units', where: 'is_preset = 1', orderBy: 'sort_order');
      expect(units, hasLength(6));
      expect(units.first['name_en'], 'kg');

      final counter = (await db
              .query('counters', where: 'name = ?', whereArgs: ['invoice_no']))
          .single;
      expect(counter['value'], 0);

      final base = (await db.query('settings',
              where: 'key = ?', whereArgs: ['base_currency_code']))
          .single;
      expect(base['value'], 'SYP');
    });
  });

  group('products constraints', () {
    test('duplicate short code is rejected, two NULL codes are fine', () async {
      await insertProduct(db, name: 'A', code: '101');
      expect(() => insertProduct(db, name: 'B', code: '101'),
          throwsA(isA<DatabaseException>()));
      await insertProduct(db, name: 'C');
      await insertProduct(db, name: 'D');
    });

    test('SERVICE products may not carry a unit', () async {
      final unitId = await insertUnit(db);
      expect(
        () => insertProduct(db, kind: 'SERVICE', unitId: unitId),
        throwsA(isA<DatabaseException>()),
      );
      await insertProduct(db, kind: 'SERVICE'); // without unit: ok
    });

    test('unknown currency code is rejected', () async {
      expect(() => insertProduct(db, currency: 'XXX'),
          throwsA(isA<DatabaseException>()));
    });
  });

  group('customers are protected (ON DELETE RESTRICT)', () {
    test('cannot delete a customer that has accounts', () async {
      final customerId = await insertCustomer(db);
      await db.insert('customer_accounts', {
        'customer_id': customerId,
        'account_number': '001-234',
        'account_number_norm': '001234',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      expect(
        () => db.delete('customers', where: 'id = ?', whereArgs: [customerId]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('cannot delete a customer that has debt transactions', () async {
      final customerId = await insertCustomer(db);
      await db.insert('debt_transactions', {
        'customer_id': customerId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'type': 'DEBT',
        'amount_base_minor': 5000,
      });
      expect(
        () => db.delete('customers', where: 'id = ?', whereArgs: [customerId]),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('invoice deletion', () {
    test('cascades to items, keeps voucher sale snapshot', () async {
      final productId =
          await insertProduct(db, kind: 'SERVICE', soldFromCodeStock: 1);
      final batchId = await insertVoucherBatch(db, productId: productId);
      final codeId = await insertVoucherCode(db,
          productId: productId, batchId: batchId, codeHash: 'H1');

      final invoiceId = await insertInvoice(db, invoiceNo: 1);
      final itemId =
          await insertInvoiceItem(db, invoiceId: invoiceId, productId: productId);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        'voucher_codes',
        {
          'status': 'SOLD',
          'status_changed_at': now,
          'sold_at': now,
          'invoice_id': invoiceId,
          'invoice_item_id': itemId,
          'sold_invoice_no': 1,
          'sold_customer_name': 'Ahmad',
          'sold_account_number': '001234',
        },
        where: 'id = ?',
        whereArgs: [codeId],
      );

      await db.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);

      final items = await db.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      expect(items, isEmpty, reason: 'items must cascade');

      final code = (await db
              .query('voucher_codes', where: 'id = ?', whereArgs: [codeId]))
          .single;
      expect(code['invoice_id'], isNull);
      expect(code['invoice_item_id'], isNull);
      expect(code['status'], 'SOLD');
      expect(code['sold_invoice_no'], 1);
      expect(code['sold_customer_name'], 'Ahmad');
      expect(code['sold_account_number'], '001234');
      expect(code['sold_at'], now);
    });
  });

  group('voucher codes', () {
    test('duplicate code hash per product is rejected', () async {
      final productId =
          await insertProduct(db, kind: 'SERVICE', soldFromCodeStock: 1);
      final batchId = await insertVoucherBatch(db, productId: productId);
      await insertVoucherCode(db,
          productId: productId, batchId: batchId, codeHash: 'SAME');
      expect(
        () => insertVoucherCode(db,
            productId: productId, batchId: batchId, codeHash: 'SAME'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('same hash under a different product is allowed', () async {
      final p1 = await insertProduct(db, kind: 'SERVICE', soldFromCodeStock: 1);
      final p2 = await insertProduct(
          db, name: 'Other', kind: 'SERVICE', soldFromCodeStock: 1);
      final b1 = await insertVoucherBatch(db, productId: p1);
      final b2 = await insertVoucherBatch(db, productId: p2);
      await insertVoucherCode(db, productId: p1, batchId: b1, codeHash: 'X');
      await insertVoucherCode(db, productId: p2, batchId: b2, codeHash: 'X');
    });
  });

  group('v1 → v2', () {
    test('recomputes name_norm with the stronger normalization, keeps names',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v2_test.db';
      await databaseFactoryFfi.deleteDatabase(path);

      // A database as version 1 of the app left it: name_norm was only
      // trimmed and lowercased.
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => const MigrationV1().apply(db),
        ),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      Future<int> oldProduct(String name) => old.insert('products', {
            'name': name,
            'name_norm': name.trim().toLowerCase(),
            'kind': 'GOODS',
            'price_minor': 1000,
            'currency_code': 'SYP',
            'created_at': now,
            'updated_at': now,
          });
      final sugarId = await oldProduct('السكر الناعم');
      final coffeeId = await oldProduct('قهوة');
      final riceId = await oldProduct('أرز');
      final teaId = await oldProduct('Tea');
      await old.insert('customers', {
        'name': 'أحمد',
        'name_norm': 'أحمد',
        'created_at': now,
      });
      final invoiceId = await insertInvoice(old, invoiceNo: 1);
      await insertInvoiceItem(old, invoiceId: invoiceId, productId: sugarId);
      await old.close();

      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final db = upgraded.db;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 2);

      Future<Map<String, Object?>> product(int id) async =>
          (await db.query('products', where: 'id = ?', whereArgs: [id])).single;
      expect((await product(sugarId))['name'], 'السكر الناعم');
      expect((await product(sugarId))['name_norm'], 'سكر ناعم');
      expect((await product(coffeeId))['name_norm'], 'قهوه');
      expect((await product(riceId))['name_norm'], 'ارز');
      expect((await product(teaId))['name_norm'], 'tea');
      expect((await db.query('customers')).single['name_norm'], 'احمد');

      // Nothing else moved: the invoice and its item are still there.
      expect(await db.query('invoices'), hasLength(1));
      expect((await db.query('invoice_items')).single['product_id'], sugarId);

      // And the old product is now found the new way.
      final found = await ProductRepository(db).list(query: 'سكر');
      expect(found.single.id, sugarId);

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('reopening', () {
    test('an existing file reopens without running migrations again',
        () async {
      // In-memory DBs vanish on close, so use a temp file.
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_test.db';
      await databaseFactoryFfi.deleteDatabase(path);

      var a = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      await insertCustomer(a.db, name: 'Keep Me');
      await a.close();

      a = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final rows = await a.db.query('customers');
      expect(rows.single['name'], 'Keep Me');
      await a.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });
}
