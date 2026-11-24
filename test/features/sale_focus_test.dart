import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The search field must survive the keyboard.
///
/// The layout that keeps the sale screen from overflowing swaps the favorites
/// bar and the totals panel out while the keyboard is up. When that swap
/// changed the Column's children list, the search field moved to another
/// index, Flutter rebuilt it from scratch, and the keyboard it had just
/// opened closed again — on the phone the field could not be typed into at
/// all. These tests pin the field's state, its focus and its typing across
/// that change.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;

  /// Found by TYPE, not by key: the test must still catch the field being
  /// rebuilt if a later change drops the key that also pins it in place.
  final searchField = find.byType(TextField);

  /// A small phone, where the keyboard leaves the least room.
  const phone = Size(360, 640);
  const keyboardInset = 300.0;

  setUp(() async => database = await openTestDb());
  tearDown(() async => database.close());

  /// The sale screen reads from a real sqflite database, whose futures only
  /// progress inside [WidgetTester.runAsync]; pumpAndSettle would wait on the
  /// loading spinner forever.
  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

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

  Future<void> addFavorite(WidgetTester tester, String name) async {
    final result = await tester.runAsync(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return database.db.insert('products', {
        'name': name,
        'name_norm': name.toLowerCase(),
        'kind': 'GOODS',
        'price_minor': 1500,
        'currency_code': 'SYP',
        'is_favorite': 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    });
    if (result == null) throw StateError('insert did not run');
  }

  /// The screen's own FocusNode, read off the live TextField.
  FocusNode focusOf(WidgetTester tester) =>
      tester.widget<TextField>(searchField).focusNode!;

  /// Raises the keyboard the way the platform does: the field takes focus
  /// first, the inset arrives afterwards.
  Future<void> raiseKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardInset * tester.view.devicePixelRatio,
    );
    await settle(tester);
  }

  testWidgets('tapping the field focuses it and the keyboard opens',
      (tester) async {
    await addFavorite(tester, 'Sugar');
    await pumpSale(tester);

    await tester.tap(searchField);
    await settle(tester);

    expect(focusOf(tester).hasFocus, isTrue);
  });

  testWidgets('the field keeps its state and its focus when the keyboard opens',
      (tester) async {
    await addFavorite(tester, 'Sugar');
    await pumpSale(tester);

    await tester.tap(searchField);
    await settle(tester);
    final before = tester.state(searchField);
    final node = focusOf(tester);
    expect(node.hasFocus, isTrue);

    await raiseKeyboard(tester);

    expect(
      tester.state(searchField),
      same(before),
      reason: 'the TextField was rebuilt from scratch by the layout change',
    );
    expect(identical(focusOf(tester), node), isTrue,
        reason: 'the FocusNode is owned by the State, never rebuilt');
    expect(node.hasFocus, isTrue);
    // The compact layout really did take over: the full panel's Save button
    // and the favorites bar are the two things it drops.
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.byKey(const ValueKey('cart-total')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing with the keyboard up reaches the field', (tester) async {
    await addFavorite(tester, 'Sugar');
    await pumpSale(tester);

    await tester.tap(searchField);
    await settle(tester);
    await raiseKeyboard(tester);

    await tester.enterText(searchField, 'Sug');
    await settle(tester);

    expect(
      tester.widget<TextField>(searchField).controller!.text,
      'Sug',
    );
    expect(focusOf(tester).hasFocus, isTrue);
    // Letter by letter, the way the seller types: each keystroke rebuilds
    // the results list, and the field must not lose focus to it.
    await tester.enterText(searchField, 'Suga');
    await settle(tester);
    await tester.enterText(searchField, 'Sugar');
    await settle(tester);

    expect(focusOf(tester).hasFocus, isTrue);
    expect(find.text('Sugar'), findsWidgets, reason: 'the result row');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the keyboard-open layout does not flap', (tester) async {
    await addFavorite(tester, 'Sugar');
    await pumpSale(tester);

    await tester.tap(searchField);
    await settle(tester);
    await raiseKeyboard(tester);
    final state = tester.state(searchField);

    // Several frames with the keyboard up: the field is the same one, still
    // focused, and nothing swings the layout back and forth.
    for (var i = 0; i < 6; i++) {
      await settle(tester, 4);
      expect(focusOf(tester).hasFocus, isTrue, reason: 'frame $i');
      expect(tester.state(searchField), same(state),
          reason: 'frame $i');
      expect(find.byKey(const ValueKey('cart-total')), findsOneWidget,
          reason: 'frame $i');
      expect(tester.takeException(), isNull, reason: 'frame $i');
    }
  });

  testWidgets('focus survives the keyboard closing again', (tester) async {
    await addFavorite(tester, 'Sugar');
    await pumpSale(tester);

    await tester.tap(searchField);
    await settle(tester);
    await raiseKeyboard(tester);
    final state = tester.state(searchField);

    tester.view.viewInsets = FakeViewPadding.zero;
    await settle(tester);

    expect(tester.state(searchField), same(state));
    expect(focusOf(tester).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
