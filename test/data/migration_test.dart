import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/data/db/migrations/migration_v1.dart';
import 'package:souqi/data/db/migrations/migration_v2.dart';
import 'package:souqi/data/db/migrations/migration_v3.dart';
import 'package:souqi/data/db/migrations/migration_v4.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/price_change_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/domain/models/price_change.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/voucher.dart';
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
      expect(rows.first.values.first, 6);
      expect(AppDatabase.schemaVersion, 6);
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
        'recorded_at': DateTime.now().millisecondsSinceEpoch,
        'type': 'DEBT',
        'direction': 1,
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

  group('v1 → latest', () {
    test('recomputes name_norm, backfills the snapshot search columns',
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
      // Written the way version 1 wrote them: no *_norm columns on the
      // snapshots at all — those arrive with v3 and must be backfilled.
      final invoiceId = await old.insert('invoices', {
        'invoice_no': 1,
        'created_at': now,
        'currency_code': 'SYP',
        'base_currency_code': 'SYP',
        'rate_num': 1,
        'rate_den': 1,
        'subtotal_minor': 1000,
        'total_minor': 1000,
        'total_base_minor': 1000,
        'customer_name': 'أحمد',
        'customer_phone': '0944 123 456',
        'account_number': '0011-2233',
      });
      await old.insert('invoice_items', {
        'invoice_id': invoiceId,
        'product_id': sugarId,
        'product_name': 'السكر الناعم',
        'kind': 'GOODS',
        'qty_thousandths': 1000,
        'orig_unit_price_minor': 1000,
        'orig_currency_code': 'SYP',
        'orig_rate_num': 1,
        'orig_rate_den': 1,
        'unit_price_minor': 1000,
        'line_total_minor': 1000,
      });
      await old.close();

      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final db = upgraded.db;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first,
          AppDatabase.schemaVersion);

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
      final item = (await db.query('invoice_items')).single;
      expect(item['product_id'], sugarId);

      // v3: the snapshots are untouched and are now searchable.
      expect(item['product_name'], 'السكر الناعم');
      expect(item['product_name_norm'], 'سكر ناعم');
      final invoice = (await db.query('invoices')).single;
      expect(invoice['customer_name'], 'أحمد');
      expect(invoice['customer_name_norm'], 'احمد');
      expect(invoice['customer_phone'], '0944 123 456');
      expect(invoice['customer_phone_norm'], '0944123456');
      expect(invoice['account_number'], '0011-2233');
      expect(invoice['account_number_norm'], '00112233');

      // And the old product is now found the new way.
      final found = await ProductRepository(db).list(query: 'سكر');
      expect(found.single.id, sugarId);

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('v3 → v4 (prepaid card codes)', () {
    test('a populated version-3 database upgrades without losing a row',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v3_test.db';
      await databaseFactoryFfi.deleteDatabase(path);

      // A database exactly as version 3 of the app (phase 4b) left it.
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await const MigrationV1().apply(db);
            await const MigrationV2().apply(db);
            await const MigrationV3().apply(db);
          },
        ),
      );
      final sugarId = await insertProduct(old, name: 'Sugar', code: '101');
      final cardId = await insertProduct(
        old,
        name: 'Card 5000',
        kind: 'SERVICE',
        soldFromCodeStock: 1,
      );
      await old.update('products', {'low_stock_threshold': 5},
          where: 'id = ?', whereArgs: [cardId]);
      final customerId = await insertCustomer(old, name: 'Ahmad');
      await old.insert('customer_accounts', {
        'customer_id': customerId,
        'account_number': '0011-2233',
        'account_number_norm': '00112233',
        'created_at': 1,
      });
      await old.insert('settings',
          {'key': 'shop_name', 'value': 'Al-Baraka', 'updated_at': 1});
      await old.update('counters', {'value': 2},
          where: 'name = ?', whereArgs: ['invoice_no']);

      final firstInvoice = await insertInvoice(old,
          invoiceNo: 1, customerName: 'Ahmad', accountNumber: '0011-2233');
      await insertInvoiceItem(old, invoiceId: firstInvoice, productId: sugarId);
      final secondInvoice = await insertInvoice(old, invoiceNo: 2);
      final cardItem = await insertInvoiceItem(old,
          invoiceId: secondInvoice, productId: cardId, name: 'Card 5000');

      // Voucher rows: version 3 never wrote any through the app, but the
      // tables were there since version 1 — the migration must carry
      // whatever they hold.
      final batchId = await old.insert('voucher_batches', {
        'product_id': cardId,
        'created_at': 1000,
        'code_count': 2,
        'cost_per_card_minor': 4500,
        'cost_currency_code': 'SYP',
        'note': 'first batch',
      });
      final cipher = CodeCipher(InMemoryKeyStore());
      Future<int> oldCode(String code, Map<String, Object?> extra) async =>
          old.insert('voucher_codes', {
            'product_id': cardId,
            'batch_id': batchId,
            'code_cipher': await cipher.encrypt(code),
            'code_hash': await cipher.hash(code),
            'created_at': 1000,
            ...extra,
          });
      final soldCode = await oldCode('1111222233334444', {
        'serial': 'SN1',
        'status': 'SOLD',
        'status_changed_at': 2000,
        'sold_at': 2000,
        'invoice_id': secondInvoice,
        'invoice_item_id': cardItem,
        'sold_invoice_no': 2,
        'sold_customer_name': 'Ahmad',
      });
      final freeCode = await oldCode('5555666677778888', {'expiry_at': 9000});
      await old.insert('audit_log', {
        'created_at': 3000,
        'action': 'CODE_REVEAL',
        'entity_type': 'code',
        'entity_id': soldCode,
        'details': '{"tail":"4444"}',
      });

      Future<Map<String, int>> counts(DatabaseExecutor db) async => {
            for (final table in [
              'products',
              'customers',
              'customer_accounts',
              'invoices',
              'invoice_items',
              'voucher_batches',
              'voucher_codes',
              'audit_log',
              'settings',
              'currencies',
              'units',
            ])
              table: (await db.rawQuery('SELECT COUNT(*) FROM $table'))
                  .first
                  .values
                  .first! as int,
          };
      final before = await counts(old);
      final codesBefore = await old.query('voucher_codes', orderBy: 'id');
      await old.close();

      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final db = upgraded.db;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first,
          AppDatabase.schemaVersion);

      // Not a row lost, in any table.
      expect(await counts(db), before);

      // Every old column of every code is exactly what it was.
      final codesAfter = await db.query('voucher_codes', orderBy: 'id');
      for (var i = 0; i < codesBefore.length; i++) {
        for (final column in codesBefore[i].keys) {
          expect(codesAfter[i][column], codesBefore[i][column],
              reason: 'voucher_codes.$column of row $i');
        }
      }
      // The new columns are there and empty.
      for (final row in codesAfter) {
        expect(row.containsKey('status_note'), isTrue);
        expect(row['status_note'], isNull);
        expect(row['sold_price_base_minor'], isNull);
        expect(row['sold_cost_base_minor'], isNull);
      }
      final batch = (await db.query('voucher_batches')).single;
      expect(batch['note'], 'first batch');
      expect(batch['cost_per_card_minor'], 4500);
      expect(batch.containsKey('expiry_at'), isTrue);
      expect(batch['expiry_at'], isNull);
      final log = (await db.query('audit_log')).single;
      expect(log['action'], 'CODE_REVEAL');
      expect(log['details'], '{"tail":"4444"}');
      expect(log.containsKey('product_id'), isTrue);
      expect(log['product_name'], isNull);

      // The rest of the shop is untouched.
      expect((await db.query('settings',
              where: 'key = ?', whereArgs: ['shop_name']))
          .single['value'], 'Al-Baraka');
      expect((await db.query('counters')).single['value'], 2);
      final card = (await db.query('products',
              where: 'id = ?', whereArgs: [cardId]))
          .single;
      expect(card['sold_from_code_stock'], 1);
      expect(card['low_stock_threshold'], 5);

      final indexes = {
        for (final row in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index'"))
          row['name'],
      };
      expect(
        indexes.containsAll([
          'idx_codes_item',
          'idx_codes_hash_lookup',
          'idx_codes_sold',
          'idx_codes_batch',
          'idx_codes_status',
        ]),
        isTrue,
        reason: 'indexes: $indexes',
      );

      // And the new code works on the old rows.
      final vouchers = VoucherRepository(db, cipher);
      final stock = (await vouchers.stockOverview(
              now: DateTime.fromMillisecondsSinceEpoch(5000)))
          .single;
      expect(stock.product.id, cardId);
      expect((stock.available, stock.sold), (1, 1));
      final found = (await vouchers.lookup('1111 2222 3333 4444')).single;
      expect(found.status, VoucherStatus.sold);
      expect(found.soldInvoiceNo, 2);
      expect(found.soldCustomerName, 'Ahmad');
      expect(await vouchers.reveal(freeCode), '5555666677778888');
      expect((await AuditRepository(db).list()).first.productName, 'Card 5000');

      // Deleting the old invoice keeps the sold-code record.
      await ArchiveRepository(db).deleteInvoice(secondInvoice);
      final sold = (await db.query('voucher_codes',
              where: 'id = ?', whereArgs: [soldCode]))
          .single;
      expect(sold['status'], 'SOLD');
      expect(sold['invoice_id'], isNull);
      expect(sold['invoice_item_id'], isNull);
      expect(sold['sold_invoice_no'], 2);

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('a fresh install and an upgraded one have the same schema',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v3_schema_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await const MigrationV1().apply(db);
            await const MigrationV2().apply(db);
            await const MigrationV3().apply(db);
          },
        ),
      );
      await old.close();
      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);

      Future<Map<String, Set<String>>> columns(Database database) async {
        final tables = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'");
        return {
          for (final table in tables)
            table['name'] as String: {
              for (final column in await database
                  .rawQuery('PRAGMA table_info(${table['name']})'))
                column['name'] as String,
            },
        };
      }

      Future<Set<Object?>> indexes(Database database) async => {
            for (final row in await database.rawQuery(
                "SELECT name FROM sqlite_master WHERE type = 'index' "
                "AND name NOT LIKE 'sqlite_%'"))
              row['name'],
          };

      // `db` is the fresh in-memory database of setUp.
      expect(await columns(upgraded.db), await columns(db));
      expect(await indexes(upgraded.db), await indexes(db));

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('v4 → v5 (debt ledger)', () {
    /// A database exactly as version 4 of the app (phase 4c) left it.
    Future<Database> openV4(String path) => databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 4,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) async {
              await const MigrationV1().apply(db);
              await const MigrationV2().apply(db);
              await const MigrationV3().apply(db);
              await const MigrationV4().apply(db);
            },
          ),
        );

    test('a populated version-4 database upgrades without losing a row',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v4_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      final old = await openV4(path);

      final sugarId = await insertProduct(old, name: 'Sugar', code: '101');
      final ahmad = await insertCustomer(old, name: 'Ahmad');
      final sara = await insertCustomer(old, name: 'Sara');
      await old.insert('customer_accounts', {
        'customer_id': ahmad,
        'account_number': '0011-2233',
        'account_number_norm': '00112233',
        'created_at': 1,
      });
      await old.insert('settings',
          {'key': 'shop_name', 'value': 'Al-Baraka', 'updated_at': 1});
      await old.update('counters', {'value': 2},
          where: 'name = ?', whereArgs: ['invoice_no']);
      final firstInvoice = await insertInvoice(old,
          invoiceNo: 1, customerName: 'Ahmad', accountNumber: '0011-2233');
      await insertInvoiceItem(old, invoiceId: firstInvoice, productId: sugarId);
      final secondInvoice = await insertInvoice(old, invoiceNo: 2);
      await insertInvoiceItem(old, invoiceId: secondInvoice, productId: sugarId);
      await old.insert('audit_log', {
        'created_at': 3000,
        'action': 'PIN_SET',
      });

      // Ledger rows in the old shape. The app never wrote any before this
      // version, but the table was there since version 1 and the migration
      // carries whatever it holds — every type the old CHECK allowed.
      const day = Duration.millisecondsPerDay;
      final debtId = await old.insert('debt_transactions', {
        'customer_id': ahmad,
        'invoice_id': secondInvoice,
        'created_at': 10 * day,
        'type': 'DEBT',
        'amount_base_minor': 9000,
        'note': 'on the slate',
      });
      final paymentId = await old.insert('debt_transactions', {
        'customer_id': ahmad,
        'created_at': 12 * day,
        'type': 'PAYMENT',
        'amount_base_minor': 2600,
        'orig_amount_minor': 20,
        'orig_currency_code': 'USD',
        'orig_rate_num': 13000,
        'orig_rate_den': 1,
      });
      final adjustmentId = await old.insert('debt_transactions', {
        'customer_id': sara,
        'created_at': 13 * day,
        'type': 'ADJUSTMENT',
        'amount_base_minor': 400,
      });

      Future<Map<String, int>> counts(DatabaseExecutor db) async => {
            for (final table in [
              'products',
              'customers',
              'customer_accounts',
              'invoices',
              'invoice_items',
              'voucher_batches',
              'voucher_codes',
              'audit_log',
              'settings',
              'currencies',
              'units',
              'debt_transactions',
            ])
              table: (await db.rawQuery('SELECT COUNT(*) FROM $table'))
                  .first
                  .values
                  .first! as int,
          };
      final before = await counts(old);
      final invoicesBefore = await old.query('invoices', orderBy: 'id');
      final customersBefore = await old.query('customers', orderBy: 'id');
      await old.close();

      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final db = upgraded.db;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first,
          AppDatabase.schemaVersion);

      // Not a row lost, in any table; the scratch copy is gone.
      expect(await counts(db), before);
      expect(
        await db.rawQuery("SELECT name FROM sqlite_master "
            "WHERE name = 'debt_transactions_v1'"),
        isEmpty,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // Every old column of every invoice and customer is what it was, and
      // the new ones are there and empty: an old invoice prints as before.
      final invoicesAfter = await db.query('invoices', orderBy: 'id');
      for (var i = 0; i < invoicesBefore.length; i++) {
        for (final column in invoicesBefore[i].keys) {
          expect(invoicesAfter[i][column], invoicesBefore[i][column],
              reason: 'invoices.$column of row $i');
        }
        for (final column in [
          'paid_minor',
          'credit_used_minor',
          'prev_balance_base_minor',
          'new_balance_base_minor',
        ]) {
          expect(invoicesAfter[i].containsKey(column), isTrue);
          expect(invoicesAfter[i][column], isNull);
        }
      }
      final customersAfter = await db.query('customers', orderBy: 'id');
      for (var i = 0; i < customersBefore.length; i++) {
        for (final column in customersBefore[i].keys) {
          expect(customersAfter[i][column], customersBefore[i][column],
              reason: 'customers.$column of row $i');
        }
        expect(customersAfter[i].containsKey('credit_limit_base_minor'), isTrue);
        expect(customersAfter[i]['credit_limit_base_minor'], isNull);
        expect(customersAfter[i]['default_due_days'], isNull);
      }

      // The old ledger rows, ids kept, in the new shape.
      final debt = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [debtId]))
          .single;
      expect(debt['type'], 'DEBT');
      expect(debt['direction'], 1);
      expect(debt['amount_base_minor'], 9000);
      expect(debt['note'], 'on the slate');
      expect(debt['invoice_id'], secondInvoice);
      expect(debt['invoice_no'], 2, reason: 'snapshotted from the invoice');
      expect(debt['created_at'], 10 * day);
      expect(debt['recorded_at'], 10 * day);
      expect(debt['due_at'], 40 * day);
      expect(debt['receipt_no'], isNull);
      expect(debt['reverses_id'], isNull);
      final payment = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [paymentId]))
          .single;
      expect(payment['direction'], -1);
      expect(payment['due_at'], isNull);
      expect(payment['orig_amount_minor'], 20);
      expect(payment['orig_currency_code'], 'USD');
      expect(payment['orig_rate_num'], 13000);
      expect(payment['invoice_no'], isNull);
      final adjustment = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [adjustmentId]))
          .single;
      expect(adjustment['type'], 'ADJUSTMENT');
      expect(adjustment['direction'], 1);

      final names = {
        for (final row in await db.rawQuery("SELECT name FROM sqlite_master "
            "WHERE type IN ('index', 'trigger')"))
          row['name'],
      };
      expect(
        names.containsAll([
          'idx_debt_customer',
          'idx_debt_fifo',
          'idx_debt_invoice',
          'idx_debt_created',
          'idx_debt_reverses',
          'idx_debt_receipt',
          'trg_debt_no_update',
          'trg_debt_no_delete',
        ]),
        isTrue,
        reason: 'indexes and triggers: $names',
      );

      // The rest of the shop is untouched.
      expect((await db.query('settings',
              where: 'key = ?', whereArgs: ['shop_name']))
          .single['value'], 'Al-Baraka');
      expect(
        (await db.query('counters',
                where: 'name = ?', whereArgs: ['invoice_no']))
            .single['value'],
        2,
      );

      // And the new code works on the old rows.
      final debts = DebtRepository(db);
      expect(await debts.balanceOf(ahmad), 6400);
      expect(await debts.balanceOf(sara), 400);
      final lines = await debts.ledger(ahmad);
      expect(lines.map((l) => l.balanceAfterBaseMinor), [6400, 9000]);
      expect(lines.first.entry.origRate, const RateFraction(13000, 1));
      final snapshot = await debts.debtors(
          now: DateTime.fromMillisecondsSinceEpoch(50 * day, isUtc: true));
      expect(snapshot.totalOutstandingBaseMinor, 6800);
      expect(snapshot.overdueCount, 2);
      // New entries continue after the old ids, and receipts start at 1.
      final receipt = await debts.recordPayment(
        customerId: ahmad,
        amountMinor: 400,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
      );
      expect(receipt.id, greaterThan(adjustmentId));
      expect(receipt.receiptNo, 1);
      final reversal = await debts.reverse(debtId, reason: 'entered twice');
      expect(reversal.reversedInvoiceNo, 2);
      expect(await debts.balanceOf(ahmad), -3000);

      // Deleting the old invoice keeps the old debt, number and all.
      await ArchiveRepository(db).deleteInvoice(secondInvoice);
      final kept = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [debtId]))
          .single;
      expect(kept['invoice_id'], isNull);
      expect(kept['invoice_no'], 2);
      expect(kept['amount_base_minor'], 9000);

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('a fresh install and an upgraded one have the same schema',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v4_schema_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      await (await openV4(path)).close();
      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);

      // The full CREATE text of everything: tables with their CHECKs,
      // indexes with their WHERE, triggers with their bodies.
      Future<Map<Object?, Object?>> schema(Database database) async => {
            for (final row in await database.rawQuery(
                "SELECT name, sql FROM sqlite_master "
                "WHERE name NOT LIKE 'sqlite_%' AND name != 'android_metadata'"))
              row['name']: row['sql'],
          };

      // `db` is the fresh in-memory database of setUp.
      final fresh = await schema(db);
      final migrated = await schema(upgraded.db);
      expect(migrated.keys.toSet(), fresh.keys.toSet());
      for (final name in const [
        'debt_transactions',
        'idx_debt_customer',
        'idx_debt_fifo',
        'idx_debt_invoice',
        'idx_debt_created',
        'idx_debt_reverses',
        'idx_debt_receipt',
        'trg_debt_no_update',
        'trg_debt_no_delete',
      ]) {
        expect(migrated[name], fresh[name], reason: name);
        expect(fresh[name], isNotNull, reason: name);
      }

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('ledger ids are AUTOINCREMENT: an id is never handed out twice',
        () async {
      final sql = (await db.rawQuery("SELECT sql FROM sqlite_master "
              "WHERE name = 'debt_transactions'"))
          .single['sql'] as String;
      expect(sql, contains('AUTOINCREMENT'));
    });
  });

  group('v5 → v6 (bulk price change undo)', () {
    Future<Database> openV5(String path) => databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 5,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) async {
              for (final m in AppDatabase.migrations) {
                if (m.version <= 5) await m.apply(db);
              }
            },
          ),
        );

    test('a populated version-5 database upgrades without losing a row',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_v5_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      final old = await openV5(path);
      final sugar = await insertProduct(old, name: 'Sugar', code: '101');
      final tea = await insertProduct(old, name: 'Tea', code: '102');
      final ahmad = await insertCustomer(old);
      final invoice = await insertInvoice(old, invoiceNo: 1);
      await insertInvoiceItem(old, invoiceId: invoice, productId: sugar);
      await DebtRepository(old).addManualDebt(
        customerId: ahmad,
        amountBaseMinor: 5000,
      );
      Future<Map<String, int>> counts(DatabaseExecutor db) async => {
            for (final table in [
              'products',
              'customers',
              'invoices',
              'invoice_items',
              'debt_transactions',
              'settings',
              'audit_log',
            ])
              table: (await db.rawQuery('SELECT COUNT(*) FROM $table'))
                  .first
                  .values
                  .first! as int,
          };
      final before = await counts(old);
      await old.close();

      final upgraded =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      final db = upgraded.db;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 6);
      expect(await counts(db), before);
      expect(await db.query('price_changes'), isEmpty);
      expect(await db.query('price_change_items'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // The new tables work on the old rows…
      final prices = PriceChangeRepository(db);
      final plan = await prices.preview(
        basisPoints: 1000,
        rounding: PriceRounding.none,
        scope: PriceChangeScope.all,
      );
      expect(await prices.apply(plan), 2);
      expect((await ProductRepository(db).getById(sugar))!.priceMinor, 1100);
      // …and a deleted product takes its undo line with it.
      await db.delete('products', where: 'id = ?', whereArgs: [tea]);
      expect(await db.query('price_change_items'), hasLength(1));

      await upgraded.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('a database from a NEWER version is refused, not relabelled',
        () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_migration_newer_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      await (await AppDatabase.open(factory: databaseFactoryFfi, path: path))
          .close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('PRAGMA user_version = 99');
      await raw.close();

      await expectLater(
        AppDatabase.open(factory: databaseFactoryFfi, path: path),
        throwsA(isA<NewerDatabaseException>()),
      );
      expect(
        await AppDatabase.fileVersion(path, factory: databaseFactoryFfi),
        99,
        reason: 'the file is left as it was',
      );
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
