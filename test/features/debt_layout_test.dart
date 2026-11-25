import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
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
import 'package:souqi/features/debts/debt_actions.dart';
import 'package:souqi/features/debts/debt_settings.dart';
import 'package:souqi/features/debts/debtors_screen.dart';
import 'package:souqi/features/debts/entry_form_screen.dart';
import 'package:souqi/features/debts/opening_balances_screen.dart';
import 'package:souqi/features/debts/payment_form_screen.dart';
import 'package:souqi/features/debts/receipt_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/sale/cash_received.dart';
import 'package:souqi/features/sale/payment_sheet.dart';
import 'package:souqi/features/sale/sale_providers.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/security/audit_log_screen.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// Every screen, sheet and dialog of the debt ledger on the smallest phone
/// this app targets — 360×640 — at system font scale 1.3, in Arabic and in
/// English, without and with the keyboard up: nothing may overflow.
///
/// The amounts are in the hundreds of millions and the names are as long as
/// real ones get, because that is what overflows on a phone. (The test font
/// draws every glyph as a square of the font size, so text here is wider
/// than on a device: what fits here fits there.)
///
/// A RenderFlex overflow is reported as a framework exception, so every
/// check ends on [WidgetTester.takeException] being null.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late DebtRepository debts;
  late int customerId;
  late Invoice creditSale;

  const phone = Size(360, 640);
  const keyboardInset = 300.0;
  const longName = 'عبد الرحمن محمد الأحمد الحسن الطويل';
  const big = 987654321;

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

  setUp(() async {
    database = await openTestDb();
    debts = DebtRepository(database.db);
  });
  tearDown(() async => database.close());

  /// A customer with a long name, a credit limit they are over, an old
  /// unpaid debt, a credit sale, a payment in dollars, a reversed payment —
  /// every kind of row, with amounts as wide as they come.
  Future<void> seed(WidgetTester tester) async {
    await db(tester, () async {
      await database.db.update(
        'currencies',
        {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
        where: 'code = ?',
        whereArgs: ['USD'],
      );
      final customers = CustomerRepository(database.db);
      customerId = await customers.insert(const Customer(
        name: longName,
        phone: '+963 944 123 456',
        notes: 'يدفع في أول كل شهر، المحل المقابل للصيدلية',
        creditLimitBaseMinor: 5000000,
        defaultDueDays: 15,
      ));
      final now = DateTime.now();
      await debts.addOpeningBalance(
        customerId: customerId,
        amountBaseMinor: big,
        at: now.subtract(const Duration(days: 200)),
        note: 'من الدفتر القديم، الصفحة السابعة والثلاثون',
      );
      creditSale = await InvoiceRepository(database.db).save(
        Invoice.fromCart(
          cart: const Cart().add(const CartLine(
            name: 'Rice with a rather long name',
            unitPriceMinor: 123456789,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          )),
          ctx: CurrencyContext.of([syp, usd], baseCode: 'SYP'),
          createdAt: now.subtract(const Duration(days: 3)),
          customerId: customerId,
          customerName: longName,
          customerPhone: '+963 944 123 456',
        ),
        payment: const SalePayment(paidMinor: 23456789, overrideCreditLimit: true),
      );
      await debts.recordPayment(
        customerId: customerId,
        amountMinor: 1234567,
        currencyCode: 'USD',
        currencyDecimals: 2,
        rate: const RateFraction(24691, 2),
        baseCode: 'SYP',
        baseDecimals: 0,
        method: PaymentMethod.transfer,
        note: 'حوالة عن طريق مكتب الصرافة في أول الشارع',
        at: now.subtract(const Duration(days: 2)),
      );
      final wrong = await debts.recordPayment(
        customerId: customerId,
        amountMinor: 55555555,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
        at: now.subtract(const Duration(days: 1)),
      );
      await debts.reverse(wrong.id, reason: 'سُجّلت على الزبون الخطأ');
      // A second debtor and a customer the shop owes.
      final other = await customers
          .insert(const Customer(name: 'Samer', phone: '0933 555 111'));
      await debts.addManualDebt(customerId: other, amountBaseMinor: 4500);
      final creditor = await customers.insert(const Customer(name: longName));
      await debts.addOpeningBalance(
        customerId: creditor,
        amountBaseMinor: big,
        customerOwes: false,
      );
      return true;
    });
  }

  /// Pumps [screen] on the 360×640 phone at font scale 1.3 and checks it,
  /// then raises the keyboard and checks it again.
  Future<void> pumpPhone(
    WidgetTester tester,
    Widget screen, {
    String locale = 'en',
    bool keyboard = true,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = phone * tester.view.devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.resetViewInsets();
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(Locale(locale))),
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
    await settle(tester, 28);
    expect(tester.takeException(), isNull, reason: 'without the keyboard');
    if (!keyboard) return;
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardInset * tester.view.devicePixelRatio,
    );
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'with the keyboard up');
  }

  /// Brings [finder] on screen before it is used: scrolls a lazy list until
  /// it is built, then scrolls it into view — sideways too, for a row of
  /// chips. On a 360×640 phone with the keyboard up most of a form is below
  /// the fold, and a tap on something that is not on screen tests nothing.
  Future<void> reach(WidgetTester tester, Finder finder) async {
    final lists = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    // Down first; and if it is not there, it was scrolled past: back up.
    for (final step in const [-200.0, 200.0]) {
      for (var i = 0;
          i < 40 && finder.evaluate().isEmpty && lists.evaluate().isNotEmpty;
          i++) {
        await tester.drag(lists.first, Offset(0, step), warnIfMissed: false);
        await settle(tester, 2);
        expect(tester.takeException(), isNull, reason: 'while scrolling');
      }
    }
    if (finder.evaluate().isEmpty) return; // the caller's tap reports it
    await tester.ensureVisible(finder.first);
    await settle(tester, 4);
    expect(tester.takeException(), isNull, reason: 'brought on screen');
  }

  void keyboardUp(WidgetTester tester) => tester.view.viewInsets =
      FakeViewPadding(bottom: keyboardInset * tester.view.devicePixelRatio);

  /// Scrolls [list] to its end in steps, checking after each one: what is
  /// below the fold of a lazy list is only laid out once it is reached.
  Future<void> scrollThrough(WidgetTester tester, Finder list) async {
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -260), warnIfMissed: false);
      await settle(tester, 4);
      expect(tester.takeException(), isNull, reason: 'scrolled $i times');
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
    expect(tester.takeException(), isNull, reason: 'opened');
    keyboardUp(tester);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'opened, keyboard up');
  }

  for (final locale in ['ar', 'en']) {
    group('[$locale]', () {
      testWidgets('the Account tab: summary, actions, filters and every kind '
          'of ledger line', (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          CustomerDetailScreen(
            customerId: customerId,
            initialTab: CustomerTab.account,
          ),
          locale: locale,
          keyboard: false,
        );
        expect(find.byKey(const ValueKey('account-tab')), findsOneWidget);
        await scrollThrough(tester, find.byKey(const ValueKey('account-tab')));
      });

      testWidgets('a ledger entry in full: a payment in dollars, a reversed '
          'payment, its reversal, a debt whose invoice exists', (tester) async {
        await seed(tester);
        final lines = await db(tester, () => debts.ledger(customerId));
        expect(lines.length, greaterThanOrEqualTo(5));
        for (final line in lines) {
          await pumpPhone(
            tester,
            host((context) => showEntrySheet(context, line)),
            locale: locale,
            keyboard: false,
          );
          await tester.tap(find.text('open it'));
          await settle(tester, 28);
          expect(tester.takeException(), isNull,
              reason: '${line.entry.type} ${line.entry.id}');
          expect(find.byKey(const ValueKey('entry-sheet')), findsOneWidget);
        }
      });

      testWidgets('the reverse-entry dialog', (tester) async {
        await pumpPhone(
          tester,
          host((context) => showDialog<String>(
                context: context,
                builder: (_) => const ReverseEntryDialog(
                  description:
                      'سند قبض 123456 · 987,654,321 ل.س — عبد الرحمن الطويل',
                ),
              )),
          locale: locale,
          keyboard: false,
        );
        await openHost(tester);
        // The error line makes it taller still.
        await reach(tester, find.byKey(const ValueKey('reverse-confirm')));
        await tester.tap(find.byKey(const ValueKey('reverse-confirm')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('record payment: base currency, then dollars with the rate '
          'and the over-balance note', (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          RecordPaymentScreen(customerId: customerId),
          locale: locale,
        );
        await reach(tester, find.byKey(const ValueKey('payment-amount')));
        await tester.enterText(
            find.byKey(const ValueKey('payment-amount')), '99999999999');
        await settle(tester);
        expect(tester.takeException(), isNull);
        await reach(tester, find.byKey(const ValueKey('payment-currency-USD')));
        await tester.tap(find.byKey(const ValueKey('payment-currency-USD')));
        await settle(tester);
        expect(tester.takeException(), isNull);
        // Errors on both fields at once.
        await reach(tester, find.byKey(const ValueKey('payment-rate')));
        await tester.enterText(find.byKey(const ValueKey('payment-rate')), 'x');
        await reach(tester, find.byKey(const ValueKey('payment-amount')));
        await tester.enterText(find.byKey(const ValueKey('payment-amount')), '');
        await settle(tester);
        await scrollThrough(tester, find.byKey(const ValueKey('payment-form')));
        await reach(tester, find.byKey(const ValueKey('payment-save')));
        await tester.tap(find.byKey(const ValueKey('payment-save')),
            warnIfMissed: false);
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the receipt screen', (tester) async {
        await seed(tester);
        final payment = (await db(tester, () => debts.ledger(customerId)))
            .firstWhere((l) => l.entry.origCurrencyCode == 'USD')
            .entry;
        await pumpPhone(
          tester,
          ReceiptScreen(entryId: payment.id, copy: true),
          locale: locale,
          keyboard: false,
        );
        await settle(tester, 30);
        expect(find.byKey(const ValueKey('receipt-screen')), findsOneWidget);
        await scrollThrough(
            tester, find.byKey(const ValueKey('receipt-screen')));
      });

      testWidgets('the statement screen', (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          StatementScreen(customerId: customerId),
          locale: locale,
          keyboard: false,
        );
        await settle(tester, 30);
        await reach(tester, find.byKey(const ValueKey('statement-period-all')));
        await tester.tap(find.byKey(const ValueKey('statement-period-all')));
        await settle(tester, 30);
        expect(tester.takeException(), isNull);
        await scrollThrough(
            tester, find.byKey(const ValueKey('statement-screen')));
      });

      for (final kind in LedgerEntryKind.values) {
        testWidgets('the entry form: ${kind.name}', (tester) async {
          await seed(tester);
          await pumpPhone(
            tester,
            LedgerEntryFormScreen(customerId: customerId, kind: kind),
            locale: locale,
          );
          // Both errors showing.
          await scrollThrough(tester, find.byKey(const ValueKey('entry-form')));
          await reach(tester, find.byKey(const ValueKey('entry-save')));
          await tester.tap(find.byKey(const ValueKey('entry-save')),
              warnIfMissed: false);
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('opening balances: the empty form, suggestions, a picked '
          'customer, and rows already entered', (tester) async {
        await seed(tester);
        await pumpPhone(tester, const OpeningBalancesScreen(), locale: locale);
        // Suggestions under the name field.
        await reach(tester, find.byKey(const ValueKey('opening-name')));
        await tester.enterText(find.byKey(const ValueKey('opening-name')), 'عبد');
        await settle(tester, 20);
        expect(tester.takeException(), isNull);
        await reach(tester, find.byKey(ValueKey('opening-suggestion-$customerId')));
        await tester.tap(
          find.byKey(ValueKey('opening-suggestion-$customerId')),
        );
        await settle(tester, 20);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('opening-picked')), findsOneWidget);
        // Errors, then a real row.
        await reach(tester, find.byKey(const ValueKey('opening-add')));
        await tester.tap(find.byKey(const ValueKey('opening-add')),
            warnIfMissed: false);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await reach(tester, find.byKey(const ValueKey('opening-amount')));
        await tester.enterText(
            find.byKey(const ValueKey('opening-amount')), '987654321');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester, 20);
        expect(tester.takeException(), isNull);
        await scrollThrough(
            tester, find.byKey(const ValueKey('opening-balances')));
      });

      testWidgets('the debtors list: summary, aging, filters, rows',
          (tester) async {
        await seed(tester);
        await pumpPhone(tester, const DebtorsScreen(), locale: locale);
        // The summary fills the little room the keyboard leaves: the rows
        // are under it.
        await reach(tester, find.byType(DebtorTile));
        expect(find.byType(DebtorTile), findsWidgets);
        await reach(tester, find.byKey(const ValueKey('debtors-filter-credit')));
        await tester.tap(find.byKey(const ValueKey('debtors-filter-credit')),
            warnIfMissed: false);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await reach(tester, find.byKey(const ValueKey('debtors-filter-owing')));
        await tester.tap(find.byKey(const ValueKey('debtors-filter-owing')),
            warnIfMissed: false);
        await settle(tester);
        tester.view.resetViewInsets();
        await settle(tester);
        await scrollThrough(tester, find.byKey(const ValueKey('debtors-list')));
      });

      testWidgets('the payment sheet: full, partial, on credit, over the '
          'limit, with a credit balance', (tester) async {
        await seed(tester);
        final ctx = CurrencyContext.of([syp, usd], baseCode: 'SYP');
        final totals = computeCartTotals(
          const Cart().add(const CartLine(
            name: 'Rice',
            unitPriceMinor: 123456789,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          )),
          ctx,
        );
        Future<void> open(SaleCustomer? customer) async {
          await pumpPhone(
            tester,
            host((context) => showModalBottomSheet<PaymentChoice>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) =>
                      PaymentSheet(totals: totals, customer: customer),
                )),
            locale: locale,
            keyboard: false,
          );
          await openHost(tester);
        }

        Future<void> check(String what) async {
          await settle(tester, 6);
          expect(tester.takeException(), isNull, reason: what);
        }

        // No customer: the short sheet, then the one that asks for one.
        await open(null);
        await check('on credit, no customer');
        await reach(tester, find.byKey(const ValueKey('pay-mode-full')));
        await tester.tap(find.byKey(const ValueKey('pay-mode-full')));
        await settle(tester);
        await reach(tester, find.byKey(const ValueKey('pay-cash-received')));
        await tester.enterText(
            find.byKey(const ValueKey('pay-cash-received')), '999999999');
        await check('full, cash received');
        await reach(tester, find.byKey(const ValueKey('pay-mode-partial')));
        await tester.tap(find.byKey(const ValueKey('pay-mode-partial')));
        await check('partial, no customer');
        await reach(tester, find.byKey(const ValueKey('pay-save')));
        await tester.tap(find.byKey(const ValueKey('pay-save')),
            warnIfMissed: false);
        await check('partial, error');

        // The long-named customer who is over their limit.
        await open(SaleCustomer(customerId: customerId, name: longName));
        await check('full, with customer');
        await reach(tester, find.byKey(const ValueKey('pay-mode-partial')));
        await tester.tap(find.byKey(const ValueKey('pay-mode-partial')));
        await reach(tester, find.byKey(const ValueKey('pay-amount-paid')));
        await tester.enterText(
            find.byKey(const ValueKey('pay-amount-paid')), '1000000');
        await check('partial, over the limit');
        expect(find.byKey(const ValueKey('pay-limit-warning')), findsOneWidget);
        await reach(tester, find.byKey(const ValueKey('pay-mode-credit')));
        await tester.tap(find.byKey(const ValueKey('pay-mode-credit')));
        await check('credit, over the limit');

        // The customer the shop owes: "use credit balance".
        final creditor = await db(tester, () async {
          final rows = await database.db.query('customers', orderBy: 'id DESC');
          return rows.first['id']! as int;
        });
        await open(SaleCustomer(customerId: creditor, name: longName));
        await reach(tester, find.byKey(const ValueKey('pay-use-credit')));
        await tester.tap(find.byKey(const ValueKey('pay-use-credit')),
            warnIfMissed: false);
        await check('credit balance used');
      });

      testWidgets('the sale screen: Save and "Credit / Partial" side by side, '
          'with the cash-received line on', (tester) async {
        await seed(tester);
        await db(tester, () async {
          await SettingsRepository(database.db)
              .setBool(SettingsKeys.showCashReceived, true);
          return true;
        });
        await pumpPhone(tester, const SaleScreen(),
            locale: locale, keyboard: false);
        // A cart in the millions (the size the cart rows are built for), a
        // discount, a customer with a long name and money on the counter in
        // the hundreds of millions: the panel at its tallest and widest.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SaleScreen)),
        );
        container.read(cartProvider.notifier)
          ..add(const CartLine(
            name: 'Rice with a rather long name',
            unitPriceMinor: 3500000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          ))
          ..setDiscount(const Discount.percent(500));
        container.read(saleCustomerProvider.notifier).attach(
              SaleCustomer(customerId: customerId, name: longName),
            );
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'no cash typed yet');
        for (final received in [999999999, 1]) {
          container.read(cashReceivedProvider.notifier).set(
                CashReceived(amountMinor: received, currencyCode: 'SYP'),
              );
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'received $received');
        }
        final save = find.byKey(const ValueKey('sale-save'));
        final credit = find.byKey(const ValueKey('sale-credit'));
        expect(save, findsOneWidget);
        expect(credit, findsOneWidget);
        // One line high, the same height, both fully on the screen.
        expect(tester.getSize(save).height, tester.getSize(credit).height);
        expect(tester.getSize(save).height, lessThan(80));
        expect(tester.getRect(credit).right, lessThanOrEqualTo(360));
        expect(tester.getRect(save).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(save).bottom, lessThanOrEqualTo(640));
      });

      testWidgets('the cash-received dialog', (tester) async {
        final totals = computeCartTotals(
          const Cart().add(const CartLine(
            name: 'Rice',
            unitPriceMinor: 123456789,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          )),
          CurrencyContext.of([syp, usd], baseCode: 'SYP'),
        );
        for (final initial in [null, 999999999, 5]) {
          await pumpPhone(
            tester,
            host((context) => showDialog<CashReceivedChoice>(
                  context: context,
                  builder: (_) => CashReceivedDialog(
                    totals: totals,
                    locale: locale,
                    initialMinor: initial,
                  ),
                )),
            locale: locale,
            keyboard: false,
          );
          await openHost(tester);
          expect(find.byType(CashReceivedDialog), findsOneWidget);
        }
        // The error line under the field.
        await reach(tester, find.byKey(const ValueKey('cash-received-field')));
        await tester.enterText(
            find.byKey(const ValueKey('cash-received-field')), '');
        await reach(tester, find.byKey(const ValueKey('cash-received-ok')));
        await tester.tap(find.byKey(const ValueKey('cash-received-ok')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the credit-limit confirmation (no PIN set)', (tester) async {
        await seed(tester);
        final ctx = CurrencyContext.of([syp, usd], baseCode: 'SYP');
        final totals = computeCartTotals(
          const Cart().add(const CartLine(
            name: 'Rice',
            unitPriceMinor: 123456789,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          )),
          ctx,
        );
        await pumpPhone(
          tester,
          host((context) => showModalBottomSheet<PaymentChoice>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => PaymentSheet(
                  totals: totals,
                  customer:
                      SaleCustomer(customerId: customerId, name: longName),
                ),
              )),
          locale: locale,
          keyboard: false,
        );
        await tester.tap(find.text('open it'));
        await settle(tester, 28);
        await reach(tester, find.byKey(const ValueKey('pay-mode-credit')));
        await tester.tap(find.byKey(const ValueKey('pay-mode-credit')));
        await settle(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('pay-save')));
        await reach(tester, find.byKey(const ValueKey('pay-save')));
        await tester.tap(find.byKey(const ValueKey('pay-save')));
        await settle(tester, 28);
        expect(
            find.byKey(const ValueKey('credit-limit-confirm')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the saved-invoice screen of a sale on credit',
          (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          SaleInvoiceScreen(invoice: creditSale),
          locale: locale,
          keyboard: false,
        );
        expect(find.byKey(const ValueKey('saved-paid-line')), findsOneWidget);
      });

      testWidgets('home with the Debts card — and with the card locked',
          (tester) async {
        await seed(tester);
        await pumpPhone(tester, const HomeScreen(), locale: locale);
        expect(find.byKey(const ValueKey('home-debts')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-debts-total')), findsOneWidget);

        await db(tester, () async {
          final settings = SettingsRepository(database.db);
          await PinRepository(settings).set('2580');
          await settings.setBool(SettingsKeys.debtRequirePin, true);
          return true;
        });
        for (final type in ['GROCERY', 'BOTH']) {
          await db(tester, () async {
            await SettingsRepository(database.db)
                .setString(SettingsKeys.shopType, type);
            return true;
          });
          await pumpPhone(tester, const HomeScreen(), locale: locale);
          expect(find.byKey(const ValueKey('home-debts-locked')), findsOneWidget,
              reason: type);
        }
      });

      testWidgets('the locked door of the debtors list', (tester) async {
        await seed(tester);
        await db(tester, () async {
          final settings = SettingsRepository(database.db);
          await PinRepository(settings).set('2580');
          await settings.setBool(SettingsKeys.debtRequirePin, true);
          return true;
        });
        await pumpPhone(tester, const DebtorsScreen(), locale: locale);
        expect(find.byKey(const ValueKey('debt-locked')), findsOneWidget);
      });

      testWidgets('statistics with the debt card', (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          const StatsScreen(),
          locale: locale,
          keyboard: false,
        );
        await scrollThrough(tester, find.byType(ListView).last);
        expect(
          find.byKey(const ValueKey('stats-debts'), skipOffstage: false),
          findsOneWidget,
        );
      });

      testWidgets('settings with the Debts section, and the reminder dialog',
          (tester) async {
        await pumpPhone(
          tester,
          const SettingsScreen(),
          locale: locale,
          keyboard: false,
        );
        await scrollThrough(tester, find.byType(ListView).first);

        await pumpPhone(
          tester,
          host((context) => showDialog<String>(
                context: context,
                builder: (_) => DebtReminderDialog(
                  initial: 'مرحباً {name}، تذكير من {shop}: رصيدكم المستحق '
                          '{balance}. آخر دفعة: {last_payment_date}. ' *
                      3,
                  defaultText: 'x',
                ),
              )),
          locale: locale,
          keyboard: false,
        );
        await openHost(tester);
      });

      testWidgets('invoice settings with the four debt toggles',
          (tester) async {
        await pumpPhone(
          tester,
          const InvoiceSettingsScreen(),
          locale: locale,
          keyboard: false,
        );
        await scrollThrough(tester, find.byType(Scrollable).last);
      });

      testWidgets('the customer form with the credit limit and days to pay',
          (tester) async {
        await seed(tester);
        final customer = await db(
          tester,
          () async =>
              (await CustomerRepository(database.db).getById(customerId))!,
        );
        await pumpPhone(
          tester,
          CustomerFormScreen(customer: customer),
          locale: locale,
        );
        await reach(tester, find.byKey(const ValueKey('customer-credit-limit-field')));
        await tester.enterText(
            find.byKey(const ValueKey('customer-credit-limit-field')), 'abc');
        await reach(tester, find.byKey(const ValueKey('customer-due-days-field')));
        await tester.enterText(
            find.byKey(const ValueKey('customer-due-days-field')), '99999');
        await settle(tester);
        await scrollThrough(tester, find.byType(ListView));
        await reach(tester, find.byKey(const ValueKey('customer-save')));
        await tester.tap(find.byKey(const ValueKey('customer-save')),
            warnIfMissed: false);
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('deactivating a customer who owes: the dialog with the '
          'balance', (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          CustomerDetailScreen(customerId: customerId),
          locale: locale,
          keyboard: false,
        );
        await reach(tester, find.byKey(const ValueKey('customer-menu')));
        await tester.tap(find.byKey(const ValueKey('customer-menu')));
        await settle(tester, 28);
        await tester.tap(find.byType(PopupMenuItem<void>).first);
        await settle(tester, 28);
        expect(find.byKey(const ValueKey('deactivate-with-balance')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the delete dialogs that say the debts stay',
          (tester) async {
        await seed(tester);
        await pumpPhone(
          tester,
          InvoiceDetailScreen(invoiceId: creditSale.id!),
          locale: locale,
          keyboard: false,
        );
        await reach(tester, find.byKey(const ValueKey('archive-delete-invoice')));
        await tester.tap(find.byKey(const ValueKey('archive-delete-invoice')));
        await settle(tester, 28);
        expect(find.byKey(const ValueKey('delete-invoice-debt-note')),
            findsOneWidget);
        expect(tester.takeException(), isNull);

        await pumpPhone(
          tester,
          const ArchiveScreen(),
          locale: locale,
          keyboard: false,
        );
        await tester.tap(find.byType(PopupMenuButton<void>));
        await settle(tester, 28);
        await reach(tester, find.byKey(const ValueKey('archive-delete-range')));
        await tester.tap(find.byKey(const ValueKey('archive-delete-range')));
        await settle(tester, 28);
        expect(find.byKey(const ValueKey('archive-delete-debt-note')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the audit log with a reversal, an adjustment and a limit '
          'override', (tester) async {
        await seed(tester);
        await db(tester, () async {
          await debts.addAdjustment(
            customerId: customerId,
            amountBaseMinor: big,
            increasesDebt: false,
            reason: 'تصحيح خطأ قديم في الدفتر بعد مراجعة الزبون',
          );
          return true;
        });
        await pumpPhone(
          tester,
          const AuditLogScreen(),
          locale: locale,
          keyboard: false,
        );
        expect(
          find.byType(ListTile, skipOffstage: false),
          findsNWidgets(3),
        );
        await scrollThrough(tester, find.byType(ListView));
      });
    });
  }
}
