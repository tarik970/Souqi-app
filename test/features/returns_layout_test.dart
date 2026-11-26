import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/debts/debt_actions.dart';
import 'package:souqi/features/returns/return_items_screen.dart';
import 'package:souqi/features/returns/return_screen.dart';
import 'package:souqi/features/returns/void_flow.dart';
import 'package:souqi/features/security/audit_log_screen.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/correction_test_kit.dart';
import 'stats_test_utils.dart';

/// Every screen and dialog of phase 7 — voiding an invoice, returns, the
/// locked door of settings / archive / statistics — on the smallest phone
/// this app targets, 360×640, at system font scale 1.3, in Arabic and in
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

  late TestShop shop;

  const phone = Size(360, 640);
  const keyboardInset = 300.0;
  const longName = 'عبد الرحمن محمد الأحمد الحسن الطويل';
  const big = 123456789;

  setUp(() async => shop = await TestShop.open());
  tearDown(() => shop.close());

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

  void keyboardUp(WidgetTester tester) => tester.view.viewInsets =
      FakeViewPadding(bottom: keyboardInset * tester.view.devicePixelRatio);

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
          databaseProvider.overrideWithValue(shop.database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(Locale(locale))),
          secretKeyStoreProvider.overrideWithValue(shop.keyStore),
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
    keyboardUp(tester);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'with the keyboard up');
  }

  /// Scrolls the first vertical list to its end in steps, checking after
  /// each one: what is below the fold of a lazy list is only laid out once
  /// it is reached.
  Future<void> scrollThrough(WidgetTester tester) async {
    final lists = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    if (lists.evaluate().isEmpty) return;
    for (var i = 0; i < 14; i++) {
      await tester.drag(lists.first, const Offset(0, -240), warnIfMissed: false);
      await settle(tester, 4);
      expect(tester.takeException(), isNull, reason: 'scrolled $i times');
    }
  }

  /// Brings [finder] on screen before it is used.
  Future<void> reach(WidgetTester tester, Finder finder) async {
    final lists = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
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

  Future<void> openHost(WidgetTester tester, {bool keyboard = true}) async {
    await tester.tap(find.text('open it'));
    await settle(tester, 28);
    expect(tester.takeException(), isNull, reason: 'opened');
    if (!keyboard) return;
    keyboardUp(tester);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'opened, keyboard up');
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  /// Ahmad gets a name as long as they come.
  Future<void> longCustomer() => shop.db.update(
        'customers',
        {'name': longName},
        where: 'id = ?',
        whereArgs: [shop.ahmad],
      );

  /// A credit sale in the hundreds of millions with a discount, two cards
  /// and the ADSL package — everything a void or a return can touch.
  Future<Invoice> bigSale() async {
    await longCustomer();
    await shop.loadCodes('1111222233334444\n5555666677778888');
    return shop.sell(
      [
        shop.sugar(qty: 2500, price: big),
        shop.tea(qty: 3000, price: 98765432),
        shop.card(cards: 2, price: 55555555),
        shop.package(price: 77777777),
      ],
      withAccount: true,
      paid: 23456789,
      discount: const Discount.percent(750),
      at: DateTime.now().subtract(const Duration(hours: 2)),
    ).then((sale) async {
      await shop.db.update(
        'invoices',
        {'customer_name': longName},
        where: 'id = ?',
        whereArgs: [sale.id],
      );
      return sale;
    });
  }

  ReturnDraft partOf(Invoice sale, {RefundMethod method = RefundMethod.debt}) =>
      ReturnDraft(
        invoiceId: sale.id!,
        method: method,
        reason: 'الزبون أعاد البضاعة لأنها لا تناسبه وطلب استرداد المبلغ كاملاً',
        lines: [
          ReturnLineRequest(
            invoiceItemId: sale.items[0].id!,
            qtyThousandths: 1250,
          ),
          ReturnLineRequest(
            invoiceItemId: sale.items[1].id!,
            qtyThousandths: 1000,
          ),
        ],
      );

  for (final locale in ['ar', 'en']) {
    group('[$locale]', () {
      testWidgets('the invoice screen: return and void buttons, its returns, '
          'its card codes', (tester) async {
        final sale = await db(tester, () async {
          final sale = await bigSale();
          await shop.corrections.saveReturn(partOf(sale));
          await shop.corrections
              .saveReturn(partOf(sale, method: RefundMethod.cash));
          return sale;
        });
        await pumpPhone(
          tester,
          InvoiceDetailScreen(invoiceId: sale.id!),
          locale: locale,
          keyboard: false,
        );
        await reach(tester, key('invoice-void'));
        expect(key('invoice-void'), findsOneWidget);
        await reach(tester, key('invoice-returns'));
        expect(key('return-tile-2'), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('a voided invoice: the banner with a long reason, the '
          'stamp on the paper', (tester) async {
        final sale = await db(tester, () async {
          final sale = await bigSale();
          await shop.corrections.voidInvoice(
            sale.id!,
            reason: 'أُدخلت الفاتورة مرتين بالخطأ والزبون استلم بضاعته من '
                'الفاتورة الأولى فقط',
          );
          return sale;
        });
        await pumpPhone(
          tester,
          InvoiceDetailScreen(invoiceId: sale.id!),
          locale: locale,
          keyboard: false,
        );
        expect(key('invoice-void-banner'), findsOneWidget);
        expect(key('invoice-void'), findsNothing);
        await scrollThrough(tester);
      });

      testWidgets('void, step 1: the reasons, "Other" with the keyboard up, '
          'the error, the card codes question', (tester) async {
        await pumpPhone(
          tester,
          host((context) => showDialog<VoidChoice>(
                context: context,
                builder: (_) => const VoidReasonDialog(
                  invoiceNo: '123,456',
                  soldCodes: 12,
                ),
              )),
          locale: locale,
          keyboard: false,
        );
        await openHost(tester);
        // Nothing chosen: the error line makes it taller still.
        await reach(tester, key('void-reason-continue'));
        await tester.tap(key('void-reason-continue'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('void-reason-error'), findsOneWidget);

        await reach(tester, key('void-reason-other'));
        await tester.tap(key('void-reason-other'));
        await settle(tester, 8);
        expect(tester.takeException(), isNull);
        await reach(tester, key('void-reason-text'));
        await tester.enterText(
          key('void-reason-text'),
          'سبب طويل جداً يكتبه صاحب المحل ليشرح ما الذي حدث بالضبط',
        );
        await settle(tester);
        expect(tester.takeException(), isNull);

        await reach(tester, key('void-codes-stock'));
        await tester.tap(key('void-codes-stock'));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('void, the confirmation: every effect at once, with the '
          'longest name and the biggest amounts', (tester) async {
        final plan = await db(tester, () async {
          final sale = await bigSale();
          return shop.corrections.voidPlan(sale.id!);
        });
        expect(plan.debtBaseMinor, greaterThan(0));
        expect(plan.soldCodes, 2);
        expect(plan.renewal, isNotNull);
        for (final codes in CodeDisposal.values) {
          await pumpPhone(
            tester,
            host((context) => showDialog<bool>(
                  context: context,
                  builder: (_) => VoidConfirmDialog(
                    plan: plan,
                    choice: VoidChoice(
                      reason: 'أُدخلت الفاتورة مرتين بالخطأ والزبون لم '
                          'يستلم شيئاً منها',
                      codes: codes,
                    ),
                  ),
                )),
            locale: locale,
            keyboard: false,
          );
          await openHost(tester, keyboard: false);
          expect(key('void-confirm-dialog'), findsOneWidget);
          await reach(tester, key('void-confirm'));
        }
      });

      testWidgets('return items: lines, card codes with their choices, the '
          'number pad, the refund; the pad makes way for a keyboard',
          (tester) async {
        final sale = await db(tester, bigSale);
        final codes =
            await db(tester, () => shop.vouchers.codesOfInvoice(sale.id!));
        await pumpPhone(
          tester,
          ReturnItemsScreen(invoiceId: sale.id!),
          locale: locale,
          keyboard: false,
        );
        expect(key('return-continue'), findsOneWidget);
        expect(key('keypad-1'), findsOneWidget);

        // Everything at once: the biggest refund the screen can show.
        await tester.tap(key('return-all'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        // The codes: ticked, each with its two choices.
        await reach(tester, key('return-code-stock-${codes.first.id}'));
        await tester.tap(key('return-code-stock-${codes.first.id}'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);

        // Nine digits typed into a line.
        await reach(tester, key('return-line-0'));
        await tester.tap(key('return-line-0'));
        await settle(tester, 4);
        for (final digit in '123456789'.split('')) {
          await tester.tap(key('keypad-$digit'));
        }
        await settle(tester);
        expect(tester.takeException(), isNull);

        keyboardUp(tester);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'keyboard up');
        expect(key('keypad-1'), findsNothing);
        expect(key('return-continue'), findsOneWidget);
      });

      testWidgets('return, the confirmation: total, the three methods, the '
          'split, the reason with the keyboard up', (tester) async {
        final preview = await db(tester, () async {
          final sale = await bigSale();
          return shop.corrections.previewReturn(sale.id!, {
            for (final item in sale.items) item.id!: item.qtyThousandths,
          });
        });
        expect(preview.owedMinor, greaterThan(0));
        await pumpPhone(
          tester,
          host((context) => showDialog<ReturnChoice>(
                context: context,
                builder: (_) => ReturnConfirmDialog(preview: preview, cards: 2),
              )),
          locale: locale,
          keyboard: false,
        );
        await openHost(tester, keyboard: false);
        expect(key('return-confirm-dialog'), findsOneWidget);
        for (final method in ['credit', 'cash', 'debt']) {
          await reach(tester, key('refund-method-$method'));
          await tester.tap(key('refund-method-$method'));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: method);
        }
        await reach(tester, key('return-reason'));
        await tester.tap(key('return-reason'));
        keyboardUp(tester);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'keyboard up');
        await tester.enterText(
          key('return-reason'),
          'الزبون أعاد البضاعة لأنها لا تناسبه وطلب استرداد المبلغ',
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await reach(tester, key('return-confirm'));
      });

      testWidgets('the return document, as the original and as a copy',
          (tester) async {
        final document = await db(tester, () async {
          final sale = await bigSale();
          return shop.corrections.saveReturn(partOf(sale));
        });
        for (final copy in [false, true]) {
          await pumpPhone(
            tester,
            ReturnScreen(returnId: document.id, copy: copy),
            locale: locale,
            keyboard: false,
          );
          expect(key('return-screen'), findsOneWidget);
          await scrollThrough(tester);
        }
      });

      testWidgets('the archive: the status filter, a voided invoice, the '
          'returns list', (tester) async {
        await db(tester, () async {
          final sale = await bigSale();
          await shop.corrections.saveReturn(partOf(sale));
          final other = await shop.sell(
            [shop.sugar(price: big)],
            customer: true,
            at: DateTime.now().subtract(const Duration(hours: 1)),
          );
          await shop.corrections.voidInvoice(other.id!, reason: 'مكررة');
          return true;
        });
        await pumpPhone(
          tester,
          const ArchiveScreen(),
          locale: locale,
          keyboard: false,
        );
        expect(key('archive-status-voided'), findsOneWidget);
        expect(key('archive-void-2'), findsOneWidget);
        // The older invoice is below the fold of a phone this small.
        await reach(tester, key('archive-returned-1'));
        expect(key('archive-returned-1'), findsOneWidget);
        keyboardUp(tester);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'keyboard up');
        tester.view.resetViewInsets();
        await settle(tester);
        for (final status in ['voided', 'returns', 'all']) {
          await tester.ensureVisible(key('archive-status-$status'));
          await settle(tester, 2);
          await tester.tap(key('archive-status-$status'));
          await settle(tester, 20);
          expect(tester.takeException(), isNull, reason: status);
          keyboardUp(tester);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: '$status, keyboard');
          tester.view.resetViewInsets();
          await settle(tester);
        }
      });

      testWidgets('statistics with net sales and returns', (tester) async {
        await db(tester, () async {
          final sale = await bigSale();
          await shop.corrections.saveReturn(partOf(sale));
          return true;
        });
        await pumpPhone(
          tester,
          const StatsScreen(),
          locale: locale,
          keyboard: false,
        );
        await statsLoaded(tester);
        // Three tall cards at this font: the third is below the fold.
        await reach(tester, key('stats-returns-value'));
        expect(key('stats-returns-value'), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('the locked door of settings, archive and statistics',
          (tester) async {
        await db(tester, () async {
          final settings = SettingsRepository(shop.db);
          await PinRepository(settings).set('2580');
          await settings.setBool(SettingsKeys.adminRequirePin, true);
          return true;
        });
        for (final screen in const <Widget>[
          SettingsScreen(),
          ArchiveScreen(),
          StatsScreen(),
        ]) {
          await pumpPhone(tester, screen, locale: locale);
          expect(key('admin-locked'), findsOneWidget);
          expect(key('admin-unlock'), findsOneWidget);
        }
      });

      testWidgets('the settings screen with its two new tiles, top to bottom',
          (tester) async {
        await pumpPhone(
          tester,
          const SettingsScreen(),
          locale: locale,
          keyboard: false,
        );
        await reach(tester, key('setting-void-age'));
        expect(key('setting-void-age'), findsOneWidget);
        // The menu of the age limit, open.
        await tester.tap(key('setting-void-age-dropdown'));
        await settle(tester, 28);
        expect(tester.takeException(), isNull, reason: 'age menu');
        await tester.tapAt(const Offset(5, 5));
        await settle(tester, 28);
        await reach(tester, key('setting-admin-require-pin'));
        expect(key('setting-admin-require-pin'), findsOneWidget);
        await scrollThrough(tester);
      });

      testWidgets('a RETURN entry of the ledger in full, and the audit log '
          'with a void and a return', (tester) async {
        final line = await db(tester, () async {
          final sale = await bigSale();
          await shop.corrections.saveReturn(partOf(sale));
          final other = await shop.sell(
            [shop.sugar(price: big)],
            customer: true,
            paid: 0,
            at: DateTime.now().subtract(const Duration(minutes: 30)),
          );
          await shop.corrections.voidInvoice(
            other.id!,
            reason: 'أُدخلت الفاتورة مرتين بالخطأ',
          );
          return (await shop.debts.ledger(shop.ahmad)).firstWhere(
            (line) => line.entry.returnNo != null,
          );
        });
        await pumpPhone(
          tester,
          host((context) => showEntrySheet(context, line)),
          locale: locale,
          keyboard: false,
        );
        await openHost(tester, keyboard: false);
        expect(key('entry-sheet'), findsOneWidget);
        expect(key('entry-open-return'), findsOneWidget);
        // Its document can only be reached from here: it is not reversed.
        expect(key('entry-reverse'), findsNothing);

        await pumpPhone(
          tester,
          const AuditLogScreen(),
          locale: locale,
          keyboard: false,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });
    });
  }
}
