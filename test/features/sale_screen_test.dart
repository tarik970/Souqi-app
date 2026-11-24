import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
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
  setUpAll(sqfliteFfiInit);

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
