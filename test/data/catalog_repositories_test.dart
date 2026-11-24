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

  setUp(() async {
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
