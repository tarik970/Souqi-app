import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// Drives the real sale screen end to end: favorite → quantity sheet → cart
/// → save, so the wiring between the UI, the cart math and the invoice
/// repository is exercised, not only the pure functions.
///
/// The screen reads from a real sqflite database, whose futures only progress
/// in [WidgetTester.runAsync]; [settle] therefore interleaves real async with
/// pumped frames instead of using `pumpAndSettle`, which would wait forever
/// on the loading spinner.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // A tap that lands on nothing (a button still sliding in, or below the
    // fold) must fail the test instead of letting it pass on an empty cart.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Runs real database work, which only makes progress outside fake async.
  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<int> insertFavorite(
    String name, {
    required int priceMinor,
    String? code,
    int? unitId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return database.db.insert('products', {
      'name': name,
      'name_norm': name.toLowerCase(),
      'code': code,
      'kind': 'GOODS',
      'unit_id': unitId,
      'price_minor': priceMinor,
      'currency_code': 'SYP',
      'is_favorite': 1,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> pumpSale(WidgetTester tester) async {
    // A phone-shaped viewport: the default 800×600 test window is too short
    // for the quantity sheet's keypad, so its buttons would fall off-screen.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider
              .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SaleScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The text of the big total in the bottom panel.
  String totalText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data!;

  /// The line total shown on a cart row.
  Finder lineTotal(String text) => find.descendant(
        of: find.byType(ListTile),
        matching: find.text(text),
      );

  /// Types [code] into the search box and presses enter.
  Future<void> submitCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  setUp(() async {
    database = await openTestDb();
  });

  tearDown(() async => database.close());

  testWidgets('a favorite goes through the sheet into the cart and is saved',
      (tester) async {
    final unitId = await db(tester, () => insertUnit(database.db));
    await db(
      tester,
      () => insertFavorite('Sugar',
          priceMinor: 1500, code: '101', unitId: unitId),
    );
    await pumpSale(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Sugar'), findsOneWidget); // the favorites bar button

    await tester.tap(find.text('Sugar'));
    await settle(tester);
    expect(find.byType(QuantitySheet), findsOneWidget);

    // Quantity starts at 1; the first keystroke replaces it, not appends.
    await tester.tap(find.byKey(const ValueKey('keypad-3')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    // 1500 × 3 = 4,500, shown on the cart line and as the total.
    expect(lineTotal('4,500 ل.س'), findsOneWidget);
    expect(totalText(tester), '4,500 ل.س');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.byType(SaleInvoiceScreen), findsOneWidget);
    expect(find.text('Invoice no. 1'), findsOneWidget);

    final invoice =
        await db(tester, () async => (await database.db.query('invoices')).single);
    expect(invoice['total_minor'], 4500);
    final item = await db(
        tester, () async => (await database.db.query('invoice_items')).single);
    expect(item['product_name'], 'Sugar');
    expect(item['qty_thousandths'], 3000);
    expect(item['unit_name'], 'kg');
  });

  testWidgets('a decimal quantity from the quick buttons reaches the invoice',
      (tester) async {
    final unitId = await db(tester, () => insertUnit(database.db));
    await db(tester,
        () => insertFavorite('Rice', priceMinor: 2000, unitId: unitId));
    await pumpSale(tester);

    await tester.tap(find.text('Rice'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('qty-preset-500'))); // 0.5
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    expect(lineTotal('1,000 ل.س'), findsOneWidget);
    expect(totalText(tester), '1,000 ل.س');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    final item = await db(
        tester, () async => (await database.db.query('invoice_items')).single);
    expect(item['qty_thousandths'], 500);
    expect(item['line_total_minor'], 1000);
  });

  testWidgets('an exact code typed into the search box is added directly',
      (tester) async {
    await db(tester, () => insertFavorite('Water', priceMinor: 500, code: '7'));
    await pumpSale(tester);

    await submitCode(tester, '7');

    // No sheet: straight into the cart with quantity 1.
    expect(find.byType(QuantitySheet), findsNothing);
    expect(lineTotal('500 ل.س'), findsOneWidget);
    expect(totalText(tester), '500 ل.س');
  });

  testWidgets('an unknown code does not add anything', (tester) async {
    await db(tester, () => insertFavorite('Water', priceMinor: 500, code: '7'));
    await pumpSale(tester);

    await submitCode(tester, '99');

    expect(find.text('No item with code 99'), findsOneWidget);
    final invoices =
        await db(tester, () => database.db.query('invoice_items'));
    expect(invoices, isEmpty);
  });

  testWidgets('the same product at the same price merges into one line',
      (tester) async {
    await db(tester, () => insertFavorite('Tea', priceMinor: 1000, code: '5'));
    await pumpSale(tester);

    await submitCode(tester, '5');
    await submitCode(tester, '5');

    expect(find.widgetWithText(ListTile, 'Tea'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    final items = await db(tester, () => database.db.query('invoice_items'));
    expect(items, hasLength(1));
    expect(items.single['qty_thousandths'], 2000);
    expect(items.single['line_total_minor'], 2000);
  });

  testWidgets('a line priced in another currency shows its ORIGINAL price',
      (tester) async {
    // 1 USD = 13,000 SYP; the product is priced 2.50 USD, the sale is in SYP.
    await db(
      tester,
      () => database.db.update(
        'currencies',
        {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await db(
      tester,
      () => database.db.insert('products', {
        'name': 'Oil',
        'name_norm': 'oil',
        'code': '9',
        'kind': 'GOODS',
        'price_minor': 250,
        'currency_code': 'USD',
        'is_favorite': 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      }),
    );
    await db(tester, () => insertFavorite('Salt', priceMinor: 300, code: '8'));
    await pumpSale(tester);

    await submitCode(tester, '9');
    await submitCode(tester, '9');
    await submitCode(tester, '8');

    // Cross-currency: "qty × original price in its own currency" — the
    // converted unit price (32,500 SYP) is not what the line multiplies.
    expect(find.text(r'2 × 2.50 $'), findsOneWidget);
    expect(lineTotal('65,000 ل.س'), findsOneWidget);
    // Same currency: "qty × unit price".
    expect(find.text('1 × 300 ل.س'), findsOneWidget);
    expect(totalText(tester), '65,300 ل.س');
  });

  testWidgets('after saving: the invoice view and the Print button',
      (tester) async {
    await db(tester, () => insertFavorite('Water', priceMinor: 500, code: '7'));
    await pumpSale(tester);
    await submitCode(tester, '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.byType(SaleInvoiceScreen), findsOneWidget);
    // Output mode defaults to Print: it is the primary button.
    expect(find.byKey(const ValueKey('invoice-primary-print')), findsOneWidget);
    expect(find.byKey(const ValueKey('invoice-primary-shareImage')), findsNothing);
    // The on-screen invoice is the same widget that gets printed, in the
    // INVOICE language (Arabic by default) although the app is in English.
    final view = find.byKey(const ValueKey('saved-invoice-view'), skipOffstage: false);
    expect(view, findsOneWidget);
    expect(
      find.descendant(
        of: view,
        matching: find.text('فاتورة رقم 1', skipOffstage: false),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('type-to-sell', () {
    /// The bottom sheet slides in over 250 ms; a tap on its lowest buttons
    /// only lands once it has stopped moving.
    Future<void> sheetSettled(WidgetTester tester) => settle(tester, 24);

    /// Types [name] into the search box and presses Enter: the new-item
    /// sheet opens.
    Future<void> typeNewItem(WidgetTester tester, String name) async {
      await submitCode(tester, name);
      await sheetSettled(tester);
    }

    Future<void> tapKeys(WidgetTester tester, String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(find.byKey(ValueKey('keypad-$digit')));
        await tester.pump();
      }
      await settle(tester, 2);
    }

    QuantitySheet sheetOf(WidgetTester tester) =>
        tester.widget<QuantitySheet>(find.byType(QuantitySheet));

    FilledButton addButton(WidgetTester tester) => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));

    Future<List<Map<String, Object?>>> productRows(WidgetTester tester) =>
        db(tester, () => database.db.query('products', orderBy: 'id ASC'));

    Future<int> setSetting(String key, String value) =>
        database.db.insert('settings', {
          'key': key,
          'value': value,
          'updated_at': 0,
        });

    testWidgets('Enter on a name with no match opens the sheet at the price',
        (tester) async {
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');

      final sheet = sheetOf(tester);
      expect(sheet.startAtPrice, isTrue);
      expect(sheet.line.name, 'Bread');
      expect(sheet.line.productId, isNull);
      expect(sheet.line.kind, ProductKind.goods);
      expect(sheet.line.qtyThousandths, 1000);
      expect(sheet.line.unitName, 'piece');
      expect(sheet.line.priceCurrencyCode, 'SYP');
      expect(sheet.line.saveAsProduct, isTrue);
      // The price is empty: there is nothing to add yet.
      expect(addButton(tester).onPressed, isNull);

      // The keypad types into the PRICE; the quantity stays 1.
      await tapKeys(tester, '750');
      expect(addButton(tester).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await sheetSettled(tester); // the sheet slides away

      expect(find.byType(QuantitySheet), findsNothing);
      expect(find.text('1 × 750 ل.س'), findsOneWidget);
      expect(lineTotal('750 ل.س'), findsOneWidget);
      expect(totalText(tester), '750 ل.س');
      expect(find.text('New product'), findsOneWidget);
      // The search box is cleared for the next item.
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('the product is created only when the invoice is saved',
        (tester) async {
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');
      await tapKeys(tester, '750');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      // In the cart, not in the catalog.
      expect(await productRows(tester), isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);

      final piece = await db(
        tester,
        () async => (await database.db.query('units',
                where: "is_preset = 1 AND name_en = 'piece'"))
            .single,
      );
      final product = (await productRows(tester)).single;
      expect(product['name'], 'Bread');
      expect(product['code'], isNull);
      expect(product['kind'], 'GOODS');
      expect(product['unit_id'], piece['id']);
      expect(product['price_minor'], 750);
      expect(product['currency_code'], 'SYP');

      final item = await db(tester,
          () async => (await database.db.query('invoice_items')).single);
      expect(item['product_id'], product['id']);
      expect(item['product_name'], 'Bread');
      expect(item['unit_name'], 'piece');
      expect(item['line_total_minor'], 750);
    });

    testWidgets('an abandoned cart creates no product', (tester) async {
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');
      await tapKeys(tester, '750');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);
      expect(find.text('New product'), findsOneWidget);

      // The seller removes the line, then walks away from the sale.
      await tester.tap(find.byTooltip('Remove'));
      await settle(tester);
      expect(find.text('Cart is empty'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);

      expect(await productRows(tester), isEmpty);
      expect(await db(tester, () => database.db.query('invoices')), isEmpty);
    });

    testWidgets('a sheet that is cancelled adds nothing', (tester) async {
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');
      await tapKeys(tester, '750');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await settle(tester);

      expect(find.text('Cart is empty'), findsNothing,
          reason: 'the typed text is still in the search box');
      expect(find.byKey(const ValueKey('add-new-item')), findsOneWidget);
      expect(tester.widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
          isNull);
      expect(await productRows(tester), isEmpty);
    });

    testWidgets('"don\'t save" sells the item once without a product',
        (tester) async {
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');
      await tester.tap(find.byKey(const ValueKey('new-item-dont-save')));
      await tapKeys(tester, '750');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);
      expect(find.text('New product'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect(await productRows(tester), isEmpty);
      final item = await db(tester,
          () async => (await database.db.query('invoice_items')).single);
      expect(item['product_name'], 'Bread');
      expect(item['product_id'], isNull);
    });

    testWidgets('with the setting off, new items are not saved by default',
        (tester) async {
      await db(tester, () => setSetting('save_new_items_as_products', '0'));
      await pumpSale(tester);
      await typeNewItem(tester, 'Bread');

      expect(sheetOf(tester).line.saveAsProduct, isFalse);
      await tapKeys(tester, '750');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);
      expect(find.text('1 × 750 ل.س'), findsOneWidget);
      expect(find.text('New product'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect(await db(tester, () => database.db.query('invoices')),
          hasLength(1));
      expect(await productRows(tester), isEmpty);
    });

    testWidgets('"+ Add" sits above partial matches; an exact name hides it',
        (tester) async {
      await db(tester, () => insertFavorite('Sugar', priceMinor: 1500));
      await pumpSale(tester);
      final addRow = find.byKey(const ValueKey('add-new-item'));
      final match = find.widgetWithText(ListTile, 'Sugar');

      await tester.enterText(find.byType(TextField), 'Sug');
      await settle(tester);
      expect(find.text('Add «Sug»'), findsOneWidget);
      expect(match, findsOneWidget);
      expect(tester.getTopLeft(addRow).dy,
          lessThan(tester.getTopLeft(match).dy));

      // A longer name that merely contains an existing one can be added.
      await tester.enterText(find.byType(TextField), 'Sugar coarse');
      await settle(tester);
      expect(find.text('Add «Sugar coarse»'), findsOneWidget);

      // The exact name (any letter case) is not offered as a new item, and
      // Enter opens the existing product instead.
      await tester.enterText(find.byType(TextField), 'sugar');
      await settle(tester);
      expect(addRow, findsNothing);
      expect(match, findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(sheetOf(tester).line.productId, isNotNull);
      expect(sheetOf(tester).startAtPrice, isFalse);
    });

    testWidgets('tapping "+ Add" starts the new item', (tester) async {
      await db(tester, () => insertFavorite('Sugar', priceMinor: 1500));
      await pumpSale(tester);
      await tester.enterText(find.byType(TextField), 'Sugar coarse');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('add-new-item')));
      await settle(tester);

      expect(sheetOf(tester).line.name, 'Sugar coarse');
      expect(sheetOf(tester).startAtPrice, isTrue);
    });

    testWidgets('"more" changes kind and unit; the unit is remembered',
        (tester) async {
      await pumpSale(tester);

      // A card: no unit.
      await typeNewItem(tester, 'Top-up card');
      await tester.tap(find.byKey(const ValueKey('new-item-more')));
      await settle(tester, 2);
      await tester.tap(find.text('Card / service'));
      await tapKeys(tester, '500');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      // Goods sold by the kilo.
      await typeNewItem(tester, 'Lentils');
      expect(sheetOf(tester).line.unitName, 'piece',
          reason: 'a service does not change the remembered unit');
      await tester.tap(find.byKey(const ValueKey('new-item-more')));
      await settle(tester, 2);
      await tester.tap(find.byKey(const ValueKey('new-item-unit')));
      await settle(tester);
      await tester.tap(find.text('kg').last);
      await settle(tester);
      await tapKeys(tester, '900');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      // The next new item starts with the unit used last.
      await typeNewItem(tester, 'Rice');
      expect(sheetOf(tester).line.unitName, 'kg');
      await tapKeys(tester, '1200');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final rows = await productRows(tester);
      expect(rows.map((r) => r['name']), ['Top-up card', 'Lentils', 'Rice']);
      expect(rows[0]['kind'], 'SERVICE');
      expect(rows[0]['unit_id'], isNull);
      expect(rows[1]['kind'], 'GOODS');
      expect(rows[1]['unit_id'], isNotNull);
      expect(rows[2]['unit_id'], rows[1]['unit_id']);
      final items = await db(tester,
          () => database.db.query('invoice_items', orderBy: 'sort_order'));
      expect(items.map((r) => r['unit_name']), [null, 'kg', 'kg']);
    });

    testWidgets('a number that matches no code is not turned into an item',
        (tester) async {
      await pumpSale(tester);
      await submitCode(tester, '6221234567890');

      expect(find.byType(QuantitySheet), findsNothing);
      expect(find.text('No item with code 6221234567890'), findsOneWidget);
      // The row is still there for a product really named with digits.
      expect(find.byKey(const ValueKey('add-new-item')), findsOneWidget);
    });

    testWidgets('a changed price shows the hint and updates the product',
        (tester) async {
      final id = await db(
          tester, () => insertFavorite('Sugar', priceMinor: 1500, code: '101'));
      await pumpSale(tester);

      await tester.tap(find.text('Sugar'));
      await sheetSettled(tester);
      expect(
        find.text('A changed price is also saved to the product when the '
            'invoice is saved'),
        findsOneWidget,
      );
      await tester.tap(find.text('Unit price'));
      await tapKeys(tester, '1800');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      expect(find.text('1 × 1,800 ل.س'), findsOneWidget);
      expect(find.text('New price will be saved'), findsOneWidget);
      // Not yet: only when the invoice is saved.
      expect((await productRows(tester)).single['price_minor'], 1500);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      final product = (await productRows(tester)).single;
      expect(product['id'], id);
      expect(product['price_minor'], 1800);
    });

    testWidgets('an unchanged price shows no hint', (tester) async {
      await db(
          tester, () => insertFavorite('Sugar', priceMinor: 1500, code: '101'));
      await pumpSale(tester);
      await submitCode(tester, '101');

      expect(find.text('1 × 1,500 ل.س'), findsOneWidget);
      expect(find.text('New price will be saved'), findsNothing);
    });

    testWidgets('with the setting off a changed price stays in the sale',
        (tester) async {
      await db(tester, () => insertFavorite('Sugar', priceMinor: 1500));
      await db(
          tester, () => setSetting('update_product_price_from_sales', '0'));
      await pumpSale(tester);

      await tester.tap(find.text('Sugar'));
      await sheetSettled(tester);
      expect(
        find.text('This sale only — the saved product price does not change'),
        findsOneWidget,
      );
      await tester.tap(find.text('Unit price'));
      await tapKeys(tester, '1800');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);
      expect(find.text('New price will be saved'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect((await productRows(tester)).single['price_minor'], 1500);
      final item = await db(tester,
          () async => (await database.db.query('invoice_items')).single);
      expect(item['orig_unit_price_minor'], 1800);
    });
  });

  group('favorites bar', () {
    testWidgets('starred first, then the best sellers; off = stars only',
        (tester) async {
      Future<int> product(String name, {bool starred = false}) async {
        final id = await insertProduct(database.db, name: name);
        if (starred) {
          await database.db.update('products', {'is_favorite': 1},
              where: 'id = ?', whereArgs: [id]);
        }
        return id;
      }

      var invoiceNo = 1;
      Future<void> sell(int productId, int times) async {
        for (var i = 0; i < times; i++) {
          final invoiceId =
              await insertInvoice(database.db, invoiceNo: invoiceNo++);
          await insertInvoiceItem(database.db,
              invoiceId: invoiceId, productId: productId);
        }
      }

      await db(tester, () async {
        await product('Zeta', starred: true);
        await product('Alpha', starred: true);
        await sell(await product('Bread'), 2);
        await sell(await product('Milk'), 5);
        await product('Never sold');
        return true;
      });
      await pumpSale(tester);

      List<String> bar() => tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((button) => button.child is Column)
          .map((button) =>
              ((button.child as Column).children.first as Text).data!)
          .toList();
      expect(bar(), ['Alpha', 'Zeta', 'Milk', 'Bread']);

      // Auto-favorites switched off in Settings: only the stars remain.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(SaleScreen)));
      await tester.runAsync(
        () => container
            .read(saleSettingsProvider.notifier)
            .change((s) => s.copyWith(autoFavorites: false)),
      );
      await settle(tester);
      expect(bar(), ['Alpha', 'Zeta']);
    });
  });

  group('secondary total shortcut', () {
    testWidgets('toggles currencies inside the invoice settings list',
        (tester) async {
      Future<String> stored() => db(
            tester,
            () async => (await database.db.query('settings',
                    where: 'key = ?',
                    whereArgs: ['extra_total_currencies']))
                .single['value']! as String,
          );
      CheckboxListTile tile(String code) => tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('secondary-total-$code')));

      await db(tester, () async {
        await database.db.update(
          'currencies',
          {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
          where: 'code = ?',
          whereArgs: ['USD'],
        );
        await database.db.insert('currencies', {
          'code': 'TRY',
          'name_ar': 'ليرة تركية',
          'name_en': 'Turkish Lira',
          'symbol': 'TL',
          'decimal_places': 2,
          'rate_num': 400,
          'rate_den': 1,
          'rate_updated_at': 1,
          'is_active': 1,
          'sort_order': 2,
        });
        // The two-currency choice made in the invoice settings.
        return database.db.insert('settings', {
          'key': 'extra_total_currencies',
          'value': '["USD","TRY"]',
          'updated_at': 0,
        });
      });
      await db(tester, () => insertFavorite('Water', priceMinor: 26000, code: '7'));
      await pumpSale(tester);
      await submitCode(tester, '7');
      // Both extra totals show under the main one.
      expect(find.text(r'≈ 2.00 $'), findsOneWidget);
      expect(find.text('≈ 65.00 TL'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Secondary total'));
      await settle(tester);

      // Opening the shortcut shows the settings' choice and changes nothing.
      expect(tile('USD').value, isTrue);
      expect(tile('TRY').value, isTrue);
      expect(tile('SYP').value, isFalse);
      expect(tile('SYP').onChanged, isNull, reason: 'two at most');
      expect(await stored(), '["USD","TRY"]');

      // Unticking one keeps the other.
      await tester.tap(find.byKey(const ValueKey('secondary-total-TRY')));
      await settle(tester);
      expect(await stored(), '["USD"]');
      expect(tile('USD').value, isTrue);
      expect(tile('SYP').onChanged, isNotNull);

      // Ticking one adds to the list instead of replacing it.
      await tester.tap(find.byKey(const ValueKey('secondary-total-TRY')));
      await settle(tester);
      expect(await stored(), '["USD","TRY"]');

      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text(r'≈ 2.00 $'), findsOneWidget);
      expect(find.text('≈ 65.00 TL'), findsOneWidget);
    });
  });

  testWidgets('saving is blocked while the cart is empty', (tester) async {
    await db(tester, () => insertFavorite('Salt', priceMinor: 300));
    await pumpSale(tester);

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(find.text('Cart is empty'), findsOneWidget);
  });
}
