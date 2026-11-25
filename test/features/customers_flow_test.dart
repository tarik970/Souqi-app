import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/utils/due_dates.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/customers/account_form_screen.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:souqi/features/customers/customer_form_screen.dart';
import 'package:souqi/features/customers/customer_picker_screen.dart';
import 'package:souqi/features/customers/customers_providers.dart';
import 'package:souqi/features/customers/customers_screen.dart';
import 'package:souqi/features/customers/due_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// Customers, accounts and renewals, driven through the real screens on a
/// real database: the quick search, "Renew", the sale screen's Customer chip
/// and its account gate, the due list, the customer page and the settings.
///
/// The screens read from sqflite, whose futures only progress in
/// [WidgetTester.runAsync]; [settle] therefore interleaves real async with
/// pumped frames instead of using `pumpAndSettle`.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // A tap that lands on nothing must fail the test, not pass it vacuously.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late CustomerRepository customers;

  // The fixture: one customer with one overdue account, three products.
  late int adslId; // SERVICE, requires a customer account, code 201
  late int adsl8Id; // SERVICE, code 202
  late int ahmadId;
  late int accountId;

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Long enough for a page, a sheet or a dialog to finish sliding in or out.
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

  Future<int> insertService(
    String name, {
    required String code,
    required int price,
    bool requiresAccount = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return database.db.insert('products', {
      'name': name,
      'name_norm': name.toLowerCase(),
      'code': code,
      'kind': 'SERVICE',
      'price_minor': price,
      'currency_code': 'SYP',
      'requires_account': requiresAccount ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// The fixture rows. Dates are relative to the real clock, because saving
  /// an invoice stamps it with the real time.
  Future<bool> seed() async {
    adslId = await insertService('ADSL 4 Mbps',
        code: '201', price: 35000, requiresAccount: true);
    adsl8Id = await insertService('ADSL 8 Mbps', code: '202', price: 60000);
    await insertProduct(database.db, name: 'Sugar', code: '101');
    ahmadId = await customers
        .insert(const Customer(name: 'Ahmad Hasan', phone: '0944 123 456'));
    final lastRenewal = DateTime.now().subtract(const Duration(days: 31));
    accountId = await customers.insertAccount(CustomerAccount(
      customerId: ahmadId,
      accountNumber: '0011-2233',
      provider: 'MTN',
      defaultProductId: adslId,
      renewalDays: 30,
      lastRenewalAt: lastRenewal,
      nextDueAt: nextDueAfter(lastRenewal, 30), // yesterday
    ));
    return true;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    DateTime Function()? clock,
    String locale = 'en',
  }) async {
    // A phone-shaped viewport, 600×1200 logical pixels.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // A new key every time: a test that pumps a second screen gets a
        // fresh app (and navigator), not the old one with a new home under
        // whatever was pushed.
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(Locale(locale))),
          nativeBridgeProvider.overrideWithValue(bridge),
          if (clock != null) clockProvider.overrideWithValue(clock),
        ],
        child: MaterialApp(
          locale: Locale(locale),
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
  final saleSearch = find.byKey(const ValueKey('sale-search-field'));
  final chip = find.byKey(const ValueKey('sale-customer-chip'));
  final saveButton = find.byKey(const ValueKey('sale-save'));

  /// Whether the sale can be saved right now: the Save button is there
  /// (a blocked sale shows "Choose account" in its place) and enabled.
  bool saveEnabled(WidgetTester tester) =>
      saveButton.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(saveButton).onPressed != null;

  String totalText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data!;

  /// Types [code] into the sale screen's search box and presses enter.
  Future<void> addByCode(WidgetTester tester, String code) async {
    await tester.enterText(saleSearch, code);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  Future<Map<String, Object?>> accountRow(WidgetTester tester) => db(
        tester,
        () async => (await database.db.query(
          'customer_accounts',
          where: 'id = ?',
          whereArgs: [accountId],
        ))
            .single,
      );

  Future<List<Map<String, Object?>>> invoiceRows(WidgetTester tester) =>
      db(tester, () => database.db.query('invoices', orderBy: 'id ASC'));

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    customers = CustomerRepository(database.db);
  });

  tearDown(() async => database.close());

  group('home screen', () {
    testWidgets('a grocery shop opens on the destinations, search on top',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());

      expect(searchBox, findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      // No renewals card on a grocery home — the tile is enough.
      expect(find.byKey(const ValueKey('home-due')), findsNothing);
      for (final label in [
        'Sale',
        'Customers',
        'Due for renewal',
        'Products',
        'Archive',
        'Statistics',
        'Settings',
      ]) {
        expect(find.text(label, skipOffstage: false), findsOneWidget,
            reason: label);
      }
      // One account is overdue: the badge says so, as a number.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-badge-due')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    for (final type in ['CARDS', 'BOTH']) {
      testWidgets('shop type $type opens on the search with the renewals card',
          (tester) async {
        await db(tester, seed);
        await setShopType(tester, type);
        await pump(tester, const HomeScreen());

        expect(searchBox, findsOneWidget);
        // The renewals summary card, and the same tile grid as a grocery.
        expect(find.byKey(const ValueKey('home-due')), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
        expect(find.text('Overdue (1)'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('home-due')),
            matching: find.text('Ahmad Hasan'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home-due-see-all')), findsOneWidget);
        // Its place on the screen: below the box.
        expect(
          tester.getTopLeft(find.text('Overdue (1)')).dy,
          greaterThan(tester.getBottomLeft(searchBox).dy),
        );
        // The destinations are still one tap away.
        expect(find.byKey(const ValueKey('home-nav-sale')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-nav-settings')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a cards shop with nothing due says so', (tester) async {
      await setShopType(tester, 'CARDS');
      await pump(tester, const HomeScreen());
      expect(find.text('Nothing is due for renewal'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-badge-due')), findsNothing);
    });

    testWidgets('changing the shop type never hides data, only reorders',
        (tester) async {
      await db(tester, seed);
      await setShopType(tester, 'CARDS');
      await pump(tester, const HomeScreen());
      expect(find.byKey(const ValueKey('home-due')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-nav-settings')));
      await animated(tester);
      await tester.tap(find.text('Cards & subscriptions'));
      await animated(tester);
      await tester.tap(find.text('Grocery').last);
      await animated(tester);
      await tester.pageBack();
      await animated(tester);

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byKey(const ValueKey('home-badge-due')), findsOneWidget);
      expect(await db(tester, () => database.db.query('customers')),
          hasLength(1));
    });
  });

  group('quick search on the home screen', () {
    testWidgets('finds by name, phone or card number, in any spelling',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      final row = find.byKey(ValueKey('quick-hit-$ahmadId-$accountId'));

      for (final typed in [
        'hasan',
        '0944 123',
        '٠٩٤٤١٢٣', // Arabic-Indic digits
        '00112233', // the card number without its dash
        '٠٠١١-٢٢',
        '0011 22',
      ]) {
        await tester.enterText(searchBox, typed);
        await settle(tester);
        expect(row, findsOneWidget, reason: typed);
        expect(find.byType(GridView), findsNothing, reason: typed);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a result says everything in words', (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, '0011');
      await settle(tester);

      final row = find.byKey(ValueKey('quick-hit-$ahmadId-$accountId'));
      Finder inRow(Finder matching) =>
          find.descendant(of: row, matching: matching);

      expect(inRow(find.text('Ahmad Hasan')), findsOneWidget);
      // Provider and account number, on one line.
      expect(inRow(find.textContaining('MTN')), findsOneWidget);
      expect(inRow(find.textContaining('0011-2233')), findsOneWidget);
      // Default package and last renewal date.
      expect(inRow(find.textContaining('Package: ADSL 4 Mbps')), findsOneWidget);
      expect(inRow(find.textContaining('Last renewal:')), findsOneWidget);
      // The due status in WORDS, not only as a colour.
      expect(inRow(find.textContaining('Overdue by 1 day')), findsOneWidget);
      expect(inRow(find.text('Renew')), findsOneWidget);
    });

    testWidgets('no match says so, and clearing brings the home back',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, 'nobody');
      await settle(tester);
      expect(find.byKey(const ValueKey('quick-search-empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick-search-clear')));
      await settle(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-search-empty')), findsNothing);
    });

    testWidgets('tapping a result opens the customer', (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, 'ahmad');
      await settle(tester);
      await tester.tap(find.text('Ahmad Hasan'));
      await animated(tester);
      expect(find.byType(CustomerDetailScreen), findsOneWidget);
    });
  });

  group('renewal', () {
    Future<void> renewFromHome(WidgetTester tester) async {
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, '0011');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('renew-$accountId')));
      await animated(tester);
    }

    testWidgets('Renew opens a sale with the customer, account and package',
        (tester) async {
      await db(tester, seed);
      await renewFromHome(tester);

      expect(find.byType(SaleScreen), findsOneWidget);
      // The customer and the account are attached…
      expect(
        find.descendant(of: chip, matching: find.textContaining('Ahmad Hasan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip, matching: find.textContaining('0011-2233')),
        findsOneWidget,
      );
      // …and the default package is in the cart at the product's price.
      expect(find.widgetWithText(ListTile, 'ADSL 4 Mbps'), findsOneWidget);
      expect(totalText(tester), contains('35,000'));
      expect(saveEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving updates the account dates and snapshots the invoice',
        (tester) async {
      await db(tester, seed);
      final before = await accountRow(tester);
      await renewFromHome(tester);

      await tester.tap(saveButton);
      await animated(tester);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);

      final invoice = (await invoiceRows(tester)).single;
      expect(invoice['customer_id'], ahmadId);
      expect(invoice['customer_name'], 'Ahmad Hasan');
      expect(invoice['customer_phone'], '0944 123 456');
      expect(invoice['account_id'], accountId);
      expect(invoice['account_number'], '0011-2233');
      expect(invoice['account_provider'], 'MTN');
      expect(invoice['account_number_norm'], '00112233');
      expect(invoice['total_minor'], 35000);

      final after = await accountRow(tester);
      // The last renewal is the invoice's own moment…
      expect(after['last_renewal_at'], invoice['created_at']);
      expect(after['last_renewal_at'], isNot(before['last_renewal_at']));
      // …and the next due day is that day + the 30-day period.
      final renewedAt = DateTime.fromMillisecondsSinceEpoch(
        invoice['created_at'] as int,
        isUtc: true,
      );
      expect(
        after['next_due_at'],
        nextDueAfter(renewedAt, 30).toUtc().millisecondsSinceEpoch,
      );
      // The default package was sold: nothing to offer.
      expect(find.byKey(const ValueKey('package-offer')), findsNothing);
      // The customer has a phone: WhatsApp goes straight to their chat.
      expect(find.byKey(const ValueKey('invoice-whatsapp')), findsOneWidget);

      // The sale is over: the next one starts with no customer.
      await tester.tap(find.text('New sale'));
      await animated(tester);
      expect(
        find.descendant(of: chip, matching: find.text('Customer')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the renewed account leaves the due list', (tester) async {
      await db(tester, seed);
      await setShopType(tester, 'CARDS');
      await pump(tester, const HomeScreen());
      expect(find.text('Overdue (1)'), findsOneWidget);

      // The home has the renewals card; Renew lives on the due screen.
      await tester.tap(find.byKey(const ValueKey('home-due-see-all')));
      await animated(tester);
      await tester.tap(find.byKey(ValueKey('due-renew-$accountId')));
      await animated(tester);
      await tester.tap(saveButton);
      await animated(tester);
      await tester.tap(find.text('Back to home'));
      await animated(tester);

      // "Back to home" goes all the way home, although the sale was opened
      // from the due list: that screen is gone, not waiting underneath.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(DueScreen, skipOffstage: false), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.text('Overdue (1)'), findsNothing);
      expect(find.text('Nothing is due for renewal'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-badge-due')), findsNothing);
    });

    testWidgets('the price can be edited as in any sale', (tester) async {
      await db(tester, seed);
      await renewFromHome(tester);
      // The cart line is an ordinary one: tapping it opens the sheet.
      await tester.tap(find.widgetWithText(ListTile, 'ADSL 4 Mbps'));
      await animated(tester);
      expect(find.text('Unit price'), findsWidgets);
    });

    testWidgets('a changed package is offered as the new default',
        (tester) async {
      await db(tester, seed);
      await renewFromHome(tester);

      // Swap the package: remove the default one, add the 8 Mbps one.
      await tester.tap(find.byTooltip('Remove'));
      await settle(tester);
      await addByCode(tester, '202');
      expect(find.widgetWithText(ListTile, 'ADSL 8 Mbps'), findsOneWidget);

      await tester.tap(saveButton);
      await animated(tester);

      final offer = find.byKey(const ValueKey('package-offer'));
      expect(offer, findsOneWidget);
      expect(
        find.descendant(of: offer, matching: find.textContaining('ADSL 8 Mbps')),
        findsOneWidget,
      );
      expect(
        find.text('Make this the default package for this account'),
        findsOneWidget,
      );
      // Only an offer: nothing changed yet.
      expect((await accountRow(tester))['default_product_id'], adslId);

      await tester.tap(find.byKey(const ValueKey('package-offer-accept')));
      await settle(tester);
      expect((await accountRow(tester))['default_product_id'], adsl8Id);
      expect(find.byKey(const ValueKey('package-offer-done')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the offer can simply be left alone', (tester) async {
      await db(tester, seed);
      await renewFromHome(tester);
      await tester.tap(find.byTooltip('Remove'));
      await settle(tester);
      await addByCode(tester, '202');
      await tester.tap(saveButton);
      await animated(tester);
      expect(find.byKey(const ValueKey('package-offer')), findsOneWidget);

      await tester.tap(find.text('Back to home'));
      await animated(tester);
      expect((await accountRow(tester))['default_product_id'], adslId);
    });

    testWidgets('an account with no default package opens an empty sale',
        (tester) async {
      await db(tester, seed);
      await db(tester, () async {
        await customers.setDefaultPackage(accountId, null);
        return true;
      });
      await renewFromHome(tester);

      expect(find.byType(SaleScreen), findsOneWidget);
      expect(find.text('Cart is empty'), findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.textContaining('Ahmad Hasan')),
        findsOneWidget,
      );
      expect(find.textContaining('no default package'), findsOneWidget);
    });

    testWidgets('a deactivated package is not put in the cart', (tester) async {
      await db(tester, seed);
      await db(
        tester,
        () => database.db.update('products', {'is_active': 0},
            where: 'id = ?', whereArgs: [adslId]),
      );
      await renewFromHome(tester);
      expect(find.text('Cart is empty'), findsOneWidget);
    });

    testWidgets('a sale left in the cart is not thrown away silently',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      container.read(cartProvider.notifier).add(
            cartLineForProduct(
              (await db(tester, () async {
                final product =
                    await container.read(productRepositoryProvider).getById(adsl8Id);
                return product!;
              })),
            ),
          );

      await tester.enterText(searchBox, '0011');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('renew-$accountId')));
      await animated(tester);

      final dialog = find.byKey(const ValueKey('renew-replace-cart-dialog'));
      expect(dialog, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(find.byType(SaleScreen), findsNothing);
      expect(container.read(cartProvider).lines.single.name, 'ADSL 8 Mbps');
      expect(container.read(saleCustomerProvider), isNull);

      await tester.tap(find.byKey(ValueKey('renew-$accountId')));
      await animated(tester);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('New sale')),
      );
      await animated(tester);
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(container.read(cartProvider).lines.single.name, 'ADSL 4 Mbps');
      expect(container.read(saleCustomerProvider)!.accountId, accountId);
    });
  });

  group('the Customer chip on the sale screen', () {
    testWidgets('attaches a customer to a sale of goods', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');

      expect(find.descendant(of: chip, matching: find.text('Customer')),
          findsOneWidget);
      await tester.tap(chip);
      await animated(tester);
      expect(find.byType(CustomerPickerScreen), findsOneWidget);

      await tester.enterText(searchBox, 'ahmad');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$ahmadId-$accountId')));
      await animated(tester);

      expect(find.byType(CustomerPickerScreen), findsNothing);
      expect(
        find.descendant(of: chip, matching: find.textContaining('Ahmad Hasan')),
        findsOneWidget,
      );

      final before = await accountRow(tester);
      await tester.tap(saveButton);
      await animated(tester);
      final invoice = (await invoiceRows(tester)).single;
      expect(invoice['customer_name'], 'Ahmad Hasan');
      expect(invoice['account_number'], '0011-2233');
      // Goods only: the account is on the invoice, but nothing was renewed.
      final after = await accountRow(tester);
      expect(after['last_renewal_at'], before['last_renewal_at']);
      expect(after['next_due_at'], before['next_due_at']);
    });

    testWidgets('can be removed again', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await tester.tap(chip);
      await animated(tester);
      await tester.enterText(searchBox, 'ahmad');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$ahmadId-$accountId')));
      await animated(tester);

      await tester.tap(find.byTooltip('Remove customer'));
      await settle(tester);
      expect(find.descendant(of: chip, matching: find.text('Customer')),
          findsOneWidget);
    });

    testWidgets('a sale with no customer stores none', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');
      await tester.tap(saveButton);
      await animated(tester);
      final invoice = (await invoiceRows(tester)).single;
      expect(invoice['customer_id'], isNull);
      expect(invoice['customer_name'], isNull);
      expect(invoice['account_number'], isNull);
    });

    testWidgets('closing the picker changes nothing', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await tester.tap(chip);
      await animated(tester);
      await tester.pageBack();
      await animated(tester);
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('Customer')),
          findsOneWidget);
    });
  });

  group('a product that requires a customer account', () {
    final blocked = find.byKey(const ValueKey('account-required'));
    final choose = find.byKey(const ValueKey('choose-account'));

    testWidgets('blocks Save, says why, and opens the picker', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '201');

      expect(find.widgetWithText(ListTile, 'ADSL 4 Mbps'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      expect(blocked, findsOneWidget);
      expect(
        find.text('"ADSL 4 Mbps" must be linked to a customer\'s card or account'),
        findsOneWidget,
      );

      // There is no Save to press while it is blocked: the button in its
      // place opens the picker.
      expect(saveButton, findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Choose account'),
          findsOneWidget);
      expect(await invoiceRows(tester), isEmpty);

      await tester.tap(choose);
      await animated(tester);
      expect(find.byType(CustomerPickerScreen), findsOneWidget);
      await tester.enterText(searchBox, '٠٠١١٢٢٣٣');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$ahmadId-$accountId')));
      await animated(tester);

      expect(blocked, findsNothing);
      expect(saveEnabled(tester), isTrue);
      await tester.tap(saveButton);
      await animated(tester);
      final invoice = (await invoiceRows(tester)).single;
      expect(invoice['account_id'], accountId);
      expect(invoice['account_number'], '0011-2233');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a customer without an account is not enough', (tester) async {
      await db(tester, seed);
      final bareId = await db(
        tester,
        () => customers.insert(const Customer(name: 'No Account')),
      );
      await pump(tester, const SaleScreen());
      await addByCode(tester, '201');
      await tester.tap(choose);
      await animated(tester);
      await tester.enterText(searchBox, 'no account');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$bareId-0')));
      await animated(tester);

      expect(
        find.descendant(of: chip, matching: find.textContaining('No Account')),
        findsOneWidget,
      );
      expect(blocked, findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('removing the account blocks the sale again', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '201');
      await tester.tap(choose);
      await animated(tester);
      await tester.enterText(searchBox, '0011');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$ahmadId-$accountId')));
      await animated(tester);
      expect(saveEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('Remove customer'));
      await settle(tester);
      expect(blocked, findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('taking the product out of the cart unblocks it',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');
      await addByCode(tester, '201');
      expect(saveEnabled(tester), isFalse);

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'ADSL 4 Mbps'),
        matching: find.byTooltip('Remove'),
      ));
      await settle(tester);
      expect(blocked, findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('a product that does not require one sells freely',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '202');
      expect(blocked, findsNothing);
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('new customer from the picker', () {
    Future<void> openPicker(WidgetTester tester, String typed) async {
      await pump(tester, const SaleScreen());
      await tester.tap(chip);
      await animated(tester);
      await tester.enterText(searchBox, typed);
      await settle(tester);
    }

    String field(WidgetTester tester, String key) => tester
        .widget<TextFormField>(find.byKey(ValueKey(key)))
        .controller!
        .text;

    testWidgets('text becomes the name', (tester) async {
      await db(tester, seed);
      await openPicker(tester, '  Samer   Haddad ');
      expect(find.text('New customer "Samer Haddad"'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-customer-phone')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('new-customer-name')));
      await animated(tester);
      expect(find.byType(CustomerFormScreen), findsOneWidget);
      expect(field(tester, 'customer-name-field'), 'Samer Haddad');
      expect(field(tester, 'customer-phone-field'), '');
      expect(field(tester, 'customer-account-number-field'), '');
    });

    testWidgets('digits are offered as a phone or as a card number',
        (tester) async {
      await db(tester, seed);
      await openPicker(tester, '0955 777 888');
      expect(find.byKey(const ValueKey('new-customer-name')), findsNothing);
      expect(find.byKey(const ValueKey('new-customer-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-customer-accountNumber')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-customer-phone')));
      await animated(tester);
      expect(field(tester, 'customer-phone-field'), '0955 777 888');
      expect(field(tester, 'customer-name-field'), '');
      expect(field(tester, 'customer-account-number-field'), '');
    });

    testWidgets('a new customer with a card number is attached to the sale',
        (tester) async {
      await db(tester, seed);
      await openPicker(tester, '7700-1');
      await tester
          .tap(find.byKey(const ValueKey('new-customer-accountNumber')));
      await animated(tester);
      expect(field(tester, 'customer-account-number-field'), '7700-1');

      // The name is required.
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await settle(tester);
      expect(find.text('This field is required'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('customer-name-field')), 'Samer');
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await animated(tester);

      // Straight back on the sale, with the new customer and card attached.
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(find.byType(CustomerPickerScreen), findsNothing);
      expect(find.descendant(of: chip, matching: find.textContaining('Samer')),
          findsOneWidget);
      expect(find.descendant(of: chip, matching: find.textContaining('7700-1')),
          findsOneWidget);

      final created = await db(
        tester,
        () => database.db.query('customer_accounts',
            where: 'account_number = ?', whereArgs: ['7700-1']),
      );
      expect(created.single['account_number_norm'], '77001');
    });

    testWidgets('text with a digit and no space may also be a card number',
        (tester) async {
      await db(tester, seed);
      await openPicker(tester, 'AB-1200');
      expect(find.byKey(const ValueKey('new-customer-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-customer-accountNumber')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('new-customer-phone')), findsNothing);
    });

    testWidgets('"New customer" is there before anything is typed',
        (tester) async {
      await db(tester, seed);
      await openPicker(tester, '');
      expect(find.text('New customer'), findsOneWidget);
      await tester.tap(find.text('New customer'));
      await animated(tester);
      expect(field(tester, 'customer-name-field'), '');
    });

    test('the offered rows follow the typed text', () {
      expect(newCustomerOptions(''), [NewCustomerPrefill.name]);
      expect(newCustomerOptions('Ahmad'), [NewCustomerPrefill.name]);
      expect(newCustomerOptions('Ahmad 2'), [NewCustomerPrefill.name]);
      expect(newCustomerOptions('0944123456'),
          [NewCustomerPrefill.phone, NewCustomerPrefill.accountNumber]);
      expect(newCustomerOptions('٠٩٤٤ ١٢٣'),
          [NewCustomerPrefill.phone, NewCustomerPrefill.accountNumber]);
      expect(newCustomerOptions('AB-1200'),
          [NewCustomerPrefill.name, NewCustomerPrefill.accountNumber]);
    });
  });

  group('the duplicate-number warning', () {
    final dialog = find.byKey(const ValueKey('account-duplicate-dialog'));

    Future<void> fill(
      WidgetTester tester, {
      required String number,
      required String provider,
    }) async {
      await tester.enterText(
          find.byKey(const ValueKey('account-number-field')), number);
      await tester.enterText(
          find.byKey(const ValueKey('account-provider-field')), provider);
      await settle(tester, 4);
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await animated(tester);
    }

    Future<int> accountCount(WidgetTester tester) async =>
        (await db(tester, () => database.db.query('customer_accounts')))
            .length;

    testWidgets('warns for the same number and provider, however typed',
        (tester) async {
      await db(tester, seed);
      final samer =
          await db(tester, () => customers.insert(const Customer(name: 'Samer')));
      await pump(tester, AccountFormScreen(customerId: samer));

      await fill(tester, number: '٠٠١١ ٢٢٣٣', provider: 'mtn');
      expect(dialog, findsOneWidget);
      // It names who already has the number.
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Ahmad Hasan')),
        findsOneWidget,
      );
      expect(await accountCount(tester), 1, reason: 'nothing saved yet');

      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(find.byType(AccountFormScreen), findsOneWidget);
      expect(await accountCount(tester), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the warning can be overridden', (tester) async {
      await db(tester, seed);
      final samer =
          await db(tester, () => customers.insert(const Customer(name: 'Samer')));
      await pump(tester, AccountFormScreen(customerId: samer));

      await fill(tester, number: '0011-2233', provider: 'MTN');
      await tester.tap(find.byKey(const ValueKey('account-duplicate-save')));
      await animated(tester);

      expect(await accountCount(tester), 2);
      final mine = await db(tester, () => customers.accountsOf(samer));
      expect(mine.single.account!.accountNumber, '0011-2233');
    });

    testWidgets('another provider is no duplicate: saved without asking',
        (tester) async {
      await db(tester, seed);
      final samer =
          await db(tester, () => customers.insert(const Customer(name: 'Samer')));
      await pump(tester, AccountFormScreen(customerId: samer));

      await fill(tester, number: '0011-2233', provider: 'Syriatel');
      expect(dialog, findsNothing);
      expect(await accountCount(tester), 2);
    });

    testWidgets('editing an account does not warn about itself',
        (tester) async {
      await db(tester, seed);
      final account =
          await db(tester, () async => (await customers.getAccount(accountId))!);
      await pump(
        tester,
        AccountFormScreen(customerId: ahmadId, account: account),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await animated(tester);
      expect(dialog, findsNothing);
    });

    testWidgets('the new-customer form warns about its card number too',
        (tester) async {
      await db(tester, seed);
      await pump(
        tester,
        const CustomerFormScreen(initialAccountNumber: '0011 2233'),
      );
      await tester.enterText(
          find.byKey(const ValueKey('customer-name-field')), 'Samer');
      await tester.enterText(
          find.byKey(const ValueKey('account-provider-field')), 'MTN');
      await tester.ensureVisible(find.byKey(const ValueKey('customer-save')));
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await animated(tester);
      expect(dialog, findsOneWidget);
      expect(await db(tester, () => database.db.query('customers')),
          hasLength(1));
    });
  });

  group('the account form', () {
    testWidgets('the number is required, the period must be a number',
        (tester) async {
      await db(tester, seed);
      await pump(tester, AccountFormScreen(customerId: ahmadId));
      await tester.enterText(
          find.byKey(const ValueKey('account-days-field')), 'soon');
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await settle(tester);
      expect(find.text('This field is required', skipOffstage: false),
          findsOneWidget);
      expect(find.text('Invalid number', skipOffstage: false), findsOneWidget);
    });

    testWidgets('suggests the providers typed before', (tester) async {
      await db(tester, seed);
      await db(tester, () async {
        await customers.insertAccount(CustomerAccount(
          customerId: ahmadId,
          accountNumber: '5',
          provider: 'Syriatel',
        ));
        return true;
      });
      await pump(tester, AccountFormScreen(customerId: ahmadId));
      expect(find.byKey(const ValueKey('provider-suggestion-MTN')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('provider-suggestion-Syriatel')),
          findsOneWidget);

      // Typing narrows them; a tap fills the field.
      await tester.enterText(
          find.byKey(const ValueKey('account-provider-field')), 'syr');
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('provider-suggestion-MTN')),
          findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('provider-suggestion-Syriatel')));
      await settle(tester, 4);
      expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('account-provider-field')))
            .controller!
            .text,
        'Syriatel',
      );
    });

    testWidgets('next due is last renewal + period', (tester) async {
      await db(tester, seed);
      final account =
          await db(tester, () async => (await customers.getAccount(accountId))!);
      await pump(
        tester,
        AccountFormScreen(customerId: ahmadId, account: account),
      );
      // 30 days → 7 days: the due date follows.
      await tester.enterText(
          find.byKey(const ValueKey('account-days-field')), '٧');
      await settle(tester, 4);
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await animated(tester);

      final row = await accountRow(tester);
      expect(row['renewal_days'], 7);
      final last = DateTime.fromMillisecondsSinceEpoch(
        row['last_renewal_at'] as int,
        isUtc: true,
      );
      expect(
        row['next_due_at'],
        nextDueAfter(last, 7).toUtc().millisecondsSinceEpoch,
      );
    });

    testWidgets('a leading zero and letters survive the form', (tester) async {
      await db(tester, seed);
      await pump(tester, AccountFormScreen(customerId: ahmadId));
      await tester.enterText(
          find.byKey(const ValueKey('account-number-field')), '00ab-12');
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await animated(tester);
      final rows = await db(
        tester,
        () => database.db.query('customer_accounts',
            where: 'account_number = ?', whereArgs: ['00ab-12']),
      );
      expect(rows.single['account_number_norm'], '00AB12');
    });
  });

  group('due for renewal screen', () {
    /// Three more accounts around a fixed "today" of 1 December 2026.
    Future<bool> seedBuckets() async {
      final id = await customers
          .insert(const Customer(name: 'Samer', phone: '0933 555 111'));
      await customers.insertAccount(CustomerAccount(
        customerId: id,
        accountNumber: 'TODAY-1',
        nextDueAt: DateTime(2026, 12, 1),
      ));
      await customers.insertAccount(CustomerAccount(
        customerId: id,
        accountNumber: 'SOON-1',
        nextDueAt: DateTime(2026, 12, 2),
      ));
      await customers.insertAccount(CustomerAccount(
        customerId: id,
        accountNumber: 'LATER-1',
        nextDueAt: DateTime(2026, 12, 20),
      ));
      await customers.insertAccount(CustomerAccount(
        customerId: id,
        accountNumber: 'OLD-1',
        nextDueAt: DateTime(2026, 11, 20),
      ));
      return true;
    }

    testWidgets('lists overdue, today and the next days, in words',
        (tester) async {
      await db(tester, seedBuckets);
      await pump(tester, const DueScreen(),
          clock: () => DateTime(2026, 12, 1, 10));

      expect(find.text('Overdue (1)'), findsOneWidget);
      expect(find.text('Due today (1)'), findsOneWidget);
      expect(find.text('Due in the next 3 days (1)'), findsOneWidget);
      expect(find.textContaining('Overdue by 11 days'), findsOneWidget);
      expect(find.textContaining('Due today'), findsWidgets);
      expect(find.textContaining('Due tomorrow'), findsOneWidget);
      expect(find.textContaining('LATER-1'), findsNothing);
      // Sorted by due date: the oldest on top.
      expect(
        tester.getTopLeft(find.textContaining('OLD-1')).dy,
        lessThan(tester.getTopLeft(find.textContaining('TODAY-1')).dy),
      );
      expect(
        tester.getTopLeft(find.textContaining('TODAY-1')).dy,
        lessThan(tester.getTopLeft(find.textContaining('SOON-1')).dy),
      );
      // Each row has the phone number.
      expect(find.textContaining('0933 555 111'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('one minute before midnight "today" is still today',
        (tester) async {
      await db(tester, seedBuckets);
      await pump(tester, const DueScreen(),
          clock: () => DateTime(2026, 12, 1, 23, 59));
      expect(find.text('Overdue (1)'), findsOneWidget);
      expect(find.text('Due today (1)'), findsOneWidget);
      expect(find.text('Due in the next 3 days (1)'), findsOneWidget);
    });

    testWidgets('at midnight the buckets move on', (tester) async {
      await db(tester, seedBuckets);
      await pump(tester, const DueScreen(), clock: () => DateTime(2026, 12, 2));
      // Yesterday's "today" is overdue, yesterday's "tomorrow" is today.
      expect(find.text('Overdue (2)'), findsOneWidget);
      expect(find.text('Due today (1)'), findsOneWidget);
      expect(find.textContaining('Due in the next'), findsNothing);
      expect(find.textContaining('Overdue by 1 day'), findsOneWidget);
    });

    testWidgets('the window follows the setting', (tester) async {
      await db(tester, seedBuckets);
      await db(tester, () async {
        await database.db.insert('settings', {
          'key': SettingsKeys.dueSoonDays,
          'value': '30',
          'updated_at': 0,
        });
        return true;
      });
      await pump(tester, const DueScreen(),
          clock: () => DateTime(2026, 12, 1, 10));
      expect(find.text('Due in the next 30 days (2)'), findsOneWidget);
      expect(find.textContaining('LATER-1'), findsOneWidget);
      expect(find.textContaining('Due in 19 days'), findsOneWidget);
    });

    testWidgets('nothing due says so', (tester) async {
      await pump(tester, const DueScreen());
      expect(find.byKey(const ValueKey('due-empty')), findsOneWidget);
    });

    testWidgets('the reminder opens the customer\'s WhatsApp chat with text',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const DueScreen());
      await tester.tap(find.byKey(ValueKey('due-remind-$accountId')));
      await settle(tester);

      final chat = bridge.chats.single;
      // The customer's own number, in international form.
      expect(chat.phone, '963944123456');
      expect(chat.package, 'com.whatsapp');
      // The default text, in the invoice language (Arabic by default).
      expect(chat.text, contains('Ahmad Hasan'));
      expect(chat.text, contains('0011-2233'));
      expect(chat.text, contains('مرحباً'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reminder uses the shop\'s own text when there is one',
        (tester) async {
      await db(tester, seed);
      await db(tester, () async {
        await database.db.insert('settings', {
          'key': SettingsKeys.renewalReminderText,
          'value': 'Dear [name], card [account] ([provider]) is due.',
          'updated_at': 0,
        });
        return true;
      });
      await pump(tester, const DueScreen());
      await tester.tap(find.byKey(ValueKey('due-remind-$accountId')));
      await settle(tester);
      expect(
        bridge.chats.single.text,
        'Dear Ahmad Hasan, card 0011-2233 (MTN) is due.',
      );
    });

    testWidgets('the English default follows the invoice language',
        (tester) async {
      await db(tester, seed);
      await db(tester, () async {
        await database.db.update(
          'settings',
          {'value': 'en'},
          where: 'key = ?',
          whereArgs: [SettingsKeys.invoiceLanguage],
        );
        return true;
      });
      await pump(tester, const DueScreen());
      await tester.tap(find.byKey(ValueKey('due-remind-$accountId')));
      await settle(tester);
      expect(bridge.chats.single.text, startsWith('Hello Ahmad Hasan'));
    });

    testWidgets('no WhatsApp on the phone: says so, opens nothing',
        (tester) async {
      await db(tester, seed);
      bridge.installedWhatsApp = const [];
      await pump(tester, const DueScreen());
      await tester.tap(find.byKey(ValueKey('due-remind-$accountId')));
      await settle(tester);
      expect(bridge.chats, isEmpty);
      expect(find.text('WhatsApp is not installed on this phone'),
          findsOneWidget);
    });

    testWidgets('a customer with no phone has no reminder button',
        (tester) async {
      await db(tester, () async {
        final id = await customers.insert(const Customer(name: 'No Phone'));
        await customers.insertAccount(CustomerAccount(
          customerId: id,
          accountNumber: 'NP-1',
          nextDueAt: DateTime(2020),
        ));
        return true;
      });
      await pump(tester, const DueScreen());
      expect(find.text('Renew'), findsOneWidget);
      expect(find.text('Remind on WhatsApp'), findsNothing);
    });

    testWidgets('Renew is one tap from the list', (tester) async {
      await db(tester, seed);
      await pump(tester, const DueScreen());
      await tester.tap(find.byKey(ValueKey('due-renew-$accountId')));
      await animated(tester);
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'ADSL 4 Mbps'), findsOneWidget);
    });
  });

  group('customers screen', () {
    testWidgets('lists, searches by name or phone, and opens a customer',
        (tester) async {
      await db(tester, seed);
      await db(tester,
          () => customers.insert(const Customer(name: 'Samer', phone: '0933')));
      await pump(tester, const CustomersScreen());

      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.text('Samer'), findsOneWidget);
      expect(find.textContaining('1 card / account'), findsOneWidget);

      final field = find.byKey(const ValueKey('customers-search-field'));
      await tester.enterText(field, '٠٩٤٤ ١٢٣');
      await settle(tester);
      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.text('Samer'), findsNothing);

      await tester.enterText(field, 'same');
      await settle(tester);
      expect(find.text('Samer'), findsOneWidget);
      expect(find.text('Ahmad Hasan'), findsNothing);

      await tester.tap(find.text('Samer'));
      await animated(tester);
      expect(find.byType(CustomerDetailScreen), findsOneWidget);
    });

    testWidgets('adds a customer and opens their page', (tester) async {
      await pump(tester, const CustomersScreen());
      expect(find.text('No customers yet'), findsOneWidget);

      await tester.tap(find.text('Add customer'));
      await animated(tester);
      await tester.enterText(
          find.byKey(const ValueKey('customer-name-field')), 'Layla');
      await tester.enterText(
          find.byKey(const ValueKey('customer-phone-field')), '0966 111 222');
      await tester.enterText(
          find.byKey(const ValueKey('customer-notes-field')), 'pays weekly');
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await animated(tester);

      expect(find.byType(CustomerDetailScreen), findsOneWidget);
      expect(find.text('Layla'), findsOneWidget);
      expect(find.textContaining('0966 111 222'), findsOneWidget);
      expect(find.text('pays weekly'), findsOneWidget);
      final rows = await db(tester, () => database.db.query('customers'));
      expect(rows.single['phone_norm'], '0966111222');
    });

    testWidgets('a deactivated customer shows only when asked',
        (tester) async {
      await db(tester, seed);
      await db(tester, () async {
        await customers.setActive(ahmadId, false);
        return true;
      });
      await pump(tester, const CustomersScreen());
      expect(find.text('Ahmad Hasan'), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await animated(tester);
      await tester.tap(find.byType(CheckedPopupMenuItem<void>));
      await animated(tester);
      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });
  });

  group('customer page', () {
    /// One renewal of the fixture account, saved through the repository.
    Future<void> renewOnce(WidgetTester tester) async {
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, '0011');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('renew-$accountId')));
      await animated(tester);
      await tester.tap(saveButton);
      await animated(tester);
    }

    testWidgets('shows the accounts, the history and the totals',
        (tester) async {
      await db(tester, seed);
      await renewOnce(tester);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));

      expect(find.text('Ahmad Hasan'), findsOneWidget);
      expect(find.textContaining('0944 123 456'), findsOneWidget);
      // The account, now renewed: it is OK again.
      final account = find.byKey(ValueKey('customer-account-$accountId'));
      expect(account, findsOneWidget);
      expect(find.descendant(of: account, matching: find.textContaining('OK')),
          findsOneWidget);
      // The renewal in the history, and in the totals.
      expect(find.byKey(const ValueKey('customer-invoice-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customer-invoice-1')),
          matching: find.text('ADSL 4 Mbps'),
        ),
        findsOneWidget,
      );
      final totals = find.byKey(const ValueKey('customer-totals'));
      expect(find.descendant(of: totals, matching: find.text('1')),
          findsOneWidget);
      expect(
        find.descendant(of: totals, matching: find.textContaining('35,000')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a history row opens the invoice', (tester) async {
      await db(tester, seed);
      await renewOnce(tester);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));
      await tester.ensureVisible(find.byKey(const ValueKey('customer-invoice-1')));
      await tester.tap(find.byKey(const ValueKey('customer-invoice-1')));
      await animated(tester);
      expect(find.byType(InvoiceDetailScreen), findsOneWidget);
    });

    testWidgets('Call opens the dialer, WhatsApp opens the chat',
        (tester) async {
      await db(tester, seed);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));

      await tester.tap(find.byKey(const ValueKey('customer-call')));
      await settle(tester);
      expect(bridge.dialed, ['0944 123 456']);

      await tester.tap(find.byKey(const ValueKey('customer-whatsapp')));
      await settle(tester);
      expect(bridge.chats.single.phone, '963944123456');
      expect(bridge.chats.single.text, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no dialer on the device: says so', (tester) async {
      await db(tester, seed);
      bridge.dialerOpens = false;
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));
      await tester.tap(find.byKey(const ValueKey('customer-call')));
      await settle(tester);
      expect(find.text('Could not open the phone dialer'), findsOneWidget);
    });

    testWidgets('a customer with no phone has no contact buttons',
        (tester) async {
      final id = await db(
        tester,
        () => customers.insert(const Customer(name: 'No Phone')),
      );
      await pump(tester, CustomerDetailScreen(customerId: id));
      expect(find.byKey(const ValueKey('customer-call')), findsNothing);
      expect(find.byKey(const ValueKey('customer-whatsapp')), findsNothing);
      expect(find.text('No cards or accounts yet'), findsOneWidget);
      expect(find.text('No invoices yet'), findsOneWidget);
    });

    testWidgets('is deactivated after a confirmation, and reactivated',
        (tester) async {
      await db(tester, seed);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));

      await tester.tap(find.byKey(const ValueKey('customer-menu')));
      await animated(tester);
      await tester.tap(find.text('Deactivate'));
      await animated(tester);
      final dialog = find.byKey(const ValueKey('deactivate-customer-dialog'));
      expect(dialog, findsOneWidget);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Deactivate')),
      );
      await animated(tester);

      expect(find.byKey(const ValueKey('customer-inactive')), findsOneWidget);
      final row = await db(
        tester,
        () async => (await database.db.query('customers')).single,
      );
      expect(row['is_active'], 0, reason: 'deactivated, not deleted');
      // No renewing a deactivated customer from their own page.
      expect(find.text('Renew'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('customer-menu')));
      await animated(tester);
      await tester.tap(find.text('Reactivate'));
      await animated(tester);
      expect(find.byKey(const ValueKey('customer-inactive')), findsNothing);
      expect(find.text('Renew'), findsOneWidget);
    });

    testWidgets('an account is added from the page', (tester) async {
      await db(tester, seed);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));
      await tester.tap(find.byKey(const ValueKey('customer-add-account')));
      await animated(tester);
      expect(find.byType(AccountFormScreen), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('account-number-field')), '0099');
      await tester.ensureVisible(find.byKey(const ValueKey('account-save')));
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await animated(tester);

      expect(find.byType(AccountFormScreen), findsNothing);
      expect(find.textContaining('0099'), findsOneWidget);
      expect(find.textContaining('No due date'), findsOneWidget);
    });

    testWidgets('the customer is edited from the page', (tester) async {
      await db(tester, seed);
      await pump(tester, CustomerDetailScreen(customerId: ahmadId));
      await tester.tap(find.byKey(const ValueKey('customer-edit')));
      await animated(tester);
      // Editing: no "first account" section.
      expect(find.byKey(const ValueKey('customer-account-number-field')),
          findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('customer-name-field')), 'Ahmad H.');
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await animated(tester);
      expect(find.byType(CustomerFormScreen), findsNothing);
      expect(find.text('Ahmad H.'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the due-soon window can be changed', (tester) async {
      await pump(tester, const SettingsScreen());
      final dropdown =
          find.byKey(const ValueKey('setting-due-soon-dropdown'));
      await tester.ensureVisible(dropdown);
      await settle(tester, 4);
      expect(
        find.descendant(of: dropdown, matching: find.text('3 days')),
        findsOneWidget,
        reason: 'the default',
      );
      await tester.tap(dropdown);
      await animated(tester);
      await tester.tap(find.text('7 days').last);
      await animated(tester);

      final stored = await db(
        tester,
        () => database.db.query('settings',
            where: 'key = ?', whereArgs: [SettingsKeys.dueSoonDays]),
      );
      expect(stored.single['value'], '7');
      expect(find.descendant(of: dropdown, matching: find.text('7 days')),
          findsOneWidget);
    });

    testWidgets('the reminder text is edited, and reset to the default',
        (tester) async {
      Future<String?> stored() async {
        final rows = await db(
          tester,
          () => database.db.query('settings',
              where: 'key = ?', whereArgs: [SettingsKeys.renewalReminderText]),
        );
        return rows.isEmpty ? null : rows.single['value'] as String?;
      }

      await pump(tester, const SettingsScreen());
      final tile = find.byKey(const ValueKey('setting-reminder-text'));
      // Below the fold of the settings list, which builds lazily.
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester, 4);
      await tester.tap(tile);
      await animated(tester);

      final field = find.byKey(const ValueKey('reminder-text-field'));
      // Starts from the default, in the invoice language (Arabic).
      expect(tester.widget<TextField>(field).controller!.text,
          contains('[name]'));
      expect(find.textContaining('[account] [provider]'), findsOneWidget);

      await tester.enterText(field, 'Renew please, [name]');
      await tester.tap(find.text('Save'));
      await animated(tester);
      expect(await stored(), 'Renew please, [name]');

      // "Use default" puts the built-in text back; saving it stores nothing,
      // so it keeps following the invoice language.
      await tester.tap(tile);
      await animated(tester);
      expect(tester.widget<TextField>(field).controller!.text,
          'Renew please, [name]');
      await tester.tap(find.byKey(const ValueKey('reminder-use-default')));
      await settle(tester, 4);
      await tester.tap(find.text('Save'));
      await animated(tester);
      expect(await stored(), '');
      expect(tester.takeException(), isNull);
    });
  });

  group('statistics', () {
    testWidgets('show renewals, top packages and sales per customer',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());
      await tester.enterText(searchBox, '0011');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('renew-$accountId')));
      await animated(tester);
      await tester.tap(saveButton);
      await animated(tester);

      await pump(tester, const StatsScreen());
      await settle(tester, 24);
      final renewals = find.byKey(const ValueKey('stats-renewals'));
      await tester.scrollUntilVisible(
        renewals,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await settle(tester);
      expect(renewals, findsOneWidget);
      expect(
        find.descendant(of: renewals, matching: find.text('1 invoices')),
        findsOneWidget,
      );
      final packages = find.byKey(const ValueKey('stats-top-packages'));
      await tester.scrollUntilVisible(
        packages,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.descendant(of: packages, matching: find.text('ADSL 4 Mbps')),
        findsOneWidget,
      );
      final byCustomer = find.byKey(const ValueKey('stats-top-customers'));
      await tester.scrollUntilVisible(
        byCustomer,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.descendant(of: byCustomer, matching: find.text('Ahmad Hasan')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a shop with no renewals sees none of it', (tester) async {
      await db(tester, seed);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');
      await tester.tap(saveButton);
      await animated(tester);

      await pump(tester, const StatsScreen());
      await settle(tester, 24);
      expect(find.byKey(const ValueKey('stats-total-value')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-renewals'), skipOffstage: false),
          findsNothing);
      expect(
        find.byKey(const ValueKey('stats-top-customers'), skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('after a sale', () {
    testWidgets('an archive opened before the sale shows the new invoice',
        (tester) async {
      await db(tester, seed);
      await pump(tester, const HomeScreen());

      // Open the archive once while it is empty: its list is loaded and
      // kept for the rest of the session.
      await tester.tap(find.byKey(const ValueKey('home-nav-archive')));
      await animated(tester);
      expect(find.byType(ArchiveScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsNothing);
      await tester.pageBack();
      await animated(tester);

      await tester.tap(find.byKey(const ValueKey('home-nav-sale')));
      await animated(tester);
      await addByCode(tester, '101');
      await tester.tap(saveButton);
      await animated(tester);
      await tester.tap(find.text('Back to home'));
      await animated(tester);

      await tester.tap(find.byKey(const ValueKey('home-nav-archive')));
      await animated(tester);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Arabic', () {
    testWidgets('the home, the search and the due words are translated',
        (tester) async {
      await db(tester, seed);
      await setShopType(tester, 'CARDS');
      await pump(tester, const HomeScreen(), locale: 'ar');

      expect(find.text('متأخرة (1)'), findsOneWidget);
      final context = tester.element(find.byType(HomeScreen));
      expect(Directionality.of(context), TextDirection.rtl);

      // The rows themselves — how late, and Renew — are on the due screen.
      await tester.tap(find.byKey(const ValueKey('home-due-see-all')));
      await animated(tester);
      expect(find.textContaining('متأخر يوماً واحداً'), findsOneWidget);
      expect(find.text('تجديد'), findsOneWidget);
      // Not pageBack(): it looks for the English "Back" tooltip.
      await tester.tap(find.byType(BackButton));
      await animated(tester);

      await tester.enterText(searchBox, '٠٠١١');
      await settle(tester);
      expect(find.byKey(ValueKey('quick-hit-$ahmadId-$accountId')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
