import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/security/pin_hash.dart';
import 'package:souqi/core/utils/due_dates.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/currencies/currency_form_screen.dart';
import 'package:souqi/features/customers/account_form_screen.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:souqi/features/customers/customer_form_screen.dart';
import 'package:souqi/features/customers/customer_picker_screen.dart';
import 'package:souqi/features/customers/customers_screen.dart';
import 'package:souqi/features/customers/due_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/products/products_screen.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/security/audit_log_screen.dart';
import 'package:souqi/features/security/pin_dialogs.dart';
import 'package:souqi/features/security/pin_recovery.dart';
import 'package:souqi/features/settings/renewal_settings.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/setup/setup_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/features/vouchers/add_batch_screen.dart';
import 'package:souqi/features/vouchers/card_stock_screen.dart';
import 'package:souqi/features/vouchers/code_lookup_screen.dart';
import 'package:souqi/features/vouchers/code_widgets.dart';
import 'package:souqi/features/vouchers/expired_codes_screen.dart';
import 'package:souqi/features/vouchers/product_stock_screen.dart';
import 'package:souqi/features/vouchers/voucher_providers.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

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

  /// The first scrollable that scrolls DOWN. On a page with tabs (the
  /// customer page, since the debt ledger) the first scrollable in the tree
  /// is the tab view itself, which scrolls sideways.
  Finder verticalScrollable() => find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;

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

  group('customers, accounts and renewals', () {
    // Names as long as real ones get, so the rows have to wrap or ellipsize
    // rather than overflow.
    const longName = 'عبد الرحمن محمد الأحمد الحسن الطويل';
    const longProvider = 'السورية للاتصالات والإنترنت';
    const longPackage = 'ADSL 8 Mbps unlimited monthly renewal';

    late int customerId;
    late int accountId;
    late int packageId;

    /// A customer with two accounts (one overdue, one due today), a package
    /// that requires an account, and a second customer.
    Future<void> seedCustomers(WidgetTester tester) async {
      await db(tester, () async {
        final customers = CustomerRepository(database.db);
        final now = DateTime.now().millisecondsSinceEpoch;
        packageId = await database.db.insert('products', {
          'name': longPackage,
          'name_norm': longPackage.toLowerCase(),
          'code': '201',
          'kind': 'SERVICE',
          'price_minor': 3500000,
          'currency_code': 'SYP',
          'requires_account': 1,
          'created_at': now,
          'updated_at': now,
        });
        customerId = await customers.insert(const Customer(
          name: longName,
          phone: '+963 944 123 456',
          notes: 'يدفع في أول كل شهر، المحل المقابل للصيدلية',
        ));
        final lastRenewal = DateTime.now().subtract(const Duration(days: 40));
        accountId = await customers.insertAccount(CustomerAccount(
          customerId: customerId,
          accountNumber: '0011-2233-4455-6677',
          label: 'ADSL line',
          provider: longProvider,
          defaultProductId: packageId,
          renewalDays: 30,
          lastRenewalAt: lastRenewal,
          nextDueAt: nextDueAfter(lastRenewal, 30),
        ));
        await customers.insertAccount(CustomerAccount(
          customerId: customerId,
          accountNumber: 'AB-7700',
          provider: 'MTN',
          renewalDays: 30,
          lastRenewalAt: DateTime.now().subtract(const Duration(days: 30)),
          nextDueAt: nextDueAfter(DateTime.now(), 0),
        ));
        await customers
            .insert(const Customer(name: 'Samer', phone: '0933 555 111'));
        return true;
      });
    }

    /// Pumps [screen] on the 360×640 phone at font scale 1.3 and checks it,
    /// then raises the keyboard and checks it again.
    Future<void> pumpPhone(
      WidgetTester tester,
      Widget screen, {
      bool keyboard = true,
      String locale = 'en',
    }) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = phone * tester.view.devicePixelRatio;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(Locale(locale))),
          ],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen,
          ),
        ),
      );
      await settle(tester, 24);
      expect(tester.takeException(), isNull);
      if (!keyboard) return;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardInset * tester.view.devicePixelRatio,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    /// Scrolls the page until [target] is built and on screen. The forms
    /// are lazy lists: what is below the fold does not exist yet.
    Future<void> reach(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        120,
        scrollable: verticalScrollable(),
      );
      await settle(tester, 4);
    }

    Future<void> keyboardUp(WidgetTester tester) async {
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardInset * tester.view.devicePixelRatio,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    Future<void> keyboardDown(WidgetTester tester) async {
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    Future<void> setShopType(WidgetTester tester, String type) => db(
          tester,
          () async {
            await database.db.insert('settings', {
              'key': SettingsKeys.shopType,
              'value': type,
              'updated_at': 0,
            });
            return true;
          },
        );

    final searchBox = find.byKey(const ValueKey('quick-search-field'));

    testWidgets('the home screen of a grocery shop fits', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(tester, const HomeScreen());
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('the home screen of a cards shop fits, with its renewals card',
        (tester) async {
      await seedCustomers(tester);
      await setShopType(tester, 'CARDS');
      await pumpPhone(tester, const HomeScreen());
      // With the keyboard up there are barely 200 px under the search box;
      // the renewals card and the tiles are one scroll away.
      tester.view.resetViewInsets();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-due'), skipOffstage: false),
          findsOneWidget);
      expect(find.byKey(const ValueKey('home-due-see-all'), skipOffstage: false),
          findsOneWidget);
      // The tiles below it scroll into view without overflowing.
      await tester.drag(find.byKey(const ValueKey('home-idle')),
          const Offset(0, -400));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quick search results fit under the keyboard', (tester) async {
      await seedCustomers(tester);
      await setShopType(tester, 'BOTH');
      await pumpPhone(tester, const HomeScreen(), keyboard: false);
      // Type first, then the keyboard — the order the phone does it in.
      await tester.enterText(searchBox, '٠٠١١');
      await settle(tester);
      await keyboardUp(tester);
      expect(find.text('Renew'), findsWidgets);
      await tester.enterText(searchBox, 'nobody at all');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await keyboardDown(tester);
    });

    testWidgets('the customers screen fits', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(tester, const CustomersScreen());
      await tester.enterText(
          find.byKey(const ValueKey('customers-search-field')), 'zzz');
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the customer form fits (new, with the first account)',
        (tester) async {
      await seedCustomers(tester);
      await pumpPhone(
        tester,
        const CustomerFormScreen(initialAccountNumber: '0011-2233-4455'),
      );
      // Every field, focused in turn with the keyboard up.
      for (final key in [
        'customer-name-field',
        'customer-phone-field',
        'customer-notes-field',
        'customer-account-number-field',
        'account-provider-field',
      ]) {
        await reach(tester, find.byKey(ValueKey(key)));
        await settle(tester, 4);
        await tester.tap(find.byKey(ValueKey(key)));
        await settle(tester, 4);
        expect(tester.takeException(), isNull, reason: key);
      }
      // Validation errors make the fields taller.
      await reach(tester, find.byKey(const ValueKey('customer-save')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the customer form fits (edit)', (tester) async {
      await seedCustomers(tester);
      final customer = await db(
        tester,
        () async => (await CustomerRepository(database.db).getById(customerId))!,
      );
      await pumpPhone(tester, CustomerFormScreen(customer: customer));
    });

    testWidgets('the account form fits (new and edit)', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(tester, AccountFormScreen(customerId: customerId));
      // The provider suggestions under the field.
      expect(find.byKey(const ValueKey('provider-suggestion-MTN')),
          findsOneWidget);
      await reach(tester, find.byKey(const ValueKey('account-save')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await settle(tester);
      expect(tester.takeException(), isNull);

      final account = await db(
        tester,
        () async =>
            (await CustomerRepository(database.db).getAccount(accountId))!,
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      await pumpPhone(
        tester,
        AccountFormScreen(customerId: customerId, account: account),
      );
      await reach(tester, find.byKey(const ValueKey('account-save')));
      await settle(tester, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the duplicate-number warning fits', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(
        tester,
        AccountFormScreen(customerId: customerId),
        keyboard: false,
      );
      await tester.enterText(
          find.byKey(const ValueKey('account-number-field')), 'ab 7700');
      await tester.enterText(
          find.byKey(const ValueKey('account-provider-field')), 'mtn');
      await keyboardUp(tester);
      await reach(tester, find.byKey(const ValueKey('account-save')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await settle(tester, 24);
      expect(find.byKey(const ValueKey('account-duplicate-dialog')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await keyboardDown(tester);
    });

    testWidgets('the date picker of the account form fits', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(
        tester,
        AccountFormScreen(customerId: customerId),
        keyboard: false,
      );
      await reach(tester, find.byKey(const ValueKey('account-last-renewal')));
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('account-last-renewal')));
      await settle(tester, 24);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the customer page fits', (tester) async {
      await seedCustomers(tester);
      // A purchase, so the history and the totals have something to show.
      await db(tester, () async {
        final id = await insertInvoice(
          database.db,
          invoiceNo: 1,
          subtotalMinor: 3500000,
          customerName: longName,
          accountNumber: '0011-2233-4455-6677',
        );
        await database.db.update('invoices', {'customer_id': customerId},
            where: 'id = ?', whereArgs: [id]);
        await insertInvoiceItem(database.db, invoiceId: id, name: longPackage);
        return true;
      });
      await pumpPhone(tester, CustomerDetailScreen(customerId: customerId));
      expect(find.byKey(const ValueKey('customer-call')), findsOneWidget);
      // Down to the history, and the confirmation over it.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('customer-invoice-1')),
        200,
        scrollable: verticalScrollable(),
      );
      await settle(tester, 4);
      expect(tester.takeException(), isNull);

      await keyboardDown(tester);
      await tester.tap(find.byKey(const ValueKey('customer-menu')));
      await settle(tester, 24);
      await tester.tap(find.text('Deactivate'));
      await settle(tester, 24);
      expect(find.byKey(const ValueKey('deactivate-customer-dialog')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the customer picker fits, with its "new customer" rows',
        (tester) async {
      await seedCustomers(tester);
      await pumpPhone(tester, const CustomerPickerScreen());
      // Digits: two "new customer" rows above the results.
      await tester.enterText(searchBox, '0011 2233 4455 6677');
      await settle(tester);
      expect(find.byKey(const ValueKey('new-customer-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-customer-accountNumber')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(searchBox, 'عبد الرحمن');
      await settle(tester);
      expect(find.text(longName, skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
      await keyboardDown(tester);
    });

    testWidgets('the due-for-renewal screen fits', (tester) async {
      await seedCustomers(tester);
      await pumpPhone(tester, const DueScreen());
      expect(find.text('Remind on WhatsApp', skipOffstage: false), findsWidgets);
      expect(find.text('Renew', skipOffstage: false), findsWidgets);
    });

    testWidgets('the due screen fits when nothing is due', (tester) async {
      await pumpPhone(tester, const DueScreen());
      expect(find.byKey(const ValueKey('due-empty')), findsOneWidget);
    });

    testWidgets(
        'the sale screen fits with a customer, a blocked product and a '
        'discount', (tester) async {
      await seedCustomers(tester);
      await addFavorite(tester, 'Sugar', code: '7');
      await pumpSale(tester, textScale: 1.3);
      Future<void> enter(String code) async {
        await tester.enterText(
            find.byKey(const ValueKey('sale-search-field')), code);
        await settle(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
      }

      // Goods and a package that needs an account: Save is blocked and the
      // panel carries the message and the "Choose account" button.
      await enter('7');
      await enter('201');
      expect(find.byKey(const ValueKey('account-required')), findsOneWidget);
      expect(find.byKey(const ValueKey('choose-account')), findsOneWidget);
      expect(find.byKey(const ValueKey('sale-save')), findsNothing);
      expect(find.byKey(const ValueKey('sale-customer-chip')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A customer with a long name on the chip, still with no account.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SaleScreen)),
      );
      container.read(saleCustomerProvider.notifier).attach(SaleCustomer(
            customerId: customerId,
            name: longName,
            phone: '+963 944 123 456',
          ));
      await settle(tester);
      expect(find.byKey(const ValueKey('account-required')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A discount on top: the panel at its tallest.
      await tester.tap(find.byIcon(Icons.percent));
      await settle(tester, 24);
      await tester.tap(find.widgetWithText(OutlinedButton, 'No discount'));
      await settle(tester, 24);
      container
          .read(cartProvider.notifier)
          .setDiscount(const Discount.percent(1000));
      await settle(tester);
      expect(find.byKey(const ValueKey('account-required')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // With the account (and its long number) attached.
      container.read(saleCustomerProvider.notifier).attach(SaleCustomer(
            customerId: customerId,
            name: longName,
            accountId: accountId,
            accountNumber: '0011-2233-4455-6677',
            accountProvider: longProvider,
          ));
      await settle(tester);
      expect(find.byKey(const ValueKey('account-required')), findsNothing);
      expect(tester.takeException(), isNull);

      // And with the keyboard up over it all.
      await tester.enterText(
          find.byKey(const ValueKey('sale-search-field')), 'Sug');
      await settle(tester);
      await keyboardUp(tester);
      await keyboardDown(tester);
    });

    testWidgets('the saved-invoice screen fits with the package offer',
        (tester) async {
      await seedCustomers(tester);
      await pumpPhone(
        tester,
        SaleInvoiceScreen(
          invoice: sypInvoice(customerPhone: '0944 123 456'),
          packageOffer: DefaultPackageOffer(
            accountId: accountId,
            productId: packageId,
            productName: longPackage,
          ),
        ),
        keyboard: false,
      );
      expect(find.byKey(const ValueKey('package-offer')), findsOneWidget);
      await reach(tester, find.byKey(const ValueKey('package-offer-accept')));
      await tester.tap(find.byKey(const ValueKey('package-offer-accept')));
      await settle(tester);
      expect(find.byKey(const ValueKey('package-offer-done')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('the whole settings screen fits, top to bottom ($locale)',
          (tester) async {
        // The longest shop type is the one that overflowed on a phone.
        await setShopType(tester, 'CARDS');
        await pumpPhone(
          tester,
          const SettingsScreen(),
          keyboard: false,
          locale: locale,
        );
        expect(
          find.byKey(const ValueKey('setting-shop-type-dropdown')),
          findsOneWidget,
        );

        // Every tile is laid out on the way down: the list is lazy, so the
        // ones below the fold are only checked once they are scrolled to.
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 40; i++) {
          final position = tester.state<ScrollableState>(list).position;
          if (position.pixels >= position.maxScrollExtent) break;
          await tester.drag(list, const Offset(0, -200));
          await settle(tester, 4);
          expect(tester.takeException(), isNull, reason: 'after $i drags');
        }
        final position = tester.state<ScrollableState>(list).position;
        expect(position.pixels, position.maxScrollExtent,
            reason: 'reached the end of the settings list');
      });
    }

    testWidgets('the shop-type menu fits when it is open', (tester) async {
      await pumpPhone(tester, const SettingsScreen(), keyboard: false);
      await tester
          .tap(find.byKey(const ValueKey('setting-shop-type-dropdown')));
      await settle(tester, 24);
      expect(find.text('Cards & subscriptions'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cards & subscriptions').last);
      await settle(tester, 24);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the auto-delete menu and its custom-days dialog fit',
        (tester) async {
      await pumpPhone(tester, const SettingsScreen(), keyboard: false);
      final dropdown =
          find.byKey(const ValueKey('setting-auto-delete-dropdown'));
      await reach(tester, dropdown);
      // Under the explanation and as wide as the tile, like the shop type.
      expect(
        tester.getTopLeft(dropdown).dy,
        greaterThan(tester
            .getTopLeft(find.text('Auto-delete old invoices'))
            .dy),
      );
      expect(tester.getSize(dropdown).width, greaterThan(200));

      await tester.tap(dropdown);
      await settle(tester, 24);
      expect(find.text('After 365 days'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Custom…').last);
      await settle(tester, 24);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await keyboardUp(tester);
      await keyboardDown(tester);
    });

    testWidgets('a custom auto-delete period fits the tile', (tester) async {
      // A number the shop typed itself: the longest label the picker shows.
      await db(tester, () async {
        await database.db.insert('settings', {
          'key': SettingsKeys.autoDeleteDays,
          'value': '12345',
          'updated_at': 0,
        });
        return true;
      });
      for (final locale in ['en', 'ar']) {
        await pumpPhone(
          tester,
          const SettingsScreen(),
          keyboard: false,
          locale: locale,
        );
        await reach(
          tester,
          find.byKey(const ValueKey('setting-auto-delete-dropdown')),
        );
        expect(find.textContaining('12,345'), findsOneWidget, reason: locale);
        expect(tester.takeException(), isNull, reason: locale);
      }
    });

    testWidgets('the reminder dialog fits, opened from the settings screen',
        (tester) async {
      await pumpPhone(tester, const SettingsScreen(), keyboard: false);
      final tile = find.byKey(const ValueKey('setting-reminder-text'));
      await reach(tester, tile);
      // Just above the tile that was scrolled to: built, but it may sit
      // above the fold now that the list goes on below (Security, About).
      expect(
        find.byKey(const ValueKey('setting-due-soon'), skipOffstage: false),
        findsOneWidget,
      );
      await tester.tap(tile);
      await settle(tester, 24);
      expect(find.byType(ReminderTextDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await keyboardUp(tester);
      await keyboardDown(tester);
    });

    testWidgets('the "start a new sale?" confirmation fits', (tester) async {
      await seedCustomers(tester);
      await setShopType(tester, 'CARDS');
      await pumpPhone(tester, const HomeScreen(), keyboard: false);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      container.read(cartProvider.notifier).add(const CartLine(
            name: 'Left in the cart',
            unitPriceMinor: 1000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          ));
      // The home has the renewals card; Renew lives on the due screen.
      final seeAll = find.byKey(const ValueKey('home-due-see-all'));
      await reach(tester, seeAll);
      await tester.tap(seeAll);
      await settle(tester, 24);
      final renew = find.byKey(ValueKey('due-renew-$accountId'));
      await reach(tester, renew);
      await settle(tester, 4);
      await tester.tap(renew);
      await settle(tester, 24);
      expect(find.byKey(const ValueKey('renew-replace-cart-dialog')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the statistics screen fits with renewals and customers',
        (tester) async {
      await seedCustomers(tester);
      await db(tester, () async {
        final id = await insertInvoice(
          database.db,
          invoiceNo: 1,
          subtotalMinor: 3500000,
          customerName: longName,
          accountNumber: '0011-2233-4455-6677',
        );
        await database.db.insert('invoice_items', {
          'invoice_id': id,
          'sort_order': 0,
          'product_name': longPackage,
          'product_name_norm': longPackage.toLowerCase(),
          'kind': 'SERVICE',
          'qty_thousandths': 1000,
          'orig_unit_price_minor': 3500000,
          'orig_currency_code': 'SYP',
          'orig_rate_num': 1,
          'orig_rate_den': 1,
          'unit_price_minor': 3500000,
          'line_total_minor': 3500000,
        });
        return true;
      });
      await pumpPhone(tester, const StatsScreen(), keyboard: false);
      for (final key in [
        'stats-renewals',
        'stats-top-packages',
        'stats-top-customers',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await settle(tester, 4);
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  });

  group('prepaid card codes', () {
    const longCard = 'Internet prepaid recharge card 100 GB monthly unlimited';
    const codes = [
      '1111222233334444',
      '5555666677778888',
      '9999000011112222',
    ];

    late InMemoryKeyStore keyStore;
    late VoucherRepository vouchers;
    late int cardId;
    late int batchId;

    setUp(() {
      keyStore = InMemoryKeyStore();
      vouchers = VoucherRepository(database.db, CodeCipher(keyStore));
    });

    /// A card product with a long name, a threshold it is under, a fresh
    /// batch with a cost and one batch that expired last month; a second
    /// card product with nothing loaded; a PIN.
    Future<void> seedCards(WidgetTester tester) => db(tester, () async {
          final now = DateTime.now().millisecondsSinceEpoch;
          Future<int> card(String name, {int favorite = 0}) =>
              database.db.insert('products', {
                'name': name,
                'name_norm': name.toLowerCase(),
                'kind': 'SERVICE',
                'price_minor': 3500000,
                'currency_code': 'SYP',
                'is_favorite': favorite,
                'sold_from_code_stock': 1,
                'low_stock_threshold': 50,
                'created_at': now,
                'updated_at': now,
              });
          cardId = await card(longCard, favorite: 1);
          await card('$longCard (2)');
          final report = await vouchers.addBatch(
            productId: cardId,
            parsed: parseCodeList(
              [
                for (final (index, code) in codes.indexed)
                  'SERIAL-0000-000$index,$code',
              ].join('\n'),
              columns: CodeColumns.serialThenCode,
            ),
            costPerCardMinor: 3250000,
            costCurrencyCode: 'SYP',
            expiryAt: expiryFromDate(
              DateTime.now().add(const Duration(days: 400)),
            ),
          );
          batchId = report.batchId!;
          await vouchers.addBatch(
            productId: cardId,
            parsed: parseCodeList(
              '7777000011112222\n7777000011113333',
              columns: CodeColumns.codeOnly,
            ),
            expiryAt: expiryFromDate(
              DateTime.now().subtract(const Duration(days: 30)),
            ),
          );
          await PinRepository(SettingsRepository(database.db)).set('2580');
          return true;
        });

    /// One saved sale of two cards to a customer with a long name.
    Future<Invoice> sellCards(WidgetTester tester) => db(tester, () {
          final syp = Currency(
            code: 'SYP',
            nameAr: 'SYP',
            nameEn: 'SYP',
            decimalPlaces: 0,
            rate: RateFraction.one,
            rateUpdatedAt: DateTime.utc(2026),
          );
          return InvoiceRepository(
            database.db,
            codeCipher: CodeCipher(keyStore),
          ).save(Invoice.fromCart(
            cart: const Cart().add(CartLine(
              productId: cardId,
              name: longCard,
              kind: ProductKind.service,
              unitPriceMinor: 3500000,
              priceCurrencyCode: 'SYP',
              qtyThousandths: 2000,
              codeStock: true,
            )),
            ctx: CurrencyContext.of([syp], baseCode: 'SYP'),
            createdAt: DateTime.now().toUtc(),
            customerName: 'Abdulrahman Mohammad Al-Khatib Al-Dimashqi',
          ));
        });

    /// Pumps [screen] on the 360×640 phone at a large system font.
    Future<void> pumpPhone(
      WidgetTester tester,
      Widget screen, {
      String locale = 'en',
    }) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = phone * tester.view.devicePixelRatio;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(Locale(locale))),
            secretKeyStoreProvider.overrideWithValue(keyStore),
            nativeBridgeProvider.overrideWithValue(FakeNativeBridge()),
          ],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen,
          ),
        ),
      );
      await settle(tester, 24);
      expect(tester.takeException(), isNull);
    }

    Future<void> keyboardUp(WidgetTester tester) async {
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardInset * tester.view.devicePixelRatio,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    Future<void> keyboardDown(WidgetTester tester) async {
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    /// Drags the first list to its end, checking for an overflow on the way.
    Future<void> scrollThrough(WidgetTester tester) async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 30; i++) {
        final position = tester.state<ScrollableState>(list).position;
        if (position.pixels >= position.maxScrollExtent) break;
        await tester.drag(list, const Offset(0, -200));
        await settle(tester, 4);
        expect(tester.takeException(), isNull, reason: 'after $i drags');
      }
    }

    /// A bare screen with one button that opens [show].
    Widget host(Future<void> Function(BuildContext context) show) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context),
                child: const Text('open it'),
              ),
            ),
          ),
        );

    Future<void> openHost(WidgetTester tester) async {
      await tester.tap(find.text('open it'));
      await settle(tester, 28);
      expect(tester.takeException(), isNull);
    }

    for (final locale in ['en', 'ar']) {
      testWidgets('the card stock screen fits, warnings and all ($locale)',
          (tester) async {
        await seedCards(tester);
        await pumpPhone(tester, const CardStockScreen(), locale: locale);
        expect(find.byKey(const ValueKey('stock-warnings')), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets("one product's stock fits, with its batches ($locale)",
          (tester) async {
        await seedCards(tester);
        await sellCards(tester);
        await pumpPhone(
          tester,
          ProductStockScreen(productId: cardId),
          locale: locale,
        );
        expect(find.byKey(ValueKey('batch-$batchId')), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('the load-codes page fits with the keyboard up ($locale)',
          (tester) async {
        await seedCards(tester);
        final product = await db(tester, () async {
          final row = (await database.db
                  .query('products', where: 'id = ?', whereArgs: [cardId]))
              .single;
          return Product.fromMap(row);
        });
        await pumpPhone(tester, AddBatchScreen(product: product),
            locale: locale);
        await tester.enterText(
          find.byKey(const ValueKey('paste-field')),
          [
            for (var i = 0; i < 8; i++)
              'SERIAL-NUMBER-000$i,4444555566667${i.toString().padLeft(3, '0')}',
            '',
            'SERIAL-NUMBER-0000,4444555566667000',
            codes.first,
          ].join('\n'),
        );
        await tester.tap(find.byKey(const ValueKey('columns-serialThenCode')));
        await settle(tester, 40);
        expect(tester.takeException(), isNull);
        // Built, though on this phone it starts below the fold.
        expect(
          find.byKey(const ValueKey('import-preview'), skipOffstage: false),
          findsOneWidget,
        );
        await keyboardUp(tester);
        await scrollThrough(tester);
        await keyboardDown(tester);

        // The other two ways in.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await settle(tester, 4);
        final segments = find.descendant(
          of: find.byKey(const ValueKey('load-method')),
          matching: find.byType(Text),
        );
        for (var i = 1; i < segments.evaluate().length; i++) {
          await tester.tap(segments.at(i));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'method $i');
        }
      });

      testWidgets('the batch codes and expired lists fit ($locale)',
          (tester) async {
        await seedCards(tester);
        await sellCards(tester);
        await pumpPhone(
          tester,
          BatchCodesScreen(batchId: batchId, productName: longCard),
          locale: locale,
        );
        expect(find.byKey(const ValueKey('batch-codes')), findsOneWidget);
        await scrollThrough(tester);

        await pumpPhone(tester, const ExpiredCodesScreen(), locale: locale);
        expect(find.byKey(const ValueKey('expired-list')), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('the code search fits, result and keyboard ($locale)',
          (tester) async {
        await seedCards(tester);
        await sellCards(tester);
        await pumpPhone(tester, const CodeLookupScreen(), locale: locale);
        await keyboardUp(tester);
        await tester.enterText(
            find.byKey(const ValueKey('lookup-field')), codes.first);
        await tester.tap(find.byKey(const ValueKey('lookup-search')));
        await settle(tester, 24);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('lookup-results')), findsOneWidget);
        await keyboardDown(tester);
        await scrollThrough(tester);

        await tester.enterText(
            find.byKey(const ValueKey('lookup-field')), '0000');
        await tester.tap(find.byKey(const ValueKey('lookup-search')));
        await settle(tester, 24);
        await keyboardUp(tester);
        expect(find.byKey(const ValueKey('lookup-not-found')), findsOneWidget);
      });

      testWidgets('the audit log fits ($locale)', (tester) async {
        await seedCards(tester);
        final invoice = await sellCards(tester);
        await db(tester, () async {
          final sold = await vouchers.codesOfInvoice(invoice.id!);
          await vouchers.reveal(sold.first.id);
          await vouchers.voidCode(
            sold.first.id,
            reason: 'The customer brought the card back, it was scratched',
          );
          await vouchers.returnToStock(sold.last.id, reason: 'Sold by mistake');
          await vouchers.lookup(codes.first);
          await vouchers.logReprint(
            invoiceNo: 1234567,
            codeCount: 2,
            output: 'print',
            productName: longCard,
          );
          return true;
        });
        await pumpPhone(tester, const AuditLogScreen(), locale: locale);
        expect(find.byKey(const ValueKey('audit-list')), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('the PIN dialogs fit with the keyboard up ($locale)',
          (tester) async {
        await pumpPhone(
          tester,
          host((context) => requirePin(
                context,
                reason: AppLocalizations.of(context).pinReasonReprint,
              )),
          locale: locale,
        );
        // No PIN yet: the "choose a PIN" dialog, the taller of the two.
        await openHost(tester);
        expect(find.byType(SetPinDialog), findsOneWidget);
        await keyboardUp(tester);
        await tester.enterText(
            find.byKey(const ValueKey('pin-new-field')), '12');
        await tester.tap(find.byKey(const ValueKey('pin-set-save')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'with its error text');
        await tester.enterText(
            find.byKey(const ValueKey('pin-new-field')), '2580');
        await tester.enterText(
            find.byKey(const ValueKey('pin-again-field')), '2580');
        await tester.tap(find.byKey(const ValueKey('pin-set-save')));

        // The new PIN ends on its recovery code: the code, three buttons, a
        // message and the "I saved it" box, with the keyboard still up for
        // a moment and then without it.
        final recovery = find.byType(RecoveryCodeDialog);
        for (var i = 0; i < 200 && recovery.evaluate().isEmpty; i++) {
          await settle(tester, 2);
        }
        await settle(tester, 28);
        expect(recovery, findsOneWidget);
        expect(tester.takeException(), isNull);
        await keyboardDown(tester);
        // No printer is set up: the longest message the dialog shows.
        final print = find.byKey(const ValueKey('recovery-print'));
        await tester.ensureVisible(print);
        await settle(tester, 4);
        await tester.tap(print);
        final message = find.byKey(const ValueKey('recovery-message'),
            skipOffstage: false);
        for (var i = 0; i < 200 && message.evaluate().isEmpty; i++) {
          await settle(tester, 2);
        }
        expect(message, findsOneWidget);
        expect(tester.takeException(), isNull);
        final saved = find.byKey(const ValueKey('recovery-saved'));
        await tester.ensureVisible(saved);
        await settle(tester, 4);
        await tester.tap(saved);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('recovery-continue')));
        for (var i = 0;
            i < 200 && find.byType(SetPinDialog).evaluate().isNotEmpty;
            i++) {
          await settle(tester, 2);
        }
        await settle(tester, 28);
        expect(tester.takeException(), isNull);

        // Now it is set: "Forgot PIN?" with a wrong code's message…
        await openHost(tester);
        expect(find.byType(PinEntryDialog), findsOneWidget);
        await keyboardUp(tester);
        // "Forgot PIN?" is beside the title, in the part of the dialog that
        // does not scroll: on THIS phone, at THIS font and with the keyboard
        // up it is on screen, above the keyboard, and takes the tap as it is
        // — nothing is scrolled to reach it.
        final forgot = find.byKey(const ValueKey('pin-forgot'));
        expect(forgot.hitTestable(), findsOneWidget);
        final forgotRect = tester.getRect(forgot);
        expect(forgotRect.top, greaterThanOrEqualTo(0));
        expect(forgotRect.bottom,
            lessThanOrEqualTo(phone.height - keyboardInset));
        expect(forgotRect.left, greaterThanOrEqualTo(0));
        expect(forgotRect.right, lessThanOrEqualTo(phone.width));
        await tester.tap(forgot);
        await settle(tester, 28);
        expect(find.byType(PinRecoveryDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.enterText(
            find.byKey(const ValueKey('recovery-field')), '0000-0000-0000');
        await tester.tap(find.byKey(const ValueKey('recovery-ok')));
        for (var i = 0;
            i < 200 &&
                tester
                        .widget<TextField>(
                            find.byKey(const ValueKey('recovery-field')))
                        .decoration
                        ?.errorText ==
                    null;
            i++) {
          await settle(tester, 2);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(
          of: find.byType(PinRecoveryDialog),
          matching: find.byType(TextButton),
        ));
        await settle(tester, 28);

        // …and the entry dialog itself, with a wrong attempt's message.
        expect(find.byType(PinEntryDialog), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey('pin-entry-field')), '0000');
        await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
        for (var i = 0;
            i < 200 &&
                tester
                        .widget<TextField>(find.descendant(
                          of: find.byKey(const ValueKey('pin-entry-field')),
                          matching: find.byType(TextField),
                        ))
                        .decoration
                        ?.errorText ==
                    null;
            i++) {
          await settle(tester, 2);
        }
        expect(tester.takeException(), isNull);
        await keyboardDown(tester);
      });

      testWidgets(
          'a PIN without a recovery code: the settings banner and the '
          'offer on the PIN prompt fit ($locale)', (tester) async {
        // A PIN as phase 4c wrote it: hash and salt, no recovery code.
        await db(tester, () async {
          final salt = newPinSalt();
          await SettingsRepository(database.db).setMany({
            SettingsKeys.pinSalt: base64Encode(salt),
            SettingsKeys.pinHash: hashPin('2580', salt),
          });
          return true;
        });

        await pumpPhone(tester, const SettingsScreen(), locale: locale);
        final banner = find.byKey(const ValueKey('recovery-missing-banner'));
        // To the PIN tile first: the banner above it reads the database when
        // it is first built, which only completes in settle()'s real async.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('setting-pin')),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(tester, 12);
        await tester.ensureVisible(banner);
        await settle(tester, 4);
        expect(banner, findsOneWidget);
        expect(tester.takeException(), isNull);
        final create = find.byKey(const ValueKey('recovery-create-now'));
        await tester.ensureVisible(create);
        await settle(tester, 4);
        await tester.tap(create);
        await settle(tester, 28);
        expect(find.byKey(const ValueKey('pin-recovery-armed')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await keyboardUp(tester);
        await keyboardDown(tester);

        // The offer on a prompt, with a reason above it and the keyboard up:
        // "Forgot PIN?" is still on screen.
        await pumpPhone(
          tester,
          host((context) => requirePin(
                context,
                reason: AppLocalizations.of(context).pinReasonReprint,
              )),
          locale: locale,
        );
        await openHost(tester);
        expect(
          find.byKey(const ValueKey('pin-recovery-offer'), skipOffstage: false),
          findsOneWidget,
        );
        await keyboardUp(tester);
        final forgot = find.byKey(const ValueKey('pin-forgot'));
        expect(forgot.hitTestable(), findsOneWidget);
        expect(tester.getRect(forgot).bottom,
            lessThanOrEqualTo(phone.height - keyboardInset));
        await keyboardDown(tester);
      });

      testWidgets('the reason, revealed-code and export dialogs fit ($locale)',
          (tester) async {
        await seedCards(tester);
        await pumpPhone(
          tester,
          host((context) {
            final l10n = AppLocalizations.of(context);
            return showDialog<String>(
              context: context,
              builder: (_) => ReasonDialog(
                title: l10n.returnCodeTitle,
                message: l10n.returnCodeMessage,
                confirmLabel: l10n.codeReturn,
              ),
            );
          }),
          locale: locale,
        );
        await openHost(tester);
        await keyboardUp(tester);
        await tester.tap(find.byKey(const ValueKey('reason-confirm')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'with its error text');
        await keyboardDown(tester);

        // A 20-character code: five groups, wrapping onto a second line.
        await pumpPhone(
          tester,
          host((context) => showDialog<void>(
                context: context,
                builder: (_) => const RevealedCodeDialog(
                  productName: longCard,
                  code: 'ABCD1234EFGH5678WXYZ',
                  serial: 'SERIAL-0000-0001-0002-0003',
                ),
              )),
          locale: locale,
        );
        await openHost(tester);
        expect(find.byKey(const ValueKey('revealed-code')), findsOneWidget);

        await pumpPhone(
          tester,
          ProductStockScreen(productId: cardId),
          locale: locale,
        );
        await tester.tap(find.byKey(const ValueKey('product-stock-menu')));
        await settle(tester, 28);
        await tester.tap(find.byKey(const ValueKey('product-stock-export')));
        await settle(tester, 28);
        expect(find.byKey(const ValueKey('export-dialog')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the invoice screens fit with their card codes ($locale)',
          (tester) async {
        await seedCards(tester);
        final invoice = await sellCards(tester);
        await pumpPhone(
          tester,
          InvoiceDetailScreen(invoiceId: invoice.id!),
          locale: locale,
        );
        expect(
          find.byKey(const ValueKey('invoice-codes'), skipOffstage: false),
          findsOneWidget,
        );
        await scrollThrough(tester);

        await pumpPhone(
          tester,
          SaleInvoiceScreen(invoice: invoice),
          locale: locale,
        );
        await scrollThrough(tester);
      });
    }

    testWidgets('a card in the sale: quantity sheet, cart and totals fit',
        (tester) async {
      await seedCards(tester);
      // A four-digit line total: the cart row's amount and its delete
      // button share a ListTile's trailing slot, which the square test font
      // fills at seven digits (that row is not what this test is about).
      await db(tester, () async {
        await database.db.update('products', {'price_minor': 1500});
        return true;
      });
      await pumpPhone(tester, const SaleScreen());
      // The stock pill sits inside the favorite's own button.
      expect(find.byKey(ValueKey('favorite-stock-$cardId')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, longCard));
      await settle(tester, 28);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('qty-stock')), findsOneWidget);
      // More than there are: the warning line replaces the stock line.
      final five = find.byKey(const ValueKey('qty-preset-5000'));
      await tester.ensureVisible(five);
      await settle(tester, 4);
      await tester.tap(five);
      await settle(tester);
      expect(tester.takeException(), isNull);
      final three = find.byKey(const ValueKey('qty-preset-3000'));
      await tester.ensureVisible(three);
      await settle(tester, 4);
      await tester.tap(three);
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester, 28);
      expect(tester.takeException(), isNull);

      // Two of the three are sold elsewhere: the cart now asks for more
      // than the stock holds and the totals panel says so.
      await db(tester, () async {
        await database.db.rawUpdate(
          "UPDATE voucher_codes SET status = 'SOLD' WHERE id IN "
          '(SELECT id FROM voucher_codes WHERE batch_id = ? LIMIT 2)',
          [batchId],
        );
        return true;
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SaleScreen)),
      );
      container.invalidate(voucherAvailabilityProvider);
      await settle(tester, 24);
      expect(find.byKey(const ValueKey('code-stock-short')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sale search shows the stock of a card', (tester) async {
      await seedCards(tester);
      await pumpPhone(tester, const SaleScreen());
      await tester.enterText(
          find.byKey(const ValueKey('sale-search-field')), 'internet');
      await keyboardUp(tester);
      await settle(tester, 24);
      expect(find.textContaining('In stock: 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the products list and the product form fit', (tester) async {
      await seedCards(tester);
      await pumpPhone(tester, const ProductsScreen());
      expect(find.byKey(ValueKey('product-stock-$cardId')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final product = await db(tester, () async {
        final row = (await database.db
                .query('products', where: 'id = ?', whereArgs: [cardId]))
            .single;
        return Product.fromMap(row);
      });
      await pumpPhone(tester, ProductFormScreen(product: product));
      await keyboardUp(tester);
      await scrollThrough(tester);
      expect(
        find.byKey(const ValueKey('product-low-stock'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('the home screen fits with the card stock tile and badge',
        (tester) async {
      await seedCards(tester);
      for (final type in ['GROCERY', 'CARDS']) {
        await db(tester, () async {
          await database.db.insert(
            'settings',
            {'key': SettingsKeys.shopType, 'value': type, 'updated_at': 0},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return true;
        });
        await pumpPhone(tester, const HomeScreen());
        expect(find.byKey(const ValueKey('home-badge-cards')), findsOneWidget,
            reason: type);
        await scrollThrough(tester);
      }
    });

    testWidgets('the statistics screen fits with cards sold', (tester) async {
      await seedCards(tester);
      await sellCards(tester);
      await pumpPhone(tester, const StatsScreen());
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('stats-cards')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await settle(tester, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the invoice settings fit with the card options',
        (tester) async {
      await pumpPhone(tester, const InvoiceSettingsScreen());
      // The form's own list: the preview above it scrolls too, and so does
      // every text field.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('toggle-code-slips')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle(tester, 4);
      expect(
        find.byKey(const ValueKey('toggle-code-qr'), skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    /// The invoice itself, laid out at a paper's width in dots.
    Future<void> pumpPaper(
      WidgetTester tester, {
      required int dots,
      required String language,
      required List<InvoiceCode> invoiceCodes,
      bool qr = true,
      bool slip = false,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(dots.toDouble(), 4000);
      addTearDown(tester.view.reset);
      final settings = InvoiceSettings(
        language: language,
        shopName: 'Al-Baraka Telecom',
        printCodeQr: qr,
      );
      final invoice = sypInvoice(lines: 1);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: SizedBox(
              width: dots.toDouble(),
              child: slip
                  ? CodeSlipView(
                      invoice: invoice,
                      code: invoiceCodes.first,
                      settings: settings,
                      isCopy: true,
                    )
                  : InvoiceView(
                      invoice: invoice,
                      settings: settings,
                      currencies: testCurrencies,
                      isCopy: true,
                      codes: invoiceCodes,
                    ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$dots dots, $language');
    }

    final printed = [
      InvoiceCode(
        id: 1,
        productName: longCard,
        code: '1111222233334444',
        masked: '•••• •••• 4444',
        serial: 'SERIAL-0000-0001-0002',
        expiryAt: DateTime(2027),
      ),
      // 20 characters, letters included: five groups.
      const InvoiceCode(
        id: 2,
        productName: 'W',
        code: 'WWWW1234MMMM5678WXYZ',
        masked: '•••• •••• WXYZ',
      ),
      // What the screen gets, and what an unreadable code prints as.
      const InvoiceCode(
        id: 3,
        productName: longCard,
        code: null,
        masked: '•••• ••••',
        unreadable: true,
      ),
    ];

    for (final language in ['en', 'ar']) {
      for (final dots in [576, 384, 280]) {
        testWidgets('the printed recovery slip fits $dots dots ($language)',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(dots.toDouble(), 4000);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: dots.toDouble(),
                  child: RecoverySlipView(
                    code: 'WWWWMMMMWXYZ',
                    settings: InvoiceSettings(
                      language: language,
                      shopName: 'Al-Baraka Telecom',
                    ),
                    printedAt: DateTime(2026, 11, 26, 14, 5),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(InvoiceCodeBlock), findsOneWidget);
        });
      }
    }

    for (final language in ['en', 'ar']) {
      for (final dots in [576, 384, 280]) {
        testWidgets('the printed codes fit $dots dots ($language)',
            (tester) async {
          await pumpPaper(
            tester,
            dots: dots,
            language: language,
            invoiceCodes: printed,
          );
          expect(find.byType(InvoiceCodeBlock), findsNWidgets(3));
          await pumpPaper(
            tester,
            dots: dots,
            language: language,
            invoiceCodes: printed,
            slip: true,
          );
          expect(find.byType(InvoiceCodeBlock), findsOneWidget);
        });
      }
    }
  });
}
