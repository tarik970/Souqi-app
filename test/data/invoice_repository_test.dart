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

Currency _currency(
  String code, {
  int decimals = 0,
  RateFraction rate = RateFraction.one,
  bool rateSet = true,
}) {
  return Currency(
    code: code,
    nameAr: code,
    nameEn: code,
    decimalPlaces: decimals,
    rate: rate,
    rateUpdatedAt: rateSet ? DateTime.utc(2026, 1, 1) : null,
  );
}

final _syp = _currency('SYP');
final _usd = _currency('USD', decimals: 2, rate: const RateFraction(13000, 1));

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late InvoiceRepository invoices;
  late int sugarId;
  late int cardId;

  CurrencyContext ctx({
    String base = 'SYP',
    List<String> extras = const [],
    bool usdRateSet = true,
  }) {
    return CurrencyContext.of(
      [
        _syp,
        usdRateSet
            ? _usd
            : _currency('USD', decimals: 2, rateSet: false),
      ],
      baseCode: base,
      extraCodes: extras,
    );
  }

  setUp(() async {
    database = await openTestDb();
    invoices = InvoiceRepository(database.db);
    final unitId = await insertUnit(database.db);
    sugarId = await insertProduct(
      database.db,
      name: 'Sugar',
      code: '101',
      unitId: unitId,
    );
    cardId = await insertProduct(
      database.db,
      name: 'Internet 100 GB',
      kind: 'SERVICE',
      currency: 'USD',
    );
  });

  tearDown(() async => database.close());

  /// A goods line for the seeded Sugar product; [unsaved] makes it a quick
  /// item with no product id.
  CartLine goodsLine({
    bool unsaved = false,
    String name = 'Sugar',
    String? code = '101',
    int priceMinor = 1500,
    String currency = 'SYP',
    int qty = 2000,
  }) =>
      CartLine(
        productId: unsaved ? null : sugarId,
        name: name,
        code: code,
        kind: ProductKind.goods,
        unitName: 'kg',
        unitPriceMinor: priceMinor,
        priceCurrencyCode: currency,
        qtyThousandths: qty,
      );

  Invoice draftOf(Cart cart, {CurrencyContext? context}) => Invoice.fromCart(
        cart: cart,
        ctx: context ?? ctx(),
        createdAt: DateTime.utc(2026, 3, 1, 10, 30),
      );

  group('saving', () {
    test('stores the invoice, its items and the totals', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1500, qty: 2000))
          .add(goodsLine(
              unsaved: true, name: 'Bread', code: null,
              priceMinor: 700, qty: 3000));
      final saved = await invoices.save(draftOf(cart));

      expect(saved.id, isNotNull);
      expect(saved.invoiceNo, 1);
      expect(saved.subtotalMinor, 3000 + 2100);
      expect(saved.totalMinor, 5100);
      expect(saved.totalBaseMinor, 5100);
      expect(saved.items, hasLength(2));
      expect(saved.items.every((i) => i.id != null), isTrue);

      final rows = await database.db.query('invoices');
      expect(rows, hasLength(1));
      expect(rows.single['invoice_no'], 1);
      expect(rows.single['currency_code'], 'SYP');
      expect(rows.single['base_currency_code'], 'SYP');
      expect(rows.single['rate_num'], 1);
      expect(rows.single['rate_den'], 1);
      expect(rows.single['total_minor'], 5100);
      expect(rows.single['created_at'],
          DateTime.utc(2026, 3, 1, 10, 30).millisecondsSinceEpoch);

      final itemRows = await database.db
          .query('invoice_items', orderBy: 'sort_order ASC');
      expect(itemRows.map((r) => r['sort_order']), [0, 1]);
      expect(itemRows.map((r) => r['product_name']), ['Sugar', 'Bread']);
      expect(itemRows.first['product_id'], sugarId);
      expect(itemRows.last['product_id'], isNull);
    });

    test('snapshots the product name, code, kind, unit and prices', () async {
      final cart = const Cart().add(goodsLine(priceMinor: 1500, qty: 500));
      await invoices.save(draftOf(cart));

      final item = (await database.db.query('invoice_items')).single;
      expect(item['product_name'], 'Sugar');
      expect(item['product_code'], '101');
      expect(item['kind'], 'GOODS');
      expect(item['unit_name'], 'kg');
      expect(item['qty_thousandths'], 500);
      expect(item['orig_unit_price_minor'], 1500);
      expect(item['orig_currency_code'], 'SYP');
      expect(item['orig_rate_num'], 1);
      expect(item['orig_rate_den'], 1);
      expect(item['unit_price_minor'], 1500);
      expect(item['line_total_minor'], 750);
    });

    test('a later product price change does not alter the invoice', () async {
      await invoices.save(draftOf(const Cart().add(goodsLine())));
      await database.db.update(
        'products',
        {'price_minor': 9999},
        where: 'id = ?',
        whereArgs: [sugarId],
      );
      final item = (await database.db.query('invoice_items')).single;
      expect(item['orig_unit_price_minor'], 1500);
      expect(item['line_total_minor'], 3000);
    });

    test('invoice numbers are sequential', () async {
      for (var expected = 1; expected <= 3; expected++) {
        final saved = await invoices.save(draftOf(const Cart().add(goodsLine())));
        expect(saved.invoiceNo, expected);
      }
      expect(await invoices.peekNextInvoiceNo(), 4);
    });

    test('numbers are never reused after an invoice is deleted', () async {
      final first = await invoices.save(draftOf(const Cart().add(goodsLine())));
      await database.db
          .delete('invoices', where: 'id = ?', whereArgs: [first.id]);
      final next = await invoices.save(draftOf(const Cart().add(goodsLine())));
      expect(next.invoiceNo, 2);
    });

    test('deleting an invoice cascades to its items', () async {
      final saved = await invoices.save(draftOf(const Cart().add(goodsLine())));
      await database.db
          .delete('invoices', where: 'id = ?', whereArgs: [saved.id]);
      expect(await database.db.query('invoice_items'), isEmpty);
    });

    test('a failing item rolls back the whole save, number included',
        () async {
      final draft = draftOf(const Cart().add(goodsLine()));
      final broken = draft.copyWith(items: [
        ...draft.items,
        // qty_thousandths has a CHECK (> 0): the insert must fail.
        InvoiceItem(
          productName: 'Broken',
          kind: ProductKind.goods,
          qtyThousandths: 0,
          origUnitPriceMinor: 100,
          origCurrencyCode: 'SYP',
          origRate: RateFraction.one,
          unitPriceMinor: 100,
          lineTotalMinor: 0,
        ),
      ]);

      await expectLater(invoices.save(broken), throwsA(isA<Exception>()));
      expect(await database.db.query('invoices'), isEmpty);
      expect(await database.db.query('invoice_items'), isEmpty);
      expect(await invoices.peekNextInvoiceNo(), 1);
    });

    test('an invoice with no items is refused', () async {
      expect(
        () => invoices.save(Invoice(
          createdAt: DateTime.utc(2026, 3, 1),
          currencyCode: 'SYP',
          baseCurrencyCode: 'SYP',
          rate: RateFraction.one,
          subtotalMinor: 0,
          totalMinor: 0,
          totalBaseMinor: 0,
        )),
        throwsArgumentError,
      );
    });
  });

  group('type-to-sell: products created by the sale', () {
    /// An item typed into the sale: no product id.
    CartLine typed(
      String name, {
      int priceMinor = 700,
      bool save = true,
      int? unitId,
      ProductKind kind = ProductKind.goods,
      String currency = 'SYP',
    }) =>
        CartLine(
          name: name,
          kind: kind,
          unitId: unitId,
          unitName: unitId == null ? null : 'kg',
          unitPriceMinor: priceMinor,
          priceCurrencyCode: currency,
          qtyThousandths: 1000,
          saveAsProduct: save,
        );

    Future<List<Map<String, Object?>>> productRows() =>
        database.db.query('products', orderBy: 'id ASC');

    test('the product is created when the invoice is saved, not before',
        () async {
      final unitId = await insertUnit(database.db);
      final cart = const Cart().add(typed('Bread', unitId: unitId));
      final draft = draftOf(cart);

      // Building the cart and the draft touched nothing.
      expect(await productRows(), hasLength(2));

      final saved = await invoices.save(draft);

      final rows = await productRows();
      expect(rows, hasLength(3));
      final bread = rows.last;
      expect(bread['name'], 'Bread');
      expect(bread['name_norm'], 'bread');
      expect(bread['code'], isNull, reason: 'no code is required');
      expect(bread['kind'], 'GOODS');
      expect(bread['unit_id'], unitId);
      expect(bread['price_minor'], 700);
      expect(bread['currency_code'], 'SYP');
      expect(bread['is_active'], 1);
      expect(bread['is_favorite'], 0);

      // The invoice line is linked to the new product.
      expect(saved.items.single.productId, bread['id']);
      final item = (await database.db.query('invoice_items')).single;
      expect(item['product_id'], bread['id']);
      expect(item['product_name'], 'Bread');
    });

    test('a "don\'t save" line creates nothing', () async {
      final cart = const Cart().add(typed('Bread', save: false));
      final saved = await invoices.save(draftOf(cart));

      expect(await productRows(), hasLength(2));
      expect(saved.items.single.productId, isNull);
      expect((await database.db.query('invoice_items')).single['product_id'],
          isNull);
    });

    test('a service keeps no unit; its currency is the line currency',
        () async {
      final unitId = await insertUnit(database.db);
      final cart = const Cart().add(typed(
        'Top-up',
        kind: ProductKind.service,
        unitId: unitId,
        priceMinor: 250,
        currency: 'USD',
      ));
      await invoices.save(draftOf(cart));

      final product = (await productRows()).last;
      expect(product['kind'], 'SERVICE');
      expect(product['unit_id'], isNull);
      expect(product['price_minor'], 250);
      expect(product['currency_code'], 'USD');
    });

    test('a failed save leaves no product behind', () async {
      final draft = draftOf(const Cart().add(typed('Bread')));
      final broken = draft.copyWith(items: [
        ...draft.items,
        InvoiceItem(
          productName: 'Broken',
          kind: ProductKind.goods,
          qtyThousandths: 0, // CHECK (> 0) fails
          origUnitPriceMinor: 100,
          origCurrencyCode: 'SYP',
          origRate: RateFraction.one,
          unitPriceMinor: 100,
          lineTotalMinor: 0,
        ),
      ]);

      await expectLater(invoices.save(broken), throwsA(isA<Exception>()));
      expect(await productRows(), hasLength(2));
      expect(await database.db.query('invoices'), isEmpty);
    });

    test('a unit deleted while the item sat in the cart does not block the sale',
        () async {
      final cart = const Cart().add(typed('Bread', unitId: 987654));
      await invoices.save(draftOf(cart));
      expect((await productRows()).last['unit_id'], isNull);
    });

    group('duplicate guard', () {
      const cases = <String, List<String>>{
        'سكر ناعم': [
          'السكر الناعم',
          '  سكر   ناعم ',
          'سُكَّر ناعِم',
          'ســكر نــاعم',
        ],
        'قهوة': ['قهوه', 'القهوة', 'القهوه'],
        'أرز': ['ارز', 'إرز', 'آرز', 'الأرز'],
        'حلوى': ['حلوي', 'الحلوى'],
        'Pepsi': ['pepsi', ' PEPSI '],
      };

      for (final MapEntry(key: existing, value: variants) in cases.entries) {
        test('"$existing" is reused for ${variants.length} spellings',
            () async {
          final existingId = await ProductRepository(database.db).insert(
            Product(
              name: existing,
              kind: ProductKind.goods,
              priceMinor: 700,
              currencyCode: 'SYP',
            ),
          );
          final before = (await productRows()).length;

          for (final variant in variants) {
            final saved =
                await invoices.save(draftOf(const Cart().add(typed(variant))));
            expect(saved.items.single.productId, existingId,
                reason: '"$variant" is "$existing"');
            // The receipt still says what the seller typed.
            expect(saved.items.single.productName, variant);
          }
          expect(await productRows(), hasLength(before),
              reason: 'no duplicate product was created');
        });
      }

      test('a genuinely different name is a new product', () async {
        await ProductRepository(database.db).insert(const Product(
          name: 'سكر',
          kind: ProductKind.goods,
          priceMinor: 700,
          currencyCode: 'SYP',
        ));
        final before = (await productRows()).length;
        await invoices.save(draftOf(const Cart().add(typed('سكر خشن'))));
        expect(await productRows(), hasLength(before + 1));
      });

      test('the same new name twice in one sale creates one product',
          () async {
        final cart = const Cart()
            .add(typed('خبز'))
            .add(typed('الخبز', priceMinor: 800));
        final saved = await invoices.save(draftOf(cart));

        expect(await productRows(), hasLength(3));
        expect(saved.items[0].productId, isNotNull);
        expect(saved.items[1].productId, saved.items[0].productId);
      });

      test('a deactivated product with that name is reused and reactivated',
          () async {
        await database.db.update(
          'products',
          {'is_active': 0},
          where: 'id = ?',
          whereArgs: [sugarId],
        );
        final saved =
            await invoices.save(draftOf(const Cart().add(typed('sugar'))));

        expect(saved.items.single.productId, sugarId);
        expect(await productRows(), hasLength(2));
        final sugar = (await ProductRepository(database.db).getById(sugarId))!;
        expect(sugar.isActive, isTrue);
      });
    });
  });

  group('remember last price', () {
    /// The seeded Sugar product costs 1000 SYP. [listPrice] is what the cart
    /// saw when the line was added; [priceMinor] is what the seller charged.
    CartLine sugar({
      required int priceMinor,
      int listPrice = 1000,
      String currency = 'SYP',
    }) =>
        CartLine(
          productId: sugarId,
          name: 'Sugar',
          code: '101',
          unitName: 'kg',
          unitPriceMinor: priceMinor,
          priceCurrencyCode: currency,
          qtyThousandths: 1000,
          listPriceMinor: listPrice,
          listCurrencyCode: 'SYP',
        );

    Future<Product> savedSugar() async =>
        (await ProductRepository(database.db).getById(sugarId))!;

    Invoice draft(CartLine line, {bool update = true}) => Invoice.fromCart(
          cart: const Cart().add(line),
          ctx: ctx(),
          createdAt: DateTime.utc(2026, 3, 1, 10, 30),
          updateProductPrices: update,
        );

    test('a changed price becomes the product price when the invoice is saved',
        () async {
      final invoice = draft(sugar(priceMinor: 1200));
      expect((await savedSugar()).priceMinor, 1000,
          reason: 'nothing changes before the save');

      await invoices.save(invoice);
      expect((await savedSugar()).priceMinor, 1200);
      // The invoice keeps what was charged.
      expect(
        (await database.db.query('invoice_items')).single
            ['orig_unit_price_minor'],
        1200,
      );
    });

    test('with the setting off the product keeps its price', () async {
      await invoices.save(draft(sugar(priceMinor: 1200), update: false));
      expect((await savedSugar()).priceMinor, 1000);
    });

    test('an unchanged price is not an update', () async {
      // The product was re-priced in the Products screen while the line sat
      // in the cart at the old list price: the sale must not push it back.
      await database.db.update('products', {'price_minor': 1500},
          where: 'id = ?', whereArgs: [sugarId]);
      await invoices.save(draft(sugar(priceMinor: 1000)));
      expect((await savedSugar()).priceMinor, 1500);
    });

    test('a price in another currency never replaces the product price',
        () async {
      await invoices.save(draft(sugar(priceMinor: 10, currency: 'USD')));
      final product = await savedSugar();
      expect(product.priceMinor, 1000);
      expect(product.currencyCode, 'SYP');
    });

    test('giving the item away for 0 does not wipe the price', () async {
      await invoices.save(draft(sugar(priceMinor: 0)));
      expect((await savedSugar()).priceMinor, 1000);
    });

    test('a typed item matching an existing product updates its price too',
        () async {
      const line = CartLine(
        name: 'sugar',
        unitPriceMinor: 1300,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
        saveAsProduct: true,
      );
      await invoices.save(draft(line));
      expect((await savedSugar()).priceMinor, 1300);

      await invoices.save(draft(line.copyWith(unitPriceMinor: 1400),
          update: false));
      expect((await savedSugar()).priceMinor, 1300);
    });

    test('CartLine.hasPriceOverride follows the same rule', () {
      expect(sugar(priceMinor: 1200).hasPriceOverride, isTrue);
      expect(sugar(priceMinor: 1000).hasPriceOverride, isFalse);
      expect(sugar(priceMinor: 0).hasPriceOverride, isFalse);
      expect(sugar(priceMinor: 10, currency: 'USD').hasPriceOverride, isFalse);
    });
  });

  group('discounts', () {
    test('a percentage discount stores the type, value and amount', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1000, qty: 10000))
          .withDiscount(const Discount.percent(1250)); // 12.50%
      final saved = await invoices.save(draftOf(cart));

      expect(saved.discountMinor, 1250);
      expect(saved.totalMinor, 8750);
      final row = (await database.db.query('invoices')).single;
      expect(row['discount_type'], 'PERCENT');
      expect(row['discount_value'], 1250);
      expect(row['discount_minor'], 1250);
      expect(row['subtotal_minor'], 10000);
      expect(row['total_minor'], 8750);
    });

    test('an amount discount stores the type, value and amount', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1000, qty: 10000))
          .withDiscount(const Discount.amount(2000));
      await invoices.save(draftOf(cart));

      final row = (await database.db.query('invoices')).single;
      expect(row['discount_type'], 'AMOUNT');
      expect(row['discount_value'], 2000);
      expect(row['discount_minor'], 2000);
      expect(row['total_minor'], 8000);
    });

    test('no discount stores nulls and a zero amount', () async {
      await invoices.save(draftOf(const Cart().add(goodsLine())));
      final row = (await database.db.query('invoices')).single;
      expect(row['discount_type'], isNull);
      expect(row['discount_value'], isNull);
      expect(row['discount_minor'], 0);
    });
  });

  group('currency snapshots', () {
    test('a mixed-currency cart stores each line\'s own rate', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1000, qty: 1000))
          .add(CartLine(
            productId: cardId,
            name: 'Internet 100 GB',
            kind: ProductKind.service,
            unitPriceMinor: 150, // 1.50 USD
            priceCurrencyCode: 'USD',
            qtyThousandths: 2000,
          ));
      final saved = await invoices.save(draftOf(cart));

      // 1000 SYP + 2 × 19500 SYP
      expect(saved.subtotalMinor, 40000);
      expect(saved.totalBaseMinor, 40000);

      final items =
          await database.db.query('invoice_items', orderBy: 'sort_order ASC');
      expect(items[0]['orig_currency_code'], 'SYP');
      expect(items[0]['orig_rate_num'], 1);
      expect(items[0]['orig_rate_den'], 1);
      expect(items[1]['orig_currency_code'], 'USD');
      expect(items[1]['orig_unit_price_minor'], 150);
      expect(items[1]['orig_rate_num'], 13000);
      expect(items[1]['orig_rate_den'], 1);
      expect(items[1]['unit_price_minor'], 19500);
      expect(items[1]['line_total_minor'], 39000);
    });

    test('a USD invoice stores its own rate and the base total', () async {
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(goodsLine(priceMinor: 130000, qty: 1000));
      final saved = await invoices.save(draftOf(cart));

      expect(saved.currencyCode, 'USD');
      expect(saved.totalMinor, 1000); // 10.00 USD
      expect(saved.totalBaseMinor, 130000);
      final row = (await database.db.query('invoices')).single;
      expect(row['currency_code'], 'USD');
      expect(row['rate_num'], 13000);
      expect(row['rate_den'], 1);
      expect(row['total_base_minor'], 130000);
    });

    test('extra totals are stored with their rates', () async {
      final cart = const Cart().add(goodsLine(priceMinor: 26000, qty: 1000));
      final saved = await invoices.save(
        draftOf(cart, context: ctx(extras: ['USD'])),
      );

      expect(saved.extraTotals, hasLength(1));
      final row = (await database.db.query('invoices')).single;
      expect(row['extra1_currency_code'], 'USD');
      expect(row['extra1_rate_num'], 13000);
      expect(row['extra1_rate_den'], 1);
      expect(row['extra1_total_minor'], 200);
      expect(row['extra2_currency_code'], isNull);
    });

    test('a stored line total is converted in one rounding step', () async {
      // 5000 SYP × 10 on a USD invoice at 13000 SYP/USD: the stored total is
      // 3.85 USD, while the stored unit price is the display-only 0.38.
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(goodsLine(priceMinor: 5000, qty: 10000));
      final saved = await invoices.save(draftOf(cart));

      expect(saved.totalMinor, 385);
      final item = (await database.db.query('invoice_items')).single;
      expect(item['orig_unit_price_minor'], 5000);
      expect(item['orig_currency_code'], 'SYP');
      expect(item['unit_price_minor'], 38);
      expect(item['line_total_minor'], 385);
      // The invoice total is the sum of the line totals, not of unit prices.
      final row = (await database.db.query('invoices')).single;
      expect(row['subtotal_minor'], 385);
      expect(row['total_base_minor'], 50050); // 3.85 USD back to SYP
    });

    test('a changed rate afterwards does not alter the saved invoice',
        () async {
      final cart = const Cart().add(CartLine(
        productId: cardId,
        name: 'Internet 100 GB',
        kind: ProductKind.service,
        unitPriceMinor: 100,
        priceCurrencyCode: 'USD',
        qtyThousandths: 1000,
      ));
      final saved = await invoices.save(draftOf(cart));
      expect(saved.totalMinor, 13000);

      await database.db.update(
        'currencies',
        {'rate_num': 20000, 'rate_den': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );
      final reread = await invoices.getById(saved.id!);
      expect(reread!.totalMinor, 13000);
      expect(reread.items.single.origRate, const RateFraction(13000, 1));
    });

    test('a cart in a currency with no rate cannot be built', () {
      final cart = const Cart().add(CartLine(
        productId: cardId,
        name: 'Internet 100 GB',
        kind: ProductKind.service,
        unitPriceMinor: 100,
        priceCurrencyCode: 'USD',
        qtyThousandths: 1000,
      ));
      expect(
        () => draftOf(cart, context: ctx(usdRateSet: false)),
        throwsStateError,
      );
    });

    test('an empty cart cannot be saved', () {
      expect(() => draftOf(const Cart()), throwsStateError);
    });
  });

  group('reading back', () {
    test('getById returns the invoice with its items in order', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1500, qty: 2000))
          .add(goodsLine(
              unsaved: true, name: 'Bread', code: null,
              priceMinor: 700, qty: 1000));
      final saved = await invoices.save(draftOf(cart));

      final read = await invoices.getById(saved.id!);
      expect(read, isNotNull);
      expect(read!.invoiceNo, saved.invoiceNo);
      expect(read.createdAt, DateTime.utc(2026, 3, 1, 10, 30));
      expect(read.currencyCode, 'SYP');
      expect(read.subtotalMinor, saved.subtotalMinor);
      expect(read.totalMinor, saved.totalMinor);
      expect(read.items.map((i) => i.productName), ['Sugar', 'Bread']);
      expect(read.items.first.unitName, 'kg');
      expect(read.items.first.lineTotalMinor, 3000);
    });

    test('getByNumber finds the invoice by its sequential number', () async {
      await invoices.save(draftOf(const Cart().add(goodsLine())));
      final second = await invoices.save(draftOf(const Cart().add(goodsLine())));
      final read = await invoices.getByNumber(2);
      expect(read!.id, second.id);
    });

    test('a discount survives the round trip', () async {
      final cart = const Cart()
          .add(goodsLine(priceMinor: 1000, qty: 10000))
          .withDiscount(const Discount.percent(1000));
      final saved = await invoices.save(draftOf(cart));
      final read = await invoices.getById(saved.id!);
      expect(read!.discountType, DiscountType.percent);
      expect(read.discountValue, 1000);
      expect(read.discountMinor, 1000);
    });

    test('getById returns null for an unknown id', () async {
      expect(await invoices.getById(404), isNull);
      expect(await invoices.getByNumber(404), isNull);
    });

    test('peekNextInvoiceNo does not consume a number', () async {
      expect(await invoices.peekNextInvoiceNo(), 1);
      expect(await invoices.peekNextInvoiceNo(), 1);
      final saved = await invoices.save(draftOf(const Cart().add(goodsLine())));
      expect(saved.invoiceNo, 1);
    });
  });
}
