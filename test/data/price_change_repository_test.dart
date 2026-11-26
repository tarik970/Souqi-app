import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/price_change_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/domain/models/price_change.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late PriceChangeRepository prices;
  late ProductRepository products;
  late int sugar, bread, oil, tea;

  Future<void> price(int id, int minor) => database.db.update(
        'products',
        {'price_minor': minor},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> priceOf(int id) async => (await products.getById(id))!.priceMinor;

  setUp(() async {
    database = await openTestDb();
    prices = PriceChangeRepository(database.db);
    products = ProductRepository(database.db);
    sugar = await insertProduct(database.db, name: 'Sugar', code: '1');
    bread = await insertProduct(database.db, name: 'Bread', code: '2');
    oil = await insertProduct(database.db, name: 'Oil', code: '3', currency: 'USD');
    tea = await insertProduct(database.db, name: 'Tea', code: '4');
    await price(sugar, 2600);
    await price(bread, 1000);
    await price(oil, 1299); // 12.99 USD
    await price(tea, 0);
  });

  tearDown(() => database.close());

  test('preview: all, one currency, a chosen few — nothing is written',
      () async {
    final all = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.all,
    );
    expect(all.lines.map((l) => l.name), ['Bread', 'Oil', 'Sugar', 'Tea']);
    expect(all.changing.map((l) => l.newPriceMinor), [1100, 1429, 2860]);

    final usd = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.currency,
      currencyCode: 'USD',
    );
    expect(usd.lines.map((l) => l.productId), [oil]);

    final chosen = await prices.preview(
      basisPoints: -1000,
      rounding: PriceRounding.nearest100,
      scope: PriceChangeScope.selected,
      productIds: {sugar, tea},
    );
    expect(chosen.lines.map((l) => l.productId), [sugar, tea]);
    expect(chosen.changing.single.newPriceMinor, 2300); // 2340 → 2300

    expect(await priceOf(sugar), 2600);
    expect(await database.db.query('price_changes'), isEmpty);
  });

  test('apply: every price, the undo record and the audit line together',
      () async {
    final plan = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.nearest50,
      scope: PriceChangeScope.currency,
      currencyCode: 'SYP',
    );
    expect(await prices.apply(plan), 2); // tea is 0 and stays 0
    expect(await priceOf(sugar), 2850);
    expect(await priceOf(bread), 1100);
    expect(await priceOf(oil), 1299, reason: 'priced in USD');
    expect(await priceOf(tea), 0);

    final record = (await prices.lastUndoable())!;
    expect(record.basisPoints, 1000);
    expect(record.rounding, PriceRounding.nearest50);
    expect(record.scope, PriceChangeScope.currency);
    expect(record.scopeCurrency, 'SYP');
    expect(record.productCount, 2);

    final audit = await database.db.query('audit_log');
    expect(audit.single['action'], 'PRICE_BULK_CHANGE');
    expect(audit.single['details'] as String, contains('"products":2'));
  });

  test('a price changed between preview and apply is scaled from its '
      'current value', () async {
    final plan = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.selected,
      productIds: {sugar},
    );
    await price(sugar, 3000);
    await prices.apply(plan);
    expect(await priceOf(sugar), 3300);
  });

  test('undo puts the old prices back, once, and leaves alone a price '
      'changed again since', () async {
    final plan = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.all,
    );
    await prices.apply(plan);
    // A sale (or the seller) changed bread again afterwards.
    await price(bread, 1250);

    final undone = (await prices.undoLast())!;
    expect(undone.restored, 2);
    expect(undone.skipped, 1);
    expect(await priceOf(sugar), 2600);
    expect(await priceOf(oil), 1299);
    expect(await priceOf(bread), 1250, reason: 'the newer decision stays');

    // One step: nothing more to undo.
    expect(await prices.lastUndoable(), isNull);
    expect(await prices.undoLast(), isNull);
    expect(
      (await database.db.query('audit_log', orderBy: 'id'))
          .map((r) => r['action']),
      ['PRICE_BULK_CHANGE', 'PRICE_BULK_UNDO'],
    );
  });

  test('a new change replaces the undo of the previous one', () async {
    await prices.apply(await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.selected,
      productIds: {sugar},
    ));
    await prices.apply(await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.selected,
      productIds: {bread},
    ));
    expect(await database.db.query('price_changes'), hasLength(1));
    await prices.undoLast();
    expect(await priceOf(bread), 1000);
    expect(await priceOf(sugar), 2860, reason: 'the older change stays');
  });

  test('a change that touches nothing leaves nothing to undo', () async {
    final plan = await prices.preview(
      basisPoints: 10,
      rounding: PriceRounding.nearest1000,
      scope: PriceChangeScope.selected,
      productIds: {bread},
    );
    expect(plan.changing, isEmpty);
    expect(await prices.apply(plan), 0);
    expect(await prices.lastUndoable(), isNull);
  });

  test('a failure half-way writes nothing (one transaction)', () async {
    final plan = await prices.preview(
      basisPoints: 1000,
      rounding: PriceRounding.none,
      scope: PriceChangeScope.all,
    );
    // Break the third write: a trigger that refuses sugar's new price.
    await database.db.execute(
      "CREATE TRIGGER t_fail BEFORE UPDATE OF price_minor ON products "
      "WHEN NEW.id = $sugar BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );
    await expectLater(prices.apply(plan), throwsA(anything));
    expect(await priceOf(bread), 1000);
    expect(await priceOf(oil), 1299);
    expect(await database.db.query('price_changes'), isEmpty);
    expect(await database.db.query('audit_log'), isEmpty);
  });
}
