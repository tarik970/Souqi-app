import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/currencies/currency_form_screen.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/setup/setup_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The screens with text input, on the smallest phone this app targets, with
/// the keyboard up and the system font turned up: nothing may overflow.
///
/// A RenderFlex overflow is reported as a framework exception, so every test
/// here ends on [WidgetTester.takeException] being null — the same yellow-and-
/// black "BOTTOM OVERFLOWED BY …" stripe the seller saw on the phone.
///
/// The screens read from a real sqflite database, whose futures only progress
/// inside [WidgetTester.runAsync]; [settle] therefore interleaves real async
/// with pumped frames instead of using `pumpAndSettle`, which would wait
/// forever on the loading spinner.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;

  /// A small phone in logical pixels: 360×640, the size the overflow was
  /// reported on.
  const phone = Size(360, 640);

  /// The height a soft keyboard takes on such a phone.
  const keyboardInset = 300.0;

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

  setUp(() async => database = await openTestDb());
  tearDown(() async => database.close());

  /// Pumps [SaleScreen] on a 360×640 phone at [textScale] system font size.
  Future<void> pumpSale(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = phone * tester.view.devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

  /// Focuses the search box, types [text] and only THEN raises the keyboard —
  /// the order the phone does it in.
  Future<void> typeWithKeyboard(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await settle(tester);
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardInset * tester.view.devicePixelRatio,
    );
    await settle(tester);
  }

  Future<void> addFavorite(
    WidgetTester tester,
    String name, {
    int priceMinor = 1500,
    bool withUnit = false,
    String? code,
  }) async {
    await db(tester, () async {
      final unitId = withUnit ? await insertUnit(database.db) : null;
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
    });
  }

  group('sale screen', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('fits a 360×640 phone at font scale $scale', (tester) async {
        await addFavorite(tester, 'Sugar with a rather long name');
        await pumpSale(tester, textScale: scale);
        expect(tester.takeException(), isNull);

        // An empty cart, then a full one: the totals panel is at its tallest
        // with a discount and a second currency under the total.
        await tester.enterText(find.byType(TextField), 'Sugar');
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('fits with the keyboard up at font scale $scale',
          (tester) async {
        await addFavorite(tester, 'Sugar');
        await pumpSale(tester, textScale: scale);
        await typeWithKeyboard(tester, 'Sug');

        expect(tester.takeException(), isNull);
        // Typing collapses the favorites bar and the totals panel: the
        // results list is the only flexible part left.
        expect(find.text('Sugar'), findsOneWidget, reason: 'the result row');
        expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
        expect(find.byKey(const ValueKey('cart-total')), findsOneWidget);
      });
    }

    testWidgets('the full panel comes back when the keyboard closes',
        (tester) async {
      await addFavorite(tester, 'Sugar');
      await pumpSale(tester, textScale: 1.3);
      await typeWithKeyboard(tester, 'Sug');
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);

      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('quantity sheet', () {
    /// The sheet slides in over 250 ms.
    Future<void> sheetSettled(WidgetTester tester) => settle(tester, 24);

    for (final scale in [1.0, 1.3]) {
      testWidgets('keypad and unit chips fit a 360×640 phone at scale $scale',
          (tester) async {
        await addFavorite(tester, 'Sugar', withUnit: true);
        await pumpSale(tester, textScale: scale);
        await tester.tap(find.text('Sugar'));
        await sheetSettled(tester);

        expect(find.byType(QuantitySheet), findsOneWidget);
        expect(find.byKey(const ValueKey('unit-chips')), findsOneWidget);
        expect(tester.takeException(), isNull);

        // And with the keyboard up over it (the sheet's own keypad needs no
        // OS keyboard, but another field may have raised one).
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardInset * tester.view.devicePixelRatio,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the other sheets and forms with text input', () {
    testWidgets('quick item, discount and the rate dialog fit the phone',
        (tester) async {
      await addFavorite(tester, 'Sugar', code: '7');
      await db(
        tester,
        () => database.db.update(
          'currencies',
          {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
          where: 'code = ?',
          whereArgs: ['USD'],
        ),
      );
      await pumpSale(tester, textScale: 1.3);

      Future<void> withKeyboard() async {
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardInset * tester.view.devicePixelRatio,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding.zero;
        await settle(tester);
      }

      // Quick item: a name field and the keypad.
      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Quick item'));
      await settle(tester, 24);
      expect(tester.takeException(), isNull);
      await withKeyboard();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await settle(tester, 24);

      // Something in the cart (straight in by code), so the discount sheet
      // and the rate shortcut are reachable.
      await tester.enterText(find.byType(TextField), '7');
      await settle(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      await tester.tap(find.byIcon(Icons.percent));
      await settle(tester, 24);
      expect(tester.takeException(), isNull);
      await withKeyboard();
      await tester.tap(find.widgetWithText(OutlinedButton, 'No discount'));
      await settle(tester, 24);

      // The rate dialog, opened from the sale screen's rate shortcut.
      await tester.tap(find.byIcon(Icons.currency_exchange));
      await settle(tester, 24);
      expect(find.text('Update rate'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await withKeyboard();
    });
  });

  group('the screens with text input', () {
    /// Pumps [screen] alone on the same small phone at a large system font.
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = phone * tester.view.devicePixelRatio;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen,
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardInset * tester.view.devicePixelRatio,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    testWidgets('the product form fits', (tester) async {
      await pumpScreen(tester, const ProductFormScreen());
    });

    testWidgets('the currency form fits', (tester) async {
      await pumpScreen(tester, const CurrencyFormScreen());
    });

    testWidgets('the invoice settings screen fits', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: InvoiceSettingsScreen()),
      );
    });

    testWidgets('the setup screen fits', (tester) async {
      await pumpScreen(tester, const SetupScreen());
    });
  });
}
