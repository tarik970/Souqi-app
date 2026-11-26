import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/config/support.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/license/license_providers.dart';
import 'package:souqi/features/returns/return_items_screen.dart';
import 'package:souqi/features/returns/return_screen.dart';
import 'package:souqi/features/security/pin_session.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/correction_test_kit.dart';
import 'invoice_test_utils.dart';

/// A license that has run out, as the screens see it.
class _Unlicensed extends LicenseController {
  @override
  LicenseStatus build() => const LicenseStatus(
        mode: LicenseMode.unlicensed,
        reason: UnlicensedReason.trialDaysOver,
        featureMask: allLicenseFeatures,
        canSell: false,
        canPrint: false,
      );
}

/// Voiding an invoice and returning items, on the screens: the steps, the
/// PIN, what lands in the database, and what the archive, the statistics
/// and the locked screens then show.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  const pin = '2580';

  late TestShop shop;
  late FakeNativeBridge bridge;
  late Directory outputDir;

  setUp(() async {
    shop = await TestShop.open();
    bridge = FakeNativeBridge();
    outputDir = await Directory.systemTemp.createTemp('souqi_returns_test');
  });
  tearDown(() async {
    await shop.close();
    if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
  });

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

  /// Waits on an effect that takes a variable amount of real time (hashing
  /// a PIN, a transaction) instead of on a fixed number of frames.
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

  Future<void> setPin(WidgetTester tester) => db(tester, () async {
        await PinRepository(SettingsRepository(shop.db)).set(pin);
        return true;
      });

  Future<void> setting(WidgetTester tester, String key, String value) =>
      db(tester, () async {
        await SettingsRepository(shop.db).setString(key, value);
        return true;
      });

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String table,
  ) =>
      db(tester, () => shop.db.query(table, orderBy: 'id'));

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    // A phone-shaped viewport, 600×1300 logical pixels.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(shop.database),
          appLocaleProvider
              .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
          nativeBridgeProvider.overrideWithValue(bridge),
          secretKeyStoreProvider.overrideWithValue(shop.keyStore),
          outputDirectoryProvider.overrideWithValue(() async => outputDir),
          ...overrides,
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

  final pinDialog = find.byKey(const ValueKey('pin-entry-dialog'));

  Future<void> enterPin(WidgetTester tester, String value) async {
    expect(pinDialog, findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pin-entry-field')), value);
    await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
    if (value == pin) {
      await until(tester, () => pinDialog.evaluate().isEmpty);
      await animated(tester);
    } else {
      await until(
        tester,
        () => find.textContaining('Wrong PIN').evaluate().isNotEmpty,
      );
    }
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await settle(tester, 2);
    await tester.tap(key(name));
    await animated(tester);
  }

  String textOf(WidgetTester tester, String name) =>
      tester.widget<Text>(key(name)).data!;

  /// The reason step of a void: [choice] is the name of a quick reason.
  Future<void> giveReason(WidgetTester tester, String choice) async {
    expect(key('void-reason-dialog'), findsOneWidget);
    await tester.tap(key('void-reason-$choice'));
    await settle(tester, 4);
    await tester.tap(key('void-reason-continue'));
    await animated(tester);
  }

  group('voiding an invoice', () {
    testWidgets('reason → confirmation that says what will happen → the '
        'invoice is marked, the debt reversed, the audit line written',
        (tester) async {
      final sale = await db(
        tester,
        () => shop.sell([shop.sugar()], customer: true, paid: 3000),
      );
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      expect(key('invoice-void-banner'), findsNothing);
      expect(key('invoice-return'), findsOneWidget);

      await tapKey(tester, 'invoice-void');
      expect(find.text('Void invoice 1?'), findsOneWidget);
      // No card codes on this invoice: the question is not asked.
      expect(key('void-codes-void'), findsNothing);
      await giveReason(tester, 'duplicate');

      // No PIN is set: straight to the confirmation.
      expect(pinDialog, findsNothing);
      expect(key('void-confirm-dialog'), findsOneWidget);
      expect(
        find.textContaining('stays in the archive, marked VOID'),
        findsOneWidget,
      );
      expect(
        find.text('The debt of 5,000 ل.س is reversed on the account of Ahmad.'),
        findsOneWidget,
      );
      expect(find.text('Give 3,000 ل.س back to the customer.'), findsOneWidget);
      expect(find.text('Reason: Duplicate'), findsOneWidget);
      // Nothing happened yet.
      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);

      await tester.tap(key('void-confirm'));
      await until(tester, () => key('invoice-void-banner').evaluate().isNotEmpty);

      expect(find.text('Invoice voided'), findsOneWidget);
      expect(textOf(tester, 'invoice-void-reason'), 'Reason: Duplicate');
      // It can be neither returned nor voided again.
      expect(key('invoice-void'), findsNothing);
      expect(key('invoice-return'), findsNothing);
      // The stamp is on the paper on screen.
      expect(key('paper-void-mark'), findsOneWidget);

      final invoice = (await rows(tester, 'invoices')).single;
      expect(invoice['voided_at'], isNotNull);
      expect(invoice['void_reason'], 'Duplicate');
      expect(await db(tester, () => shop.debts.balanceOf(shop.ahmad)), 0);
      final log = (await db(tester, () => shop.audit('INVOICE_VOID'))).single;
      expect('${log['details']}', contains('"reason":"Duplicate"'));
    });

    testWidgets('the reason is required; "Other" must be typed',
        (tester) async {
      final sale = await db(tester, () => shop.sell([shop.sugar()]));
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');

      await tester.tap(key('void-reason-continue'));
      await settle(tester, 4);
      expect(textOf(tester, 'void-reason-error'), 'Enter the reason');
      expect(key('void-reason-dialog'), findsOneWidget);

      await tester.tap(key('void-reason-other'));
      await settle(tester, 6);
      await tester.tap(key('void-reason-continue'));
      await settle(tester, 4);
      expect(key('void-reason-error'), findsOneWidget);

      await tester.enterText(key('void-reason-text'), 'rang up twice');
      await tester.tap(key('void-reason-continue'));
      await animated(tester);
      expect(find.text('Reason: rang up twice'), findsOneWidget);

      // Backing out of the confirmation voids nothing.
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);
      expect(key('invoice-void'), findsOneWidget);
    });

    testWidgets('with a PIN set, the PIN comes between the reason and the '
        'confirmation; a wrong one voids nothing', (tester) async {
      await setPin(tester);
      final sale = await db(tester, () => shop.sell([shop.sugar()]));
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');
      await giveReason(tester, 'wrongPrice');

      expect(find.text('Enter the PIN to void an invoice.'), findsOneWidget);
      expect(key('void-confirm-dialog'), findsNothing);
      await enterPin(tester, '0000');
      expect(key('void-confirm-dialog'), findsNothing);
      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);

      await enterPin(tester, pin);
      expect(key('void-confirm-dialog'), findsOneWidget);
      await tester.tap(key('void-confirm'));
      await until(tester, () => key('invoice-void-banner').evaluate().isNotEmpty);
      expect(
        (await rows(tester, 'invoices')).single['void_reason'],
        'Wrong price',
      );
    });

    testWidgets('cancelling at the PIN voids nothing', (tester) async {
      await setPin(tester);
      final sale = await db(tester, () => shop.sell([shop.sugar()]));
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');
      await giveReason(tester, 'duplicate');
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(key('void-confirm-dialog'), findsNothing);
      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);
      expect(await db(tester, () => shop.audit('INVOICE_VOID')), isEmpty);
    });

    testWidgets('card codes: voided by default, or returned to stock — the '
        'confirmation says which', (tester) async {
      await db(tester, () async {
        await shop.loadCodes('1111222233334444\n5555666677778888');
        return true;
      });
      final sale =
          await db(tester, () => shop.sell([shop.card(cards: 2)]));
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');

      expect(find.text('Its 2 card codes'), findsOneWidget);
      expect(
        textOf(tester, 'void-codes-hint'),
        contains('printed or handed over'),
      );
      await tester.tap(key('void-codes-stock'));
      await settle(tester, 4);
      expect(
        textOf(tester, 'void-codes-hint'),
        contains('never received them'),
      );
      await giveReason(tester, 'customerCancelled');
      expect(find.text('2 card codes go back to stock.'), findsOneWidget);
      await tester.tap(key('void-confirm'));
      await until(tester, () => key('invoice-void-banner').evaluate().isNotEmpty);

      expect(await db(tester, shop.codeStatuses), ['AVAILABLE', 'AVAILABLE']);
      expect(await db(tester, () => shop.audit('CODE_RESTORE')), hasLength(2));
    });

    testWidgets('a renewal: the confirmation names the account and the date '
        'it goes back to', (tester) async {
      final sale = await db(
        tester,
        () => shop.sell([shop.package()], withAccount: true),
      );
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');
      await giveReason(tester, 'wrongItems');
      expect(
        find.text('Account 0011-2233: the renewal is undone. '
            'It is due again on 11/19/2026.'),
        findsOneWidget,
      );
      await tester.tap(key('void-confirm'));
      await until(tester, () => key('invoice-void-banner').evaluate().isNotEmpty);
      final account = await db(tester, shop.account);
      expect(account.nextDueAt!.toLocal(), TestShop.accountDue);
    });

    testWidgets('an invoice older than the limit: said at once, nothing is '
        'asked', (tester) async {
      await setting(tester, SettingsKeys.voidMaxAgeDays, '30');
      final sale = await db(
        tester,
        () => shop.sell(
          [shop.sugar()],
          at: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      await tapKey(tester, 'invoice-void');
      expect(key('void-reason-dialog'), findsNothing);
      expect(
        find.textContaining('more than 30 days old'),
        findsOneWidget,
      );
      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);
    });

    testWidgets('an invoice with returns is not voided', (tester) async {
      final sale = await db(tester, () => shop.sell([shop.sugar(qty: 2000)]));
      await db(
        tester,
        () => shop.corrections.saveReturn(ReturnDraft(
          invoiceId: sale.id!,
          lines: [
            ReturnLineRequest(
              invoiceItemId: sale.items.single.id!,
              qtyThousandths: 1000,
            ),
          ],
        )),
      );
      await pump(tester, InvoiceDetailScreen(invoiceId: sale.id!));
      // Its returns are listed on it.
      expect(key('invoice-returns'), findsOneWidget);
      expect(key('return-tile-1'), findsOneWidget);
      await tapKey(tester, 'invoice-void');
      expect(key('void-reason-dialog'), findsNothing);
      expect(find.textContaining('This invoice has returns'), findsOneWidget);
    });
  });

  group('returning items', () {
    Future<Invoice> sugarAndTea(WidgetTester tester, {int? paid}) => db(
          tester,
          () => shop.sell(
            [shop.sugar(qty: 3000), shop.tea(qty: 2000)],
            customer: true,
            paid: paid,
          ),
        );

    testWidgets('the lines with what is returnable, the number pad (first '
        'key replaces), the refund as it is typed', (tester) async {
      final sale = await sugarAndTea(tester);
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));

      expect(textOf(tester, 'return-left-0'), 'Sold 3 kg · Returnable 3 kg');
      expect(textOf(tester, 'return-left-1'), 'Sold 2 · Returnable 2');
      expect(textOf(tester, 'return-qty-0'), '0');
      expect(textOf(tester, 'return-refund-preview'), '—');
      expect(
        tester.widget<FilledButton>(key('return-continue')).onPressed,
        isNull,
      );

      // The pad types into the first line until another is tapped.
      await tester.tap(key('keypad-1'));
      await settle(tester, 2);
      await tester.tap(key('keypad-separator'));
      await tester.tap(key('keypad-5'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-qty-0'), '1.5');
      expect(textOf(tester, 'return-refund-preview'), '12,000 ل.س');

      // "Return all" fills every line; the values are selected…
      await tester.tap(key('return-all'));
      await settle(tester, 4);
      expect(textOf(tester, 'return-qty-0'), '3');
      expect(textOf(tester, 'return-qty-1'), '2');
      expect(textOf(tester, 'return-refund-preview'), '30,000 ل.س');
      expect(key('return-qty-selected-0'), findsOneWidget);
      // …so the first key REPLACES the 3, and the next one appends.
      await tester.tap(key('keypad-2'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-qty-0'), '2');
      expect(key('return-qty-selected-0'), findsNothing);
      await tester.tap(key('keypad-separator'));
      await tester.tap(key('keypad-5'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-qty-0'), '2.5');
      expect(textOf(tester, 'return-refund-preview'), '26,000 ل.س');

      // Tapping the other line moves the pad to it, its value selected.
      await tester.tap(key('return-line-1'));
      await settle(tester, 2);
      expect(key('return-qty-selected-1'), findsOneWidget);
      await tester.tap(key('keypad-1'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-qty-1'), '1');
      expect(textOf(tester, 'return-refund-preview'), '23,000 ل.س');

      // More than is returnable: no refund, no way on.
      await tester.tap(key('keypad-9'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-qty-1'), '19');
      expect(textOf(tester, 'return-refund-preview'), '—');
      expect(
        tester.widget<FilledButton>(key('return-continue')).onPressed,
        isNull,
      );
      // Backspace takes the 9 off again.
      await tester.tap(key('keypad-backspace'));
      await settle(tester, 2);
      expect(textOf(tester, 'return-refund-preview'), '23,000 ل.س');
    });

    testWidgets('continue → the refund total and method before confirming → '
        'saved, and its document opens', (tester) async {
      final sale = await sugarAndTea(tester);
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));
      await tester.tap(key('keypad-1'));
      await settle(tester, 2);
      await tester.tap(key('return-continue'));
      await animated(tester);

      expect(key('return-confirm-dialog'), findsOneWidget);
      expect(textOf(tester, 'return-confirm-total'), '8,000 ل.س');
      // A cash sale: cash, and the customer's account as a choice.
      expect(
        tester.widget<ChoiceChip>(key('refund-method-cash')).selected,
        isTrue,
      );
      expect(key('refund-method-credit'), findsOneWidget);
      // He owes nothing: there is no debt to reduce.
      expect(key('refund-method-debt'), findsNothing);
      expect(textOf(tester, 'refund-part-cash'), '8,000 ل.س');
      // Nothing is saved before the confirmation.
      expect(await rows(tester, 'invoice_returns'), isEmpty);

      await tester.enterText(key('return-reason'), 'damaged bag');
      await tester.tap(key('return-confirm'));
      await until(tester, () => key('return-screen').evaluate().isNotEmpty);
      // The document slides in over the screen it replaces.
      await animated(tester);

      expect(find.byType(ReturnItemsScreen), findsNothing);
      expect(find.byType(ReturnScreen), findsOneWidget);
      expect(textOf(tester, 'return-number'), 'Return no. 1');
      expect(find.text('From invoice 1'), findsWidgets);
      expect(textOf(tester, 'return-refund-total'), '8,000 ل.س');
      final saved = (await rows(tester, 'invoice_returns')).single;
      expect(saved['refund_minor'], 8000);
      expect(saved['refund_method'], 'CASH');
      expect(saved['reason'], 'damaged bag');
      expect(await rows(tester, 'debt_transactions'), isEmpty);
      final log = (await db(tester, () => shop.audit('INVOICE_RETURN'))).single;
      expect('${log['details']}', contains('"return_no":1'));

      // The document prints through the invoice pipeline; this one is the
      // original, not a copy.
      await db(tester, () async {
        await SettingsRepository(shop.db)
            .setString(SettingsKeys.printerMac, 'AA:BB:CC:DD:EE:FF');
        return true;
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReturnScreen)),
      );
      container.invalidate(invoiceSettingsProvider);
      await settle(tester);
      await tester.tap(key('paper-primary-print'));
      await until(tester, () => bridge.printed.length == 1);
      expect(find.textContaining('marked as a copy'), findsNothing);
    });

    testWidgets('a sale on credit opens on "off the debt", with what goes '
        'where; the seller can change it', (tester) async {
      // 30,000 sold, 25,000 paid: Ahmad owes 5,000.
      final sale = await sugarAndTea(tester, paid: 25000);
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));
      await tester.tap(key('keypad-1'));
      await settle(tester, 2);
      await tester.tap(key('return-continue'));
      await animated(tester);

      expect(
        tester.widget<ChoiceChip>(key('refund-method-debt')).selected,
        isTrue,
      );
      // 8,000 to refund: 5,000 off the debt, the rest in cash.
      expect(textOf(tester, 'refund-part-debt'), '5,000 ل.س');
      expect(textOf(tester, 'refund-part-cash'), '3,000 ل.س');

      await tester.tap(key('refund-method-credit'));
      await settle(tester, 4);
      expect(textOf(tester, 'refund-part-credit'), '8,000 ل.س');
      expect(key('refund-part-cash'), findsNothing);

      await tester.tap(key('refund-method-debt'));
      await settle(tester, 4);
      await tester.tap(key('return-confirm'));
      await until(tester, () => key('return-screen').evaluate().isNotEmpty);

      final saved = (await rows(tester, 'invoice_returns')).single;
      expect(saved['debt_minor'], 5000);
      expect(saved['cash_minor'], 3000);
      expect(await db(tester, () => shop.debts.balanceOf(shop.ahmad)), 0);
      expect(
        (await rows(tester, 'debt_transactions')).last['type'],
        'RETURN',
      );
    });

    testWidgets('with a PIN set, the PIN comes before the return is saved',
        (tester) async {
      await setPin(tester);
      final sale = await sugarAndTea(tester);
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));
      await tester.tap(key('return-all'));
      await settle(tester, 4);
      await tester.tap(key('return-continue'));
      await animated(tester);
      await tester.tap(key('return-confirm'));
      await animated(tester);

      expect(find.text('Enter the PIN to save a return.'), findsOneWidget);
      expect(await rows(tester, 'invoice_returns'), isEmpty);
      await enterPin(tester, '0000');
      expect(await rows(tester, 'invoice_returns'), isEmpty);
      await enterPin(tester, pin);
      await until(tester, () => key('return-screen').evaluate().isNotEmpty);
      expect(
        (await rows(tester, 'invoice_returns')).single['refund_minor'],
        30000,
      );
    });

    testWidgets('cards are returned by ticking their codes: void, or back '
        'to stock', (tester) async {
      await db(tester, () async {
        await shop.loadCodes('1111222233334444\n5555666677778888');
        return true;
      });
      final sale =
          await db(tester, () => shop.sell([shop.card(cards: 2)]));
      final codes =
          await db(tester, () => shop.vouchers.codesOfInvoice(sale.id!));
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));

      // A card line takes no number: there is no pad for it.
      expect(key('return-qty-0'), findsNothing);
      expect(key('keypad-1'), findsNothing);
      expect(find.text('•••• •••• 4444'), findsOneWidget);
      expect(find.text('•••• •••• 8888'), findsOneWidget);

      await tester.tap(key('return-code-${codes.last.id}'));
      await settle(tester, 4);
      expect(textOf(tester, 'return-refund-preview'), '5,000 ل.س');
      // Voided unless said otherwise.
      expect(
        tester
            .widget<ChoiceChip>(key('return-code-void-${codes.last.id}'))
            .selected,
        isTrue,
      );
      await tester.tap(key('return-code-stock-${codes.last.id}'));
      await settle(tester, 4);

      await tester.tap(key('return-continue'));
      await animated(tester);
      expect(find.text('1 cards'), findsOneWidget);
      await tester.tap(key('return-confirm'));
      await until(tester, () => key('return-screen').evaluate().isNotEmpty);

      expect(await db(tester, shop.codeStatuses), ['SOLD', 'AVAILABLE']);
      final saved = (await rows(tester, 'invoice_returns')).single;
      expect(saved['codes_restocked'], 1);
      expect(saved['codes_voided'], 0);
    });

    testWidgets('what was returned before is no longer offered',
        (tester) async {
      final sale = await sugarAndTea(tester);
      await db(
        tester,
        () => shop.corrections.saveReturn(ReturnDraft(
          invoiceId: sale.id!,
          lines: [
            ReturnLineRequest(
              invoiceItemId: sale.items.first.id!,
              qtyThousandths: 1000,
            ),
            ReturnLineRequest(
              invoiceItemId: sale.items.last.id!,
              qtyThousandths: 2000,
            ),
          ],
        )),
      );
      await pump(tester, ReturnItemsScreen(invoiceId: sale.id!));
      expect(textOf(tester, 'return-left-0'), 'Sold 3 kg · Returnable 2 kg');
      expect(textOf(tester, 'return-left-1'), 'Sold 2 · fully returned');
      expect(key('return-qty-1'), findsNothing);
      await tester.tap(key('return-all'));
      await settle(tester, 4);
      expect(textOf(tester, 'return-qty-0'), '2');
      expect(textOf(tester, 'return-refund-preview'), '16,000 ل.س');
    });
  });

  group('without a license', () {
    testWidgets('an invoice is still looked at; voiding and returning say '
        'that the app must be activated, and write nothing', (tester) async {
      final sale = await db(tester, () => shop.sell([shop.sugar()]));
      await pump(
        tester,
        InvoiceDetailScreen(invoiceId: sale.id!),
        overrides: [licenseProvider.overrideWith(_Unlicensed.new)],
      );
      // Viewing stays open.
      expect(key('archive-invoice-total'), findsOneWidget);
      expect(key('archive-invoice-view'), findsOneWidget);

      await tapKey(tester, 'invoice-void');
      expect(key('license-needed'), findsOneWidget);
      expect(key('void-reason-dialog'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await animated(tester);

      await tapKey(tester, 'invoice-return');
      expect(key('license-needed'), findsOneWidget);
      expect(find.byType(ReturnItemsScreen), findsNothing);

      expect((await rows(tester, 'invoices')).single['voided_at'], isNull);
      expect(await rows(tester, 'invoice_returns'), isEmpty);
    });
  });

  group('the archive and the statistics', () {
    /// Three sales today: one voided, one with a return, one untouched.
    Future<void> seed(WidgetTester tester) async {
      await db(tester, () async {
        final now = DateTime.now();
        final at = DateTime(now.year, now.month, now.day, 0, 1);
        final voided = await shop.sell([shop.sugar(price: 9000)], at: at);
        final returned = await shop.sell(
          [shop.sugar(qty: 2000, price: 5000)],
          customer: true,
          at: at.add(const Duration(minutes: 1)),
        );
        await shop.sell([shop.tea()], at: at.add(const Duration(minutes: 2)));
        await shop.corrections.voidInvoice(voided.id!, reason: 'duplicate');
        await shop.corrections.saveReturn(ReturnDraft(
          invoiceId: returned.id!,
          lines: [
            ReturnLineRequest(
              invoiceItemId: returned.items.single.id!,
              qtyThousandths: 1000,
            ),
          ],
        ));
        return true;
      });
    }

    testWidgets('the archive marks voided invoices, filters them, and lists '
        'the returns', (tester) async {
      await seed(tester);
      await pump(tester, const ArchiveScreen());

      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(key('archive-void-1'), findsOneWidget);
      expect(key('archive-void-2'), findsNothing);
      expect(key('archive-returned-2'), findsOneWidget);
      // Three invoices in the archive; the voided 9,000 is not in the total.
      expect(
        textOf(tester, 'archive-match-summary'),
        '3 invoices · 13,000 ل.س',
      );

      await tester.tap(key('archive-status-voided'));
      await settle(tester);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-2')), findsNothing);
      expect(find.byKey(const ValueKey('archive-invoice-3')), findsNothing);

      await tester.tap(key('archive-status-returns'));
      await settle(tester);
      expect(key('archive-returns-list'), findsOneWidget);
      expect(key('return-tile-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-2')), findsNothing);
      expect(
        textOf(tester, 'archive-returns-summary'),
        '1 returns · 5,000 ل.س given back',
      );
      expect(find.textContaining('From invoice 2'), findsOneWidget);
      expect(find.textContaining('Ahmad'), findsOneWidget);

      // The document opens from the list, as a copy.
      await tester.tap(key('return-tile-1'));
      await animated(tester);
      expect(textOf(tester, 'return-number'), 'Return no. 1');
      expect(find.textContaining('marked as a copy'), findsOneWidget);
    });

    testWidgets('deleting by period is not offered while a filter narrows '
        'the list', (tester) async {
      await seed(tester);
      await pump(tester, const ArchiveScreen());
      await tester.tap(key('archive-status-voided'));
      await settle(tester);
      await tester.tap(find.byType(PopupMenuButton<void>));
      await animated(tester);
      final item = tester.widget<PopupMenuItem<void>>(
        find.byKey(const ValueKey('archive-delete-range')),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets('statistics: net sales, the sales before returns and the '
        'returns as their own figure; the voided invoice in none of them',
        (tester) async {
      await seed(tester);
      await pump(tester, const StatsScreen());
      await settle(tester);

      expect(find.text('Net sales'), findsOneWidget);
      expect(find.text('Total sales'), findsNothing);
      // 10,000 + 3,000 sold (not the voided 9,000), 5,000 returned.
      expect(textOf(tester, 'stats-total-value'), '8,000 ل.س');
      expect(textOf(tester, 'stats-gross-value'), '13,000 ل.س');
      expect(find.text('Returns (1)'), findsOneWidget);
      expect(textOf(tester, 'stats-returns-value'), '5,000 ل.س');
      expect(textOf(tester, 'stats-count-value'), '2');
    });

    testWidgets('statistics without any return keep their old name',
        (tester) async {
      await db(tester, () async {
        await shop.sell([shop.tea()], at: DateTime.now());
        return true;
      });
      await pump(tester, const StatsScreen());
      await settle(tester);
      expect(find.text('Total sales'), findsOneWidget);
      expect(find.text('Net sales'), findsNothing);
      expect(key('stats-returns-value'), findsNothing);
      expect(textOf(tester, 'stats-total-value'), '3,000 ل.س');
    });

    testWidgets('the customer page strikes a voided invoice through',
        (tester) async {
      await db(tester, () async {
        final sale = await shop.sell([shop.sugar()], customer: true);
        await shop.sell([shop.tea()], customer: true);
        await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');
        return true;
      });
      await pump(tester, CustomerDetailScreen(customerId: shop.ahmad));
      await settle(tester);
      final voided = find.descendant(
        of: key('customer-invoice-1'),
        matching: find.textContaining('VOID'),
      );
      expect(voided, findsOneWidget);
      expect(
        find.descendant(
          of: key('customer-invoice-2'),
          matching: find.textContaining('VOID'),
        ),
        findsNothing,
      );
    });
  });

  group('PIN to open settings, archive and statistics', () {
    Future<void> turnOn(WidgetTester tester) async {
      await setPin(tester);
      await setting(tester, SettingsKeys.adminRequirePin, '1');
    }

    Future<void> seedHome(WidgetTester tester) async {
      await setting(tester, SettingsKeys.setupDone, '1');
      await db(tester, () async {
        await shop.sell([shop.tea()], at: DateTime.now());
        return true;
      });
    }

    testWidgets('off by default: the three tiles open at once',
        (tester) async {
      await seedHome(tester);
      await pump(tester, const HomeScreen());
      for (final (tile, screen) in [
        ('archive', ArchiveScreen),
        ('stats', StatsScreen),
        ('settings', SettingsScreen),
      ]) {
        await tapKey(tester, 'home-nav-$tile');
        expect(pinDialog, findsNothing);
        expect(find.byType(screen), findsOneWidget);
        expect(key('admin-locked'), findsNothing);
        await tester.pageBack();
        await animated(tester);
      }
    });

    testWidgets('on: a tile asks for the PIN once; the session then opens '
        'all three, and locks again after the idle time', (tester) async {
      await turnOn(tester);
      await seedHome(tester);
      await pump(tester, const HomeScreen());

      await tapKey(tester, 'home-nav-archive');
      expect(
        find.text('Enter the PIN to open settings, the archive and '
            'statistics.'),
        findsOneWidget,
      );
      expect(find.byType(ArchiveScreen), findsNothing);
      // Backing out opens nothing.
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(find.byType(ArchiveScreen), findsNothing);

      await tapKey(tester, 'home-nav-archive');
      await enterPin(tester, pin);
      await animated(tester);
      expect(find.byType(ArchiveScreen), findsOneWidget);
      expect(key('admin-locked'), findsNothing);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      await tester.pageBack();
      await animated(tester);

      // Still unlocked: the statistics open without the PIN.
      await tapKey(tester, 'home-nav-stats');
      expect(pinDialog, findsNothing);
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(key('admin-locked'), findsNothing);

      // Five minutes without a touch: the door closes over the screen.
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await settle(tester);
      expect(key('admin-locked'), findsOneWidget);
      expect(key('stats-total-value').hitTestable(), findsNothing);

      // "Unlock" asks again, and the screen is back as it was.
      await tester.tap(key('admin-unlock'));
      await animated(tester);
      await enterPin(tester, pin);
      await animated(tester);
      expect(key('admin-locked'), findsNothing);
      expect(key('stats-total-value').hitTestable(), findsOneWidget);
    });

    testWidgets('a touch on a page opened FROM the archive keeps the '
        'session alive; when it locks, that page closes', (tester) async {
      await turnOn(tester);
      await seedHome(tester);
      await pump(tester, const HomeScreen());
      await tapKey(tester, 'home-nav-archive');
      await enterPin(tester, pin);
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('archive-invoice-1')));
      await animated(tester);
      expect(find.byType(InvoiceDetailScreen), findsOneWidget);

      // Four minutes, a touch on the invoice, four more: nine minutes in
      // the archive and still open, because the owner is using it.
      await tester.pump(const Duration(minutes: 4));
      await tester.tapAt(const Offset(300, 120));
      await settle(tester, 2);
      await tester.pump(const Duration(minutes: 4));
      await settle(tester);
      expect(find.byType(InvoiceDetailScreen), findsOneWidget);
      expect(key('admin-locked'), findsNothing);

      // Then nothing for five minutes: locked, and the invoice is not left
      // readable on top of the lock.
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await animated(tester);
      expect(find.byType(InvoiceDetailScreen), findsNothing);
      expect(key('admin-locked'), findsOneWidget);
    });

    testWidgets('it locks at once when the app goes to the background',
        (tester) async {
      await turnOn(tester);
      await seedHome(tester);
      await pump(tester, const HomeScreen());
      await tapKey(tester, 'home-nav-settings');
      await enterPin(tester, pin);
      await animated(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(key('admin-locked'), findsNothing);

      // The observer that hands the lifecycle to the locks sits above the
      // whole app (SouqiApp); here its guard is told directly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      lockAllPinSessions(container);
      await settle(tester);
      expect(key('admin-locked'), findsOneWidget);
    });

    testWidgets('the switch: turning it on needs a PIN to exist, turning it '
        'off asks for it; both are logged', (tester) async {
      await setPin(tester);
      await pump(tester, const SettingsScreen());
      final tile = key('setting-admin-require-pin');
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(tile);
      await settle(tester, 4);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      // On: a PIN exists, so nothing more is asked — and whoever set the
      // lock is inside it.
      await tester.tap(tile);
      await until(tester, () => tester.widget<SwitchListTile>(tile).value);
      expect(pinDialog, findsNothing);
      expect(key('admin-locked'), findsNothing);
      expect(
        (await db(tester, () => shop.audit('ADMIN_LOCK_ON'))),
        hasLength(1),
      );

      // Off: the PIN.
      await tester.tap(tile);
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester, () => !tester.widget<SwitchListTile>(tile).value);
      expect(
        (await db(tester, () => shop.audit('ADMIN_LOCK_OFF'))),
        hasLength(1),
      );
    });
  });

  group('settings', () {
    testWidgets('the age limit of a void: 30 days unless changed; changing '
        'it asks for the PIN and is logged', (tester) async {
      await setPin(tester);
      await setting(tester, SettingsKeys.voidMaxAgeDays, '30');
      await pump(tester, const SettingsScreen());
      final dropdown = key('setting-void-age-dropdown');
      await tester.scrollUntilVisible(
        dropdown,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(dropdown);
      await settle(tester, 4);
      expect(
        find.descendant(of: dropdown, matching: find.text('30 days')),
        findsOneWidget,
      );

      await tester.tap(dropdown);
      await animated(tester);
      await tester.tap(find.text('7 days').last);
      await animated(tester);
      expect(
        find.text('Enter the PIN to change the age limit for voiding '
            'invoices.'),
        findsOneWidget,
      );
      await enterPin(tester, pin);
      await until(
        tester,
        () => find
            .descendant(of: dropdown, matching: find.text('7 days'))
            .evaluate()
            .isNotEmpty,
      );
      expect(await db(tester, shop.corrections.voidMaxAgeDays), 7);
      final log = (await db(tester, () => shop.audit('VOID_AGE_LIMIT'))).single;
      expect('${log['details']}', '{"days":7}');
    });
  });

  group('the developer WhatsApp number', () {
    test('the placeholder is not a number: the chat is not opened on it', () {
      expect(developerWhatsApp, '+963XXXXXXXXX');
      expect(developerWhatsAppNumber, '');
    });

    test('a real number is taken in the form WhatsApp wants', () {
      expect(whatsAppNumberOf('+963 944 123 456'), '963944123456');
      expect(whatsAppNumberOf('963-944-123-456'), '963944123456');
      expect(whatsAppNumberOf('963944123456'), '963944123456');
      expect(whatsAppNumberOf(''), '');
      expect(whatsAppNumberOf('+963'), '');
      expect(whatsAppNumberOf('0944123456x'), '');
    });
  });
}
