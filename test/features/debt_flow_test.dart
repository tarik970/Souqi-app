import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:souqi/features/customers/customer_form_screen.dart';
import 'package:souqi/features/debts/debtors_screen.dart';
import 'package:souqi/features/debts/opening_balances_screen.dart';
import 'package:souqi/features/debts/payment_form_screen.dart';
import 'package:souqi/features/debts/receipt_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/security/audit_log_screen.dart';
import 'package:souqi/features/security/pin_session.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/vouchers/code_widgets.dart';
import 'package:souqi/features/setup/setup_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';
import 'stats_test_utils.dart';

/// The debt ledger through its screens: a sale that goes on credit, the
/// customer's account, a payment and its receipt, a reversal, the debtors
/// list, opening balances, the statement — and the places the ledger shows
/// up elsewhere (home, statistics, the delete dialogs, the settings).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // A tap that lands on nothing must fail the test, not pass it vacuously.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late Directory outputDir;
  late DebtRepository debts;
  late int ahmad; // has a phone
  late int sara; // no phone

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

  /// Pumps frames (and lets real async work run) until [done] holds:
  /// rendering and file writes take a variable amount of real time.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1500 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(done(), isTrue, reason: 'timed out waiting');
    await settle(tester, 3);
  }

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    outputDir = await Directory.systemTemp.createTemp('souqi-debt-flow');
    debts = DebtRepository(database.db);
    final customers = CustomerRepository(database.db);
    ahmad = await customers
        .insert(const Customer(name: 'Ahmad Hasan', phone: '0944 123 456'));
    sara = await customers.insert(const Customer(name: 'Sara Ali'));
    // Sugar (101) costs 1,000; Rice (102) costs 8,000.
    await insertProduct(database.db, name: 'Sugar', code: '101');
    final rice = await insertProduct(database.db, name: 'Rice', code: '102');
    await database.db.update('products', {'price_minor': 8000},
        where: 'id = ?', whereArgs: [rice]);
  });

  tearDown(() async {
    await database.close();
    if (outputDir.existsSync()) await outputDir.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool debtOn = true,
    String locale = 'en',
  }) async {
    // A phone-shaped viewport, 600×1300 logical pixels.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The ledger off = a license (or a build) without it: `featureOn`.
    FeatureGate.applyWithout([if (!debtOn) Feature.debt]);
    addTearDown(FeatureGate.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(Locale(locale))),
          // The fake phone, UNDER the app's own doorway: what the doorway
          // tells the PIN locks ("the app is opening WhatsApp") is real.
          platformBridgeProvider.overrideWithValue(bridge),
          outputDirectoryProvider.overrideWithValue(() async => outputDir),
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

  Future<void> store(WidgetTester tester, Map<String, String> values) => db(
        tester,
        () async {
          await SettingsRepository(database.db).setMany(values);
          return true;
        },
      );

  Future<void> setPin(WidgetTester tester) => db(tester, () async {
        await PinRepository(SettingsRepository(database.db)).set('2580');
        return true;
      });

  Future<void> enterPin(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('pin-entry-field')), '2580');
    await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
    await animated(tester);
  }

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String table, {
    String? orderBy,
  }) =>
      db(tester, () => database.db.query(table, orderBy: orderBy ?? 'id'));

  Future<int> balance(WidgetTester tester, int customer) =>
      db(tester, () => debts.balanceOf(customer));

  /// A debt of [amount] dated [daysAgo] days ago.
  Future<DebtEntry> owe(
    WidgetTester tester,
    int customer,
    int amount, {
    int daysAgo = 0,
  }) =>
      db(
        tester,
        () => debts.addManualDebt(
          customerId: customer,
          amountBaseMinor: amount,
          at: DateTime.now().subtract(Duration(days: daysAgo, minutes: 1)),
        ),
      );

  Future<DebtEntry> pay(
    WidgetTester tester,
    int customer,
    int amount, {
    int daysAgo = 0,
  }) =>
      db(
        tester,
        () => debts.recordPayment(
          customerId: customer,
          amountMinor: amount,
          currencyCode: 'SYP',
          currencyDecimals: 0,
          baseCode: 'SYP',
          baseDecimals: 0,
          at: DateTime.now().subtract(Duration(days: daysAgo)),
        ),
      );

  /// An invoice of [total] for [customer], [paid] of it paid — saved through
  /// the repository, like the sale screen does.
  Future<Invoice> creditInvoice(
    WidgetTester tester,
    int customer, {
    int total = 8000,
    int paid = 3000,
  }) =>
      db(tester, () {
        final ctx = CurrencyContext.of(
          [syp, usd],
          baseCode: 'SYP',
        );
        return InvoiceRepository(database.db).save(
          Invoice.fromCart(
            cart: const Cart().add(CartLine(
              name: 'Rice',
              unitPriceMinor: total,
              priceCurrencyCode: 'SYP',
              qtyThousandths: 1000,
            )),
            ctx: ctx,
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
            customerId: customer,
            customerName: 'Ahmad Hasan',
            customerPhone: '0944 123 456',
          ),
          payment: SalePayment(paidMinor: paid),
        );
      });

  final saleSearch = find.byKey(const ValueKey('sale-search-field'));
  final saveButton = find.byKey(const ValueKey('sale-save'));
  final sheet = find.byKey(const ValueKey('payment-sheet'));
  final paySave = find.byKey(const ValueKey('pay-save'));
  final creditButton = find.byKey(const ValueKey('sale-credit'));

  Future<void> addByCode(WidgetTester tester, String code) async {
    await tester.enterText(saleSearch, code);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  /// Attaches [customer] to the sale in progress, as the customer chip does.
  void attach(WidgetTester tester, int customer, String name) {
    ProviderScope.containerOf(tester.element(find.byType(SaleScreen)))
        .read(saleCustomerProvider.notifier)
        .attach(SaleCustomer(customerId: customer, name: name));
  }

  /// Opens the payment sheet with the "Credit / Partial" button — Save
  /// itself never opens it.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(creditButton);
    await animated(tester);
    expect(sheet, findsOneWidget);
  }

  /// The text of the widget keyed [key] — the widget itself when it is a
  /// [Text], otherwise the first text inside it (a balance, a badge).
  String textOf(WidgetTester tester, String key) {
    final finder = find.byKey(ValueKey(key));
    final widget = tester.widget(finder);
    if (widget is Text) return widget.data!;
    return tester
        .widget<Text>(
          find.descendant(of: finder, matching: find.byType(Text)).first,
        )
        .data!;
  }

  /// Scrolls the page down until [finder] is on screen. What is below the
  /// fold of a lazy list does not exist yet — and what is merely in its
  /// cache is built but cannot be tapped.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable && widget.axisDirection == AxisDirection.down,
        )
        .last;
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -250), warnIfMissed: false);
      await settle(tester, 2);
    }
    await tester.ensureVisible(finder);
    await settle(tester, 4);
  }

  group('the sale', () {
    testWidgets('a cash sale is ONE tap: Save saves it as paid in full, with '
        'no sheet and nothing on any account', (tester) async {
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');

      await tester.tap(saveButton);
      await animated(tester);

      expect(sheet, findsNothing);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-paid-line')), findsNothing);
      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['paid_minor'], 1000);
      expect(invoice['credit_used_minor'], 0);
      expect(invoice['customer_id'], isNull);
      expect(await rows(tester, 'debt_transactions'), isEmpty);
    });

    testWidgets('one tap for a known customer too: paid in full, their '
        'balance untouched and noted on the invoice', (tester) async {
      await owe(tester, ahmad, 2000, daysAgo: 3);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);

      await tester.tap(saveButton);
      await animated(tester);

      expect(sheet, findsNothing);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['paid_minor'], 8000);
      expect(invoice['prev_balance_base_minor'], 2000);
      expect(invoice['new_balance_base_minor'], 2000);
      expect(await balance(tester, ahmad), 2000);
      expect(await rows(tester, 'debt_transactions'), hasLength(1));
    });

    testWidgets('even a customer over their credit limit buys for cash in '
        'one tap', (tester) async {
      await db(tester, () async {
        await database.db.update(
          'customers',
          {'credit_limit_base_minor': 1000},
          where: 'id = ?',
          whereArgs: [ahmad],
        );
        return true;
      });
      await owe(tester, ahmad, 6000, daysAgo: 3);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);
      await tester.tap(saveButton);
      await animated(tester);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect(await rows(tester, 'audit_log'), isEmpty);
    });

    testWidgets('"Credit / Partial" sits beside Save and opens the sheet, on '
        '"On credit"; both are disabled on an empty cart', (tester) async {
      await pump(tester, const SaleScreen());
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(creditButton).onPressed, isNull);

      await addByCode(tester, '101');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(creditButton).onPressed, isNotNull);
      // Side by side, Save first and the wider of the two.
      expect(tester.getTopLeft(saveButton).dy, tester.getTopLeft(creditButton).dy);
      expect(tester.getSize(saveButton).height,
          tester.getSize(creditButton).height);
      expect(tester.getSize(saveButton).width,
          greaterThan(tester.getSize(creditButton).width));
      expect(find.text('Credit / Partial'), findsOneWidget);

      await openSheet(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('pay-mode-credit')))
            .selected,
        isTrue,
      );
      expect(textOf(tester, 'payment-sheet-total'), '1,000 ل.س');
      expect(textOf(tester, 'pay-remaining'), 'Goes on the account: 1,000 ل.س');
      // On credit with no customer: the sheet asks for one.
      expect(find.byKey(const ValueKey('pay-choose-customer')), findsOneWidget);
    });

    testWidgets('dismissing the sheet saves nothing and keeps the cart',
        (tester) async {
      await pump(tester, const SaleScreen());
      await addByCode(tester, '101');
      await openSheet(tester);
      await tester.binding.handlePopRoute();
      await animated(tester);

      expect(sheet, findsNothing);
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(textOf(tester, 'cart-total'), contains('1,000'));
      expect(await rows(tester, 'invoices'), isEmpty);
    });

    testWidgets('the sheet still works out the change: "Paid in full" with '
        'cash received', (tester) async {
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('pay-mode-full')));
      await settle(tester);
      expect(find.byKey(const ValueKey('pay-choose-customer')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('pay-cash-received')), '10000');
      await settle(tester);
      expect(textOf(tester, 'pay-change'), 'Change to give back: 2,000 ل.س');
      await tester.enterText(
          find.byKey(const ValueKey('pay-cash-received')), '5000');
      await settle(tester);
      expect(textOf(tester, 'pay-change'), 'Less than the amount to pay');

      // And saving from there is still a sale paid in full.
      await tester.tap(paySave);
      await animated(tester);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect((await rows(tester, 'invoices')).single['paid_minor'], 8000);
      expect(await rows(tester, 'debt_transactions'), isEmpty);
    });

    group('the optional "cash received" line under the total', () {
      final line = find.byKey(const ValueKey('cash-received-line'));

      testWidgets('is hidden unless the setting is on', (tester) async {
        await pump(tester, const SaleScreen());
        await addByCode(tester, '102');
        expect(line, findsNothing);
      });

      testWidgets('shows the change, and Save is still one tap, paid in full',
          (tester) async {
        await store(tester, {SettingsKeys.showCashReceived: '1'});
        await pump(tester, const SaleScreen());
        // Nothing to receive for an empty cart.
        expect(line, findsNothing);
        await addByCode(tester, '102');
        expect(line, findsOneWidget);
        expect(find.byKey(const ValueKey('cash-received-change')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('cash-received-button')));
        await animated(tester);
        expect(find.text('Total: 8,000 ل.س'), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey('cash-received-field')), '10000');
        await settle(tester);
        expect(textOf(tester, 'cash-received-dialog-change'),
            'Change to give back: 2,000 ل.س');
        await tester.tap(find.byKey(const ValueKey('cash-received-ok')));
        await animated(tester);

        expect(find.text('Received 10,000 ل.س'), findsOneWidget);
        expect(textOf(tester, 'cash-received-change'), 'Change 2,000 ل.س');

        // Another item: the change follows the total.
        await addByCode(tester, '101');
        expect(textOf(tester, 'cash-received-change'), 'Change 1,000 ل.س');

        await tester.tap(saveButton);
        await animated(tester);
        expect(sheet, findsNothing);
        expect(find.byType(SaleInvoiceScreen), findsOneWidget);
        final invoice = (await rows(tester, 'invoices')).single;
        expect(invoice['total_minor'], 9000);
        expect(invoice['paid_minor'], 9000);
        expect(await rows(tester, 'debt_transactions'), isEmpty);
      });

      testWidgets('less than the total says so; it can be cleared; a new '
          'sale starts empty', (tester) async {
        await store(tester, {SettingsKeys.showCashReceived: '1'});
        await pump(tester, const SaleScreen());
        await addByCode(tester, '102');
        await tester.tap(find.byKey(const ValueKey('cash-received-button')));
        await animated(tester);
        // Nothing typed is not an amount.
        await tester.tap(find.byKey(const ValueKey('cash-received-ok')));
        await settle(tester);
        expect(find.text('Enter an amount greater than zero'), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey('cash-received-field')), '5000');
        await tester.tap(find.byKey(const ValueKey('cash-received-ok')));
        await animated(tester);
        expect(textOf(tester, 'cash-received-change'),
            'Less than the amount to pay');

        await tester.tap(find.byKey(const ValueKey('cash-received-button')));
        await animated(tester);
        expect(find.text('5000'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('cash-received-clear')));
        await animated(tester);
        expect(find.byKey(const ValueKey('cash-received-change')), findsNothing);
        expect(find.text('Cash received'), findsOneWidget);

        // Typed again, sold: the next sale does not inherit it.
        await tester.tap(find.byKey(const ValueKey('cash-received-button')));
        await animated(tester);
        await tester.enterText(
            find.byKey(const ValueKey('cash-received-field')), '8000');
        await tester.tap(find.byKey(const ValueKey('cash-received-ok')));
        await animated(tester);
        expect(textOf(tester, 'cash-received-change'), 'Change 0 ل.س');
        await tester.tap(saveButton);
        await animated(tester);
        await tester.tap(find.text('New sale'));
        await animated(tester);
        await addByCode(tester, '102');
        expect(line, findsOneWidget);
        expect(find.byKey(const ValueKey('cash-received-change')), findsNothing);
      });

      testWidgets('the setting is a switch under Selling, off by default',
          (tester) async {
        await pump(tester, const SettingsScreen());
        final tile = find.byKey(const ValueKey('setting-cash-received'));
        await reveal(tester, tile);
        expect(tester.widget<SwitchListTile>(tile).value, isFalse);
        await tester.tap(tile);
        await settle(tester, 20);
        expect(tester.widget<SwitchListTile>(tile).value, isTrue);
        final stored = await db(
          tester,
          () => SettingsRepository(database.db)
              .getString(SettingsKeys.showCashReceived),
        );
        expect(stored, '1');
      });
    });

    testWidgets('partial: asks for a customer, picked right in the sheet; the '
        'rest becomes their debt', (tester) async {
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('pay-mode-partial')));
      await settle(tester);
      await tester.enterText(
          find.byKey(const ValueKey('pay-amount-paid')), '3000');
      await settle(tester);
      expect(textOf(tester, 'pay-remaining'), 'Goes on the account: 5,000 ل.س');

      // No customer yet: Save says so and saves nothing.
      await tester.tap(paySave);
      await settle(tester);
      expect(textOf(tester, 'pay-error'), 'Choose a customer to sell on credit');
      expect(await rows(tester, 'invoices'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('pay-choose-customer')));
      await animated(tester);
      await tester.enterText(
          find.byKey(const ValueKey('quick-search-field')), 'Ahmad');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('quick-hit-$ahmad-0')));
      await animated(tester);

      // Back in the sheet, with what was typed still there.
      expect(sheet, findsOneWidget);
      expect(find.byKey(const ValueKey('pay-customer')), findsOneWidget);
      expect(find.text('Ahmad Hasan'), findsWidgets);
      expect(textOf(tester, 'pay-remaining'), 'Goes on the account: 5,000 ل.س');
      await settle(tester);

      await tester.tap(paySave);
      await animated(tester);

      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect(
        textOf(tester, 'saved-paid-line'),
        'Paid 3,000 ل.س · on account 5,000 ل.س',
      );
      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['customer_id'], ahmad);
      expect(invoice['customer_name'], 'Ahmad Hasan');
      expect(invoice['paid_minor'], 3000);
      expect(invoice['prev_balance_base_minor'], 0);
      expect(invoice['new_balance_base_minor'], 5000);
      final entry = (await rows(tester, 'debt_transactions')).single;
      expect(entry['type'], 'DEBT');
      expect(entry['amount_base_minor'], 5000);
      expect(entry['invoice_id'], invoice['id']);
      expect(entry['invoice_no'], invoice['invoice_no']);
      expect(await balance(tester, ahmad), 5000);
    });

    testWidgets('partial needs an amount smaller than the total',
        (tester) async {
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('pay-mode-partial')));
      await settle(tester);
      for (final typed in ['', '0', '8000', '9000']) {
        await tester.enterText(
            find.byKey(const ValueKey('pay-amount-paid')), typed);
        await settle(tester);
        await tester.tap(paySave);
        await settle(tester);
        expect(textOf(tester, 'pay-error'),
            'Enter an amount smaller than the amount to pay',
            reason: '"$typed"');
      }
      expect(await rows(tester, 'invoices'), isEmpty);
    });

    testWidgets('on credit: all of it goes on the attached customer\'s '
        'account, due in the default 30 days', (tester) async {
      await owe(tester, ahmad, 2000, daysAgo: 3);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);
      await openSheet(tester);

      // The customer is shown with what they already owe.
      expect(textOf(tester, 'pay-customer-balance'), 'Owes 2,000 ل.س');
      await tester.tap(find.byKey(const ValueKey('pay-mode-credit')));
      await settle(tester);
      expect(textOf(tester, 'pay-remaining'), 'Goes on the account: 8,000 ل.س');
      expect(find.byKey(const ValueKey('pay-cash-received')), findsNothing);
      expect(find.byKey(const ValueKey('pay-due-date')), findsOneWidget);

      await tester.tap(paySave);
      await animated(tester);

      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect(await balance(tester, ahmad), 10000);
      final entry = (await rows(tester, 'debt_transactions')).last;
      final created =
          DateTime.fromMillisecondsSinceEpoch(entry['created_at']! as int);
      expect(
        DateTime.fromMillisecondsSinceEpoch(entry['due_at']! as int),
        DateTime(created.year, created.month, created.day + 30),
      );
      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['paid_minor'], 0);
      expect(invoice['prev_balance_base_minor'], 2000);
      expect(invoice['new_balance_base_minor'], 10000);
    });

    testWidgets('a credit balance can pay part of the invoice', (tester) async {
      // The shop owes Ahmad 5,000.
      await db(
        tester,
        () => debts.addOpeningBalance(
          customerId: ahmad,
          amountBaseMinor: 5000,
          customerOwes: false,
          at: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);
      await openSheet(tester);

      expect(textOf(tester, 'pay-customer-balance'), 'Credit 5,000 ل.س');
      expect(find.text('Use credit balance (5,000 ل.س)'), findsOneWidget);
      // The rest is paid in cash, now.
      await tester.tap(find.byKey(const ValueKey('pay-mode-full')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pay-use-credit')));
      await settle(tester);
      expect(textOf(tester, 'pay-due-now'), 'To pay now: 3,000 ل.س');

      // The change is counted on what is paid now, not on the total.
      await tester.enterText(
          find.byKey(const ValueKey('pay-cash-received')), '5000');
      await settle(tester);
      expect(textOf(tester, 'pay-change'), 'Change to give back: 2,000 ل.س');

      await tester.tap(paySave);
      await animated(tester);

      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['paid_minor'], 3000);
      expect(invoice['credit_used_minor'], 5000);
      expect(invoice['prev_balance_base_minor'], -5000);
      expect(invoice['new_balance_base_minor'], 0);
      expect(await balance(tester, ahmad), 0);
    });

    group('over the credit limit', () {
      Future<void> toTheWarning(WidgetTester tester) async {
        await db(tester, () async {
          await database.db.update(
            'customers',
            {'credit_limit_base_minor': 10000},
            where: 'id = ?',
            whereArgs: [ahmad],
          );
          return true;
        });
        await owe(tester, ahmad, 6000, daysAgo: 3);
        await pump(tester, const SaleScreen());
        await addByCode(tester, '102');
        attach(tester, ahmad, 'Ahmad Hasan');
        await settle(tester);
        await openSheet(tester);
        await tester.tap(find.byKey(const ValueKey('pay-mode-credit')));
        await settle(tester);
      }

      testWidgets('the warning gives the numbers, and paying cash removes it',
          (tester) async {
        await toTheWarning(tester);
        expect(find.byKey(const ValueKey('pay-limit-warning')), findsOneWidget);
        expect(
          find.text('Balance 6,000 ل.س + this sale 8,000 ل.س = 14,000 ل.س. '
              'The limit is 10,000 ل.س.'),
          findsOneWidget,
        );
        expect(
          find.descendant(of: paySave, matching: find.text('Override and save')),
          findsOneWidget,
        );
        // Within the limit: 4,000 on credit is exactly at it.
        await tester.tap(find.byKey(const ValueKey('pay-mode-partial')));
        await settle(tester);
        await tester.enterText(
            find.byKey(const ValueKey('pay-amount-paid')), '4000');
        await settle(tester);
        expect(find.byKey(const ValueKey('pay-limit-warning')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('pay-mode-full')));
        await settle(tester);
        expect(find.byKey(const ValueKey('pay-limit-warning')), findsNothing);
        expect(find.descendant(of: paySave, matching: find.text('Save')),
            findsOneWidget);
      });

      testWidgets('with a PIN set: the PIN overrides, and it is logged',
          (tester) async {
        await setPin(tester);
        await toTheWarning(tester);
        await tester.tap(paySave);
        await animated(tester);
        expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
        expect(find.text('Enter the PIN to sell over the credit limit.'),
            findsOneWidget);
        await enterPin(tester);
        await animated(tester);

        expect(find.byType(SaleInvoiceScreen), findsOneWidget);
        expect(await balance(tester, ahmad), 14000);
        final log = (await db(tester, () => AuditRepository(database.db).list()))
            .single;
        expect(log.action, 'CREDIT_LIMIT_OVERRIDE');
        expect(log.details['customer'], 'Ahmad Hasan');
        expect(log.details['balance'], 6000);
        expect(log.details['new_balance'], 14000);
        expect(log.details['limit'], 10000);
      });

      testWidgets('with a PIN set: cancelling the PIN saves nothing',
          (tester) async {
        await setPin(tester);
        await toTheWarning(tester);
        await tester.tap(paySave);
        await animated(tester);
        await tester.tap(find.text('Cancel'));
        await animated(tester);

        expect(sheet, findsOneWidget, reason: 'still choosing');
        expect(await rows(tester, 'invoices'), isEmpty);
        expect(await balance(tester, ahmad), 6000);
        expect(await rows(tester, 'audit_log'), isEmpty);
      });

      testWidgets('without a PIN: a confirmation overrides, and it is logged',
          (tester) async {
        await toTheWarning(tester);
        await tester.tap(paySave);
        await animated(tester);
        expect(
            find.byKey(const ValueKey('credit-limit-confirm')), findsOneWidget);
        expect(find.byKey(const ValueKey('pin-entry-dialog')), findsNothing);
        expect(find.byKey(const ValueKey('pin-set-dialog')), findsNothing,
            reason: 'selling on credit never makes anyone choose a PIN');
        await tester
            .tap(find.byKey(const ValueKey('credit-limit-confirm-yes')));
        await animated(tester);
        await animated(tester);

        expect(find.byType(SaleInvoiceScreen), findsOneWidget);
        expect(await balance(tester, ahmad), 14000);
        expect((await rows(tester, 'audit_log')).single['action'],
            'CREDIT_LIMIT_OVERRIDE');
      });
    });

    testWidgets('with the debt ledger off, Save saves at once: no sheet, no '
        'payment columns', (tester) async {
      await pump(tester, const SaleScreen(), debtOn: false);
      await addByCode(tester, '101');
      expect(creditButton, findsNothing);
      await tester.tap(saveButton);
      await animated(tester);

      expect(sheet, findsNothing);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['paid_minor'], isNull);
      expect(invoice['prev_balance_base_minor'], isNull);
    });
  });

  group('the Account tab', () {
    Future<void> openAccount(WidgetTester tester, [int? customer]) async {
      await pump(
        tester,
        CustomerDetailScreen(
          customerId: customer ?? ahmad,
          initialTab: CustomerTab.account,
        ),
      );
      await animated(tester);
    }

    testWidgets('the customer page has a Details tab and an Account tab',
        (tester) async {
      await pump(tester, CustomerDetailScreen(customerId: ahmad));
      expect(find.byKey(const ValueKey('customer-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('customer-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-tab')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('customer-tab-account')));
      await animated(tester);
      expect(find.byKey(const ValueKey('account-tab')), findsOneWidget);
      expect(textOf(tester, 'account-balance'), 'No balance');
      expect(textOf(tester, 'ledger-empty'), 'No entries yet');
    });

    testWidgets('balance in words, limit, last payment, oldest debt, and the '
        'ledger with running balances', (tester) async {
      await db(tester, () async {
        await database.db.update(
          'customers',
          {'credit_limit_base_minor': 9000},
          where: 'id = ?',
          whereArgs: [ahmad],
        );
        return true;
      });
      final old = await owe(tester, ahmad, 10000, daysAgo: 45);
      final payment = await pay(tester, ahmad, 4000, daysAgo: 10);
      final recent = await owe(tester, ahmad, 4500, daysAgo: 2);
      await openAccount(tester);

      expect(textOf(tester, 'account-balance'), 'Owes 10,500 ل.س');
      expect(textOf(tester, 'account-limit'), 'Credit limit: 9,000 ل.س');
      expect(find.byKey(const ValueKey('account-over-limit')), findsOneWidget);
      // The 45-day-old debt (6,000 of it unpaid) is past its 30 days.
      expect(
        tester
            .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('account-overdue')),
              matching: find.byType(Text),
            ))
            .data,
        'Overdue: 6,000 ل.س',
      );
      expect(textOf(tester, 'account-last-payment'), startsWith('Last payment'));
      expect(textOf(tester, 'account-oldest'), 'Oldest debt: 45 days');

      Finder inTile(int id, String text) => find.descendant(
            of: find.byKey(ValueKey('ledger-entry-$id')),
            matching: find.text(text),
          );
      // Newest first; each line with the balance after it.
      expect(inTile(recent.id, 'Debit 4,500'), findsOneWidget);
      expect(inTile(recent.id, 'Owes 10,500'), findsOneWidget);
      expect(inTile(payment.id, 'Receipt 1'), findsOneWidget);
      expect(inTile(payment.id, 'Credit 4,000'), findsOneWidget);
      expect(inTile(payment.id, 'Owes 6,000'), findsOneWidget);
      expect(inTile(old.id, 'Debt'), findsOneWidget);
      expect(inTile(old.id, 'Owes 10,000'), findsOneWidget);
      final order = [recent.id, payment.id, old.id]
          .map((id) => tester
              .getTopLeft(find.byKey(ValueKey('ledger-entry-$id')))
              .dy)
          .toList();
      expect(order, [...order]..sort());
    });

    testWidgets('the type filter hides rows but never changes a balance',
        (tester) async {
      final debt = await owe(tester, ahmad, 10000, daysAgo: 5);
      final payment = await pay(tester, ahmad, 4000, daysAgo: 1);
      await openAccount(tester);

      await tester.tap(find.byKey(const ValueKey('ledger-type-payments')));
      await settle(tester);
      expect(find.byKey(ValueKey('ledger-entry-${debt.id}')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('ledger-entry-${payment.id}')),
          matching: find.text('Owes 6,000'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ledger-type-debts')));
      await settle(tester);
      expect(find.byKey(ValueKey('ledger-entry-${payment.id}')), findsNothing);
      expect(find.byKey(ValueKey('ledger-entry-${debt.id}')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ledger-type-other')));
      await settle(tester);
      expect(textOf(tester, 'ledger-empty'), 'No entries match the filter');
    });

    testWidgets('an invoice entry opens its invoice — and says so when the '
        'invoice is gone', (tester) async {
      final invoice = await creditInvoice(tester, ahmad);
      await openAccount(tester);
      final entryId =
          (await rows(tester, 'debt_transactions')).single['id']! as int;
      expect(find.text('Invoice ${invoice.invoiceNo}'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('ledger-entry-$entryId')));
      await animated(tester);
      expect(find.byKey(const ValueKey('entry-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('entry-invoice-deleted')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('entry-open-invoice')));
      await animated(tester);
      expect(find.byType(InvoiceDetailScreen), findsOneWidget);

      // Delete it from there: the dialog says the debt stays.
      await tester.tap(find.byKey(const ValueKey('archive-delete-invoice')));
      await animated(tester);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('delete-invoice-debt-note')))
            .data,
        contains('The debt is not deleted'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await animated(tester);

      // Back on the account: same debt, same balance, no invoice to open.
      expect(find.byKey(const ValueKey('account-tab')), findsOneWidget);
      expect(textOf(tester, 'account-balance'), 'Owes 5,000 ل.س');
      expect(find.text('Invoice ${invoice.invoiceNo}'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('ledger-entry-$entryId')));
      await animated(tester);
      expect(find.byKey(const ValueKey('entry-open-invoice')), findsNothing);
      expect(
        textOf(tester, 'entry-invoice-deleted'),
        'Invoice ${invoice.invoiceNo} was deleted from the archive. '
        'The debt stays in the account.',
      );
      final row = (await rows(tester, 'debt_transactions')).single;
      expect(row['invoice_id'], isNull);
      expect(row['invoice_no'], invoice.invoiceNo);
      expect(row['amount_base_minor'], 5000);
    });

    testWidgets('reversing an entry: a reason, the PIN, a struck-through line '
        'linked to its reversal, and the audit log', (tester) async {
      await setPin(tester);
      await owe(tester, ahmad, 10000, daysAgo: 5);
      final payment = await pay(tester, ahmad, 4000, daysAgo: 1);
      await openAccount(tester);

      await tester.tap(find.byKey(ValueKey('ledger-entry-${payment.id}')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('entry-reverse')));
      await animated(tester);
      expect(find.byKey(const ValueKey('reverse-entry-dialog')), findsOneWidget);
      expect(find.text('Receipt 1 · 4,000 ل.س'), findsOneWidget);

      // No reason, no reversal.
      await tester.tap(find.byKey(const ValueKey('reverse-confirm')));
      await settle(tester);
      expect(find.text('Enter the reason'), findsOneWidget);
      expect(await rows(tester, 'debt_transactions'), hasLength(2));

      await tester.enterText(
          find.byKey(const ValueKey('reverse-reason')), 'wrong customer');
      await tester.tap(find.byKey(const ValueKey('reverse-confirm')));
      await animated(tester);
      expect(find.text('Enter the PIN to reverse a ledger entry.'),
          findsOneWidget);
      await enterPin(tester);
      await animated(tester);

      expect(find.text('Entry reversed'), findsOneWidget);
      expect(textOf(tester, 'account-balance'), 'Owes 10,000 ل.س');
      final all = await rows(tester, 'debt_transactions');
      expect(all, hasLength(3));
      final reversal = all.last;
      expect(reversal['type'], 'REVERSAL');
      expect(reversal['reverses_id'], payment.id);
      expect(reversal['note'], 'wrong customer');

      // The cancelled payment is struck through and badged; the reversal
      // says what it cancels.
      final cancelled = find.byKey(ValueKey('ledger-entry-${payment.id}'));
      expect(
        find.descendant(of: cancelled, matching: find.text('Reversed')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.descendant(
              of: cancelled,
              matching: find.text('Receipt 1'),
            ))
            .style!
            .decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text('Reversal: Receipt 1'), findsOneWidget);

      // From the cancelled entry to its reversal, and back.
      await tester.tap(cancelled);
      await animated(tester);
      expect(find.byKey(const ValueKey('entry-reverse')), findsNothing,
          reason: 'nothing is reversed twice');
      await tester.tap(find.byKey(const ValueKey('entry-linked')));
      await animated(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('entry-sheet')),
          matching: find.text('wrong customer'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('entry-reverse')), findsNothing,
          reason: 'a reversal cannot be reversed');

      final log =
          (await db(tester, () => AuditRepository(database.db).list())).single;
      expect(log.action, 'DEBT_REVERSAL');
      expect(log.details['reason'], 'wrong customer');
      expect(log.details['receipt_no'], 1);
    });

    testWidgets('a reversal without the PIN does not happen', (tester) async {
      await setPin(tester);
      final debt = await owe(tester, ahmad, 10000, daysAgo: 5);
      await openAccount(tester);
      await tester.tap(find.byKey(ValueKey('ledger-entry-${debt.id}')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('entry-reverse')));
      await animated(tester);
      await tester.enterText(
          find.byKey(const ValueKey('reverse-reason')), 'oops');
      await tester.tap(find.byKey(const ValueKey('reverse-confirm')));
      await animated(tester);
      await tester.tap(find.text('Cancel'));
      await animated(tester);

      expect(await rows(tester, 'debt_transactions'), hasLength(1));
      expect(await rows(tester, 'audit_log'), isEmpty);
      expect(textOf(tester, 'account-balance'), 'Owes 10,000 ل.س');
    });

    testWidgets('add a manual debt from the account', (tester) async {
      await openAccount(tester);
      await tester.tap(find.byKey(const ValueKey('account-add-debt')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('entry-save')));
      await settle(tester);
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('entry-amount')), '2500');
      await tester.enterText(
          find.byKey(const ValueKey('entry-note')), 'cash loan');
      await tester.tap(find.byKey(const ValueKey('entry-save')));
      await animated(tester);

      expect(find.byKey(const ValueKey('account-tab')), findsOneWidget);
      expect(textOf(tester, 'account-balance'), 'Owes 2,500 ل.س');
      final row = (await rows(tester, 'debt_transactions')).single;
      expect(row['type'], 'MANUAL_DEBT');
      expect(row['note'], 'cash loan');
      expect(row['due_at'], isNotNull);
    });

    testWidgets('an adjustment asks for a reason and the PIN, and is logged',
        (tester) async {
      await setPin(tester);
      await owe(tester, ahmad, 10000, daysAgo: 5);
      await openAccount(tester);
      await tester.tap(find.byKey(const ValueKey('account-more')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('account-adjust')));
      await animated(tester);

      await tester.tap(find.byKey(const ValueKey('entry-decrease')));
      await tester.enterText(
          find.byKey(const ValueKey('entry-amount')), '1500');
      await tester.tap(find.byKey(const ValueKey('entry-save')));
      await settle(tester);
      expect(find.text('Enter the reason'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('entry-note')), 'price mistake');
      await tester.tap(find.byKey(const ValueKey('entry-save')));
      await animated(tester);
      await enterPin(tester);
      await animated(tester);

      expect(textOf(tester, 'account-balance'), 'Owes 8,500 ل.س');
      expect((await rows(tester, 'audit_log')).single['action'],
          'DEBT_ADJUSTMENT');
    });

    testWidgets('deactivating a customer with a balance shows the balance '
        'first', (tester) async {
      await owe(tester, ahmad, 7500, daysAgo: 1);
      await pump(tester, CustomerDetailScreen(customerId: ahmad));
      await tester.tap(find.byKey(const ValueKey('customer-menu')));
      await animated(tester);
      await tester.tap(find.text('Deactivate'));
      await animated(tester);

      expect(
        textOf(tester, 'deactivate-with-balance'),
        '"Ahmad Hasan" has an open balance: Owes 7,500 ل.س. Deactivating '
        'hides them from the search; the balance stays in the debtors list.',
      );
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect((await rows(tester, 'customers')).first['is_active'], 1);

      // A customer who owes nothing gets the plain question.
      await pump(tester, CustomerDetailScreen(customerId: sara));
      await tester.tap(find.byKey(const ValueKey('customer-menu')));
      await animated(tester);
      await tester.tap(find.text('Deactivate'));
      await animated(tester);
      expect(find.byKey(const ValueKey('deactivate-plain')), findsOneWidget);
    });

    testWidgets('the customer form takes a credit limit and days to pay',
        (tester) async {
      final customer =
          await db(tester, () async => (await CustomerRepository(database.db).getById(sara))!);
      await pump(tester, CustomerFormScreen(customer: customer));
      await tester.enterText(
          find.byKey(const ValueKey('customer-credit-limit-field')), '25000');
      await tester.enterText(
          find.byKey(const ValueKey('customer-due-days-field')), '14');
      await tester.tap(find.byKey(const ValueKey('customer-save')));
      await animated(tester);
      final row = (await rows(tester, 'customers')).last;
      expect(row['credit_limit_base_minor'], 25000);
      expect(row['default_due_days'], 14);

      // And shows them again when the form is opened the next time.
      final again =
          await db(tester, () async => (await CustomerRepository(database.db).getById(sara))!);
      await pump(tester, CustomerFormScreen(customer: again));
      expect(find.text('25000'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
    });
  });

  group('recording a payment', () {
    testWidgets('amount, method, note → the entry and its receipt, which '
        'prints', (tester) async {
      await store(tester, {
        SettingsKeys.printerMac: 'AA:BB:CC:DD:EE:FF',
        SettingsKeys.printerName: 'Printer',
        SettingsKeys.shopName: 'Al-Baraka',
        SettingsKeys.invoiceLanguage: 'en',
      });
      await owe(tester, ahmad, 10000, daysAgo: 5);
      await pump(tester, RecordPaymentScreen(customerId: ahmad));
      expect(textOf(tester, 'payment-balance'), 'Owes 10,000 ل.س');

      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await settle(tester);
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '4000');
      await tester.tap(find.byKey(const ValueKey('payment-method-transfer')));
      await tester.enterText(
          find.byKey(const ValueKey('payment-note')), 'for November');
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await animated(tester);

      expect(find.byType(ReceiptScreen), findsOneWidget);
      await until(
        tester,
        () => find.byKey(const ValueKey('receipt-preview')).evaluate().isNotEmpty,
      );
      expect(find.text('Receipt no. 1'), findsOneWidget);
      final row = (await rows(tester, 'debt_transactions')).last;
      expect(row['type'], 'PAYMENT');
      expect(row['amount_base_minor'], 4000);
      expect(row['payment_method'], 'TRANSFER');
      expect(row['receipt_no'], 1);
      expect(row['balance_before_base_minor'], 10000);
      expect(row['note'], 'for November');
      expect(await balance(tester, ahmad), 6000);

      // The original, straight to the printer — no COPY mark.
      expect(find.text('COPY'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paper-primary-print')));
      await until(tester, () => bridge.printed.isNotEmpty);
      expect(bridge.printed.single.address, 'AA:BB:CC:DD:EE:FF');
      expect(bridge.printed.single.bytes.length, greaterThan(1000));

      // To the customer's WhatsApp chat, as an image.
      await tester.tap(find.byKey(const ValueKey('paper-whatsapp')));
      await until(tester, () => bridge.whatsAppSends.isNotEmpty);
      expect(bridge.whatsAppSends.single.phone, '963944123456');
      expect(bridge.whatsAppSends.single.path, endsWith('receipt-1.png'));
    });

    testWidgets('"pay full balance" fills the amount', (tester) async {
      await owe(tester, ahmad, 12500, daysAgo: 5);
      await pump(tester, RecordPaymentScreen(customerId: ahmad));
      await tester.tap(find.byKey(const ValueKey('payment-full-balance')));
      await settle(tester);
      expect(find.text('12500'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await animated(tester);
      expect(await balance(tester, ahmad), 0);
    });

    testWidgets('in another currency: converted with the rate shown, which '
        'can be changed for this payment and is kept with it', (tester) async {
      await db(tester, () async {
        await database.db.update(
          'currencies',
          {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
          where: 'code = ?',
          whereArgs: ['USD'],
        );
        return true;
      });
      await owe(tester, ahmad, 200000, daysAgo: 5);
      await pump(tester, RecordPaymentScreen(customerId: ahmad));

      await tester.tap(find.byKey(const ValueKey('payment-currency-USD')));
      await settle(tester);
      // The current rate is offered.
      expect(find.text('13000'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '10.50');
      await settle(tester);
      expect(textOf(tester, 'payment-base-value'), 'Counts as 136,500 ل.س');

      // Today the shop takes dollars at 13,500.
      await tester.enterText(
          find.byKey(const ValueKey('payment-rate')), '13500');
      await settle(tester);
      expect(textOf(tester, 'payment-base-value'), 'Counts as 141,750 ل.س');

      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await animated(tester);

      final row = (await rows(tester, 'debt_transactions')).last;
      expect(row['amount_base_minor'], 141750);
      expect(row['orig_amount_minor'], 1050);
      expect(row['orig_currency_code'], 'USD');
      expect(row['orig_rate_num'], 13500);
      expect(row['orig_rate_den'], 1);
      // The currency's own rate was not touched.
      final usdRow = (await db(
        tester,
        () => database.db
            .query('currencies', where: 'code = ?', whereArgs: ['USD']),
      ))
          .single;
      expect(usdRow['rate_num'], 13000);
    });

    testWidgets('more than the balance: says the customer will have a credit',
        (tester) async {
      await owe(tester, ahmad, 3000, daysAgo: 5);
      await pump(tester, RecordPaymentScreen(customerId: ahmad));
      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '5000');
      await settle(tester);
      expect(
        textOf(tester, 'payment-over-balance'),
        'More than the balance: the customer will have a credit of 2,000 ل.س.',
      );
    });

    testWidgets('a receipt opened again from the ledger is a COPY',
        (tester) async {
      await owe(tester, ahmad, 10000, daysAgo: 5);
      final payment = await pay(tester, ahmad, 4000, daysAgo: 1);
      await pump(
        tester,
        CustomerDetailScreen(
          customerId: ahmad,
          initialTab: CustomerTab.account,
        ),
      );
      await animated(tester);
      await tester.tap(find.byKey(ValueKey('ledger-entry-${payment.id}')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('entry-open-receipt')));
      await animated(tester);
      await until(
        tester,
        () => find.byKey(const ValueKey('receipt-preview')).evaluate().isNotEmpty,
      );
      // The invoice language is Arabic by default.
      expect(find.text('نسخة'), findsOneWidget);
      expect(find.text('سند قبض رقم 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paper-more')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('paper-more-shareImage')));
      await until(tester, () => bridge.shared.isNotEmpty);
      expect(bridge.shared.single.path, endsWith('receipt-1-copy.png'));
      expect(bridge.shared.single.mimeType, 'image/png');
    });
  });

  group('the account statement', () {
    testWidgets('pick a range, see the paper, share it as a PDF',
        (tester) async {
      await owe(tester, ahmad, 10000, daysAgo: 60);
      await pay(tester, ahmad, 4000, daysAgo: 3);
      await pump(
        tester,
        CustomerDetailScreen(
          customerId: ahmad,
          initialTab: CustomerTab.account,
        ),
      );
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('account-statement')));
      await animated(tester);
      await until(
        tester,
        () =>
            find.byKey(const ValueKey('statement-preview')).evaluate().isNotEmpty,
      );
      // This month: the old debt is the balance brought forward (Arabic
      // paper).
      expect(find.text('كشف حساب'), findsOneWidget);
      expect(find.text('رصيد سابق'), findsOneWidget);
      expect(find.text('سند قبض 1'), findsOneWidget);
      expect(find.text('دين'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('statement-period-all')));
      await settle(tester);
      await until(tester, () => find.text('دين').evaluate().isNotEmpty);
      expect(find.text('كامل الحساب'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paper-more')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('paper-more-sharePdf')));
      await until(tester, () => bridge.shared.isNotEmpty);
      expect(bridge.shared.single.mimeType, 'application/pdf');
      expect(bridge.shared.single.path, contains('statement-$ahmad-'));
    });
  });

  group('the debtors list', () {
    Future<void> seedDebtors(WidgetTester tester) async {
      // Ahmad: 5,000 from 100 days ago, never paid — overdue.
      await owe(tester, ahmad, 5000, daysAgo: 100);
      // Sara: 9,000 from 10 days ago, paid 1,000 two days ago.
      await owe(tester, sara, 9000, daysAgo: 10);
      await pay(tester, sara, 1000, daysAgo: 2);
      // Omar: the shop owes him 3,000.
      final omar = await db(
        tester,
        () => CustomerRepository(database.db).insert(const Customer(name: 'Omar')),
      );
      await pay(tester, omar, 3000, daysAgo: 1);
    }

    List<String> order(WidgetTester tester) => [
          for (final tile in tester.widgetList<DebtorTile>(find.byType(DebtorTile)))
            tile.debtor.name,
        ];

    testWidgets('total, aging, and every customer who owes', (tester) async {
      await seedDebtors(tester);
      await pump(tester, const DebtorsScreen());

      expect(textOf(tester, 'debtors-total'), '13,000 ل.س');
      expect(textOf(tester, 'debtors-count'), '2 customers owe');
      expect(textOf(tester, 'debtors-credit-total'),
          'We owe customers: 3,000 ل.س');
      expect(textOf(tester, 'aging-current'), '8,000 ل.س');
      expect(textOf(tester, 'aging-days31to60'), '0 ل.س');
      expect(textOf(tester, 'aging-over90'), '5,000 ل.س');
      // By amount: the largest balance first; credit balances are not here.
      expect(order(tester), ['Sara Ali', 'Ahmad Hasan']);

      final ahmadTile = find.byKey(ValueKey('debtor-$ahmad'));
      expect(find.descendant(of: ahmadTile, matching: find.text('Overdue')),
          findsOneWidget);
      expect(
        find.descendant(
            of: ahmadTile, matching: find.text('Oldest debt: 100 days')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ahmadTile, matching: find.text('No payment yet')),
        findsOneWidget,
      );
      final saraTile = find.byKey(ValueKey('debtor-$sara'));
      expect(find.descendant(of: saraTile, matching: find.text('Overdue')),
          findsNothing);
      expect(
        find.descendant(
            of: saraTile, matching: find.text('Oldest debt: 10 days')),
        findsOneWidget,
      );
    });

    testWidgets('sort, filter and search', (tester) async {
      await seedDebtors(tester);
      await pump(tester, const DebtorsScreen());

      await tester.tap(find.byKey(const ValueKey('debtors-sort')));
      await animated(tester);
      await tester.tap(find.text('Oldest debt').last);
      await animated(tester);
      expect(order(tester), ['Ahmad Hasan', 'Sara Ali']);

      await tester.tap(find.byKey(const ValueKey('debtors-filter-overdue')));
      await settle(tester);
      expect(order(tester), ['Ahmad Hasan']);
      await tester.tap(find.byKey(const ValueKey('debtors-filter-credit')));
      await settle(tester);
      expect(order(tester), ['Omar']);
      await tester.tap(find.byKey(const ValueKey('debtors-filter-overLimit')));
      await settle(tester);
      expect(order(tester), isEmpty);
      expect(textOf(tester, 'debtors-empty'), 'No matching customers');

      await tester.tap(find.byKey(const ValueKey('debtors-filter-owing')));
      await settle(tester);
      await tester.enterText(
          find.byKey(const ValueKey('debtors-search')), 'sara');
      await settle(tester);
      expect(order(tester), ['Sara Ali']);
      await tester.enterText(
          find.byKey(const ValueKey('debtors-search')), '0944 123');
      await settle(tester);
      expect(order(tester), ['Ahmad Hasan']);
    });

    testWidgets('a payment recorded from a row brings the list up to date',
        (tester) async {
      await seedDebtors(tester);
      await pump(tester, const DebtorsScreen());
      await tester.tap(find.byKey(ValueKey('debtor-pay-$sara')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('payment-full-balance')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await animated(tester);
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await tester.pageBack();
      await animated(tester);

      expect(find.byType(DebtorsScreen), findsOneWidget);
      expect(textOf(tester, 'debtors-total'), '5,000 ل.س');
      expect(order(tester), ['Ahmad Hasan']);
    });

    testWidgets('the WhatsApp reminder opens the customer\'s chat with the '
        'text filled in — only for a customer with a phone', (tester) async {
      await seedDebtors(tester);
      await store(tester, {
        SettingsKeys.shopName: 'Al-Baraka',
        SettingsKeys.invoiceLanguage: 'en',
      });
      await pump(tester, const DebtorsScreen());
      expect(find.byKey(ValueKey('debtor-remind-$sara')), findsNothing);

      await tester.tap(find.byKey(ValueKey('debtor-remind-$ahmad')));
      await until(tester, () => bridge.chats.isNotEmpty);
      final chat = bridge.chats.single;
      expect(chat.phone, '963944123456');
      expect(
        chat.text,
        'Hello Ahmad Hasan, a reminder from Al-Baraka: your balance is '
        '5,000 ل.س. Thank you.',
      );
    });

    testWidgets('the shop\'s own reminder text is used', (tester) async {
      await seedDebtors(tester);
      await store(tester, {
        SettingsKeys.debtReminderText: '{name} — {balance}',
        SettingsKeys.invoiceLanguage: 'en',
      });
      await pump(tester, const DebtorsScreen());
      await tester.tap(find.byKey(ValueKey('debtor-remind-$ahmad')));
      await until(tester, () => bridge.chats.isNotEmpty);
      expect(bridge.chats.single.text, 'Ahmad Hasan — 5,000 ل.س');
    });

    testWidgets('a row opens the customer on the Account tab', (tester) async {
      await seedDebtors(tester);
      await pump(tester, const DebtorsScreen());
      await tester.tap(find.text('Ahmad Hasan'));
      await animated(tester);
      expect(find.byType(CustomerDetailScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('account-tab')), findsOneWidget);
      expect(textOf(tester, 'account-balance'), 'Owes 5,000 ل.س');
    });

    testWidgets('nobody owes anything', (tester) async {
      await pump(tester, const DebtorsScreen());
      expect(textOf(tester, 'debtors-total'), '0 ل.س');
      expect(textOf(tester, 'debtors-empty'), 'Nobody owes anything');
    });
  });

  group('opening balances in bulk', () {
    testWidgets('one row after another: a new customer, then the same name '
        'again, then one picked from the suggestions', (tester) async {
      await pump(tester, const OpeningBalancesScreen());

      // Nothing typed: nothing saved.
      await tester.tap(find.byKey(const ValueKey('opening-add')));
      await settle(tester);
      expect(find.text("Enter the customer's name"), findsOneWidget);
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('opening-name')), 'Khaled Najjar');
      await tester.enterText(
          find.byKey(const ValueKey('opening-phone')), '0933 555 666');
      await tester.enterText(
          find.byKey(const ValueKey('opening-amount')), '15000');
      await tester.tap(find.byKey(const ValueKey('opening-add')));
      await settle(tester, 20);

      expect(textOf(tester, 'opening-session-count'), '1 entered');
      expect(find.text('New customer'), findsOneWidget);
      // The form is empty again for the next line of the notebook.
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('opening-name')))
            .controller!
            .text,
        isEmpty,
      );
      final khaled = (await rows(tester, 'customers')).last;
      expect(khaled['name'], 'Khaled Najjar');
      expect(khaled['phone'], '0933 555 666');
      final khaledId = khaled['id']! as int;
      expect(await balance(tester, khaledId), 15000);

      // The same name typed again is the same customer.
      await tester.enterText(
          find.byKey(const ValueKey('opening-name')), 'khaled  najjar');
      await tester.enterText(
          find.byKey(const ValueKey('opening-amount')), '500');
      await tester.tap(find.byKey(const ValueKey('opening-add')));
      await settle(tester, 20);
      expect(textOf(tester, 'opening-session-count'), '2 entered');
      expect(find.text('Existing customer'), findsOneWidget);
      expect(await rows(tester, 'customers'), hasLength(3));
      expect(await balance(tester, khaledId), 15500);

      // An existing customer picked from the suggestions; the shop owes her.
      await tester.enterText(find.byKey(const ValueKey('opening-name')), 'Sar');
      await settle(tester, 20);
      await tester.tap(find.byKey(ValueKey('opening-suggestion-$sara')));
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('opening-picked')), findsOneWidget);
      expect(find.byKey(const ValueKey('opening-name')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('opening-credit')));
      await tester.enterText(
          find.byKey(const ValueKey('opening-amount')), '2000');
      await tester.tap(find.byKey(const ValueKey('opening-add')));
      await settle(tester, 20);
      expect(await balance(tester, sara), -2000);
      expect(await rows(tester, 'customers'), hasLength(3));
      final types = (await rows(tester, 'debt_transactions'))
          .map((r) => r['type'])
          .toSet();
      expect(types, {'OPENING_BALANCE'});
    });
  });

  group('elsewhere in the app', () {
    testWidgets('home: the Debts card shows the total and the overdue count, '
        'and opens the debtors list', (tester) async {
      await owe(tester, ahmad, 5000, daysAgo: 100);
      await owe(tester, sara, 9000, daysAgo: 3);
      await pump(tester, const HomeScreen());
      await settle(tester, 20);

      expect(find.byKey(const ValueKey('home-debts')), findsOneWidget);
      expect(textOf(tester, 'home-debts-total'), '14,000 ل.س');
      expect(textOf(tester, 'home-debts-overdue'), '1 overdue');
      await tester.tap(find.byKey(const ValueKey('home-debts')));
      await animated(tester);
      expect(find.byType(DebtorsScreen), findsOneWidget);
    });

    testWidgets('home: the card is there for every shop type', (tester) async {
      for (final type in [shopTypeGrocery, shopTypeCards, shopTypeBoth]) {
        await store(tester, {SettingsKeys.shopType: type});
        await pump(tester, const HomeScreen());
        await settle(tester, 20);
        expect(find.byKey(const ValueKey('home-debts')), findsOneWidget,
            reason: type);
        expect(textOf(tester, 'home-debts-overdue'), 'Nobody overdue');
      }
    });

    testWidgets('statistics: outstanding, new debt, collected, rate, top '
        'debtors, aging', (tester) async {
      await owe(tester, ahmad, 5000, daysAgo: 100);
      await owe(tester, sara, 9000);
      await pay(tester, sara, 3000);
      await pump(tester, const StatsScreen());
      await statsLoaded(tester);
      await reveal(tester, find.byKey(const ValueKey('stats-debt-rate')));
      await settle(tester);

      // The period is today.
      expect(textOf(tester, 'stats-debt-outstanding'), '11,000 ل.س');
      expect(textOf(tester, 'stats-debt-new'), '9,000 ل.س');
      expect(textOf(tester, 'stats-debt-collected'), '3,000 ل.س');
      // 3,000 of (5,000 owed before today + 9,000 new) = 21.43%.
      expect(textOf(tester, 'stats-debt-rate'), '21.43%');
      await reveal(tester, find.byKey(ValueKey('stats-debtor-$ahmad')));
      expect(find.byKey(ValueKey('stats-debtor-$sara')), findsOneWidget);
      expect(find.byKey(const ValueKey('aging-grid')), findsOneWidget);
    });

    testWidgets('deleting a period says how many invoices carry debts, and '
        'the debts stay', (tester) async {
      await creditInvoice(tester, ahmad);
      await creditInvoice(tester, ahmad, total: 2000, paid: 2000);
      await pump(tester, const ArchiveScreen());
      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester, 20);

      expect(
        textOf(tester, 'archive-delete-debt-note'),
        '1 of these invoices carry debts. The debts are not deleted: they '
        'stay in the customers\' accounts.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await until(tester, () => find.textContaining('deleted').evaluate().isNotEmpty);

      expect(await rows(tester, 'invoices'), isEmpty);
      final entry = (await rows(tester, 'debt_transactions')).single;
      expect(entry['invoice_id'], isNull);
      expect(entry['invoice_no'], 1);
      expect(await balance(tester, ahmad), 5000);
    });

    testWidgets('a period without debts gets no such note', (tester) async {
      await creditInvoice(tester, ahmad, total: 2000, paid: 2000);
      await pump(tester, const ArchiveScreen());
      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester, 20);
      expect(find.textContaining('1 invoices totalling'), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-delete-debt-note')), findsNothing);
    });

    testWidgets('invoice settings: the four debt toggles, paid and remaining '
        'on, the balances off', (tester) async {
      await pump(tester, const InvoiceSettingsScreen());
      await settle(tester, 20);
      for (final (key, on) in [
        ('toggle-paid-amount', true),
        ('toggle-remaining-amount', true),
        ('toggle-previous-balance', false),
        ('toggle-new-balance', false),
      ]) {
        final toggle = find.byKey(ValueKey(key));
        await reveal(tester, toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, on, reason: key);
      }
      await tester.tap(find.byKey(const ValueKey('toggle-new-balance')));
      await settle(tester, 20);
      final stored = await db(
        tester,
        () => SettingsRepository(database.db)
            .getString(SettingsKeys.showNewBalance),
      );
      expect(stored, '1');
    });
  });

  group('the PIN in front of the debts (off by default)', () {
    Future<void> lockDebts(WidgetTester tester) async {
      await setPin(tester);
      await store(tester, {SettingsKeys.debtRequirePin: '1'});
      await owe(tester, ahmad, 5000, daysAgo: 100);
    }

    testWidgets('home shows a lock instead of the figures; the PIN opens the '
        'debtors list', (tester) async {
      await lockDebts(tester);
      await pump(tester, const HomeScreen());
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('home-debts-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-debts-total')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-debts')));
      await animated(tester);
      expect(find.byType(DebtorsScreen), findsNothing);
      expect(find.text('Enter the PIN to open the debts.'), findsOneWidget);
      await enterPin(tester);
      await animated(tester);
      expect(find.byType(DebtorsScreen), findsOneWidget);
      expect(textOf(tester, 'debtors-total'), '5,000 ل.س');

      // Unlocked for this run of the app: home now shows the figures.
      await tester.pageBack();
      await animated(tester);
      expect(textOf(tester, 'home-debts-total'), '5,000 ل.س');
    });

    testWidgets('a wrong PIN opens nothing', (tester) async {
      await lockDebts(tester);
      await pump(tester, const HomeScreen());
      await settle(tester, 20);
      await tester.tap(find.byKey(const ValueKey('home-debts')));
      await animated(tester);
      await tester.enterText(
          find.byKey(const ValueKey('pin-entry-field')), '1111');
      await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
      await animated(tester);
      expect(find.byType(DebtorsScreen), findsNothing);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(find.byKey(const ValueKey('home-debts-locked')), findsOneWidget);
    });

    testWidgets('the Account tab and the statistics are behind the same door',
        (tester) async {
      await lockDebts(tester);
      await pump(
        tester,
        CustomerDetailScreen(
          customerId: ahmad,
          initialTab: CustomerTab.account,
        ),
      );
      await animated(tester);
      expect(find.byKey(const ValueKey('debt-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-tab')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('debt-unlock')));
      await animated(tester);
      await enterPin(tester);
      await animated(tester);
      expect(textOf(tester, 'account-balance'), 'Owes 5,000 ل.س');

      await pump(tester, const StatsScreen());
      await statsLoaded(tester);
      await reveal(tester, find.byKey(const ValueKey('stats-debts')));
      expect(find.byKey(const ValueKey('stats-debts-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-debt-outstanding')), findsNothing);
    });

    testWidgets('selling on credit never asks for it', (tester) async {
      await lockDebts(tester);
      await pump(tester, const SaleScreen());
      await addByCode(tester, '102');
      attach(tester, ahmad, 'Ahmad Hasan');
      await settle(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('pay-mode-credit')));
      await settle(tester);
      await tester.tap(paySave);
      await animated(tester);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsNothing);
      expect(find.byType(SaleInvoiceScreen), findsOneWidget);
      expect(await balance(tester, ahmad), 13000);
    });

    testWidgets('the setting: turning it on makes sure there is a PIN; '
        'turning it off asks for it', (tester) async {
      await setPin(tester);
      await pump(tester, const SettingsScreen());
      final tile = find.byKey(const ValueKey('setting-debt-require-pin'));
      await reveal(tester, tile);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.tap(tile);
      await settle(tester, 20);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      await tester.tap(tile);
      await animated(tester);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue,
          reason: 'the lock stays without the PIN');
      await tester.tap(tile);
      await animated(tester);
      await enterPin(tester);
      await settle(tester, 20);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    });
  });

  group('what the PIN opened locks again', () {
    Future<void> lockDebts(WidgetTester tester, {int? minutes}) async {
      await setPin(tester);
      await store(tester, {
        SettingsKeys.debtRequirePin: '1',
        if (minutes != null) SettingsKeys.pinAutoLockMinutes: '$minutes',
      });
      await owe(tester, ahmad, 5000, daysAgo: 100);
    }

    Future<void> unlockHere(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('debt-unlock')));
      await animated(tester);
      await enterPin(tester);
      await animated(tester);
    }

    /// The app is left (another app, the home screen, the screen off) and
    /// opened again.
    Future<void> leaveAndComeBack(WidgetTester tester) async {
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await animated(tester);
    }

    final locked = find.byKey(const ValueKey('debt-locked'));
    final total = find.byKey(const ValueKey('debtors-total'));

    testWidgets('after 5 minutes without a touch on a debt screen — and a '
        'touch pushes that back', (tester) async {
      await lockDebts(tester);
      await pump(tester, const DebtorsScreen());
      expect(locked, findsOneWidget);
      await unlockHere(tester);
      expect(total, findsOneWidget);

      await tester.pump(const Duration(minutes: 4));
      await settle(tester);
      expect(total, findsOneWidget, reason: '4 minutes idle');

      // A touch on the screen: the five minutes start again.
      await tester.tap(find.byKey(const ValueKey('debtors-filter-overdue')));
      await settle(tester);
      await tester.pump(const Duration(minutes: 4));
      await settle(tester);
      expect(total, findsOneWidget, reason: '8 minutes in, 4 since the touch');

      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await settle(tester);
      expect(locked, findsOneWidget);
      expect(total, findsNothing);

      // The PIN opens it again.
      await unlockHere(tester);
      expect(total, findsOneWidget);
    });

    for (final minutes in [1, 15]) {
      testWidgets('the "lock again after" setting: $minutes min',
          (tester) async {
        await lockDebts(tester, minutes: minutes);
        await pump(tester, const DebtorsScreen());
        await unlockHere(tester);
        await tester.pump(Duration(minutes: minutes) - const Duration(seconds: 2));
        await settle(tester);
        expect(total, findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);
        expect(locked, findsOneWidget);
      });
    }

    testWidgets('the setting is a choice of 1, 5 or 15 minutes, 5 unless '
        'changed', (tester) async {
      await pump(tester, const SettingsScreen());
      final dropdown =
          find.byKey(const ValueKey('setting-pin-auto-lock-dropdown'));
      await reveal(tester, dropdown);
      expect(tester.widget<DropdownButton<int>>(dropdown).value, 5);
      await tester.tap(dropdown);
      await animated(tester);
      expect(find.text('1 minute'), findsOneWidget);
      expect(find.text('5 minutes'), findsWidgets);
      await tester.tap(find.text('15 minutes').last);
      await animated(tester);
      expect(tester.widget<DropdownButton<int>>(dropdown).value, 15);
      final stored = await db(
        tester,
        () => SettingsRepository(database.db)
            .getString(SettingsKeys.pinAutoLockMinutes),
      );
      expect(stored, '15');
    });

    testWidgets('at once when the app goes to the background — not for a '
        'passing "inactive"', (tester) async {
      await lockDebts(tester);
      await pump(tester, const PinSessionObserver(child: DebtorsScreen()));
      await unlockHere(tester);
      expect(total, findsOneWidget);

      // A permission dialog, the notification shade: the app is still
      // there.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(total, findsOneWidget);

      await leaveAndComeBack(tester);
      expect(locked, findsOneWidget);
      expect(total, findsNothing);
    });

    testWidgets('the real app has that watch above every screen',
        (tester) async {
      await lockDebts(tester);
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
            setupDoneProvider.overrideWith(() => SetupDoneNotifier(true)),
            platformBridgeProvider.overrideWithValue(bridge),
          ],
          child: const SouqiApp(),
        ),
      );
      await settle(tester, 30);
      await tester.tap(find.byKey(const ValueKey('home-debts')));
      await animated(tester);
      await enterPin(tester);
      await animated(tester);
      expect(total, findsOneWidget);

      await leaveAndComeBack(tester);
      expect(locked, findsOneWidget);
      // Back on the home screen the card is a lock again too.
      await tester.pageBack();
      await animated(tester);
      expect(find.byKey(const ValueKey('home-debts-locked')), findsOneWidget);
    });

    testWidgets('the home card goes back to a lock after the idle time',
        (tester) async {
      await lockDebts(tester);
      await pump(tester, const HomeScreen());
      await settle(tester, 20);
      await tester.tap(find.byKey(const ValueKey('home-debts')));
      await animated(tester);
      await enterPin(tester);
      await animated(tester);
      await tester.pageBack();
      await animated(tester);
      expect(textOf(tester, 'home-debts-total'), '5,000 ل.س');

      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-debts-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-debts-total')), findsNothing);
    });

    testWidgets('a form half filled in is still there after the lock',
        (tester) async {
      await lockDebts(tester);
      await pump(
        tester,
        PinSessionObserver(child: RecordPaymentScreen(customerId: ahmad)),
      );
      // The payment form is a debt screen: behind the same door.
      expect(locked, findsOneWidget);
      expect(find.byKey(const ValueKey('payment-amount')), findsNothing);
      await unlockHere(tester);
      await tester.enterText(
          find.byKey(const ValueKey('payment-amount')), '4000');
      await tester.enterText(
          find.byKey(const ValueKey('payment-note')), 'for November');
      await settle(tester);

      // The seller leaves to read the amount of a transfer.
      await leaveAndComeBack(tester);
      expect(locked, findsOneWidget);
      expect(find.byKey(const ValueKey('payment-amount')), findsNothing);
      expect(find.text('4000'), findsNothing);

      await unlockHere(tester);
      expect(find.text('4000'), findsOneWidget);
      expect(find.text('for November'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-save')));
      await animated(tester);
      expect(await balance(tester, ahmad), 1000);
    });

    testWidgets('a ledger entry open in its sheet closes with the session',
        (tester) async {
      await lockDebts(tester);
      await pump(
        tester,
        PinSessionObserver(
          child: CustomerDetailScreen(
            customerId: ahmad,
            initialTab: CustomerTab.account,
          ),
        ),
      );
      await animated(tester);
      await unlockHere(tester);
      final entryId =
          (await rows(tester, 'debt_transactions')).single['id']! as int;
      await tester.tap(find.byKey(ValueKey('ledger-entry-$entryId')));
      await animated(tester);
      expect(find.byKey(const ValueKey('entry-sheet')), findsOneWidget);

      await leaveAndComeBack(tester);
      expect(find.byKey(const ValueKey('entry-sheet')), findsNothing);
      expect(locked, findsOneWidget);
      expect(find.byKey(const ValueKey('account-balance')), findsNothing);
    });

    testWidgets('with the "PIN to open debts" setting off nothing ever locks',
        (tester) async {
      await setPin(tester);
      await owe(tester, ahmad, 5000, daysAgo: 100);
      await pump(tester, const PinSessionObserver(child: DebtorsScreen()));
      expect(total, findsOneWidget);
      await tester.pump(const Duration(minutes: 30));
      await settle(tester);
      await leaveAndComeBack(tester);
      expect(total, findsOneWidget);
      expect(locked, findsNothing);
    });

    group('behind something the app opened itself: two minutes', () {
      /// To the background…
      Future<void> leave(WidgetTester tester) async {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await settle(tester);
      }

      /// …and back.
      Future<void> comeBack(WidgetTester tester) async {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await animated(tester);
      }

      /// The debtors list, unlocked, and a WhatsApp reminder sent from it.
      Future<void> remind(WidgetTester tester, {int? minutes}) async {
        await lockDebts(tester, minutes: minutes);
        await pump(tester, const PinSessionObserver(child: DebtorsScreen()));
        await unlockHere(tester);
        await tester.tap(find.byKey(ValueKey('debtor-remind-$ahmad')));
        await until(tester, () => bridge.chats.isNotEmpty);
      }

      testWidgets('a WhatsApp reminder, back within two minutes: no PIN — '
          'and the home button after that locks at once', (tester) async {
        await remind(tester);
        await leave(tester);
        await tester.pump(const Duration(minutes: 1, seconds: 50));
        await comeBack(tester);
        expect(total, findsOneWidget);
        expect(locked, findsNothing);

        // The reminder bought ONE trip.
        await leaveAndComeBack(tester);
        expect(locked, findsOneWidget);
        expect(total, findsNothing);
      });

      testWidgets('a WhatsApp reminder, away for more than two minutes: the '
          'PIN again', (tester) async {
        await remind(tester);
        await leave(tester);
        await tester.pump(const Duration(minutes: 2, seconds: 1));
        await comeBack(tester);
        expect(locked, findsOneWidget);
        expect(total, findsNothing);
      });

      testWidgets('WhatsApp could not be opened: nothing was bought, the '
          'home button locks at once', (tester) async {
        bridge.chatOpens = false;
        await remind(tester);
        await settle(tester);
        await leaveAndComeBack(tester);
        expect(locked, findsOneWidget);
      });

      testWidgets('the reminder was sent a while ago: the home button locks '
          'at once', (tester) async {
        await remind(tester);
        // WhatsApp never came up, and the seller went on working.
        await tester.pump(const Duration(seconds: 30));
        await leaveAndComeBack(tester);
        expect(locked, findsOneWidget);
      });

      testWidgets('"lock again after 1 minute" still counts: 70 seconds in '
          'WhatsApp is the PIN again', (tester) async {
        await remind(tester, minutes: 1);
        await leave(tester);
        await tester.pump(const Duration(seconds: 70));
        await comeBack(tester);
        expect(locked, findsOneWidget);
      });

      testWidgets('a receipt through the share sheet: the time spent '
          'choosing, then the other app, then back — no PIN', (tester) async {
        await lockDebts(tester);
        final payment = await pay(tester, ahmad, 2000);
        await pump(
          tester,
          PinSessionObserver(child: ReceiptScreen(entryId: payment.id)),
        );
        await unlockHere(tester);
        final preview = find.byKey(const ValueKey('receipt-preview'));
        await until(tester, () => preview.evaluate().isNotEmpty);

        await tester.tap(find.byKey(const ValueKey('paper-more')));
        await animated(tester);
        await tester.tap(find.byKey(const ValueKey('paper-more-shareImage')));
        await until(tester, () => bridge.shared.isNotEmpty);

        // The share sheet is a panel over the app…
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(seconds: 40));
        // …and the app only leaves the screen once a target is chosen.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        await comeBack(tester);
        expect(locked, findsNothing);
        expect(preview, findsOneWidget);

        await leaveAndComeBack(tester);
        expect(locked, findsOneWidget);
        expect(preview, findsNothing);
      });

      testWidgets('a card code shown in full: open on the way back in time, '
          'closed when it took too long', (tester) async {
        await pump(
          tester,
          PinSessionObserver(
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const RevealedCodeDialog(
                      productName: 'Card 5000',
                      code: '1111222233334444',
                    ),
                  ),
                  child: const Text('reveal'),
                ),
              ),
            ),
          ),
        );
        final dialog = find.byKey(const ValueKey('revealed-code-dialog'));
        final guard = ProviderScope.containerOf(
          tester.element(find.text('reveal')),
        ).read(pinBackgroundGuardProvider);
        await tester.tap(find.text('reveal'));
        await animated(tester);
        expect(dialog, findsOneWidget);

        guard.externalActionStarting();
        await leave(tester);
        await tester.pump(const Duration(minutes: 1, seconds: 30));
        await comeBack(tester);
        expect(dialog, findsOneWidget);

        guard.externalActionStarting();
        await leave(tester);
        await tester.pump(const Duration(minutes: 2, seconds: 1));
        await comeBack(tester);
        expect(dialog, findsNothing);
      });
    });

    group('the same rule for the other things the PIN opens', () {
      Future<void> openAuditLog(WidgetTester tester) async {
        await setPin(tester);
        await pump(tester, const PinSessionObserver(child: SettingsScreen()));
        final tile = find.byKey(const ValueKey('setting-audit-log'));
        await reveal(tester, tile);
        await tester.tap(tile);
        await animated(tester);
        await enterPin(tester);
        await animated(tester);
        expect(find.byType(AuditLogScreen), findsOneWidget);
      }

      testWidgets('the audit log closes after the idle time; a touch keeps '
          'it open', (tester) async {
        await openAuditLog(tester);
        await tester.pump(const Duration(minutes: 4));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('audit-period-today')));
        await settle(tester);
        await tester.pump(const Duration(minutes: 4));
        await settle(tester);
        expect(find.byType(AuditLogScreen), findsOneWidget);

        await tester.pump(const Duration(minutes: 1, seconds: 1));
        await animated(tester);
        expect(find.byType(AuditLogScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('the audit log closes at once when the app is left',
          (tester) async {
        await openAuditLog(tester);
        await leaveAndComeBack(tester);
        expect(find.byType(AuditLogScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsOneWidget);
        // Getting back in is the PIN again.
        await tester.tap(find.byKey(const ValueKey('setting-audit-log')));
        await animated(tester);
        expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      });

      testWidgets('a card code shown in full closes the same two ways',
          (tester) async {
        Widget host() => PinSessionObserver(
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const RevealedCodeDialog(
                        productName: 'Card 5000',
                        code: '1111222233334444',
                      ),
                    ),
                    child: const Text('reveal'),
                  ),
                ),
              ),
            );
        final dialog = find.byKey(const ValueKey('revealed-code-dialog'));

        await pump(tester, host());
        await tester.tap(find.text('reveal'));
        await animated(tester);
        expect(dialog, findsOneWidget);
        await tester.pump(const Duration(minutes: 5, seconds: 1));
        await animated(tester);
        expect(dialog, findsNothing);

        await tester.tap(find.text('reveal'));
        await animated(tester);
        expect(dialog, findsOneWidget);
        await leaveAndComeBack(tester);
        expect(dialog, findsNothing);
      });
    });
  });

  group('with the debt ledger off, nothing of it shows anywhere', () {
    testWidgets('home, customer page, statistics, settings, invoice settings',
        (tester) async {
      await owe(tester, ahmad, 5000, daysAgo: 100);

      await pump(tester, const HomeScreen(), debtOn: false);
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('home-debts')), findsNothing);

      await pump(tester, CustomerDetailScreen(customerId: ahmad), debtOn: false);
      expect(find.byKey(const ValueKey('customer-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('customer-phone')), findsOneWidget);

      await pump(tester, const StatsScreen(), debtOn: false);
      await statsLoaded(tester);
      expect(
        find.byKey(const ValueKey('stats-debts'), skipOffstage: false),
        findsNothing,
      );

      await pump(tester, const SettingsScreen(), debtOn: false);
      expect(find.text('Days to pay', skipOffstage: false), findsNothing);
      expect(
        find.byKey(
          const ValueKey('setting-debt-require-pin'),
          skipOffstage: false,
        ),
        findsNothing,
      );

      await pump(tester, const InvoiceSettingsScreen(), debtOn: false);
      await settle(tester, 20);
      expect(find.text('Debt lines', skipOffstage: false), findsNothing);

      final customer =
          await db(tester, () async => (await CustomerRepository(database.db).getById(sara))!);
      await pump(tester, CustomerFormScreen(customer: customer), debtOn: false);
      expect(
        find.byKey(const ValueKey('customer-credit-limit-field')),
        findsNothing,
      );
    });
  });
}
