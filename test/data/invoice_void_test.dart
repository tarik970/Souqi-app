import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_report_repository.dart';
import 'package:souqi/data/repositories/invoice_correction_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'correction_test_kit.dart';

/// VOIDING AN INVOICE: it is never deleted, and everything the sale did is
/// undone in ONE transaction — the debt, the credit it used, the card codes,
/// the renewal dates — or none of it is.
void main() {
  setUpAll(sqfliteFfiInit);

  late TestShop shop;
  final saleTime = TestShop.saleTime;
  final voidTime = DateTime(2026, 11, 26, 10);

  setUp(() async => shop = await TestShop.open());
  tearDown(() => shop.close());

  Future<int> balance() => shop.debts.balanceOf(shop.ahmad);

  group('the invoice itself', () {
    test('stays in the archive, marked void with the time and the reason',
        () async {
      final sale = await shop.sell([shop.sugar()]);
      final voided = await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'wrong price',
        now: voidTime,
      );

      expect(voided.isVoided, isTrue);
      expect(voided.voidedAt!.toLocal(), voidTime);
      expect(voided.voidReason, 'wrong price');
      // Not a row, not a number, not an item is gone.
      expect(voided.id, sale.id);
      expect(voided.invoiceNo, sale.invoiceNo);
      expect(voided.items, hasLength(1));
      expect(voided.totalMinor, 8000);
      expect(await shop.count('invoices'), 1);
      expect(await shop.count('invoice_items'), 1);

      final archived = await ArchiveRepository(shop.db).getById(sale.id!);
      expect(archived!.isVoided, isTrue);
    });

    test('its number is never reused: the next sale takes the next one',
        () async {
      final first = await shop.sell([shop.sugar()]);
      await shop.corrections.voidInvoice(first.id!, reason: 'duplicate');
      final next = await shop.sell([shop.sugar()]);
      expect(first.invoiceNo, 1);
      expect(next.invoiceNo, 2);
    });

    test('a reason is required', () async {
      final sale = await shop.sell([shop.sugar()]);
      await expectLater(
        shop.corrections.voidInvoice(sale.id!, reason: '   '),
        throwsArgumentError,
      );
      expect((await shop.invoices.getById(sale.id!))!.isVoided, isFalse);
    });

    test('products the sale created and prices it wrote stay as they are',
        () async {
      final before = await ProductRepository(shop.db).getById(shop.sugarId);
      final sale = await shop.sell([shop.sugar(price: 9500)]);
      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong items');
      final after = await ProductRepository(shop.db).getById(shop.sugarId);
      expect(after!.priceMinor, before!.priceMinor);
      expect(after.isActive, isTrue);
    });
  });

  group('the debt', () {
    test('a sale on credit: its debt entry is cancelled by a REVERSAL — the '
        'entry itself is not touched', () async {
      final sale =
          await shop.sell([shop.sugar()], customer: true, paid: 3000);
      expect(await balance(), 5000);
      final debtBefore = (await shop.ledgerRows()).single;

      await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'customer cancelled',
        now: voidTime,
      );

      expect(await balance(), 0);
      final rows = await shop.ledgerRows();
      expect(rows, hasLength(2));
      expect(rows.first, debtBefore, reason: 'never edited');
      final reversal = rows.last;
      expect(reversal['type'], 'REVERSAL');
      expect(reversal['direction'], -1);
      expect(reversal['amount_base_minor'], 5000);
      expect(reversal['reverses_id'], debtBefore['id']);
      expect(reversal['note'], 'customer cancelled');

      // The ledger shows the pair as any reversed entry.
      final lines = await shop.debts.ledger(shop.ahmad);
      expect(lines.first.entry.isReversal, isTrue);
      expect(lines.first.entry.reversedInvoiceNo, sale.invoiceNo);
      expect(lines.last.entry.isReversed, isTrue);
    });

    test('a credit balance the sale used is given back', () async {
      // The shop owes Ahmad 500; a sale of 800 takes it and 300 in cash.
      await shop.debts.addOpeningBalance(
        customerId: shop.ahmad,
        amountBaseMinor: 500,
        customerOwes: false,
      );
      expect(await balance(), -500);
      final sale = await shop.sell(
        [shop.sugar(price: 800)],
        customer: true,
        paid: 300,
        creditUsed: 500,
      );
      expect(await balance(), 0);

      final plan = await shop.corrections.voidPlan(sale.id!, now: voidTime);
      expect(plan.debtBaseMinor, 500);
      expect(plan.paidMinor, 300);
      await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');

      expect(await balance(), -500, reason: 'his credit is his again');
    });

    test('a sale paid in full leaves the ledger alone', () async {
      final sale =
          await shop.sell([shop.sugar()], customer: true, paid: 8000);
      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong items');
      expect(await shop.ledgerRows(), isEmpty);
    });

    test('a sale in dollars: the reversal carries the same amounts', () async {
      final sale = await shop.sell(
        [shop.sugar(price: 250, currency: 'USD')],
        customer: true,
        paid: 0,
        currency: 'USD',
      );
      expect(await balance(), 32500);
      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong price');
      expect(await balance(), 0);
      final reversal = (await shop.ledgerRows()).last;
      expect(reversal['orig_amount_minor'], 250);
      expect(reversal['orig_currency_code'], 'USD');
      expect(reversal['orig_rate_num'], 13000);
    });

    test('a debt entry already reversed by hand is not reversed twice',
        () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      final entry = (await shop.debts.ledger(shop.ahmad)).single.entry;
      await shop.debts.reverse(entry.id, reason: 'by hand');
      expect(await balance(), 0);

      final plan = await shop.corrections.voidPlan(sale.id!, now: voidTime);
      expect(plan.debtBaseMinor, 0);
      await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');

      expect(await balance(), 0);
      expect(await shop.ledgerRows(), hasLength(2));
    });
  });

  group('the card codes', () {
    setUp(
      () => shop.loadCodes(
        '1111222233334444\n5555666677778888\n9999000011112222',
      ),
    );

    test('voided by default: they were handed over, and stay recorded as '
        'sold on that invoice', () async {
      final sale = await shop.sell([shop.card(cards: 2)]);
      expect(await shop.codeStatuses(), ['SOLD', 'SOLD', 'AVAILABLE']);
      expect((await shop.corrections.voidPlan(sale.id!)).soldCodes, 2);

      await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'customer cancelled',
        now: voidTime,
      );

      expect(await shop.codeStatuses(), ['VOID', 'VOID', 'AVAILABLE']);
      final codes = await shop.db.query('voucher_codes', orderBy: 'id');
      expect(codes.first['invoice_id'], sale.id);
      expect(codes.first['sold_invoice_no'], sale.invoiceNo);
      expect(codes.first['status_note'], 'customer cancelled');
      // Nothing of them is printed again.
      expect(await shop.vouchers.printableCodes(sale.id!), isEmpty);
      // One audit line per card, and one for the invoice.
      final lines = await shop.audit('CODE_VOID');
      expect(lines, hasLength(2));
      expect('${lines.first['details']}', contains('"tail":"4444"'));
      expect('${lines.first['details']}', isNot(contains('1111222233334444')));
    });

    test('or returned to stock, for cards the customer never received',
        () async {
      final sale = await shop.sell([shop.card(cards: 2)]);
      await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'wrong items',
        codes: CodeDisposal.returnToStock,
        now: voidTime,
      );

      expect(await shop.codeStatuses(), ['AVAILABLE', 'AVAILABLE', 'AVAILABLE']);
      final codes = await shop.db.query('voucher_codes', orderBy: 'id');
      expect(codes.first['invoice_id'], isNull);
      expect(codes.first['sold_at'], isNull);
      expect(await shop.audit('CODE_RESTORE'), hasLength(2));
      // And they can be sold again.
      final again = await shop.sell([shop.card(cards: 3)]);
      expect(await shop.vouchers.printableCodes(again.id!), hasLength(3));
    });

    test('a code already voided by hand is left as it is', () async {
      final sale = await shop.sell([shop.card(cards: 2)]);
      final first = (await shop.vouchers.codesOfInvoice(sale.id!)).first;
      await shop.vouchers.voidCode(first.id, reason: 'defective');

      await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'duplicate',
        codes: CodeDisposal.returnToStock,
      );
      expect(await shop.codeStatuses(), ['VOID', 'AVAILABLE', 'AVAILABLE']);
    });
  });

  group('the renewal dates', () {
    test('an account the invoice renewed gets back the dates it had before '
        'the sale', () async {
      final sale = await shop.sell([shop.package()], withAccount: true);
      var account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), saleTime);
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 25));

      final plan = await shop.corrections.voidPlan(sale.id!, now: voidTime);
      expect(plan.renewal!.applies, isTrue);
      expect(plan.renewal!.accountNumber, '0011-2233');
      expect(plan.renewal!.nextDueAt!.toLocal(), TestShop.accountDue);

      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong price');

      account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), TestShop.accountLastRenewal);
      expect(account.nextDueAt!.toLocal(), TestShop.accountDue);
    });

    test('an account that had never been renewed has no dates again',
        () async {
      await shop.db.update(
        'customer_accounts',
        {'last_renewal_at': null, 'next_due_at': null},
        where: 'id = ?',
        whereArgs: [shop.accountId],
      );
      final sale = await shop.sell([shop.package()], withAccount: true);
      expect((await shop.account()).nextDueAt, isNotNull);
      await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');
      final account = await shop.account();
      expect(account.lastRenewalAt, isNull);
      expect(account.nextDueAt, isNull);
    });

    test('an invoice from before version 8 stored no previous dates: they '
        'are worked out from the earlier renewals of the account', () async {
      final first = await shop.sell(
        [shop.package()],
        withAccount: true,
        at: DateTime(2026, 10, 25, 9),
      );
      final second = await shop.sell([shop.package()], withAccount: true);
      // As an invoice saved by the previous version of the app left it.
      await shop.db.update(
        'invoices',
        {
          'renewal_prev_stored': 0,
          'prev_last_renewal_at': null,
          'prev_next_due_at': null,
        },
      );

      await shop.corrections.voidInvoice(second.id!, reason: 'duplicate');

      var account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), DateTime(2026, 10, 25, 9));
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 11, 24));

      // And with no earlier renewal left, the account has none.
      await shop.corrections.voidInvoice(first.id!, reason: 'duplicate');
      account = await shop.account();
      expect(account.lastRenewalAt, isNull);
      expect(account.nextDueAt, isNull);
    });

    test('voiding an OLDER renewal leaves the newer one in force — and '
        'voiding that one afterwards lands on the dates before both',
        () async {
      final older = await shop.sell(
        [shop.package()],
        withAccount: true,
        at: DateTime(2026, 11, 20, 9),
      );
      final newer = await shop.sell([shop.package()], withAccount: true);

      final plan = await shop.corrections.voidPlan(older.id!, now: voidTime);
      expect(plan.renewal!.applies, isFalse);
      await shop.corrections.voidInvoice(older.id!, reason: 'duplicate');
      var account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), saleTime);
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 25));

      await shop.corrections.voidInvoice(newer.id!, reason: 'duplicate');
      account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), TestShop.accountLastRenewal);
      expect(account.nextDueAt!.toLocal(), TestShop.accountDue);
    });

    test('dates set by hand since the sale are not overwritten', () async {
      final sale = await shop.sell([shop.package()], withAccount: true);
      final byHand = DateTime(2027, 1, 15);
      await shop.db.update(
        'customer_accounts',
        {
          'last_renewal_at': DateTime(2026, 12, 15).millisecondsSinceEpoch,
          'next_due_at': byHand.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [shop.accountId],
      );
      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong price');
      expect((await shop.account()).nextDueAt!.toLocal(), byHand);
    });

    test('goods sold to a customer with an account renew nothing, and '
        'voiding them moves no date', () async {
      final sale = await shop.sell([shop.sugar()], withAccount: true);
      expect((await shop.corrections.voidPlan(sale.id!)).renewal, isNull);
      await shop.corrections.voidInvoice(sale.id!, reason: 'wrong items');
      expect((await shop.account()).nextDueAt!.toLocal(), TestShop.accountDue);
    });
  });

  group('one transaction', () {
    test('a failure at the very end rolls EVERYTHING back: debt, codes, '
        'renewal dates, the mark on the invoice and the audit lines',
        () async {
      await shop.loadCodes('1111222233334444\n5555666677778888');
      final sale = await shop.sell(
        [shop.card(cards: 2), shop.package()],
        withAccount: true,
        paid: 10000,
      );
      expect(await balance(), 35000);
      final ledgerBefore = await shop.ledgerRows();
      final accountBefore = await shop.account();
      final auditBefore = await shop.count('audit_log');

      // The last thing a void writes is its own audit line: make that fail.
      await shop.db.execute(
        'CREATE TRIGGER fail_void BEFORE INSERT ON audit_log '
        "WHEN NEW.action = 'INVOICE_VOID' "
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await expectLater(
        shop.corrections.voidInvoice(
          sale.id!,
          reason: 'customer cancelled',
          codes: CodeDisposal.returnToStock,
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect((await shop.invoices.getById(sale.id!))!.isVoided, isFalse);
      expect(await shop.ledgerRows(), ledgerBefore);
      expect(await balance(), 35000);
      expect(await shop.codeStatuses(), ['SOLD', 'SOLD']);
      expect(await shop.vouchers.printableCodes(sale.id!), hasLength(2));
      final account = await shop.account();
      expect(account.lastRenewalAt, accountBefore.lastRenewalAt);
      expect(account.nextDueAt, accountBefore.nextDueAt);
      expect(await shop.count('audit_log'), auditBefore);

      // With the fault gone the same void goes through, whole.
      await shop.db.execute('DROP TRIGGER fail_void');
      await shop.corrections.voidInvoice(sale.id!, reason: 'customer cancelled');
      expect(await balance(), 0);
      expect(await shop.codeStatuses(), ['VOID', 'VOID']);
      expect(
        (await shop.account()).nextDueAt!.toLocal(),
        TestShop.accountDue,
      );
    });
  });

  group('what is refused', () {
    test('a second void: nothing is reversed twice', () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');
      expect(
        (await shop.corrections.voidPlan(sale.id!)).blocker,
        VoidBlocker.alreadyVoided,
      );
      await expectLater(
        shop.corrections.voidInvoice(sale.id!, reason: 'again'),
        throwsA(isA<InvoiceVoidedException>()
            .having((e) => e.invoiceNo, 'number', sale.invoiceNo)),
      );
      expect(await shop.ledgerRows(), hasLength(2));
      expect(await balance(), 0);
      expect(await shop.audit('INVOICE_VOID'), hasLength(1));
      expect(
        (await shop.invoices.getById(sale.id!))!.voidReason,
        'duplicate',
      );
    });

    test('an invoice older than the limit (30 days unless changed)', () async {
      // The shop of these tests has the limit off; this is a new install.
      await shop.db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [SettingsKeys.voidMaxAgeDays],
      );
      final now = DateTime(2026, 11, 26, 10);
      final old = await shop.sell(
        [shop.sugar()],
        at: DateTime(2026, 10, 26, 23, 50),
      );
      final recent = await shop.sell(
        [shop.sugar()],
        at: DateTime(2026, 10, 27, 0, 10),
      );
      expect(await shop.corrections.voidMaxAgeDays(), 30);

      final plan = await shop.corrections.voidPlan(old.id!, now: now);
      expect(plan.blocker, VoidBlocker.tooOld);
      expect(plan.maxAgeDays, 30);
      await expectLater(
        shop.corrections.voidInvoice(old.id!, reason: 'duplicate', now: now),
        throwsA(isA<InvoiceTooOldException>()
            .having((e) => e.maxAgeDays, 'days', 30)),
      );
      expect((await shop.invoices.getById(old.id!))!.isVoided, isFalse);

      // Thirty calendar days old is still inside the limit.
      expect(
        (await shop.corrections.voidPlan(recent.id!, now: now)).canVoid,
        isTrue,
      );
      await shop.corrections
          .voidInvoice(recent.id!, reason: 'duplicate', now: now);
    });

    test('the limit is a setting: shorter, longer, or none', () async {
      final settings = SettingsRepository(shop.db);
      final now = DateTime(2026, 11, 26, 10);
      final lastWeek =
          await shop.sell([shop.sugar()], at: DateTime(2026, 11, 18, 9));
      final lastYear =
          await shop.sell([shop.sugar()], at: DateTime(2025, 11, 18, 9));

      await settings.setInt(SettingsKeys.voidMaxAgeDays, 7);
      expect(
        (await shop.corrections.voidPlan(lastWeek.id!, now: now)).blocker,
        VoidBlocker.tooOld,
      );
      await settings.setInt(SettingsKeys.voidMaxAgeDays, 14);
      expect(
        (await shop.corrections.voidPlan(lastWeek.id!, now: now)).canVoid,
        isTrue,
      );
      expect(
        (await shop.corrections.voidPlan(lastYear.id!, now: now)).blocker,
        VoidBlocker.tooOld,
      );
      // 0 = no limit.
      await settings.setInt(SettingsKeys.voidMaxAgeDays, 0);
      await shop.corrections
          .voidInvoice(lastYear.id!, reason: 'duplicate', now: now);
      expect((await shop.invoices.getById(lastYear.id!))!.isVoided, isTrue);
    });

    test('an invoice that has returns: what is left of it is returned',
        () async {
      final sale = await shop.sell([shop.sugar(qty: 2000)]);
      await shop.corrections.saveReturn(ReturnDraft(
        invoiceId: sale.id!,
        lines: [
          ReturnLineRequest(
            invoiceItemId: sale.items.single.id!,
            qtyThousandths: 500,
          ),
        ],
      ));
      expect(
        (await shop.corrections.voidPlan(sale.id!)).blocker,
        VoidBlocker.hasReturns,
      );
      await expectLater(
        shop.corrections.voidInvoice(sale.id!, reason: 'duplicate'),
        throwsA(isA<InvoiceHasReturnsException>()),
      );
    });

    test('without a license, like a sale — and nothing is written', () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      final locked = InvoiceCorrectionRepository(
        shop.db,
        codeCipher: shop.cipher,
        guard: RefusingGuard(),
      );
      await expectLater(
        locked.voidInvoice(sale.id!, reason: 'duplicate'),
        throwsA(isA<LicenseRequiredException>()
            .having((e) => e.action, 'action', LicensedAction.sell)),
      );
      expect((await shop.invoices.getById(sale.id!))!.isVoided, isFalse);
      expect(await balance(), 8000);
      // Looking stays open: the plan is only read.
      expect((await locked.voidPlan(sale.id!)).canVoid, isTrue);
    });
  });

  group('a voided invoice counts nowhere', () {
    late int voidedId;
    late int keptId;
    final from = DateTime(2026, 11, 25);
    final to = DateTime(2026, 11, 26);

    setUp(() async {
      // Two sales on the same day to the same customer; the bigger one is
      // voided.
      final kept = await shop.sell(
        [shop.sugar(price: 2000), shop.tea()],
        customer: true,
        paid: 5000,
      );
      final voided = await shop.sell(
        [shop.sugar(qty: 5000, price: 8000)],
        customer: true,
        paid: 0,
        at: saleTime.add(const Duration(hours: 1)),
      );
      keptId = kept.id!;
      voidedId = voided.id!;
      await shop.corrections.voidInvoice(
        voidedId,
        reason: 'duplicate',
        now: saleTime.add(const Duration(hours: 2)),
      );
    });

    test('statistics: total, count, average, by currency, top products, '
        'top customers', () async {
      final stats = StatsRepository(shop.db);
      final summary = await stats.summary(from: from, to: to, baseDecimals: 0);
      expect(summary.invoiceCount, 1);
      expect(summary.totalBaseMinor, 5000);
      expect(summary.netBaseMinor, 5000);
      expect(summary.averageBaseMinor, 5000);

      final byCurrency = await stats.byCurrency(from: from, to: to);
      expect(byCurrency.single.invoiceCount, 1);
      expect(byCurrency.single.totalMinor, 5000);

      final top = await stats.topProducts(from: from, to: to, baseDecimals: 0);
      expect(
        {for (final row in top) row.name: row.amountBaseMinor},
        {'Tea': 3000, 'Sugar': 2000},
      );
      final sugar = top.firstWhere((row) => row.name == 'Sugar');
      expect(sugar.salesCount, 1);
      expect(sugar.qtyThousandths, 1000);

      final customers = await stats.topCustomers(from: from, to: to);
      expect(customers.single.invoiceCount, 1);
      expect(customers.single.totalBaseMinor, 5000);
    });

    test('the favorites bar: a sale that was voided sold nothing', () async {
      final products = ProductRepository(shop.db);
      final now = saleTime.add(const Duration(days: 1));
      var bar = await products.favoritesBar(now: now);
      expect(bar.map((p) => p.name), containsAll(['Sugar', 'Tea']));

      // Void the other one too: nothing was sold in the window any more.
      await shop.corrections.voidInvoice(keptId, reason: 'duplicate');
      bar = await products.favoritesBar(now: now);
      expect(bar.map((p) => p.name), isNot(contains('Sugar')));
      expect(bar.map((p) => p.name), isNot(contains('Tea')));
    });

    test('the customer page: listed and marked, out of the totals', () async {
      final customers = CustomerRepository(shop.db);
      final totals = await customers.totals(shop.ahmad);
      expect(totals.invoiceCount, 1);
      expect(totals.totalBaseMinor, 5000);
      expect(totals.lastPurchaseAt!.toLocal(), saleTime);

      final history = await customers.history(shop.ahmad);
      expect(history, hasLength(2));
      expect(history.first.id, voidedId);
      expect(history.first.isVoided, isTrue);
      expect(history.last.isVoided, isFalse);
    });

    test('the archive: still listed, with its own filter, and out of the '
        'total of the period', () async {
      final archive = ArchiveRepository(shop.db);
      final all = await archive.page();
      expect(all, hasLength(2));
      expect(all.firstWhere((e) => e.id == voidedId).isVoided, isTrue);
      expect(all.firstWhere((e) => e.id == keptId).isVoided, isFalse);

      const voidedOnly = ArchiveFilter(status: ArchiveStatus.voided);
      expect((await archive.page(filter: voidedOnly)).single.id, voidedId);
      expect(await archive.countMatching(voidedOnly), 1);
      expect(voidedOnly.isNarrowed, isTrue);
      // Deleting stays "by period": the filter is not part of it.
      expect(voidedOnly.datesOnly.status, ArchiveStatus.all);

      final today = await archive.summary(ArchiveFilter(from: from, to: to));
      expect(today.count, 2, reason: 'both are in the archive');
      expect(today.totalBaseMinor, 5000, reason: 'one of them counts');
    });

    test('the debts: balance, new debt of the period, the daily report',
        () async {
      expect(await balance(), 0);
      final now = saleTime.add(const Duration(hours: 3));
      final stats = await shop.debts.stats(from: from, to: to, now: now);
      expect(stats.newDebtBaseMinor, 0);
      expect(stats.outstandingBaseMinor, 0);

      final report = await DebtReportRepository(shop.db).build(now: now);
      expect(report.summary.newDebtTodayBaseMinor, 0);
      expect(report.summary.totalOutstandingBaseMinor, 0);
      expect(report.debtors, isEmpty);
      // What happened is still there to read: the debt and its reversal.
      expect(
        report.movements.map((m) => m.entry.type),
        unorderedEquals([DebtEntryType.debt, DebtEntryType.reversal]),
      );
    });
  });

  group('the audit log', () {
    test('says which invoice, how much, why, and what was undone', () async {
      await shop.loadCodes('1111222233334444');
      final sale = await shop.sell(
        [shop.card(), shop.package()],
        withAccount: true,
        paid: 10000,
      );
      await shop.corrections.voidInvoice(
        sale.id!,
        reason: 'customer cancelled',
        now: voidTime,
      );

      final line = (await shop.audit('INVOICE_VOID')).single;
      expect(line['entity_type'], 'invoice');
      expect(line['entity_id'], sale.id);
      expect(
        DateTime.fromMillisecondsSinceEpoch(line['created_at'] as int),
        voidTime,
      );
      final details = '${line['details']}';
      expect(details, contains('"invoice_no":${sale.invoiceNo}'));
      expect(details, contains('"amount":40000'));
      expect(details, contains('"customer":"Ahmad"'));
      expect(details, contains('"debt_reversed":30000'));
      expect(details, contains('"count":1'));
      expect(details, contains('"codes":"VOID"'));
      expect(details, contains('"account":"0011-2233"'));
      expect(details, contains('"reason":"customer cancelled"'));
    });
  });
}
