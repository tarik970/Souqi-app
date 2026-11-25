import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/widgets/numeric_input.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/quick_item_sheet.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// "The first keystroke replaces the value": every numeric entry in the app,
/// whether it is typed on the quantity sheet's own keypad or on the OS
/// keyboard, must treat the value it opened with as selected. A line that
/// says 1 and is typed 5 into becomes 5, not 15 — the seller is restating
/// the number, not continuing it. Keystrokes after the first append as
/// usual, so 1 then 2 still gives 12.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // A tap that lands on nothing must fail the test instead of letting it
    // pass against an untouched screen.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;

  // The sale screen reads a real sqflite database, whose futures only make
  // progress inside runAsync; pumpAndSettle would wait forever on the
  // loading spinner, so real async and pumped frames are interleaved.
  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// A sheet slides in over 250 ms; its lowest buttons only take a tap once
  /// it has stopped moving.
  Future<void> sheetSettled(WidgetTester tester) => settle(tester, 24);

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
    int? unitId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return database.db.insert('products', {
      'name': name,
      'name_norm': name.toLowerCase(),
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
    // for the keypad, so its buttons would fall off-screen.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(
            () => AppLocaleNotifier(const Locale('en')),
          ),
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

  Future<void> seedSugar(WidgetTester tester) async {
    final unitId = await db(tester, () => insertUnit(database.db));
    await db(
      tester,
      () => insertFavorite('Sugar', priceMinor: 1000, unitId: unitId),
    );
    await pumpSale(tester);
  }

  /// Presses keypad keys in order; 'backspace' names itself, every other
  /// entry is a digit or '.'.
  Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
    for (final key in keys) {
      final id = key == '.' ? 'separator' : key;
      await tester.tap(find.byKey(ValueKey('keypad-$id')));
      await tester.pump();
    }
    await settle(tester, 2);
  }

  /// Types a number on the keypad, one character at a time: '2.5' is the
  /// 2 key, the decimal key and the 5 key.
  Future<void> tapDigits(WidgetTester tester, String digits) =>
      tapKeys(tester, digits.split(''));

  /// The number the sheet is showing in the quantity / unit-price field.
  String shownQty(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('qty-value'))).data!;

  String shownPrice(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('price-value'))).data!;

  String cartLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('cart-line-detail-1')))
      .data!;

  setUp(() async => database = await openTestDb());
  tearDown(() async => database.close());

  /// Puts one Sugar line in the cart, with [qtyDigits] typed on the keypad
  /// when given (otherwise the prefilled quantity 1).
  Future<void> addSugarLine(
    WidgetTester tester, {
    String qtyDigits = '',
  }) async {
    await tester.tap(find.text('Sugar'));
    await sheetSettled(tester);
    if (qtyDigits.isNotEmpty) await tapDigits(tester, qtyDigits);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);
  }

  /// Taps the cart row: the quantity sheet re-opens on an existing line,
  /// which is the path the bug was reported on.
  Future<void> openCartLine(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ListTile, 'Sugar'));
    await sheetSettled(tester);
    expect(find.byType(QuantitySheet), findsOneWidget);
  }

  group('quantity sheet keypad', () {
    testWidgets('a line that says 1, typed 5 into, becomes 5 — not 15',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      expect(cartLine(tester), '1 × 1,000 ل.س');

      await openCartLine(tester);
      expect(shownQty(tester), '1');

      await tapDigits(tester, '5');
      expect(shownQty(tester), '5');

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await settle(tester);
      expect(cartLine(tester), '5 × 1,000 ل.س');
    });

    testWidgets('a line that says 2.5, typed 3 into, becomes 3',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester, qtyDigits: '2.5');
      expect(cartLine(tester), '2.5 × 1,000 ل.س');

      await openCartLine(tester);
      expect(shownQty(tester), '2.5');

      await tapDigits(tester, '3');
      expect(shownQty(tester), '3');

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await settle(tester);
      expect(cartLine(tester), '3 × 1,000 ل.س');
    });

    testWidgets('only the FIRST key replaces: 1 then 2 gives 12',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);

      await tapDigits(tester, '12');
      expect(shownQty(tester), '12');

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await settle(tester);
      expect(cartLine(tester), '12 × 1,000 ل.س');
    });

    testWidgets('a decimal still types through after the first key',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);

      // 3 replaces the 1, then ".5" is appended to it.
      await tapDigits(tester, '3.5');
      expect(shownQty(tester), '3.5');
    });

    testWidgets('tapping the quantity field again arms the replace',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);

      await tapDigits(tester, '12');
      expect(shownQty(tester), '12');

      // Tapping the field is the seller starting that number over.
      await tester.tap(find.byKey(const ValueKey('qty-field')));
      await settle(tester, 2);
      await tapDigits(tester, '7');
      expect(shownQty(tester), '7');
    });

    testWidgets('the unit price replaces its prefilled value too',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);
      expect(shownPrice(tester), '1000');

      await tester.tap(find.byKey(const ValueKey('price-field')));
      await settle(tester, 2);
      await tapDigits(tester, '2');
      expect(shownPrice(tester), '2');

      // Switching back to the quantity re-selects it in turn.
      await tester.tap(find.byKey(const ValueKey('qty-field')));
      await settle(tester, 2);
      await tapDigits(tester, '4');
      expect(shownQty(tester), '4');

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await settle(tester);
      expect(cartLine(tester), '4 × 2 ل.س');
    });

    testWidgets('backspace on the selected value clears it to empty',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester, qtyDigits: '2.5');
      await openCartLine(tester);
      expect(shownQty(tester), '2.5');

      await tapKeys(tester, ['backspace']);
      // Cleared outright, not nibbled down to "2.": the field is empty and
      // shows its 0 placeholder, so typing starts fresh.
      expect(shownQty(tester), '0');
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Update'),
        ).onPressed,
        isNull,
        reason: 'an empty quantity cannot be saved',
      );

      await tapDigits(tester, '4');
      expect(shownQty(tester), '4');
    });

    testWidgets('backspace after the first key deletes one digit',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);

      await tapDigits(tester, '12');
      await tapKeys(tester, ['backspace']);
      expect(shownQty(tester), '1');
    });

    testWidgets('the value is shown selected until the first key',
        (tester) async {
      await seedSugar(tester);
      await addSugarLine(tester);
      await openCartLine(tester);

      // Highlighted while the next key would replace it...
      expect(find.byKey(const ValueKey('qty-selected')), findsOneWidget);
      // ...and only the field the keypad types into is highlighted.
      expect(find.byKey(const ValueKey('price-selected')), findsNothing);

      await tapDigits(tester, '5');
      expect(find.byKey(const ValueKey('qty-selected')), findsNothing);

      // Re-tapping it selects the value again, highlight and all.
      await tester.tap(find.byKey(const ValueKey('qty-field')));
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('qty-selected')), findsOneWidget);
    });
  });

  group('quick item sheet', () {
    /// Opens Sale → menu → "Quick item".
    Future<void> openQuickItem(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<void>));
      await sheetSettled(tester);
      await tester.tap(find.text('Quick item'));
      await sheetSettled(tester);
      expect(find.byType(QuickItemSheet), findsOneWidget);
    }

    testWidgets('its quantity field opens on 1 with the 1 selected',
        (tester) async {
      await seedSugar(tester);
      await openQuickItem(tester);

      final qty = find.widgetWithText(TextFormField, 'Quantity');
      await tester.tap(qty);
      await settle(tester, 2);

      final controller = tester.widget<TextField>(
        find.descendant(of: qty, matching: find.byType(TextField)),
      ).controller!;
      expect(controller.text, '1');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
        reason: 'the whole value is selected, so the OS keyboard replaces it',
      );

      // What the keyboard then does with a keystroke.
      typeOnKeyboard(controller, '5');
      expect(controller.text, '5');
      typeOnKeyboard(controller, '0');
      expect(controller.text, '50', reason: 'later keystrokes append');
    });
  });

  group('SelectAllOnFocus', () {
    /// Builds a bare numeric field, wrapped the way every numeric field in
    /// the app is, and returns its controller.
    Future<TextEditingController> pumpField(
      WidgetTester tester, {
      required String initial,
      bool autofocus = false,
    }) async {
      final controller = TextEditingController(text: initial);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SelectAllOnFocus(
                  controller: controller,
                  child: TextField(
                    key: const ValueKey('field'),
                    controller: controller,
                    autofocus: autofocus,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const TextField(key: ValueKey('other')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    TextSelection whole(String text) =>
        TextSelection(baseOffset: 0, extentOffset: text.length);

    testWidgets('a tap selects the whole value', (tester) async {
      final controller = await pumpField(tester, initial: '1500');
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pumpAndSettle();

      expect(controller.selection, whole('1500'));
      typeOnKeyboard(controller, '2');
      expect(controller.text, '2');
    });

    testWidgets('autofocus selects the whole value', (tester) async {
      final controller =
          await pumpField(tester, initial: '2.5', autofocus: true);
      expect(controller.selection, whole('2.5'));
    });

    testWidgets('an empty field is left alone', (tester) async {
      final controller = await pumpField(tester, initial: '');
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(controller.selection.isCollapsed, isTrue);
    });

    testWidgets('coming back to the field selects the value again',
        (tester) async {
      final controller = await pumpField(tester, initial: '7');
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pumpAndSettle();
      typeOnKeyboard(controller, '9');
      expect(controller.text, '9');

      // Away to another field, then back.
      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pumpAndSettle();
      expect(controller.selection, whole('9'));
    });

    testWidgets('it does not take focus from the field it wraps',
        (tester) async {
      await pumpField(tester, initial: '1');
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.pumpAndSettle();

      // The wrapper only watches: the editable itself holds the focus, so
      // the keyboard opens and typing works as it always did.
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.widget.focusNode.hasPrimaryFocus, isTrue);
    });
  });
}

/// One keystroke from the OS keyboard: it replaces whatever is selected and
/// leaves the caret after what was typed. This is what the platform does
/// with the selection the app hands it, so a field whose value is selected
/// is a field whose next keystroke replaces it.
void typeOnKeyboard(TextEditingController controller, String key) {
  final selection = controller.selection;
  final start = selection.start < 0 ? controller.text.length : selection.start;
  final end = selection.end < 0 ? controller.text.length : selection.end;
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(start, end, key),
    selection: TextSelection.collapsed(offset: start + key.length),
  );
}
