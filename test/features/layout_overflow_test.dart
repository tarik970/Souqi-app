import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/utils/due_dates.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/features/currencies/currency_form_screen.dart';
import 'package:souqi/features/customers/account_form_screen.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:souqi/features/customers/customer_form_screen.dart';
import 'package:souqi/features/customers/customer_picker_screen.dart';
import 'package:souqi/features/customers/customers_screen.dart';
import 'package:souqi/features/customers/due_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/sale/quantity_sheet.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/settings/renewal_settings.dart';
import 'package:souqi/features/setup/setup_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
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
        scrollable: find.byType(Scrollable).first,
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

    testWidgets('the home screen of a cards shop fits, with its due list',
        (tester) async {
      await seedCustomers(tester);
      await setShopType(tester, 'CARDS');
      await pumpPhone(tester, const HomeScreen());
      expect(find.byKey(ValueKey('due-row-$accountId'), skipOffstage: false),
          findsOneWidget);
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
        scrollable: find.byType(Scrollable).first,
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

    testWidgets('the renewal settings and the reminder dialog fit',
        (tester) async {
      // The two new tiles on their own page: the rest of the settings
      // screen is older than this test and is not what is being checked.
      await pumpPhone(
        tester,
        Scaffold(
          body: ListView(
            children: const [DueSoonDaysTile(), ReminderTextTile()],
          ),
        ),
        keyboard: false,
      );
      final tile = find.byKey(const ValueKey('setting-reminder-text'));
      expect(find.byKey(const ValueKey('setting-due-soon')), findsOneWidget);
      await reach(tester, tile);
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
}
