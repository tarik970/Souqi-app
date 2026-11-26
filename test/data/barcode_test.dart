import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late ProductRepository products;
  late InvoiceRepository invoices;

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

  /// A typed item, as the sale screen makes it for "new product with this
  /// barcode".
  CartLine typed(String name, {String? barcode, int price = 750}) => CartLine(
        name: name,
        kind: ProductKind.goods,
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
        saveAsProduct: true,
        barcode: barcode,
      );

  Future<Invoice> sell(List<CartLine> lines) {
    var cart = const Cart();
    for (final line in lines) {
      cart = cart.add(line);
    }
    return invoices.save(
      Invoice.fromCart(cart: cart, ctx: ctx, createdAt: DateTime.utc(2026, 11, 26)),
    );
  }

  setUp(() async {
    database = await openTestDb();
    products = ProductRepository(database.db);
    invoices = InvoiceRepository(database.db);
  });

  tearDown(() => database.close());

  group('lookup', () {
    test('a barcode is stored normalized and found however it is typed',
        () async {
      final id = await products.insert(const Product(
        name: 'Biscuits',
        barcode: ' 6221-234 567890 ',
        kind: ProductKind.goods,
        priceMinor: 500,
        currencyCode: 'SYP',
      ));
      expect((await products.getById(id))!.barcode, '6221234567890');
      // What a scanner types, with Arabic-Indic digits from a phone keyboard.
      expect((await products.getByExactCode('6221234567890'))!.id, id);
      expect((await products.getByExactCode('٦٢٢١٢٣٤٥٦٧٨٩٠'))!.id, id);
      expect((await products.findByBarcode('6221-2345-67890'))!.id, id);
      expect(await products.getByExactCode('6221234567891'), isNull);
    });

    test('an empty barcode is no barcode', () async {
      final id = await products.insert(const Product(
        name: 'Rice',
        barcode: '  ',
        kind: ProductKind.goods,
        priceMinor: 500,
        currencyCode: 'SYP',
      ));
      expect((await products.getById(id))!.barcode, isNull);
    });

    test('a short code wins over a barcode with the same digits', () async {
      final byCode = await insertProduct(database.db, name: 'Water', code: '7');
      await products.insert(const Product(
        name: 'Gum',
        barcode: '7',
        kind: ProductKind.goods,
        priceMinor: 100,
        currencyCode: 'SYP',
      ));
      expect((await products.getByExactCode('7'))!.id, byCode);
    });

    test('one barcode, one product', () async {
      final id = await products.insert(const Product(
        name: 'Biscuits',
        barcode: '123456',
        kind: ProductKind.goods,
        priceMinor: 500,
        currencyCode: 'SYP',
      ));
      expect(await products.isBarcodeTaken('123-456'), isTrue);
      expect(await products.isBarcodeTaken('123456', excludeId: id), isFalse);
      expect(await products.isBarcodeTaken('654321'), isFalse);
    });

    test('search finds a product by its barcode', () async {
      await products.insert(const Product(
        name: 'Biscuits',
        barcode: '6221234567890',
        kind: ProductKind.goods,
        priceMinor: 500,
        currencyCode: 'SYP',
      ));
      final found = await products.list(query: '6221234567890');
      expect(found.single.name, 'Biscuits');
    });
  });

  group('an unknown barcode becomes a product when the invoice is saved', () {
    test('the new product carries the barcode', () async {
      await sell([typed('Biscuits', barcode: '6221234567890')]);
      final product = (await products.findByBarcode('6221234567890'))!;
      expect(product.name, 'Biscuits');
      expect(product.priceMinor, 750);
      // The next scan finds it.
      expect((await products.getByExactCode('6221234567890'))!.id, product.id);
    });

    test('a name that already exists: that product learns the barcode',
        () async {
      final rice = await insertProduct(database.db, name: 'Rice');
      await sell([typed('rice', barcode: '999888777')]);
      expect((await products.findByBarcode('999888777'))!.id, rice);
      expect(await database.db.query('products'), hasLength(1));
    });

    test('a barcode another product has is never given to a second one',
        () async {
      await sell([typed('Biscuits', barcode: '111222333')]);
      await sell([typed('Crackers', barcode: '111222333')]);
      final rows = await database.db
          .query('products', where: 'barcode = ?', whereArgs: ['111222333']);
      expect(rows.single['name'], 'Biscuits');
      final crackers = (await products.findByName('Crackers'))!;
      expect(crackers.barcode, isNull);
    });

    test('an abandoned cart creates nothing', () async {
      // The line exists only in the cart; nothing was saved.
      typed('Biscuits', barcode: '6221234567890');
      expect(await products.findByBarcode('6221234567890'), isNull);
    });
  });
}
