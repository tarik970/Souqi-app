import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/db/migrations/migration_v1.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// Customers, accounts and renewals needed NO schema change: the tables and
/// their indexes have been there since version 1. These tests pin that down
/// — the indexes the new queries rely on exist, and a database created by
/// the very first version of the app, with customers and accounts already
/// in it, comes through the upgrade with every row intact and works with
/// the new code.
void main() {
  setUpAll(sqfliteFfiInit);

  test('the indexes the customer queries rely on exist', () async {
    final appDb = await openTestDb();
    final rows = await appDb.db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
    final names = rows.map((r) => r['name']).toSet();
    expect(
      names,
      containsAll(<String>[
        'idx_customers_name_norm',
        'idx_customers_phone_norm',
        'idx_accounts_customer',
        'idx_accounts_number_norm',
        'idx_accounts_due',
        'idx_invoices_customer',
      ]),
    );
    await appDb.close();
  });

  test('accounts keep their customer: deleting one is refused by the schema',
      () async {
    final appDb = await openTestDb();
    final db = appDb.db;
    final customerId = await insertCustomer(db);
    await db.insert('customer_accounts', {
      'customer_id': customerId,
      'account_number': '0011',
      'account_number_norm': '0011',
      'created_at': 0,
    });
    expect(
      () => db.delete('customers'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('customers'), hasLength(1));
    await appDb.close();
  });

  test('a version-1 database with customers and accounts upgrades intact',
      () async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final path = '$dir/souqi_customers_upgrade_test.db';
    await databaseFactoryFfi.deleteDatabase(path);

    // A database as version 1 of the app left it.
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => const MigrationV1().apply(db),
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final packageId = await old.insert('products', {
      'name': 'ADSL 4 Mbps',
      'name_norm': 'adsl 4 mbps',
      'kind': 'SERVICE',
      'price_minor': 35000,
      'currency_code': 'SYP',
      'requires_account': 1,
      'created_at': now,
      'updated_at': now,
    });
    final customerId = await old.insert('customers', {
      'name': 'أحمد الحسن',
      // Version 1 only trimmed and lowercased names.
      'name_norm': 'أحمد الحسن',
      'phone': '0944 123 456',
      'phone_norm': '0944123456',
      'notes': 'old note',
      'created_at': now,
    });
    final lastRenewal = DateTime(2026, 10, 1, 9);
    final accountId = await old.insert('customer_accounts', {
      'customer_id': customerId,
      'account_number': '0011-2233',
      'account_number_norm': '00112233',
      'label': 'ADSL',
      'provider': 'MTN',
      'default_product_id': packageId,
      'renewal_days': 30,
      'last_renewal_at': lastRenewal.toUtc().millisecondsSinceEpoch,
      'next_due_at': DateTime(2026, 10, 31).toUtc().millisecondsSinceEpoch,
      'notes': 'account note',
      'created_at': now,
    });
    await old.insert('invoices', {
      'invoice_no': 1,
      'created_at': lastRenewal.toUtc().millisecondsSinceEpoch,
      'currency_code': 'SYP',
      'base_currency_code': 'SYP',
      'rate_num': 1,
      'rate_den': 1,
      'subtotal_minor': 35000,
      'total_minor': 35000,
      'total_base_minor': 35000,
      'customer_id': customerId,
      'customer_name': 'أحمد الحسن',
      'customer_phone': '0944 123 456',
      'account_id': accountId,
      'account_number': '0011-2233',
      'account_provider': 'MTN',
    });
    await old.update('counters', {'value': 1},
        where: 'name = ?', whereArgs: ['invoice_no']);
    await old.close();

    final upgraded =
        await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final db = upgraded.db;
    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      AppDatabase.schemaVersion,
    );
    final customers = CustomerRepository(db);

    // Nothing was lost.
    final customer = (await customers.getById(customerId))!;
    expect(customer.name, 'أحمد الحسن');
    expect(customer.phone, '0944 123 456');
    expect(customer.notes, 'old note');
    expect(customer.isActive, isTrue);
    final account = (await customers.getAccount(accountId))!;
    expect(account.accountNumber, '0011-2233');
    expect(account.label, 'ADSL');
    expect(account.provider, 'MTN');
    expect(account.defaultProductId, packageId);
    expect(account.renewalDays, 30);
    expect(account.lastRenewalAt!.toLocal(), lastRenewal);
    expect(account.nextDueAt!.toLocal(), DateTime(2026, 10, 31));
    expect(account.notes, 'account note');

    // The new quick search finds the old rows: by the name as people type
    // it now, by phone and by card number.
    for (final typed in ['احمد', 'حسن', '٠٩٤٤ ١٢٣', '0011 22']) {
      final hits = await customers.quickSearch(typed);
      expect(hits.single.account!.id, accountId, reason: typed);
      expect(hits.single.packageName, 'ADSL 4 Mbps', reason: typed);
    }
    // The due list sees the old due date.
    final due =
        await customers.dueList(now: DateTime(2026, 11, 25, 10), soonDays: 3);
    expect(due.single.account!.id, accountId);
    // The history lists the old invoice.
    expect((await customers.history(customerId)).single.invoiceNo, 1);
    expect((await customers.totals(customerId)).totalBaseMinor, 35000);

    // And a renewal saved by the new code moves the old account's dates.
    final syp = Currency(
      code: 'SYP',
      nameAr: 'ليرة سورية',
      nameEn: 'Syrian Pound',
      decimalPlaces: 0,
      rate: RateFraction.one,
      rateUpdatedAt: DateTime.utc(2026),
    );
    final saved = await InvoiceRepository(db).save(
      Invoice.fromCart(
        cart: const Cart().add(CartLine(
          productId: packageId,
          name: 'ADSL 4 Mbps',
          kind: ProductKind.service,
          unitPriceMinor: 35000,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
          requiresAccount: true,
        )),
        ctx: CurrencyContext.of([syp], baseCode: 'SYP'),
        createdAt: DateTime(2026, 11, 25, 10).toUtc(),
        customerId: customerId,
        customerName: customer.name,
        customerPhone: customer.phone,
        accountId: accountId,
        accountNumber: account.accountNumber,
        accountProvider: account.provider,
      ),
    );
    expect(saved.invoiceNo, 2, reason: 'the counter carried on');
    final renewed = (await customers.getAccount(accountId))!;
    expect(renewed.lastRenewalAt!.toLocal(), DateTime(2026, 11, 25, 10));
    expect(renewed.nextDueAt!.toLocal(), DateTime(2026, 12, 25));

    await upgraded.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
}
