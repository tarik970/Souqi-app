import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_return.dart';
import 'package:souqi/domain/models/product.dart';

/// An invoice of [lines] — each (quantity in thousandths, line total) — with
/// an amount [discount] taken off. Item ids are 1, 2, 3…
Invoice invoiceOf(
  List<(int, int)> lines, {
  int discount = 0,
  String currency = 'SYP',
  RateFraction rate = RateFraction.one,
  int? totalBase,
  int? customerId,
  int? paid,
}) {
  final subtotal = lines.fold(0, (sum, line) => sum + line.$2);
  final total = subtotal - discount;
  return Invoice(
    id: 1,
    invoiceNo: 152,
    createdAt: DateTime.utc(2026, 11, 26, 9),
    currencyCode: currency,
    baseCurrencyCode: 'SYP',
    rate: rate,
    subtotalMinor: subtotal,
    discountType: discount > 0 ? DiscountType.amount : null,
    discountValue: discount > 0 ? discount : null,
    discountMinor: discount,
    totalMinor: total,
    totalBaseMinor: totalBase ?? total,
    customerId: customerId,
    paidMinor: paid,
    items: [
      for (var i = 0; i < lines.length; i++)
        InvoiceItem(
          id: i + 1,
          productName: 'Item ${i + 1}',
          kind: ProductKind.goods,
          qtyThousandths: lines[i].$1,
          origUnitPriceMinor: 0,
          origCurrencyCode: currency,
          origRate: rate,
          unitPriceMinor: 0,
          lineTotalMinor: lines[i].$2,
        ),
    ],
  );
}

/// The refund of a return is worked out from the ORIGINAL invoice: each
/// line's total, less its pro-rata share of the invoice discount, for the
/// part returned — exactly, with one half-up rounding, and so that the
/// returns of an invoice add up to what a single full return gives.
void main() {
  group('a full return', () {
    test('gives back exactly the invoice total, and its lines add up to it',
        () {
      final invoice = invoiceOf([(2000, 3000), (500, 4500), (1000, 2500)]);
      final refund = computeRefund(
        invoice: invoice,
        returnedBefore: const {},
        returning: const {1: 2000, 2: 500, 3: 1000},
      );
      expect(refund.refundMinor, 10000);
      expect(refund.returnedBeforeMinor, 0);
      expect(refund.returnedAfterMinor, invoice.totalMinor);
      expect(refund.lines.map((l) => l.refundMinor), [3000, 4500, 2500]);
      expect(refund.lines.map((l) => l.grossMinor), [3000, 4500, 2500]);
    });

    test('with a discount: the total PAID, not the price before the discount',
        () {
      // 1,000 + 3,000 less 10% (400): 3,600 was paid.
      final invoice = invoiceOf([(1000, 1000), (1000, 3000)], discount: 400);
      final refund = computeRefund(
        invoice: invoice,
        returnedBefore: const {},
        returning: const {1: 1000, 2: 1000},
      );
      expect(refund.refundMinor, 3600);
      // Each line carries its own share of the discount: 100 and 300.
      expect(refund.lines.map((l) => l.refundMinor), [900, 2700]);
      // What "top products" takes off is the line as it was sold.
      expect(refund.lines.map((l) => l.grossMinor), [1000, 3000]);
    });
  });

  group('the pro-rata share of the discount', () {
    test('a line returned alone gives back its total less its share', () {
      final invoice = invoiceOf([(1000, 1000), (1000, 3000)], discount: 400);
      expect(
        computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {2: 1000},
        ).refundMinor,
        2700,
      );
    });

    test('half a line gives back half of that', () {
      // 4 kg for 10,000 on an invoice of 20,000 less 2,000: the line is
      // worth 9,000, so 1 kg is 2,250.
      final invoice = invoiceOf([(4000, 10000), (1000, 10000)], discount: 2000);
      final refund = computeRefund(
        invoice: invoice,
        returnedBefore: const {},
        returning: const {1: 1000},
      );
      expect(refund.refundMinor, 2250);
      expect(refund.lines.single.grossMinor, 2500);
      expect(refund.lines.single.qtyThousandths, 1000);
    });

    test('rounds half-up, once: 2.5 becomes 3', () {
      // 1 of 2 units of a line worth 5 → exactly 2.5.
      final invoice = invoiceOf([(2000, 5)]);
      expect(
        computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {1: 1000},
        ).refundMinor,
        3,
      );
    });

    test('an invoice discounted to nothing gives nothing back', () {
      final invoice = invoiceOf([(1000, 700)], discount: 700);
      expect(
        computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {1: 1000},
        ).refundMinor,
        0,
      );
    });
  });

  group('several returns of one invoice', () {
    test('three lines of 100 less 1: line by line it is 100, 99, 100 — 299, '
        'never 300', () {
      final invoice = invoiceOf(
        [(1000, 100), (1000, 100), (1000, 100)],
        discount: 1,
      );
      final returned = <int, int>{};
      final refunds = <int>[];
      for (final line in [1, 2, 3]) {
        final refund = computeRefund(
          invoice: invoice,
          returnedBefore: returned,
          returning: {line: 1000},
        );
        refunds.add(refund.refundMinor);
        returned[line] = 1000;
      }
      expect(refunds, [100, 99, 100]);
      expect(refunds.fold(0, (a, b) => a + b), invoice.totalMinor);
    });

    test('a line of 200 returned a third at a time adds up to 200', () {
      final invoice = invoiceOf([(3000, 200)]);
      var before = 0;
      final refunds = <int>[];
      for (var i = 0; i < 3; i++) {
        final refund = computeRefund(
          invoice: invoice,
          returnedBefore: {1: before},
          returning: const {1: 1000},
        );
        expect(refund.returnedBeforeMinor, refunds.fold(0, (a, b) => a + b));
        refunds.add(refund.refundMinor);
        before += 1000;
      }
      // 66.67 → 67, 133.33 → 133, 200.
      expect(refunds, [67, 66, 67]);
      expect(refunds.fold(0, (a, b) => a + b), 200);
    });

    test('the returned share of a line total adds up to the line total', () {
      final invoice = invoiceOf([(3000, 1000)], discount: 100);
      var before = 0;
      var gross = 0;
      for (var i = 0; i < 3; i++) {
        gross += computeRefund(
          invoice: invoice,
          returnedBefore: {1: before},
          returning: const {1: 1000},
        ).lines.single.grossMinor;
        before += 1000;
      }
      expect(gross, 1000);
    });

    test('however an invoice is returned, the refunds add up to its total '
        '(1,000 random invoices)', () {
      final random = Random(20261126);
      for (var round = 0; round < 1000; round++) {
        final lineCount = 1 + random.nextInt(5);
        final lines = [
          for (var i = 0; i < lineCount; i++)
            (
              // 0.001 … 12 units, often fractional.
              1 + random.nextInt(12000),
              random.nextInt(250000),
            ),
        ];
        final subtotal = lines.fold(0, (sum, line) => sum + line.$2);
        final discount = subtotal == 0 ? 0 : random.nextInt(subtotal + 1);
        final invoice = invoiceOf(lines, discount: discount);

        final returned = {for (var i = 1; i <= lineCount; i++) i: 0};
        var given = 0;
        var guard = 0;
        while (returned.entries.any(
          (e) => e.value < invoice.items[e.key - 1].qtyThousandths,
        )) {
          expect(guard++, lessThan(200));
          final returning = <int, int>{};
          for (final item in invoice.items) {
            final left = item.qtyThousandths - returned[item.id]!;
            if (left == 0 || random.nextBool()) continue;
            returning[item.id!] =
                random.nextInt(4) == 0 ? left : 1 + random.nextInt(left);
          }
          if (returning.isEmpty) continue;
          final refund = computeRefund(
            invoice: invoice,
            returnedBefore: returned,
            returning: returning,
          );
          expect(refund.refundMinor, greaterThanOrEqualTo(0));
          expect(refund.returnedBeforeMinor, given, reason: 'round $round');
          // The lines of one return add up to its total.
          expect(
            refund.lines.fold(0, (sum, line) => sum + line.refundMinor),
            refund.refundMinor,
          );
          for (final line in refund.lines) {
            expect(line.refundMinor, greaterThanOrEqualTo(0));
          }
          given += refund.refundMinor;
          expect(given, lessThanOrEqualTo(invoice.totalMinor));
          returning.forEach((id, qty) => returned[id] = returned[id]! + qty);
        }
        expect(given, invoice.totalMinor, reason: 'round $round: $lines');
      }
    });
  });

  group('what cannot be returned', () {
    final invoice = invoiceOf([(2000, 3000), (1000, 500)]);

    test('nothing', () {
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {},
        ),
        throwsA(isA<ReturnQuantityException>()),
      );
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {1: 0},
        ),
        throwsA(isA<ReturnQuantityException>()),
      );
    });

    test('a line that is not on the invoice, or a negative quantity', () {
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {9: 1000},
        ),
        throwsA(isA<ReturnQuantityException>()
            .having((e) => e.invoiceItemId, 'line', 9)),
      );
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {1: -1},
        ),
        throwsA(isA<ReturnQuantityException>()),
      );
    });

    test('more than was sold', () {
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {},
          returning: const {1: 2001},
        ),
        throwsA(isA<ReturnQuantityException>()
            .having((e) => e.invoiceItemId, 'line', 1)),
      );
    });

    test('more than is LEFT after earlier returns', () {
      expect(
        computeRefund(
          invoice: invoice,
          returnedBefore: const {1: 1500},
          returning: const {1: 500},
        ).refundMinor,
        750,
      );
      expect(
        () => computeRefund(
          invoice: invoice,
          returnedBefore: const {1: 1500},
          returning: const {1: 501},
        ),
        throwsA(isA<ReturnQuantityException>()),
      );
    });
  });

  group('an invoice in another currency', () {
    // A USD invoice (2 decimals) at 13,000 SYP per dollar: 3.85 + 5.00 less
    // 0.85 = 8.00 USD, stored as 104,000 SYP.
    const rate = RateFraction(13000, 1);
    final invoice = invoiceOf(
      [(10000, 385), (2000, 500)],
      discount: 85,
      currency: 'USD',
      rate: rate,
      totalBase: 104000,
    );

    test('the refund is in the invoice currency, from the stored line totals',
        () {
      // Half of line 1: 385 × 800/885 × 5/10 = 174.01… cents.
      final half = computeRefund(
        invoice: invoice,
        returnedBefore: const {},
        returning: const {1: 5000},
      );
      expect(half.refundMinor, 174);
      // The other half: line 1 in full is 348.02… → 348, less the 174.
      final rest = computeRefund(
        invoice: invoice,
        returnedBefore: const {1: 5000},
        returning: const {1: 5000},
      );
      expect(rest.refundMinor, 174);
      // Line 2 takes the invoice to exactly 8.00.
      final last = computeRefund(
        invoice: invoice,
        returnedBefore: const {1: 10000},
        returning: const {2: 2000},
      );
      expect(last.refundMinor, 452);
      expect(last.returnedAfterMinor, 800);
    });

    test('in base currency at the invoice rate, one rounding, adding up to '
        'the stored base total', () {
      int base(int before, int after) => refundBaseMinor(
            invoice: invoice,
            returnedBeforeMinor: before,
            returnedAfterMinor: after,
            invoiceDecimals: 2,
            baseDecimals: 0,
          );
      // 1.74 USD = 22,620 SYP; then to 3.48 = 45,240; then all of it.
      expect(base(0, 174), 22620);
      expect(base(174, 348), 22620);
      expect(base(348, 800), 104000 - 45240);
      expect(base(0, 174) + base(174, 348) + base(348, 800), 104000);
      // A full return in one go is the stored figure itself.
      expect(base(0, 800), invoice.totalBaseMinor);
    });

    test('a rate that does not divide evenly still adds up', () {
      // 1 USD = 13,333.33… SYP; 1.00 USD stored as 13,333 SYP.
      final odd = invoiceOf(
        [(3000, 100)],
        currency: 'USD',
        rate: const RateFraction(40000, 3),
        totalBase: 13333,
      );
      var before = 0;
      var qty = 0;
      var baseSum = 0;
      for (var i = 0; i < 3; i++) {
        final refund = computeRefund(
          invoice: odd,
          returnedBefore: {1: qty},
          returning: const {1: 1000},
        );
        baseSum += refundBaseMinor(
          invoice: odd,
          returnedBeforeMinor: refund.returnedBeforeMinor,
          returnedAfterMinor: refund.returnedAfterMinor,
          invoiceDecimals: 2,
          baseDecimals: 0,
        );
        before += refund.refundMinor;
        qty += 1000;
      }
      expect(before, 100);
      expect(baseSum, 13333);
    });
  });

  group('how a refund is given back', () {
    test('cash: all of it over the counter', () {
      final split = splitRefund(
        refundMinor: 5000,
        method: RefundMethod.cash,
        owedMinor: 9000,
      );
      expect(split.cashMinor, 5000);
      expect(split.onAccountMinor, 0);
      expect(split.method, RefundMethod.cash);
    });

    test('reduce the debt: as much as is owed, the rest in cash', () {
      final covered = splitRefund(
        refundMinor: 5000,
        method: RefundMethod.debt,
        owedMinor: 9000,
      );
      expect(covered.debtMinor, 5000);
      expect(covered.cashMinor, 0);

      final partly = splitRefund(
        refundMinor: 5000,
        method: RefundMethod.debt,
        owedMinor: 2000,
      );
      expect(partly.debtMinor, 2000);
      expect(partly.cashMinor, 3000);
      expect(partly.totalMinor, 5000);
      expect(partly.method, RefundMethod.debt);
    });

    test('reduce the debt of a customer who owes nothing is a cash refund',
        () {
      final split = splitRefund(
        refundMinor: 5000,
        method: RefundMethod.debt,
        owedMinor: 0,
      );
      expect(split.cashMinor, 5000);
      expect(split.method, RefundMethod.cash);
    });

    test('customer credit: all of it on the account', () {
      final split = splitRefund(
        refundMinor: 5000,
        method: RefundMethod.credit,
        owedMinor: 2000,
      );
      expect(split.creditMinor, 5000);
      expect(split.cashMinor, 0);
      expect(split.method, RefundMethod.credit);
    });

    test('the default: a sale on credit to a customer who still owes reduces '
        'the debt; everything else is cash', () {
      final onCredit = invoiceOf([(1000, 8000)], customerId: 4, paid: 3000);
      final paid = invoiceOf([(1000, 8000)], customerId: 4, paid: 8000);
      final noCustomer = invoiceOf([(1000, 8000)]);
      RefundMethod of(Invoice invoice, {int owed = 5000, bool ledger = true}) =>
          defaultRefundMethod(
            invoice: invoice,
            owedMinor: owed,
            ledgerOn: ledger,
          );
      expect(of(onCredit), RefundMethod.debt);
      // Already paid off since.
      expect(of(onCredit, owed: 0), RefundMethod.cash);
      // The ledger is off: nothing of it is offered.
      expect(of(onCredit, ledger: false), RefundMethod.cash);
      expect(of(paid), RefundMethod.cash);
      expect(of(noCustomer), RefundMethod.cash);
    });
  });
}
