// What the phase 6 review changed in the data layer, each with the case that
// used to go wrong.
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/currency_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/price_change_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/price_change.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late Database db;

  setUp(() async {
    database = await openTestDb();
    db = database.db;
  });

  tearDown(() => database.close());

  final ctx = CurrencyContext.of(
    [
      Currency(
        code: 'SYP',
        nameAr: 'SYP',
        nameEn: 'SYP',
        decimalPlaces: 0,
        rate: RateFraction.one,
        rateUpdatedAt: DateTime.utc(2026),
      ),
    ],
    baseCode: 'SYP',
    extraCodes: const [],
  );

  group('the background engine has a connection of its own', () {
    test('closing it leaves the app\'s connection open', () async {
      final dir = await databaseFactoryFfi.getDatabasesPath();
      final path = '$dir/souqi_own_connection_test.db';
      await databaseFactoryFfi.deleteDatabase(path);
      final app = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      await insertCustomer(app.db, name: 'Ahmad');

      final worker = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        ownConnection: true,
      );
      expect(identical(worker.db, app.db), isFalse);
      expect(await worker.db.query('customers'), hasLength(1));
      await worker.close();

      // The app goes on reading and writing.
      await insertCustomer(app.db, name: 'Sami');
      expect(await app.db.query('customers'), hasLength(2));
      await app.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
  });

  group('a sale survives a product deleted while it sat in the cart', () {
    test('the line is saved from its own snapshot, without the product',
        () async {
      final products = ProductRepository(db);
      final id = await products.insert(const Product(
        name: 'Biscuits',
        kind: ProductKind.goods,
        priceMinor: 750,
        currencyCode: 'SYP',
      ));
      final product = (await products.getById(id))!;
      final cart = const Cart().add(CartLine(
        productId: product.id,
        name: product.name,
        kind: product.kind,
        unitPriceMinor: product.priceMinor,
        priceCurrencyCode: product.currencyCode,
        qtyThousandths: 2000,
      ));
      // Never sold: the delete is a hard one.
      expect(await products.delete(id), ProductDeleteResult.deleted);

      final saved = await InvoiceRepository(db).save(
        Invoice.fromCart(cart: cart, ctx: ctx, createdAt: DateTime.utc(2026, 11, 26)),
      );
      final item = (await db.query('invoice_items')).single;
      expect(item['product_id'], isNull);
      expect(item['product_name'], 'Biscuits');
      expect(saved.totalMinor, 1500);
    });
  });

  group('cart', () {
    CartLine sugar({int? unitId, int price = 8500}) => CartLine(
          productId: 1,
          name: 'Sugar',
          kind: ProductKind.goods,
          unitId: unitId,
          unitPriceMinor: price,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
          listPriceMinor: 8500,
          listCurrencyCode: 'SYP',
          listUnitId: 1,
        );

    test('a price typed for ANOTHER unit is never the product\'s new price',
        () {
      // By the kilo (the product's unit), a new price is written back…
      expect(sugar(unitId: 1, price: 9000).hasPriceOverride, isTrue);
      // …by the bag it is this sale's price only.
      expect(sugar(unitId: 2, price: 400000).hasPriceOverride, isFalse);
    });

    test('an amount discount does not survive a change of the invoice '
        'currency; a percentage does', () {
      final cart = const Cart().add(sugar(unitId: 1));
      expect(
        cart
            .withDiscount(const Discount.amount(5000))
            .withInvoiceCurrency('USD')
            .discount,
        isNull,
      );
      expect(
        cart
            .withDiscount(const Discount.percent(1000))
            .withInvoiceCurrency('USD')
            .discount
            ?.value,
        1000,
      );
      // The same currency again changes nothing.
      expect(
        cart
            .withInvoiceCurrency('USD')
            .withDiscount(const Discount.amount(500))
            .withInvoiceCurrency('USD')
            .discount
            ?.value,
        500,
      );
    });
  });

  group('product codes', () {
    test('a code is stored the way it is looked up', () async {
      final products = ProductRepository(db);
      final id = await products.insert(const Product(
        name: 'Tea',
        code: ' ١٠-١ ',
        kind: ProductKind.goods,
        priceMinor: 100,
        currencyCode: 'SYP',
      ));
      expect((await products.getById(id))!.code, '101');
      expect((await products.getByExactCode('١٠١'))!.id, id);
      expect((await products.getByExactCode('101'))!.id, id);
      expect(await products.isCodeTaken('١٠١'), isTrue);
      expect(await products.isCodeTaken('10 1', excludeId: id), isFalse);
    });
  });

  group('currencies', () {
    late CurrencyRepository currencies;

    setUp(() => currencies = CurrencyRepository(db, SettingsRepository(db)));

    Future<Currency> usd() async =>
        (await currencies.list(includeInactive: true))
            .firstWhere((c) => c.code == 'USD');

    test('the decimal places of an unused currency can change', () async {
      expect(await currencies.isInUse('USD'), isFalse);
      final before = await usd();
      await currencies.update(Currency(
        code: before.code,
        nameAr: before.nameAr,
        nameEn: before.nameEn,
        symbol: before.symbol,
        decimalPlaces: 3,
        rate: before.rate,
        rateUpdatedAt: before.rateUpdatedAt,
      ));
      expect((await usd()).decimalPlaces, 3);
    });

    test('once a price is stored in it they are frozen — names are not',
        () async {
      await insertProduct(db, name: 'Oil', currency: 'USD');
      expect(await currencies.isInUse('USD'), isTrue);
      final before = await usd();
      Currency edited({required int decimals, required String name}) => Currency(
            code: before.code,
            nameAr: before.nameAr,
            nameEn: name,
            symbol: before.symbol,
            decimalPlaces: decimals,
            rate: before.rate,
            rateUpdatedAt: before.rateUpdatedAt,
          );
      await expectLater(
        currencies.update(edited(decimals: 0, name: 'Dollar')),
        throwsA(isA<CurrencyInUseException>()),
      );
      expect((await usd()).decimalPlaces, before.decimalPlaces);
      await currencies.update(
        edited(decimals: before.decimalPlaces, name: 'Dollar'),
      );
      expect((await usd()).nameEn, 'Dollar');
    });

    test('the base currency is in use as soon as there is an invoice',
        () async {
      expect(await currencies.isInUse('SYP'), isFalse);
      await insertInvoice(db, invoiceNo: 1);
      expect(await currencies.isInUse('SYP'), isTrue);
    });

    test('setBase is one transaction, and the new base is active', () async {
      await currencies.setActive('USD', false);
      await currencies.setBase('USD');
      expect(await currencies.baseCode(), 'USD');
      final base = await usd();
      expect(base.isActive, isTrue);
      expect(base.rate, RateFraction.one);
      // A credit limit is an amount of the base currency: it locks the base.
      final customer = await insertCustomer(db);
      await db.update('customers', {'credit_limit_base_minor': 500000},
          where: 'id = ?', whereArgs: [customer]);
      await expectLater(
        currencies.setBase('SYP'),
        throwsA(isA<BaseCurrencyLockedException>()),
      );
      expect(await currencies.baseCode(), 'USD');
    });
  });

  group('bulk price change', () {
    test('more selected products than SQLite takes parameters', () async {
      final ids = <int>{};
      await db.transaction((txn) async {
        for (var i = 0; i < 1200; i++) {
          ids.add(await insertProduct(txn, name: 'P$i'));
        }
      });
      final other = await insertProduct(db, name: 'Not selected');
      final plan = await PriceChangeRepository(db).preview(
        basisPoints: 1000,
        rounding: PriceRounding.none,
        scope: PriceChangeScope.selected,
        productIds: ids,
      );
      expect(plan.changing, hasLength(1200));
      expect(plan.changing.any((c) => c.productId == other), isFalse);
    });
  });

  group('archive', () {
    test('the newest invoice', () async {
      final archive = ArchiveRepository(db);
      expect(await archive.newestInvoiceAt(), isNull);
      await insertInvoice(db, invoiceNo: 1, createdAt: DateTime(2026, 11, 1));
      await insertInvoice(db, invoiceNo: 2, createdAt: DateTime(2026, 11, 20));
      await insertInvoice(db, invoiceNo: 3, createdAt: DateTime(2026, 11, 5));
      expect(await archive.newestInvoiceAt(), DateTime(2026, 11, 20));
    });
  });

  group('card code files', () {
    test('a third column or a trailing separator is not part of the code', () {
      final parsed = parseCodeList(
        'SN1,4567890123456,100\nSN2;9876543210987;\nSN3\t1111222233334444',
        columns: CodeColumns.serialThenCode,
      );
      expect(
        [for (final c in parsed.codes) (c.serial, c.code)],
        [
          ('SN1', '4567890123456'),
          ('SN2', '9876543210987'),
          ('SN3', '1111222233334444'),
        ],
      );
    });
  });
}
