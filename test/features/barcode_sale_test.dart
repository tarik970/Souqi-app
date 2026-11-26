import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/sale/new_barcode_item_dialog.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// Barcodes on the sale screen: what a hardware scanner (a keyboard that
/// types the code and Enter) does, and the "new product with this barcode"
/// flow for one nobody knows.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
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

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<void> pumpSale(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
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

  /// What a hardware scanner does with the search box focused.
  Future<void> scanInto(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const ValueKey('sale-search-field')), code);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  Future<int> insertWithBarcode(String name, String barcode, int price) =>
      database.db.insert('products', {
        'name': name,
        'name_norm': name.toLowerCase(),
        'barcode': barcode,
        'kind': 'GOODS',
        'price_minor': price,
        'currency_code': 'SYP',
        'is_active': 1,
        'created_at': 0,
        'updated_at': 0,
      });

  String totalText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data!;

  setUp(() async {
    database = await openTestDb();
  });

  tearDown(() async => database.close());

  testWidgets('a known barcode from a scanner goes straight into the cart, '
      'and the box is ready for the next one', (tester) async {
    await db(tester, () => insertWithBarcode('Biscuits', '6221234567890', 500));
    await pumpSale(tester);

    await scanInto(tester, '6221234567890');
    expect(find.byType(QuantitySheet), findsNothing);
    expect(totalText(tester), '500 ل.س');
    await scanInto(tester, '6221234567890');
    expect(totalText(tester), '1,000 ل.س', reason: 'two scans, two pieces');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('sale-search-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a scanner typing while the search box is NOT focused still '
      'lands in it, and Enter adds the product', (tester) async {
    await db(tester, () => insertWithBarcode('Biscuits', '777', 500));
    await pumpSale(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('sale-search-field')),
    );
    field.focusNode!.unfocus();
    await settle(tester, 2);
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await settle(tester, 2);
    expect(field.controller!.text, '7');
    expect(field.focusNode!.hasFocus, isTrue);
    // The rest of the code goes in through the text field itself.
    await tester.enterText(find.byKey(const ValueKey('sale-search-field')), '777');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(totalText(tester), '500 ل.س');
  });

  testWidgets('an unknown barcode: never an item by itself — one tap makes a '
      'new product with it, created when the invoice is saved',
      (tester) async {
    await pumpSale(tester);
    await scanInto(tester, '6221234567890');

    expect(find.byType(QuantitySheet), findsNothing);
    expect(find.text('No item with code 6221234567890'), findsOneWidget);
    await settle(tester, 24); // the snack bar slides in
    await tester.tap(find.byKey(const ValueKey('code-not-found-new')));
    await settle(tester, 24);

    expect(find.byType(NewBarcodeItemDialog), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('new-barcode-name')), 'Biscuits');
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('new-barcode-next')));
    await settle(tester, 24);

    // The type-to-sell sheet, price first, with the barcode attached.
    final sheet = tester.widget<QuantitySheet>(find.byType(QuantitySheet));
    expect(sheet.startAtPrice, isTrue);
    expect(sheet.line.name, 'Biscuits');
    expect(sheet.line.barcode, '6221234567890');
    expect(sheet.line.saveAsProduct, isTrue);
    for (final digit in '650'.split('')) {
      await tester.tap(find.byKey(ValueKey('keypad-$digit')));
      await tester.pump();
    }
    await settle(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester, 24);

    // Nothing in the catalog until the sale is saved.
    expect(await db(tester, () => database.db.query('products')), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.byType(SaleInvoiceScreen), findsOneWidget);

    final product = (await db(tester, () => database.db.query('products'))).single;
    expect(product['name'], 'Biscuits');
    expect(product['barcode'], '6221234567890');
    expect(product['price_minor'], 650);
  });

  testWidgets('cancelling the name adds nothing', (tester) async {
    await pumpSale(tester);
    await scanInto(tester, '123456789');
    await settle(tester, 24); // the snack bar slides in
    await tester.tap(find.byKey(const ValueKey('code-not-found-new')));
    await settle(tester, 24);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester, 24);
    expect(find.byType(NewBarcodeItemDialog), findsNothing);
    expect(find.byType(QuantitySheet), findsNothing);
  });
}
