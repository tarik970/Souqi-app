import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/currency_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/data/repositories/unit_repository.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late ProductRepository products;
  late UnitRepository units;
  late CurrencyRepository currencies;
  var nextInvoiceNo = 1;

  setUp(() async {
    nextInvoiceNo = 1;
    appDb = await openTestDb();
    products = ProductRepository(appDb.db);
    units = UnitRepository(appDb.db);
    currencies =
        CurrencyRepository(appDb.db, SettingsRepository(appDb.db));
  });

  tearDown(() => appDb.close());

  Product goods(String name, {String? code, int? unitId}) => Product(
        name: name,
        code: code,
        kind: ProductKind.goods,
        unitId: unitId,
        priceMinor: 1000,
        currencyCode: 'SYP',
      );

  group('ProductRepository', () {
    test('insert and list, favorites first', () async {
      await products.insert(goods('Sugar'));
      final riceId = await products.insert(goods('Rice'));
      await products.setFavorite(riceId, true);
      final list = await products.list();
      expect(list.map((p) => p.name), ['Rice', 'Sugar']);
      expect(list.first.isFavorite, isTrue);
    });

    test('search matches normalized Arabic names and code prefixes',
        () async {
      await products.insert(goods('سكر ناعم', code: '101'));
      await products.insert(goods('أرز', code: '102'));

      final byName = await products.list(query: 'سكر');
      expect(byName.single.name, 'سكر ناعم');

      final byCode = await products.list(query: '10');
      expect(byCode, hasLength(2));

      final byArabicDigitCode = await products.list(query: '١٠١');
      expect(byArabicDigitCode.single.code, '101');
    });

    test('kind filter separates goods from services', () async {
      await products.insert(goods('Sugar'));
      await products.insert(const Product(
        name: 'Internet 100GB',
        kind: ProductKind.service,
        priceMinor: 50000,
        currencyCode: 'SYP',
        requiresAccount: true,
      ));
      final g = await products.list(kind: ProductKind.goods);
      final s = await products.list(kind: ProductKind.service);
      expect(g.single.name, 'Sugar');
      expect(s.single.requiresAccount, isTrue);
    });

    test('isCodeTaken respects excludeId', () async {
      final id = await products.insert(goods('Sugar', code: '101'));
      expect(await products.isCodeTaken('101'), isTrue);
      expect(await products.isCodeTaken('101', excludeId: id), isFalse);
      expect(await products.isCodeTaken('999'), isFalse);
    });

    test('unused product is hard-deleted', () async {
      final id = await products.insert(goods('Sugar'));
      expect(await products.delete(id), ProductDeleteResult.deleted);
      expect(await products.getById(id), isNull);
    });

    test('product used in an invoice is deactivated instead', () async {
      final id = await products.insert(goods('Sugar'));
      final invoiceId = await insertInvoice(appDb.db, invoiceNo: 1);
      await insertInvoiceItem(appDb.db, invoiceId: invoiceId, productId: id);

      expect(await products.delete(id), ProductDeleteResult.deactivated);
      final p = (await products.getById(id))!;
      expect(p.isActive, isFalse);

      expect(await products.list(), isEmpty);
      expect(await products.list(includeInactive: true), hasLength(1));
    });

    test('update persists changed fields and service drops its unit',
        () async {
      final unitList = await units.list();
      final id = await products
          .insert(goods('Sugar', unitId: unitList.first.id));
      final p = (await products.getById(id))!;
      await products.update(p.copyWith(
        name: 'Sugar Fine',
        kind: ProductKind.service,
        priceMinor: 2000,
      ));
      final updated = (await products.getById(id))!;
      expect(updated.name, 'Sugar Fine');
      expect(updated.kind, ProductKind.service);
      expect(updated.unitId, isNull, reason: 'services carry no unit');
      expect(updated.priceMinor, 2000);
    });
  });

  /// Records [times] sales of the product, [daysAgo] days back.
  Future<void> sell(int productId, {int times = 1, int daysAgo = 0}) async {
    for (var i = 0; i < times; i++) {
      final invoiceId = await insertInvoice(
        appDb.db,
        invoiceNo: nextInvoiceNo++,
        createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      );
      await insertInvoiceItem(appDb.db,
          invoiceId: invoiceId, productId: productId);
    }
  }

  group('search ranking', () {
    test('exact code, then name starts with, then name contains', () async {
      await products.insert(goods('Tea 7 herbs'));
      await products.insert(goods('7 Up'));
      await products.insert(goods('Water', code: '7'));

      final found = await products.list(query: '7');
      expect(found.map((p) => p.name), ['Water', '7 Up', 'Tea 7 herbs']);
    });

    test('an exact name beats a name that only starts with the text',
        () async {
      await products.insert(goods('Sugar cubes'));
      await products.insert(goods('Sugar'));
      final cubes = (await products.list(query: 'cubes')).single;
      await sell(cubes.id!, times: 5); // popularity must not outrank exactness

      final found = await products.list(query: 'sugar');
      expect(found.map((p) => p.name), ['Sugar', 'Sugar cubes']);
    });

    test('within a group the most-sold product of the last 30 days leads',
        () async {
      final coarse = await products.insert(goods('Sugar coarse'));
      final fine = await products.insert(goods('Sugar fine'));
      final brown = await products.insert(goods('Sugar brown'));

      // No sales yet: plain name order.
      expect((await products.list(query: 'sugar')).map((p) => p.name),
          ['Sugar brown', 'Sugar coarse', 'Sugar fine']);

      await sell(fine, times: 3);
      await sell(coarse, times: 1);
      await sell(brown, times: 9, daysAgo: 45); // too old to count

      expect((await products.list(query: 'sugar')).map((p) => p.name),
          ['Sugar fine', 'Sugar coarse', 'Sugar brown']);
    });

    test('a starts-with match stays above a better-selling contains match',
        () async {
      final brown = await products.insert(goods('Brown sugar'));
      await products.insert(goods('Sugar'));
      await sell(brown, times: 10);

      final found = await products.list(query: 'sug');
      expect(found.map((p) => p.name), ['Sugar', 'Brown sugar']);
    });

    test('Arabic variants find the product: "السكر" finds "سكر"', () async {
      await products.insert(goods('سكر'));
      await products.insert(goods('قهوة تركية'));
      await products.insert(goods('أرز مصري'));

      expect((await products.list(query: 'السكر')).single.name, 'سكر');
      expect((await products.list(query: 'سُكَّر')).single.name, 'سكر');
      expect((await products.list(query: 'قهوه')).single.name, 'قهوة تركية');
      expect((await products.list(query: 'القهوة')).single.name, 'قهوة تركية');
      expect((await products.list(query: 'ارز')).single.name, 'أرز مصري');
      expect((await products.list(query: 'الأرز المصري')).single.name,
          'أرز مصري');
    });

    test('% and _ in the typed text match only themselves', () async {
      await products.insert(goods('Discount 50%'));
      await products.insert(goods('Sugar'));
      expect((await products.list(query: '%')).single.name, 'Discount 50%');
      expect(await products.list(query: '_'), isEmpty);
    });

    test('text that normalizes to nothing matches nothing', () async {
      await products.insert(goods('Sugar'));
      expect(await products.list(query: 'ـــ'), isEmpty);
    });
  });

  group('favorites bar', () {
    test('starred products first, then the most sold of the last 30 days',
        () async {
      final zeta = await products.insert(goods('Zeta'));
      final alpha = await products.insert(goods('Alpha'));
      await products.setFavorite(zeta, true);
      await products.setFavorite(alpha, true);

      final bread = await products.insert(goods('Bread'));
      final milk = await products.insert(goods('Milk'));
      final old = await products.insert(goods('Old hit'));
      await products.insert(goods('Never sold'));
      final gone = await products.insert(goods('Deactivated'));

      await sell(bread, times: 2);
      await sell(milk, times: 5);
      await sell(old, times: 20, daysAgo: 31); // outside the window
      await sell(gone, times: 9);
      await products.setActive(gone, false);
      await sell(zeta, times: 50); // starred: listed once, with the stars

      final bar = await products.favoritesBar();
      expect(bar.map((p) => p.name), ['Alpha', 'Zeta', 'Milk', 'Bread']);
    });

    test('auto-favorites fill the bar up to 12 buttons in total', () async {
      final star = await products.insert(goods('Star'));
      await products.setFavorite(star, true);
      for (var i = 1; i <= 15; i++) {
        final id = await products
            .insert(goods('Item ${i.toString().padLeft(2, '0')}'));
        await sell(id, times: i); // Item 15 sells best
      }

      final bar = await products.favoritesBar();
      expect(bar, hasLength(12));
      expect(bar.first.name, 'Star');
      expect(bar[1].name, 'Item 15');
      expect(bar.last.name, 'Item 05');
    });

    test('switched off: only the starred products', () async {
      final star = await products.insert(goods('Star'));
      await products.setFavorite(star, true);
      final bread = await products.insert(goods('Bread'));
      await sell(bread, times: 3);

      final bar = await products.favoritesBar(includeAuto: false);
      expect(bar.map((p) => p.name), ['Star']);
    });

    test('more than 12 starred products are all shown', () async {
      for (var i = 0; i < 14; i++) {
        final id = await products.insert(goods('Star $i'));
        await products.setFavorite(id, true);
      }
      final bread = await products.insert(goods('Bread'));
      await sell(bread);

      final bar = await products.favoritesBar();
      expect(bar, hasLength(14));
      expect(bar.every((p) => p.isFavorite), isTrue);
    });
  });

  group('duplicate guard and price memory', () {
    test('findByName matches the normalized name, active product first',
        () async {
      final inactive = await products.insert(goods('سكر ناعم'));
      await products.setActive(inactive, false);
      expect((await products.findByName('السكر الناعم'))!.id, inactive);

      final active = await products.insert(goods('السكر الناعم'));
      expect((await products.findByName('ســكر ناعم'))!.id, active);
      expect(await products.findByName('سكر خشن'), isNull);
      expect(await products.findByName('  '), isNull);
    });

    test('updatePriceFromSale: same currency only, never to zero', () async {
      final id = await products.insert(goods('Sugar')); // 1000 SYP

      expect(
        await products.updatePriceFromSale(id,
            priceMinor: 1200, currencyCode: 'SYP'),
        isTrue,
      );
      expect((await products.getById(id))!.priceMinor, 1200);

      expect(
        await products.updatePriceFromSale(id,
            priceMinor: 150, currencyCode: 'USD'),
        isFalse,
        reason: 'a price in another currency is not the product price',
      );
      expect(
        await products.updatePriceFromSale(id,
            priceMinor: 0, currencyCode: 'SYP'),
        isFalse,
      );
      expect(
        await products.updatePriceFromSale(id,
            priceMinor: 1200, currencyCode: 'SYP'),
        isFalse,
        reason: 'unchanged price',
      );
      final product = (await products.getById(id))!;
      expect(product.priceMinor, 1200);
      expect(product.currencyCode, 'SYP');
    });
  });

  group('UnitRepository', () {
    test('presets come first, custom units can be added and renamed',
        () async {
      final id = await units.insertCustom('دزينة');
      var list = await units.list();
      expect(list.first.isPreset, isTrue);
      expect(list.last.nameAr, 'دزينة');

      await units.updateCustom(id, 'dozen');
      list = await units.list();
      expect(list.last.nameEn, 'dozen');
    });

    test('deleting a used unit throws UnitInUseException', () async {
      final id = await units.insertCustom('دزينة');
      await products.insert(goods('Eggs', unitId: id));
      expect(
        () => units.deleteCustom(id),
        throwsA(isA<UnitInUseException>()),
      );
      await products.insert(goods('More eggs', unitId: id));
      expect(await units.countProductsUsing(id), 2);
    });

    test('unused custom unit is deleted, presets never are', () async {
      final id = await units.insertCustom('دزينة');
      await units.deleteCustom(id);
      expect(await units.getById(id), isNull);

      final preset = (await units.list()).first;
      await units.deleteCustom(preset.id!);
      expect(await units.getById(preset.id!), isNotNull);
    });
  });

  group('CurrencyRepository', () {
    test('insert, update rate, and list', () async {
      await currencies.insert(const Currency(
        code: 'try',
        nameAr: 'ليرة تركية',
        nameEn: 'Turkish Lira',
        symbol: '₺',
        decimalPlaces: 2,
        rate: RateFraction(325, 1),
      ));
      var c = (await currencies.getByCode('TRY'))!;
      expect(c.code, 'TRY', reason: 'codes are stored uppercase');
      expect(c.rate, const RateFraction(325, 1));

      await currencies.updateRate('TRY', const RateFraction(661, 2));
      c = (await currencies.getByCode('TRY'))!;
      expect(c.rate, const RateFraction(661, 2));
      expect(c.rateUpdatedAt, isNotNull);
    });

    test('base currency cannot be disabled', () async {
      expect(await currencies.baseCode(), 'SYP');
      expect(
        () => currencies.setActive('SYP', false),
        throwsA(isA<BaseCurrencyException>()),
      );
      await currencies.setActive('USD', false); // non-base is fine
      final active = await currencies.list();
      expect(active.map((c) => c.code), isNot(contains('USD')));
    });

    test('setBase swaps the base and resets other rate timestamps',
        () async {
      expect(await currencies.canChangeBase(), isTrue);
      await currencies.updateRate('USD', const RateFraction(13000, 1));

      await currencies.setBase('USD');
      expect(await currencies.baseCode(), 'USD');

      final usd = (await currencies.getByCode('USD'))!;
      expect(usd.rate, RateFraction.one);
      expect(usd.rateUpdatedAt, isNotNull);

      final syp = (await currencies.getByCode('SYP'))!;
      expect(syp.rateUpdatedAt, isNull,
          reason: 'old base must be re-rated against the new base');
    });

    test('setBase is locked once an invoice exists', () async {
      await insertInvoice(appDb.db, invoiceNo: 1);
      expect(await currencies.canChangeBase(), isFalse);
      expect(
        () => currencies.setBase('USD'),
        throwsA(isA<BaseCurrencyLockedException>()),
      );
      expect(await currencies.baseCode(), 'SYP');
    });

    test('setBase is locked once a debt transaction exists', () async {
      final customerId = await insertCustomer(appDb.db);
      await appDb.db.insert('debt_transactions', {
        'customer_id': customerId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'type': 'DEBT',
        'amount_base_minor': 5000,
      });
      expect(await currencies.canChangeBase(), isFalse);
    });
  });
}
