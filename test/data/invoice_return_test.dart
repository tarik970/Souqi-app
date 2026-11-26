import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_report_repository.dart';
import 'package:souqi/data/repositories/invoice_correction_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'correction_test_kit.dart';

/// RETURNS: a document of its own, with its own number, whose amounts come
/// from the original invoice — and everything it does lands in one
/// transaction.
void main() {
  setUpAll(sqfliteFfiInit);

  late TestShop shop;
  // The sales are made on 25 November (TestShop.saleTime).
  final returnTime = DateTime(2026, 11, 27, 16, 30);

  setUp(() async => shop = await TestShop.open());
  tearDown(() => shop.close());

  Future<int> balance() => shop.debts.balanceOf(shop.ahmad);

  /// Returns [quantities] — thousandths by position of the invoice line.
  Future<InvoiceReturn> giveBack(
    Invoice invoice,
    Map<int, int> quantities, {
    RefundMethod method = RefundMethod.cash,
    String? reason,
    Map<int, Map<int, CodeDisposal>> codes = const {},
    DateTime? at,
    InvoiceCorrectionRepository? repository,
  }) =>
      (repository ?? shop.corrections).saveReturn(
        ReturnDraft(
          invoiceId: invoice.id!,
          method: method,
          reason: reason,
          lines: [
            for (final entry in quantities.entries)
              ReturnLineRequest(
                invoiceItemId: invoice.items[entry.key].id!,
                qtyThousandths: entry.value,
                codes: codes[entry.key] ?? const {},
              ),
          ],
        ),
        now: at ?? returnTime,
      );

  Future<Map<String, int>> returnable(Invoice invoice) async => {
        for (final line in await shop.corrections.returnableLines(invoice.id!))
          line.item.productName: line.remainingThousandths,
      };

  group('the document', () {
    test('a partial return: its number, the invoice it comes from, the '
        'lines, the refund, the customer', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 3000, price: 8000), shop.tea()],
        customer: true,
      );
      final doc = await giveBack(sale, {0: 1500}, reason: 'damaged bag');

      expect(doc.returnNo, 1);
      expect(doc.invoiceId, sale.id);
      expect(doc.invoiceNo, sale.invoiceNo);
      expect(doc.createdAt.toLocal(), returnTime);
      expect(doc.currencyCode, 'SYP');
      expect(doc.refundMinor, 12000);
      expect(doc.refundBaseMinor, 12000);
      expect(doc.method, RefundMethod.cash);
      expect(doc.cashMinor, 12000);
      expect(doc.onAccountMinor, 0);
      expect(doc.reason, 'damaged bag');
      expect(doc.customerId, shop.ahmad);
      expect(doc.customerName, 'Ahmad');
      expect(doc.customerPhone, '0944 111 222');
      final line = doc.items.single;
      expect(line.productName, 'Sugar');
      expect(line.unitName, 'kg');
      expect(line.qtyThousandths, 1500);
      expect(line.refundMinor, 12000);
      expect(line.invoiceItemId, sale.items.first.id);

      // The invoice itself is untouched.
      final invoice = (await shop.invoices.getById(sale.id!))!;
      expect(invoice.totalMinor, sale.totalMinor);
      expect(invoice.items.first.qtyThousandths, 3000);
      expect(invoice.isVoided, isFalse);
      // It is read back the same, alone and from its invoice.
      expect((await shop.corrections.returnById(doc.id))!.returnNo, 1);
      expect(
        (await shop.corrections.returnsOf(sale.id!)).single.items,
        hasLength(1),
      );
    });

    test('a blank reason is no reason', () async {
      final sale = await shop.sell([shop.sugar()]);
      expect((await giveBack(sale, {0: 1000}, reason: '  ')).reason, isNull);
    });
  });

  group('returnable quantities', () {
    test('sold minus already returned, over several returns — never below '
        'zero', () async {
      final sale =
          await shop.sell([shop.sugar(qty: 3000), shop.tea(qty: 2000)]);
      expect(await returnable(sale), {'Sugar': 3000, 'Tea': 2000});

      await giveBack(sale, {0: 1000});
      expect(await returnable(sale), {'Sugar': 2000, 'Tea': 2000});
      await giveBack(sale, {0: 1500, 1: 2000});
      expect(await returnable(sale), {'Sugar': 500, 'Tea': 0});

      // More than is left of a line: refused whole — the tea of the same
      // return is not returned either, and no number is used up.
      await expectLater(
        giveBack(sale, {0: 501}),
        throwsA(isA<ReturnQuantityException>()),
      );
      await expectLater(
        giveBack(sale, {0: 500, 1: 1}),
        throwsA(isA<ReturnQuantityException>()),
      );
      expect(await returnable(sale), {'Sugar': 500, 'Tea': 0});
      expect(await shop.count('invoice_returns'), 2);

      final last = await giveBack(sale, {0: 500});
      expect(last.returnNo, 3);
      expect(await returnable(sale), {'Sugar': 0, 'Tea': 0});
      await expectLater(
        giveBack(sale, {0: 1}),
        throwsA(isA<ReturnQuantityException>()),
      );
    });

    test('a return of nothing, or the same line twice, is refused', () async {
      final sale = await shop.sell([shop.sugar(qty: 3000)]);
      await expectLater(
        giveBack(sale, {0: 0}),
        throwsA(isA<ReturnQuantityException>()),
      );
      await expectLater(
        shop.corrections.saveReturn(ReturnDraft(
          invoiceId: sale.id!,
          lines: [
            for (var i = 0; i < 2; i++)
              ReturnLineRequest(
                invoiceItemId: sale.items.single.id!,
                qtyThousandths: 2000,
              ),
          ],
        )),
        throwsA(isA<ReturnQuantityException>()),
      );
      expect(await shop.count('invoice_returns'), 0);
      expect(await shop.count('invoice_return_items'), 0);
    });

    test('a full return in pieces gives back exactly the invoice total',
        () async {
      final sale = await shop.sell(
        [
          shop.sugar(qty: 3000, price: 3333),
          shop.tea(qty: 1000, price: 100),
        ],
        discount: const Discount.amount(1),
      );
      // 9,999 + 100 − 1.
      expect(sale.totalMinor, 10098);
      var given = 0;
      for (final step in [
        {0: 1000},
        {0: 1000},
        {1: 1000},
        {0: 1000},
      ]) {
        given += (await giveBack(sale, step)).refundMinor;
      }
      expect(given, sale.totalMinor);
      final preview = await shop.corrections.returnableLines(sale.id!);
      expect(preview.every((line) => line.remainingThousandths == 0), isTrue);
    });
  });

  group('the refund', () {
    test('the pro-rata share of the invoice discount comes off each line',
        () async {
      // 1,000 + 3,000 less 10% = 3,600.
      final sale = await shop.sell(
        [shop.sugar(price: 1000), shop.tea(price: 3000)],
        discount: const Discount.percent(1000),
      );
      expect(sale.totalMinor, 3600);

      final preview =
          await shop.corrections.previewReturn(sale.id!, {sale.items[1].id!: 1000});
      expect(preview.refund.refundMinor, 2700);

      final tea = await giveBack(sale, {1: 1000});
      expect(tea.refundMinor, 2700);
      expect(tea.items.single.refundMinor, 2700);
      expect(tea.items.single.grossMinor, 3000);
      final sugar = await giveBack(sale, {0: 1000});
      expect(sugar.refundMinor, 900);
      expect(tea.refundMinor + sugar.refundMinor, sale.totalMinor);
    });

    test('an invoice in dollars is refunded in dollars at ITS rate — today\'s '
        'rate changes nothing', () async {
      // 10 kg at 5,000 SYP on a USD invoice = 3.85 USD, stored as 50,050.
      final sale = await shop.sell(
        [shop.sugar(qty: 10000, price: 5000)],
        currency: 'USD',
      );
      expect(sale.currencyCode, 'USD');
      expect(sale.totalMinor, 385);
      expect(sale.totalBaseMinor, 50050);
      // The dollar doubles after the sale.
      await shop.db.update(
        'currencies',
        {'rate_num': 26000},
        where: 'code = ?',
        whereArgs: ['USD'],
      );

      // 3 kg: 115.5 → 116 cents (half-up, once).
      final first = await giveBack(sale, {0: 3000});
      expect(first.currencyCode, 'USD');
      expect(first.rate.numerator, 13000);
      expect(first.refundMinor, 116);
      expect(first.refundBaseMinor, 15080);
      // 3 kg more: 231 so far, so 115 now — not 116 again.
      final second = await giveBack(sale, {0: 3000});
      expect(second.refundMinor, 115);
      expect(second.refundBaseMinor, 30030 - 15080);
      // The rest takes it to exactly what was paid, in both currencies.
      final last = await giveBack(sale, {0: 4000});
      expect(last.refundMinor, 385 - 231);
      expect(
        first.refundMinor + second.refundMinor + last.refundMinor,
        sale.totalMinor,
      );
      expect(
        first.refundBaseMinor + second.refundBaseMinor + last.refundBaseMinor,
        sale.totalBaseMinor,
      );
    });
  });

  group('how it is given back', () {
    test('cash touches no ledger', () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      expect(await balance(), 8000);
      final doc = await giveBack(sale, {0: 1000});
      expect(doc.method, RefundMethod.cash);
      expect(await balance(), 8000);
      expect(await shop.ledgerRows(), hasLength(1));
    });

    test('reduce the debt: a RETURN entry, linked to the document; no entry '
        'is edited', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 6000,
      );
      expect(await balance(), 10000);
      final before = (await shop.ledgerRows()).single;
      final preview = await shop.corrections
          .previewReturn(sale.id!, {sale.items.single.id!: 1000});
      expect(preview.owedMinor, 10000);
      expect(preview.hasCustomer, isTrue);
      expect(
        defaultRefundMethod(
          invoice: preview.invoice,
          owedMinor: preview.owedMinor,
          ledgerOn: true,
        ),
        RefundMethod.debt,
      );

      final doc = await giveBack(
        sale,
        {0: 1000},
        method: RefundMethod.debt,
        reason: 'opened',
      );

      expect(doc.method, RefundMethod.debt);
      expect(doc.debtMinor, 8000);
      expect(doc.cashMinor, 0);
      expect(await balance(), 2000);
      final rows = await shop.ledgerRows();
      expect(rows, hasLength(2));
      expect(rows.first, before);
      final entry = rows.last;
      expect(entry['type'], 'RETURN');
      expect(entry['direction'], -1);
      expect(entry['amount_base_minor'], 8000);
      expect(entry['return_id'], doc.id);
      expect(entry['return_no'], doc.returnNo);
      expect(entry['invoice_id'], sale.id);
      expect(entry['invoice_no'], sale.invoiceNo);
      expect(entry['note'], 'opened');
      expect(entry['receipt_no'], isNull);
      expect(
        DateTime.fromMillisecondsSinceEpoch(entry['created_at'] as int),
        returnTime,
      );

      // As the ledger screens read it.
      final line = (await shop.debts.ledger(shop.ahmad)).first;
      expect(line.entry.type, DebtEntryType.saleReturn);
      expect(line.entry.returnNo, doc.returnNo);
      expect(line.entry.returnId, doc.id);
      expect(line.entry.isDebit, isFalse);
      expect(line.balanceAfterBaseMinor, 2000);
    });

    test('reduce the debt, then cash for the rest: no more comes off than '
        'is owed', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 13000,
      );
      expect(await balance(), 3000);
      final doc = await giveBack(sale, {0: 1000}, method: RefundMethod.debt);
      expect(doc.refundMinor, 8000);
      expect(doc.debtMinor, 3000);
      expect(doc.cashMinor, 5000);
      expect(doc.method, RefundMethod.debt);
      expect(await balance(), 0);
    });

    test('reduce the debt of a customer who owes nothing is a cash refund',
        () async {
      final sale =
          await shop.sell([shop.sugar()], customer: true, paid: 8000);
      final doc = await giveBack(sale, {0: 1000}, method: RefundMethod.debt);
      expect(doc.method, RefundMethod.cash);
      expect(doc.cashMinor, 8000);
      expect(await shop.ledgerRows(), isEmpty);
    });

    test('keep as customer credit: the balance goes in his favour', () async {
      final sale =
          await shop.sell([shop.sugar()], customer: true, paid: 8000);
      final doc = await giveBack(sale, {0: 1000}, method: RefundMethod.credit);
      expect(doc.method, RefundMethod.credit);
      expect(doc.creditMinor, 8000);
      expect(doc.cashMinor, 0);
      expect(await balance(), -8000);
      expect((await shop.ledgerRows()).single['type'], 'RETURN');
    });

    test('on the account of an invoice in dollars: converted at the '
        'invoice rate, with what was returned kept beside it', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 10000, price: 5000)],
        customer: true,
        paid: 0,
        currency: 'USD',
      );
      expect(await balance(), 50050);
      final doc = await giveBack(sale, {0: 10000}, method: RefundMethod.debt);
      expect(doc.debtMinor, 385);
      expect(await balance(), 0);
      final entry = (await shop.ledgerRows()).last;
      expect(entry['amount_base_minor'], 50050);
      expect(entry['orig_amount_minor'], 385);
      expect(entry['orig_currency_code'], 'USD');
      expect(entry['orig_rate_num'], 13000);
      expect(entry['orig_rate_den'], 1);
    });

    test('the account needs a customer on the invoice', () async {
      final sale = await shop.sell([shop.sugar()]);
      final preview = await shop.corrections
          .previewReturn(sale.id!, {sale.items.single.id!: 1000});
      expect(preview.hasCustomer, isFalse);
      expect(preview.owedMinor, 0);
      for (final method in [RefundMethod.debt, RefundMethod.credit]) {
        await expectLater(
          giveBack(sale, {0: 1000}, method: method),
          throwsA(isA<ReturnCustomerRequiredException>()),
        );
      }
      expect(await shop.count('invoice_returns'), 0);
    });

    test('a RETURN entry cannot be edited, deleted, or reversed on its own',
        () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      await giveBack(sale, {0: 1000}, method: RefundMethod.debt);
      final entry = (await shop.debts.ledger(shop.ahmad)).first.entry;
      expect(entry.canBeReversed, isFalse);
      await expectLater(
        shop.debts.reverse(entry.id, reason: 'mistake'),
        throwsA(isA<NotReversibleException>()),
      );
      await expectLater(
        shop.db.update(
          'debt_transactions',
          {'amount_base_minor': 1},
          where: 'id = ?',
          whereArgs: [entry.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        shop.db.update(
          'debt_transactions',
          {'return_no': 99},
          where: 'id = ?',
          whereArgs: [entry.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        shop.db.delete(
          'debt_transactions',
          where: 'id = ?',
          whereArgs: [entry.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await balance(), 0);
    });
  });

  group('return numbers', () {
    test('their own sequence, apart from the invoices, never reused — not '
        'after a refused return, not after their document is deleted',
        () async {
      final first = await shop.sell([shop.sugar(qty: 5000)]);
      final second = await shop.sell([shop.tea(qty: 5000)]);
      expect((await giveBack(first, {0: 1000})).returnNo, 1);
      expect((await giveBack(second, {0: 1000})).returnNo, 2);
      // A refused return draws no number.
      await expectLater(
        giveBack(first, {0: 9000}),
        throwsA(isA<ReturnQuantityException>()),
      );
      expect((await giveBack(first, {0: 1000})).returnNo, 3);

      // The invoice goes, and its returns with it; their numbers do not
      // come back.
      await ArchiveRepository(shop.db).deleteInvoice(first.id!);
      expect(await shop.corrections.returnsOf(first.id!), isEmpty);
      expect(await shop.count('invoice_returns'), 1);
      expect((await giveBack(second, {0: 1000})).returnNo, 4);
      // And the invoice numbers went their own way.
      expect((await shop.sell([shop.sugar()])).invoiceNo, 3);
    });
  });

  group('card codes on returned lines', () {
    setUp(
      () => shop.loadCodes(
        '1111222233334444\n5555666677778888\n9999000011112222',
      ),
    );

    test('each returned card is one of the codes of its line: voided, or '
        'put back in stock — with an audit line each', () async {
      final sale = await shop.sell([shop.card(cards: 3), shop.sugar()]);
      final line =
          (await shop.corrections.returnableLines(sale.id!)).first;
      expect(line.hasCodes, isTrue);
      expect(line.codes, hasLength(3));
      expect(line.codes.first.masked, '•••• •••• 4444');
      final ids = [for (final code in line.codes) code.id];

      final doc = await giveBack(
        sale,
        {0: 2000},
        codes: {
          0: {
            ids[0]: CodeDisposal.voidCode,
            ids[2]: CodeDisposal.returnToStock,
          },
        },
        reason: 'not needed',
      );

      expect(doc.refundMinor, 10000);
      expect(doc.codesVoided, 1);
      expect(doc.codesRestocked, 1);
      expect(await shop.codeStatuses(), ['VOID', 'SOLD', 'AVAILABLE']);
      // What is left on the invoice is the card the customer kept.
      expect(await shop.vouchers.printableCodes(sale.id!), hasLength(1));
      final voided = (await shop.audit('CODE_VOID')).single;
      expect('${voided['details']}', contains('"return_no":1'));
      expect('${voided['details']}', contains('"reason":"not needed"'));
      expect(await shop.audit('CODE_RESTORE'), hasLength(1));
      // The line now has one card and one code left.
      final after = (await shop.corrections.returnableLines(sale.id!)).first;
      expect(after.remainingThousandths, 1000);
      expect(after.codes.single.id, ids[1]);
    });

    test('a card is not refunded while its code stays with the customer',
        () async {
      final sale = await shop.sell([shop.card(cards: 2)]);
      final ids = [
        for (final code
            in (await shop.corrections.returnableLines(sale.id!)).first.codes)
          code.id,
      ];
      // Two cards returned, no code chosen.
      await expectLater(
        giveBack(sale, {0: 2000}),
        throwsA(isA<ReturnCodesException>()),
      );
      // Two cards, one code.
      await expectLater(
        giveBack(sale, {0: 2000}, codes: {
          0: {ids[0]: CodeDisposal.voidCode},
        }),
        throwsA(isA<ReturnCodesException>()),
      );
      // A code that is not on this invoice.
      await expectLater(
        giveBack(sale, {0: 1000}, codes: {
          0: {ids[1] + 1: CodeDisposal.voidCode},
        }),
        throwsA(isA<ReturnCodesException>()),
      );
      expect(await shop.codeStatuses(), ['SOLD', 'SOLD', 'AVAILABLE']);
      expect(await shop.count('invoice_returns'), 0);
    });

    test('a card whose code was already voided by hand is returned without '
        'one', () async {
      final sale = await shop.sell([shop.card(cards: 2)]);
      final first = (await shop.vouchers.codesOfInvoice(sale.id!)).first;
      await shop.vouchers.voidCode(first.id, reason: 'defective');
      final line = (await shop.corrections.returnableLines(sale.id!)).single;
      expect(line.remainingThousandths, 2000);
      expect(line.codes, hasLength(1));

      final doc = await giveBack(sale, {0: 1000});
      expect(doc.refundMinor, 5000);
      expect(await shop.codeStatuses(), ['VOID', 'SOLD', 'AVAILABLE']);
    });
  });

  group('a returned renewal', () {
    test('returning the package puts the account back on its previous dates',
        () async {
      final sale = await shop.sell(
        [shop.package(), shop.sugar()],
        withAccount: true,
      );
      expect((await shop.account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));

      // The sugar alone: the renewal stands.
      await giveBack(sale, {1: 1000});
      expect((await shop.account()).nextDueAt!.toLocal(), DateTime(2026, 12, 25));

      await giveBack(sale, {0: 1000});
      final account = await shop.account();
      expect(account.lastRenewalAt!.toLocal(), TestShop.accountLastRenewal);
      expect(account.nextDueAt!.toLocal(), TestShop.accountDue);
      expect('${(await shop.audit('INVOICE_RETURN')).last['details']}',
          contains('"account":"0011-2233"'));
    });

    test('it is no longer a renewal in the statistics', () async {
      final stats = StatsRepository(shop.db);
      final from = DateTime(2026, 11, 25);
      final to = DateTime(2026, 11, 26);
      final sale = await shop.sell([shop.package()], withAccount: true);
      expect((await stats.renewals(from: from, to: to)).count, 1);
      await giveBack(sale, {0: 1000});
      expect((await stats.renewals(from: from, to: to)).count, 0);
    });
  });

  group('statistics', () {
    final saleDay = (DateTime(2026, 11, 25), DateTime(2026, 11, 26));
    final returnDay = (DateTime(2026, 11, 27), DateTime(2026, 11, 28));
    final week = (DateTime(2026, 11, 23), DateTime(2026, 11, 30));

    test('net sales = sales − returns, counted on the day of the RETURN',
        () async {
      final stats = StatsRepository(shop.db);
      final sale = await shop.sell(
        [shop.sugar(qty: 2000), shop.tea()],
        discount: const Discount.amount(1900),
      );
      expect(sale.totalMinor, 17100);
      final doc = await giveBack(sale, {0: 1000});
      // 8,000 of 19,000, less its share of the discount (800).
      expect(doc.refundMinor, 7200);

      Future<PeriodStats> of((DateTime, DateTime) period) =>
          stats.summary(from: period.$1, to: period.$2, baseDecimals: 0);

      // The day of the sale still shows the whole sale.
      final sold = await of(saleDay);
      expect(sold.invoiceCount, 1);
      expect(sold.totalBaseMinor, 17100);
      expect(sold.returnsBaseMinor, 0);
      expect(sold.netBaseMinor, 17100);

      // The day of the return shows the refund, as its own figure.
      final returned = await of(returnDay);
      expect(returned.invoiceCount, 0);
      expect(returned.totalBaseMinor, 0);
      expect(returned.returnCount, 1);
      expect(returned.returnsBaseMinor, 7200);
      expect(returned.netBaseMinor, -7200);

      // A period that holds both nets them.
      final both = await of(week);
      expect(both.totalBaseMinor, 17100);
      expect(both.returnsBaseMinor, 7200);
      expect(both.netBaseMinor, 9900);
    });

    test('top products use net quantities and amounts', () async {
      final stats = StatsRepository(shop.db);
      final sale = await shop.sell([shop.sugar(qty: 3000), shop.tea()]);
      await shop.sell([shop.sugar(qty: 1000)]);
      await giveBack(sale, {0: 1500});

      Future<Map<String, (int, int, int)>> top((DateTime, DateTime) period,
              {ProductRanking ranking = ProductRanking.amount}) async =>
          {
            for (final row in await stats.topProducts(
              from: period.$1,
              to: period.$2,
              baseDecimals: 0,
              ranking: ranking,
            ))
              row.name: (row.salesCount, row.qtyThousandths, row.amountBaseMinor),
          };

      // Sold that day: 4 kg in two sales.
      expect(await top(saleDay), {
        'Sugar': (2, 4000, 32000),
        'Tea': (1, 1000, 3000),
      });
      // Over the week: 1.5 kg came back.
      expect(await top(week), {
        'Sugar': (2, 2500, 20000),
        'Tea': (1, 1000, 3000),
      });
      expect(
        (await top(week, ranking: ProductRanking.sales)).keys.first,
        'Sugar',
      );
      // Only returned that day: not a best seller of it.
      expect(await top(returnDay), isEmpty);
    });

    test('a customer\'s total is net of what they returned', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 16000,
      );
      await giveBack(sale, {0: 500});
      final totals = await CustomerRepository(shop.db).totals(shop.ahmad);
      expect(totals.invoiceCount, 1);
      expect(totals.totalBaseMinor, 12000);
    });
  });

  group('the archive', () {
    test('lists the returns of a period by the date of the return, finds '
        'them by number, product and customer', () async {
      final first = await shop.sell([shop.sugar(qty: 3000)], customer: true);
      final second = await shop.sell([shop.tea(qty: 3000)]);
      final r1 = await giveBack(first, {0: 1000});
      final r2 = await giveBack(
        second,
        {0: 1000},
        at: returnTime.add(const Duration(days: 1)),
      );

      final corrections = shop.corrections;
      const returns = ArchiveFilter(status: ArchiveStatus.returns);
      final all = await corrections.returnsPage(returns);
      expect(all.map((r) => r.returnNo), [r2.returnNo, r1.returnNo]);
      final summary = await corrections.returnsSummary(returns);
      expect(summary.count, 2);
      expect(summary.totalBaseMinor, 11000);

      // By the day of the RETURN, not of the sale.
      final thatDay = ArchiveFilter(
        status: ArchiveStatus.returns,
        from: DateTime(2026, 11, 27),
        to: DateTime(2026, 11, 28),
      );
      expect((await corrections.returnsPage(thatDay)).single.id, r1.id);
      expect(
        await corrections.returnsPage(ArchiveFilter(
          status: ArchiveStatus.returns,
          from: DateTime(2026, 11, 25),
          to: DateTime(2026, 11, 26),
        )),
        isEmpty,
      );
      // By the number of the invoice or of the return itself.
      expect(
        (await corrections.returnsPage(
          returns.copyWith(invoiceNo: () => second.invoiceNo),
        ))
            .map((r) => r.id),
        // Invoice 2 — and return 2, which is the same document here.
        [r2.id],
      );
      expect(
        (await corrections
                .returnsPage(returns.copyWith(productQuery: 'sug')))
            .single
            .id,
        r1.id,
      );
      expect(
        (await corrections
                .returnsPage(returns.copyWith(customerQuery: 'ahm')))
            .single
            .id,
        r1.id,
      );

      // The invoices know which of them has returns.
      final archive = ArchiveRepository(shop.db);
      final entries = await archive.page();
      expect(entries.every((e) => e.returnCount == 1), isTrue);
      expect((await archive.page(filter: returns)).length, 2);
    });
  });

  group('deleting old invoices', () {
    test('deletes their return documents and never their ledger entries: '
        'the entry keeps the return number and the invoice number', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 0,
      );
      final other = await shop.sell([shop.tea()]);
      final doc = await giveBack(sale, {0: 1000}, method: RefundMethod.debt);
      await giveBack(other, {0: 1000});
      expect(await balance(), 8000);
      final before = await shop.ledgerRows();

      // The way the archive and the retention sweep delete: by period, in
      // chunks.
      final deleted = await ArchiveRepository(shop.db)
          .deleteMatchingChunk(const ArchiveFilter());
      expect(deleted, 2);

      expect(await shop.count('invoices'), 0);
      expect(await shop.count('invoice_returns'), 0);
      expect(await shop.count('invoice_return_items'), 0);
      final after = await shop.ledgerRows();
      expect(after, hasLength(before.length));
      expect(await balance(), 8000);
      final entry = after.last;
      expect(entry['type'], 'RETURN');
      expect(entry['amount_base_minor'], 8000);
      expect(entry['return_id'], isNull);
      expect(entry['return_no'], doc.returnNo);
      expect(entry['invoice_id'], isNull);
      expect(entry['invoice_no'], sale.invoiceNo);
      // Nothing else of any entry changed.
      for (var i = 0; i < before.length; i++) {
        for (final column in before[i].keys) {
          if (column == 'invoice_id' || column == 'return_id') continue;
          expect(after[i][column], before[i][column], reason: column);
        }
      }
      expect(await shop.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('what is refused', () {
    test('a return from a voided invoice', () async {
      final sale = await shop.sell([shop.sugar()]);
      await shop.corrections.voidInvoice(sale.id!, reason: 'duplicate');
      await expectLater(
        giveBack(sale, {0: 1000}),
        throwsA(isA<InvoiceVoidedException>()),
      );
      await expectLater(
        shop.corrections.previewReturn(sale.id!, {sale.items.single.id!: 1000}),
        throwsA(isA<InvoiceVoidedException>()),
      );
      expect(await shop.count('invoice_returns'), 0);
    });

    test('without a license, like a sale — and nothing is written', () async {
      final sale = await shop.sell([shop.sugar()], customer: true, paid: 0);
      final locked = InvoiceCorrectionRepository(
        shop.db,
        codeCipher: shop.cipher,
        guard: RefusingGuard(),
      );
      await expectLater(
        giveBack(sale, {0: 1000}, repository: locked),
        throwsA(isA<LicenseRequiredException>()),
      );
      expect(await shop.count('invoice_returns'), 0);
      expect(await balance(), 8000);
      // Looking stays open.
      expect(await locked.returnableLines(sale.id!), hasLength(1));
    });

    test('a failure half way leaves nothing behind', () async {
      await shop.loadCodes('1111222233334444');
      final sale = await shop.sell(
        [shop.card(), shop.sugar()],
        customer: true,
        paid: 0,
      );
      final code = (await shop.vouchers.codesOfInvoice(sale.id!)).single;
      await shop.db.execute(
        'CREATE TRIGGER fail_return BEFORE INSERT ON audit_log '
        "WHEN NEW.action = 'INVOICE_RETURN' "
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await expectLater(
        giveBack(
          sale,
          {0: 1000, 1: 1000},
          method: RefundMethod.debt,
          codes: {
            0: {code.id: CodeDisposal.voidCode},
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await shop.count('invoice_returns'), 0);
      expect(await shop.count('invoice_return_items'), 0);
      expect(await shop.ledgerRows(), hasLength(1));
      expect(await balance(), 13000);
      expect(await shop.codeStatuses(), ['SOLD']);
      expect(await shop.audit('CODE_VOID'), isEmpty);
      // The number it drew went back with it.
      await shop.db.execute('DROP TRIGGER fail_return');
      expect((await giveBack(sale, {1: 1000})).returnNo, 1);
    });
  });

  group('the audit log and the daily report', () {
    test('a return is logged with the invoice, its number, the amount and '
        'how it was given back', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 0,
      );
      final doc = await giveBack(
        sale,
        {0: 1000},
        method: RefundMethod.debt,
        reason: 'wrong size',
      );
      final line = (await shop.audit('INVOICE_RETURN')).single;
      expect(line['entity_type'], 'return');
      expect(line['entity_id'], doc.id);
      final details = '${line['details']}';
      expect(details, contains('"invoice_no":${sale.invoiceNo}'));
      expect(details, contains('"return_no":1'));
      expect(details, contains('"amount":8000'));
      expect(details, contains('"customer":"Ahmad"'));
      expect(details, contains('"method":"DEBT"'));
      expect(details, contains('"on_account":8000'));
      expect(details, contains('"reason":"wrong size"'));
    });

    test('today\'s return entries are in the daily debt report', () async {
      final sale = await shop.sell(
        [shop.sugar(qty: 2000)],
        customer: true,
        paid: 0,
      );
      await giveBack(sale, {0: 1000}, method: RefundMethod.debt);
      final report = await DebtReportRepository(shop.db)
          .build(now: returnTime.add(const Duration(hours: 1)));
      final entry = report.movements
          .map((m) => m.entry)
          .singleWhere((e) => e.type == DebtEntryType.saleReturn);
      expect(entry.returnNo, 1);
      expect(entry.amountBaseMinor, 8000);
      expect(report.summary.totalOutstandingBaseMinor, 8000);
      expect(report.debtors.single.balanceBaseMinor, 8000);
    });
  });
}
