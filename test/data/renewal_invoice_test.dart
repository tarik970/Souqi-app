import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// A sale linked to a customer's account: what lands on the invoice, and
/// what happens to the account's dates — all in the one invoice transaction.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late InvoiceRepository invoices;
  late CustomerRepository customers;
  late int packageId;
  late int customerId;
  late int accountId;

  final syp = Currency(
    code: 'SYP',
    nameAr: 'ليرة سورية',
    nameEn: 'Syrian Pound',
    decimalPlaces: 0,
    rate: RateFraction.one,
    rateUpdatedAt: DateTime.utc(2026),
  );
  final ctx = CurrencyContext.of([syp], baseCode: 'SYP');

  final lastRenewal = DateTime(2026, 10, 20, 11);
  final oldDue = DateTime(2026, 11, 19);

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    invoices = InvoiceRepository(db);
    customers = CustomerRepository(db);
    packageId = await insertProduct(db, name: 'ADSL 4 Mbps', kind: 'SERVICE');
    customerId = await customers
        .insert(const Customer(name: 'أحمد الحسن', phone: '٠٩٤٤ ١٢٣ ٤٥٦'));
    accountId = await customers.insertAccount(CustomerAccount(
      customerId: customerId,
      accountNumber: '0011-2233',
      provider: 'MTN',
      defaultProductId: packageId,
      renewalDays: 30,
      lastRenewalAt: lastRenewal,
      nextDueAt: oldDue,
    ));
  });

  tearDown(() => appDb.close());

  CartLine package({int? productId, int price = 35000}) => CartLine(
        productId: productId ?? packageId,
        name: 'ADSL 4 Mbps',
        kind: ProductKind.service,
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
        requiresAccount: true,
      );

  const sugar = CartLine(
    name: 'Sugar',
    unitPriceMinor: 9000,
    priceCurrencyCode: 'SYP',
    qtyThousandths: 1000,
  );

  Invoice draft(
    List<CartLine> lines, {
    required DateTime at,
    bool withAccount = true,
    bool withCustomer = true,
  }) {
    var cart = const Cart();
    for (final line in lines) {
      cart = cart.add(line);
    }
    return Invoice.fromCart(
      cart: cart,
      ctx: ctx,
      createdAt: at.toUtc(),
      customerId: withCustomer ? customerId : null,
      customerName: withCustomer ? 'أحمد الحسن' : null,
      customerPhone: withCustomer ? '٠٩٤٤ ١٢٣ ٤٥٦' : null,
      accountId: withAccount ? accountId : null,
      accountNumber: withAccount ? '0011-2233' : null,
      accountProvider: withAccount ? 'MTN' : null,
    );
  }

  Future<CustomerAccount> account() async =>
      (await customers.getAccount(accountId))!;

  group('saving a renewal', () {
    test('moves the last renewal and the next due date with the invoice',
        () async {
      final at = DateTime(2026, 11, 25, 16, 30);
      final saved = await invoices.save(draft([package()], at: at));

      expect(saved.id, isNotNull);
      final renewed = await account();
      expect(renewed.lastRenewalAt!.toLocal(), at);
      // Last renewal + 30 calendar days, as a day.
      expect(renewed.nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });

    test('a renewal late at night is due on the same day as one at noon',
        () async {
      await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 23, 58)));
      expect((await account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });

    test('the price edited for this sale does not matter to the dates',
        () async {
      await invoices.save(
        draft([package(price: 30000)], at: DateTime(2026, 11, 25, 9)),
      );
      expect((await account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });

    test('another package renews the account just the same', () async {
      final other = await insertProduct(db, name: 'ADSL 8', kind: 'SERVICE');
      await invoices.save(
        draft([package(productId: other)], at: DateTime(2026, 11, 25, 9)),
      );
      final renewed = await account();
      expect(renewed.nextDueAt!.toLocal(), DateTime(2026, 12, 25));
      // The default package is only changed when the seller says so.
      expect(renewed.defaultProductId, packageId);
    });

    test('an account without a period gets its date but no due day',
        () async {
      await db.update('customer_accounts', {'renewal_days': null},
          where: 'id = ?', whereArgs: [accountId]);
      final at = DateTime(2026, 11, 25, 9);
      await invoices.save(draft([package()], at: at));
      final renewed = await account();
      expect(renewed.lastRenewalAt!.toLocal(), at);
      expect(renewed.nextDueAt, isNull);
    });

    test('takes the account off the due list', () async {
      final now = DateTime(2026, 11, 25, 10);
      expect(await customers.dueList(now: now, soonDays: 3), hasLength(1));
      await invoices.save(draft([package()], at: now));
      expect(await customers.dueList(now: now, soonDays: 3), isEmpty);
      expect((await customers.dueCounts(now: now, soonDays: 3)).total, 0);
    });

    test('goods beside the package: still a renewal', () async {
      await invoices
          .save(draft([sugar, package()], at: DateTime(2026, 11, 25, 9)));
      expect((await account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });
  });

  group('a sale that is not a renewal leaves the dates alone', () {
    test('goods only, with the customer\'s account attached', () async {
      final saved =
          await invoices.save(draft([sugar], at: DateTime(2026, 11, 25, 9)));
      // The account is on the invoice…
      expect(saved.accountId, accountId);
      // …but nothing was renewed.
      final same = await account();
      expect(same.lastRenewalAt!.toLocal(), lastRenewal);
      expect(same.nextDueAt!.toLocal(), oldDue);
    });

    test('a customer with no account attached', () async {
      const optional = CartLine(
        name: 'Top-up',
        kind: ProductKind.service,
        unitPriceMinor: 5000,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
      );
      await invoices.save(draft(
        [optional],
        at: DateTime(2026, 11, 25, 9),
        withAccount: false,
      ));
      final same = await account();
      expect(same.lastRenewalAt!.toLocal(), lastRenewal);
      expect(same.nextDueAt!.toLocal(), oldDue);
    });
  });

  group('rollback', () {
    /// A draft whose second item breaks a CHECK constraint (quantity 0), so
    /// the save fails AFTER the invoice row and the renewal were written.
    Invoice broken(DateTime at) {
      final good = draft([package()], at: at);
      return good.copyWith(items: [
        good.items.single,
        InvoiceItem(
          productName: 'Broken',
          kind: ProductKind.goods,
          qtyThousandths: 0,
          origUnitPriceMinor: 1,
          origCurrencyCode: 'SYP',
          origRate: RateFraction.one,
          unitPriceMinor: 1,
          lineTotalMinor: 0,
        ),
      ]);
    }

    test('a save that fails leaves both dates exactly as they were',
        () async {
      await expectLater(
        invoices.save(broken(DateTime(2026, 11, 25, 9))),
        throwsA(isA<DatabaseException>()),
      );

      final same = await account();
      expect(same.lastRenewalAt!.toLocal(), lastRenewal);
      expect(same.nextDueAt!.toLocal(), oldDue);
      // And nothing else of the sale is there either.
      expect(await db.query('invoices'), isEmpty);
      expect(await db.query('invoice_items'), isEmpty);
    });

    test('the account is still on the due list after the failed save',
        () async {
      final now = DateTime(2026, 11, 25, 10);
      await expectLater(invoices.save(broken(now)), throwsA(anything));
      final due = await customers.dueList(now: now, soonDays: 3);
      expect(due.single.account!.id, accountId);
    });

    test('the failed save did not use up an invoice number', () async {
      await expectLater(
        invoices.save(broken(DateTime(2026, 11, 25, 9))),
        throwsA(anything),
      );
      final saved = await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 9, 5)));
      expect(saved.invoiceNo, 1);
      expect((await account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });

    test('an account that does not exist fails the whole sale', () async {
      final ghost = draft([package()], at: DateTime(2026, 11, 25, 9));
      final wrong = Invoice(
        createdAt: ghost.createdAt,
        currencyCode: ghost.currencyCode,
        baseCurrencyCode: ghost.baseCurrencyCode,
        rate: ghost.rate,
        subtotalMinor: ghost.subtotalMinor,
        totalMinor: ghost.totalMinor,
        totalBaseMinor: ghost.totalBaseMinor,
        customerId: customerId,
        customerName: 'x',
        accountId: 9999,
        accountNumber: '9999',
        items: ghost.items,
      );
      await expectLater(
        invoices.save(wrong),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('invoices'), isEmpty);
    });
  });

  group('invoice snapshots', () {
    test('the customer and the account are stored as text on the invoice',
        () async {
      final saved = await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 9)));
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [saved.id]))
              .single;
      expect(row['customer_id'], customerId);
      expect(row['customer_name'], 'أحمد الحسن');
      expect(row['customer_phone'], '٠٩٤٤ ١٢٣ ٤٥٦', reason: 'as typed');
      expect(row['account_id'], accountId);
      expect(row['account_number'], '0011-2233');
      expect(row['account_provider'], 'MTN');
      // The search columns beside them, through the shared normalizers.
      expect(row['customer_name_norm'], 'احمد حسن');
      expect(row['customer_phone_norm'], '0944123456');
      expect(row['account_number_norm'], '00112233');
    });

    test('are read back with the invoice', () async {
      final saved = await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 9)));
      final read = (await invoices.getById(saved.id!))!;
      expect(read.customerName, 'أحمد الحسن');
      expect(read.customerPhone, '٠٩٤٤ ١٢٣ ٤٥٦');
      expect(read.accountNumber, '0011-2233');
      expect(read.accountProvider, 'MTN');
    });

    test('do not change when the customer and the account are edited later',
        () async {
      final saved = await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 9)));

      final customer = (await customers.getById(customerId))!;
      await customers.update(customer.copyWith(
        name: 'Someone Else',
        phone: () => '0999 000 000',
      ));
      await customers.updateAccount(
        (await account()).copyWith(
          accountNumber: '9999',
          provider: () => 'Syriatel',
        ),
      );

      final read = (await invoices.getById(saved.id!))!;
      expect(read.customerName, 'أحمد الحسن');
      expect(read.customerPhone, '٠٩٤٤ ١٢٣ ٤٥٦');
      expect(read.accountNumber, '0011-2233');
      expect(read.accountProvider, 'MTN');
    });

    test('survive the customer being deactivated', () async {
      final saved = await invoices
          .save(draft([package()], at: DateTime(2026, 11, 25, 9)));
      await customers.setActive(customerId, false);
      await customers.setAccountActive(accountId, false);
      final read = (await invoices.getById(saved.id!))!;
      expect(read.customerId, customerId);
      expect(read.customerName, 'أحمد الحسن');
      expect(read.accountNumber, '0011-2233');
    });

    test('show up in the customer\'s history', () async {
      await invoices.save(draft([package()], at: DateTime(2026, 11, 25, 9)));
      final history = await customers.history(customerId);
      expect(history.single.firstItemName, 'ADSL 4 Mbps');
      expect(history.single.accountNumber, '0011-2233');
      expect((await customers.totals(customerId)).totalBaseMinor, 35000);
    });

    test('a sale with no customer stores none', () async {
      final saved = await invoices.save(draft(
        [sugar],
        at: DateTime(2026, 11, 25, 9),
        withAccount: false,
        withCustomer: false,
      ));
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [saved.id]))
              .single;
      expect(row['customer_id'], isNull);
      expect(row['customer_name'], isNull);
      expect(row['account_number'], isNull);
      expect(row['customer_name_norm'], isNull);
    });
  });

  group('statistics from the snapshots', () {
    late StatsRepository stats;
    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 12, 1);

    setUp(() => stats = StatsRepository(db));

    test('renewals: invoices with an account that sold a card or service',
        () async {
      await invoices.save(draft([package()], at: DateTime(2026, 11, 5, 9)));
      await invoices
          .save(draft([sugar, package()], at: DateTime(2026, 11, 6, 9)));
      // Goods with the account attached: not a renewal.
      await invoices.save(draft([sugar], at: DateTime(2026, 11, 7, 9)));
      // A sale with no customer at all.
      await invoices.save(draft(
        [sugar],
        at: DateTime(2026, 11, 8, 9),
        withAccount: false,
        withCustomer: false,
      ));
      // A renewal outside the period.
      await invoices.save(draft([package()], at: DateTime(2026, 10, 5, 9)));

      final renewals = await stats.renewals(from: from, to: to);
      expect(renewals.count, 2);
      expect(renewals.totalBaseMinor, 35000 + 44000);
    });

    test('no renewals, no amount', () async {
      final renewals = await stats.renewals(from: from, to: to);
      expect(renewals.count, 0);
      expect(renewals.totalBaseMinor, 0);
    });

    test('top packages: the cards and services those renewals sold',
        () async {
      final other = await insertProduct(db, name: 'ADSL 8', kind: 'SERVICE');
      CartLine big() => CartLine(
            productId: other,
            name: 'ADSL 8',
            kind: ProductKind.service,
            unitPriceMinor: 60000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          );
      await invoices.save(draft([package()], at: DateTime(2026, 11, 5, 9)));
      await invoices.save(draft([package()], at: DateTime(2026, 11, 6, 9)));
      await invoices
          .save(draft([big(), sugar], at: DateTime(2026, 11, 7, 9)));
      // The same package sold to a walk-in, no account: not a renewal.
      await invoices.save(draft(
        [
          const CartLine(
            name: 'ADSL 8',
            kind: ProductKind.service,
            unitPriceMinor: 60000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          ),
        ],
        at: DateTime(2026, 11, 8, 9),
        withAccount: false,
        withCustomer: false,
      ));

      final top = await stats.topProducts(
        from: from,
        to: to,
        baseDecimals: 0,
        ranking: ProductRanking.sales,
        renewalsOnly: true,
      );
      expect(top.map((p) => p.name), ['ADSL 4 Mbps', 'ADSL 8']);
      expect(top.map((p) => p.salesCount), [2, 1]);
      expect(top.map((p) => p.amountBaseMinor), [70000, 60000]);
      // Sugar rode along on a renewal invoice but is not a package.
      expect(top.any((p) => p.name == 'Sugar'), isFalse);
    });

    test('sales per customer, the biggest first', () async {
      final samer = await customers.insert(const Customer(name: 'Samer'));
      await invoices.save(draft([package()], at: DateTime(2026, 11, 5, 9)));
      await invoices.save(draft([sugar], at: DateTime(2026, 11, 6, 9)));
      await invoices.save(
        Invoice.fromCart(
          cart: const Cart().add(sugar).add(sugar),
          ctx: ctx,
          createdAt: DateTime(2026, 11, 7, 9).toUtc(),
          customerId: samer,
          customerName: 'Samer',
        ),
      );
      // No customer: in nobody's row.
      await invoices.save(draft(
        [sugar],
        at: DateTime(2026, 11, 8, 9),
        withAccount: false,
        withCustomer: false,
      ));

      final top = await stats.topCustomers(from: from, to: to);
      expect(top.map((c) => c.name), ['أحمد الحسن', 'Samer']);
      expect(top.map((c) => c.invoiceCount), [2, 1]);
      expect(top.map((c) => c.totalBaseMinor), [44000, 18000]);
      expect(top.first.customerId, customerId);
    });

    test('a renamed customer is still one row, under the latest name',
        () async {
      await invoices.save(draft([package()], at: DateTime(2026, 11, 5, 9)));
      final customer = (await customers.getById(customerId))!;
      await customers.update(customer.copyWith(name: 'Ahmad H.'));
      await invoices.save(
        Invoice.fromCart(
          cart: const Cart().add(sugar),
          ctx: ctx,
          createdAt: DateTime(2026, 11, 9, 9).toUtc(),
          customerId: customerId,
          customerName: 'Ahmad H.',
        ),
      );
      final top = await stats.topCustomers(from: from, to: to);
      expect(top, hasLength(1));
      expect(top.single.name, 'Ahmad H.');
      expect(top.single.invoiceCount, 2);
    });

    test('amounts are base currency at the rate stored with each invoice',
        () async {
      // A USD invoice of 2.00 USD at 13,000 SYP: 26,000 SYP then, whatever
      // the rate is today.
      final id = await insertInvoice(
        db,
        invoiceNo: 900,
        createdAt: DateTime(2026, 11, 10),
        currency: 'USD',
        rateNum: 13000,
        subtotalMinor: 200,
        totalBaseMinor: 26000,
        customerName: 'Dollar Customer',
        accountNumber: 'USD-1',
      );
      await db.insert('invoice_items', {
        'invoice_id': id,
        'sort_order': 0,
        'product_name': 'Card',
        'product_name_norm': 'card',
        'kind': 'SERVICE',
        'qty_thousandths': 1000,
        'orig_unit_price_minor': 200,
        'orig_currency_code': 'USD',
        'orig_rate_num': 13000,
        'orig_rate_den': 1,
        'unit_price_minor': 200,
        'line_total_minor': 200,
      });
      await db.update(
        'currencies',
        {'rate_num': 15000, 'rate_den': 1, 'rate_updated_at': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );

      expect((await stats.renewals(from: from, to: to)).totalBaseMinor, 26000);
      final customer = (await stats.topCustomers(from: from, to: to)).single;
      expect(customer.name, 'Dollar Customer');
      expect(customer.customerId, isNull, reason: 'a snapshot with no link');
      expect(customer.totalBaseMinor, 26000);
      final packages = await stats.topProducts(
        from: from,
        to: to,
        baseDecimals: 0,
        renewalsOnly: true,
      );
      expect(packages.single.amountBaseMinor, 26000);
    });
  });
}
