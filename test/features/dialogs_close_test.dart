import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/currencies/currencies_screen.dart';
import 'package:souqi/features/currencies/currency_form_screen.dart';
import 'package:souqi/features/currencies/update_rate_dialog.dart';
import 'package:souqi/features/invoice/invoice_actions.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/products/products_screen.dart';
import 'package:souqi/features/sale/discount_sheet.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/quick_item_sheet.dart';
import 'package:souqi/features/sale/rates_sheet.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/units/units_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// How a dialog, sheet or page is dismissed without saving.
enum CloseBy {
  /// Its own Cancel / Close / back-arrow button.
  button,

  /// A tap on the dimmed area around it.
  outside,

  /// The Android back button.
  back,
}

typedef Step = Future<void> Function(WidgetTester tester);

/// One dialog, bottom sheet or pushed page, and how to get it on screen.
class Closable {
  const Closable(
    this.name, {
    required this.home,
    this.seed,
    required this.open,
    required this.shown,
    this.button,
    this.keyboard = false,
    this.isPage = false,
    this.after,
  });

  final String name;

  /// The screen it is opened from.
  final Widget home;

  /// Rows the screen needs, inserted before it is pumped.
  final Future<void> Function(AppDatabase database)? seed;

  final Step open;

  /// Matches only while it is on screen.
  final Finder shown;

  /// Its Cancel / Close button; null when it has none.
  final Finder? button;

  /// It has a text field that takes focus: the soft keyboard is up while it
  /// is open and slides away while it closes.
  final bool keyboard;

  /// A full page: there is nothing "outside" it to tap.
  final bool isPage;

  /// Extra checks once it is closed.
  final Step? after;
}

/// Every dialog, bottom sheet and form page in the app is opened and then
/// dismissed three ways — its own button, a tap outside, the Android back
/// button — and none of them may throw.
///
/// This guards a crash seen on a phone: Cancel in the "update rate" dialog
/// raised `'_dependents.isEmpty': is not true`. The dialog's text controller
/// was disposed by the code that opened it as soon as `showDialog` returned,
/// while the dialog was still on screen for its exit animation; the text
/// field then rebuilt on a disposed controller. The tests therefore keep
/// pumping frames through the whole exit animation, and take the keyboard
/// away in the middle of it, exactly as a phone does.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;
  late FakeNativeBridge bridge;

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Long enough for a dialog or sheet to finish sliding in or out; a page
  /// transition takes longer, so keep going while an animation is running.
  Future<void> animated(WidgetTester tester) async {
    await settle(tester, 28);
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await settle(tester, 4);
    }
  }

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider
              .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
          nativeBridgeProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  /// Dismisses what is open and plays the exit animation to its end.
  Future<void> close(WidgetTester tester, Closable target, CloseBy by) async {
    switch (by) {
      case CloseBy.button:
        await tester.tap(target.button!);
      case CloseBy.outside:
        await tester.tapAt(const Offset(6, 6));
      case CloseBy.back:
        await tester.binding.handlePopRoute();
    }
    // First frame of the exit animation: the route is popped, the widgets
    // are still on screen.
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The field lost focus, so the keyboard goes away mid-animation.
    tester.view.resetViewInsets();
    await animated(tester);
    expect(tester.takeException(), isNull);
    expect(target.shown, findsNothing);
  }

  // --- Seeds -------------------------------------------------------------

  Future<void> rateUsd(AppDatabase database) => database.db.update(
        'currencies',
        {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );

  Future<void> rateUsdAndTry(AppDatabase database) async {
    await rateUsd(database);
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
  }

  /// One archived sale, so the archive screen has a row to open.
  Future<void> archivedSale(AppDatabase database) async {
    final id = await insertInvoice(database.db, invoiceNo: 1);
    await insertInvoiceItem(database.db, invoiceId: id, name: 'Sugar');
  }

  Future<void> sugar(AppDatabase database) async {
    final id = await insertProduct(database.db, name: 'Sugar', code: '101');
    await database.db.update('products', {'is_favorite': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // --- Ways in -----------------------------------------------------------

  Future<void> openSaleMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byType(PopupMenuButton<void>));
    await animated(tester);
    await tester.tap(find.text(item));
    await animated(tester);
  }

  Future<void> addSugarToCart(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '101');
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  /// Opens the "⋮" menu of the list row titled [title] and picks [item].
  Future<void> openRowMenu(
    WidgetTester tester,
    String title,
    String item,
  ) async {
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byType(PopupMenuButton<void>),
    ));
    await animated(tester);
    await tester.tap(find.text(item));
    await animated(tester);
  }

  const rateButton = '1 USD = 13,000 SYP';
  final alert = find.byType(AlertDialog);
  final cancel = find.text('Cancel');
  final actions = Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: InvoiceActions(invoice: sypInvoice()),
    ),
  );

  final targets = <Closable>[
    // The one that crashed on the phone.
    Closable(
      'update-rate dialog, from the sale screen',
      home: const SaleScreen(),
      seed: rateUsd,
      open: (tester) async {
        await tester.tap(find.text(rateButton));
        await animated(tester);
      },
      shown: find.byType(UpdateRateDialog),
      button: cancel,
      keyboard: true,
    ),
    Closable(
      'update-rate dialog, from the currencies screen',
      home: const CurrenciesScreen(),
      open: (tester) =>
          openRowMenu(tester, 'US Dollar (USD)', 'Update rate'),
      shown: find.byType(UpdateRateDialog),
      button: cancel,
      keyboard: true,
    ),
    Closable(
      'exchange-rates sheet',
      home: const SaleScreen(),
      seed: rateUsdAndTry,
      open: (tester) async {
        await tester.tap(find.text(rateButton));
        await animated(tester);
      },
      shown: find.byType(RatesSheet),
    ),
    Closable(
      'update-rate dialog, on top of the exchange-rates sheet',
      home: const SaleScreen(),
      seed: rateUsdAndTry,
      open: (tester) async {
        await tester.tap(find.text(rateButton));
        await animated(tester);
        await tester.tap(find.text('1 TRY = 400 SYP'));
        await animated(tester);
      },
      shown: find.byType(UpdateRateDialog),
      button: cancel,
      keyboard: true,
      // Only the dialog closed; the sheet under it is untouched.
      after: (tester) async => expect(find.byType(RatesSheet), findsOneWidget),
    ),
    Closable(
      'unit name dialog (add)',
      home: const UnitsScreen(),
      open: (tester) async {
        await tester.tap(find.text('Add unit'));
        await animated(tester);
      },
      shown: alert,
      button: cancel,
      keyboard: true,
    ),
    Closable(
      'unit name dialog (edit)',
      home: const UnitsScreen(),
      seed: (database) => insertUnit(database.db),
      open: (tester) async {
        await tester.tap(find.byTooltip('Edit'));
        await animated(tester);
      },
      shown: alert,
      button: cancel,
      keyboard: true,
    ),
    Closable(
      'delete-unit confirmation',
      home: const UnitsScreen(),
      seed: (database) => insertUnit(database.db),
      open: (tester) async {
        await tester.tap(find.byTooltip('Delete'));
        await animated(tester);
      },
      shown: alert,
      button: cancel,
      after: (tester) async => expect(find.byTooltip('Delete'), findsOneWidget),
    ),
    Closable(
      'quantity sheet',
      home: const SaleScreen(),
      seed: sugar,
      open: (tester) async {
        await tester.tap(find.text('Sugar'));
        await animated(tester);
      },
      shown: find.byType(QuantitySheet),
      button: find.widgetWithText(OutlinedButton, 'Cancel'),
      after: (tester) async => expect(find.text('Cart is empty'), findsOneWidget),
    ),
    Closable(
      'new-item sheet with "More" open',
      home: const SaleScreen(),
      open: (tester) async {
        await tester.enterText(find.byType(TextField), 'Bread');
        await settle(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await animated(tester);
        await tester.tap(find.byKey(const ValueKey('new-item-more')));
        await settle(tester, 4);
      },
      shown: find.byType(QuantitySheet),
      button: find.widgetWithText(OutlinedButton, 'Cancel'),
    ),
    Closable(
      'quick item sheet',
      home: const SaleScreen(),
      open: (tester) => openSaleMenu(tester, 'Quick item'),
      shown: find.byType(QuickItemSheet),
      button: find.widgetWithText(OutlinedButton, 'Cancel'),
      keyboard: true,
      after: (tester) async => expect(find.text('Cart is empty'), findsOneWidget),
    ),
    Closable(
      'discount sheet',
      home: const SaleScreen(),
      seed: sugar,
      open: (tester) async {
        await addSugarToCart(tester);
        await tester.tap(find.text('Invoice discount'));
        await animated(tester);
      },
      shown: find.byType(DiscountSheet),
      // The sheet's way out without a discount.
      button: find.widgetWithText(OutlinedButton, 'No discount'),
      keyboard: true,
      after: (tester) async =>
          expect(find.text('Invoice discount'), findsOneWidget),
    ),
    Closable(
      'secondary-total dialog',
      home: const SaleScreen(),
      seed: rateUsd,
      open: (tester) => openSaleMenu(tester, 'Secondary total'),
      shown: alert,
      button: find.text('Done'),
    ),
    Closable(
      'clear-cart confirmation',
      home: const SaleScreen(),
      seed: sugar,
      open: (tester) async {
        await addSugarToCart(tester);
        await openSaleMenu(tester, 'Clear cart');
      },
      shown: alert,
      button: cancel,
      // Not confirmed: the line is still in the cart.
      after: (tester) async =>
          expect(find.widgetWithText(ListTile, 'Sugar'), findsOneWidget),
    ),
    Closable(
      'printer picker',
      home: const InvoiceSettingsScreen(),
      open: (tester) async {
        await tester.tap(find.text('Choose printer'));
        await animated(tester);
      },
      shown: alert,
      button: cancel,
    ),
    Closable(
      'full-size invoice preview',
      home: const InvoiceSettingsScreen(),
      open: (tester) async {
        await tester.tap(find.byIcon(Icons.fullscreen));
        await animated(tester);
      },
      shown: find.byType(Dialog),
      button: find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close),
      ),
    ),
    Closable(
      'more-actions sheet of a saved invoice',
      home: actions,
      open: (tester) async {
        await tester.tap(find.byKey(const ValueKey('invoice-more')));
        await animated(tester);
      },
      shown: find.byKey(const ValueKey('invoice-more-savePdf')),
    ),
    Closable(
      'WhatsApp number dialog',
      home: actions,
      open: (tester) async {
        await tester.tap(find.byKey(const ValueKey('invoice-more')));
        await animated(tester);
        await tester.tap(find.byKey(const ValueKey('invoice-more-whatsApp')));
        await animated(tester);
      },
      shown: alert,
      button: cancel,
      keyboard: true,
      // The action ended: its buttons are enabled again.
      after: (tester) async => expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('invoice-more')))
            .onPressed,
        isNotNull,
      ),
    ),
    Closable(
      'delete-product confirmation',
      home: const ProductsScreen(),
      seed: sugar,
      open: (tester) => openRowMenu(tester, 'Sugar', 'Delete'),
      shown: alert,
      button: cancel,
      after: (tester) async =>
          expect(find.widgetWithText(ListTile, 'Sugar'), findsOneWidget),
    ),
    Closable(
      'change-base-currency confirmation',
      home: const CurrenciesScreen(),
      open: (tester) =>
          openRowMenu(tester, 'US Dollar (USD)', 'Set as base currency'),
      shown: alert,
      button: cancel,
    ),
    Closable(
      'currency form',
      home: const CurrenciesScreen(),
      open: (tester) async {
        await tester.tap(find.text('Add currency'));
        await animated(tester);
        await tester.tap(find.byType(TextFormField).first);
        await settle(tester, 4);
      },
      shown: find.byType(CurrencyFormScreen),
      button: find.byType(BackButton),
      keyboard: true,
      isPage: true,
    ),
    // --- Phase 4: the archive, its deletions and the retention picker ---
    Closable(
      'delete-range confirmation in the archive',
      home: const ArchiveScreen(),
      seed: archivedSale,
      open: (tester) async {
        await tester.tap(find.byType(PopupMenuButton<void>));
        await animated(tester);
        await tester.tap(find.text('Delete these invoices'));
        await animated(tester);
      },
      shown: find.byKey(const ValueKey('archive-delete-range-dialog')),
      button: cancel,
      // Not confirmed: the invoice is still in the list.
      after: (tester) async => expect(
        find.byKey(const ValueKey('archive-invoice-1')),
        findsOneWidget,
      ),
    ),
    Closable(
      'archived invoice detail page',
      home: const ArchiveScreen(),
      seed: archivedSale,
      open: (tester) async {
        await tester.tap(find.byKey(const ValueKey('archive-invoice-1')));
        await animated(tester);
      },
      shown: find.byType(InvoiceDetailScreen),
      button: find.byType(BackButton),
      isPage: true,
    ),
    Closable(
      'delete-invoice confirmation',
      home: const ArchiveScreen(),
      seed: archivedSale,
      open: (tester) async {
        await tester.tap(find.byKey(const ValueKey('archive-invoice-1')));
        await animated(tester);
        await tester.tap(find.byKey(const ValueKey('archive-delete-invoice')));
        await animated(tester);
      },
      shown: find.byKey(const ValueKey('delete-invoice-dialog')),
      button: cancel,
      // Not confirmed: the invoice is still open behind the dialog.
      after: (tester) async =>
          expect(find.byType(InvoiceDetailScreen), findsOneWidget),
    ),
    Closable(
      'retention custom-days dialog',
      home: const SettingsScreen(),
      open: (tester) async {
        await tester.tap(
          find.byKey(const ValueKey('setting-auto-delete-dropdown')),
        );
        await animated(tester);
        await tester.tap(find.text('Custom…').last);
        await animated(tester);
      },
      shown: alert,
      button: cancel,
      keyboard: true,
    ),
    Closable(
      'product form',
      home: const ProductsScreen(),
      seed: sugar,
      open: (tester) async {
        await tester.tap(find.text('Add product'));
        await animated(tester);
        await tester.tap(find.byType(TextFormField).first);
        await settle(tester, 4);
      },
      shown: find.byType(ProductFormScreen),
      button: find.byType(BackButton),
      keyboard: true,
      isPage: true,
    ),
  ];

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
  });

  tearDown(() async => database.close());

  for (final target in targets) {
    group(target.name, () {
      for (final by in CloseBy.values) {
        if (by == CloseBy.button && target.button == null) continue;
        if (by == CloseBy.outside && target.isPage) continue;

        testWidgets('closes by ${by.name}', (tester) async {
          final seed = target.seed;
          if (seed != null) {
            await tester.runAsync(() => seed(database));
          }
          await pumpHome(tester, target.home);

          await target.open(tester);
          expect(tester.takeException(), isNull);
          expect(target.shown, findsOneWidget);
          if (target.keyboard) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 560);
            await settle(tester, 4);
          }

          await close(tester, target, by);
          await target.after?.call(tester);

          // And it opens and closes a second time: nothing was left behind
          // disposed or half torn down.
          if (!target.isPage && target.after == null) {
            await target.open(tester);
            expect(target.shown, findsOneWidget);
            await close(tester, target, by);
          }
        });
      }
    });
  }

  group('the dialogs still do their job', () {
    final dialogSave = find.descendant(
      of: find.byType(UpdateRateDialog),
      matching: find.text('Save'),
    );

    testWidgets('a rate typed into the dialog is saved', (tester) async {
      await tester.runAsync(() => rateUsd(database));
      await pumpHome(tester, const SaleScreen());
      await tester.tap(find.text(rateButton));
      await animated(tester);

      // Not a number: the dialog stays open and says so.
      await tester.enterText(find.byType(TextField).last, 'abc');
      await tester.tap(dialogSave);
      await settle(tester);
      expect(find.text('Invalid exchange rate'), findsOneWidget);
      expect(find.byType(UpdateRateDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '14500');
      await tester.tap(dialogSave);
      await tester.pump();
      tester.view.resetViewInsets();
      await animated(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(UpdateRateDialog), findsNothing);
      final usd = await db(
        tester,
        () async => (await database.db
                .query('currencies', where: 'code = ?', whereArgs: ['USD']))
            .single,
      );
      expect(usd['rate_num'], 14500);
      expect(usd['rate_den'], 1);
      // The sale screen shows the new rate straight away.
      expect(find.text('1 USD = 14,500 SYP'), findsOneWidget);
    });

    testWidgets('Enter on the keyboard saves the rate too', (tester) async {
      await pumpHome(tester, const CurrenciesScreen());
      await openRowMenu(tester, 'US Dollar (USD)', 'Update rate');
      await tester.enterText(find.byType(TextField), '13000.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await animated(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(UpdateRateDialog), findsNothing);
      expect(find.textContaining('1 USD = 13,000.5 SYP'), findsOneWidget);
    });

    testWidgets('a rate saved from the list inside the sheet updates the list',
        (tester) async {
      await tester.runAsync(() => rateUsdAndTry(database));
      await pumpHome(tester, const SaleScreen());
      await tester.tap(find.text(rateButton));
      await animated(tester);
      await tester.tap(find.text('1 TRY = 400 SYP'));
      await animated(tester);
      await tester.enterText(find.byType(TextField).last, '425');
      await tester.tap(dialogSave);
      await animated(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(RatesSheet), findsOneWidget);
      expect(find.text('1 TRY = 425 SYP'), findsOneWidget);
    });

    testWidgets('a unit can be added and renamed', (tester) async {
      await pumpHome(tester, const UnitsScreen());
      await tester.tap(find.text('Add unit'));
      await animated(tester);
      await tester.enterText(find.byType(TextField), '  Dozen ');
      await tester.tap(find.text('Save'));
      await animated(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Dozen'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await animated(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Dozen',
      );
      await tester.enterText(find.byType(TextField), 'Carton');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await animated(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Carton'), findsOneWidget);
      expect(find.text('Dozen'), findsNothing);
    });

    testWidgets('an empty unit name adds nothing', (tester) async {
      await pumpHome(tester, const UnitsScreen());
      final before = find.byType(ListTile).evaluate().length;
      await tester.tap(find.text('Add unit'));
      await animated(tester);
      await tester.tap(find.text('Save'));
      await animated(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(ListTile).evaluate().length, before);
    });
  });
}
