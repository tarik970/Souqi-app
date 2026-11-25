import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/features/debts/debt_text.dart';
import 'package:souqi/features/debts/debtors_screen.dart';
import 'package:souqi/features/sale/payment_sheet.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';

import 'invoice_test_utils.dart';

/// The wording and the arithmetic of the debt ledger that need no screen:
/// balances in words, entry descriptions, the WhatsApp reminder, the order
/// of the debtors list and the numbers of the payment sheet.
void main() {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));
  String money(int minor) => '$minor SYP';

  DebtEntry entry(
    DebtEntryType type, {
    int direction = 1,
    int? invoiceNo,
    int? receiptNo,
    DebtEntryType? reversedType,
    int? reversedReceiptNo,
    int? reversedInvoiceNo,
  }) =>
      DebtEntry(
        id: 1,
        customerId: 1,
        type: type,
        direction: direction,
        amountBaseMinor: 100,
        invoiceNo: invoiceNo,
        receiptNo: receiptNo,
        reversesId: type == DebtEntryType.reversal ? 9 : null,
        reversedType: reversedType,
        reversedReceiptNo: reversedReceiptNo,
        reversedInvoiceNo: reversedInvoiceNo,
        createdAt: DateTime.utc(2026, 11, 25),
        recordedAt: DateTime.utc(2026, 11, 25),
      );

  group('balance in words', () {
    test('owes, is owed, settled — in both languages', () {
      expect(balanceInWords(ar, 5000, money), 'عليه 5000 SYP');
      expect(balanceInWords(ar, -2000, money), 'له 2000 SYP');
      expect(balanceInWords(ar, 0, money), 'لا يوجد رصيد');
      expect(balanceInWords(en, 5000, money), 'Owes 5000 SYP');
      expect(balanceInWords(en, -2000, money), 'Credit 2000 SYP');
      expect(balanceInWords(en, 0, money), 'No balance');
    });
  });

  group('entry descriptions', () {
    test('each kind of entry says what it is', () {
      expect(
        describeEntry(ar, entry(DebtEntryType.debt, invoiceNo: 152),
            locale: 'ar'),
        'فاتورة 152',
      );
      expect(
        describeEntry(
          ar,
          entry(DebtEntryType.payment, direction: -1, receiptNo: 37),
          locale: 'ar',
        ),
        'سند قبض 37',
      );
      expect(
        describeEntry(ar, entry(DebtEntryType.openingBalance), locale: 'ar'),
        'رصيد افتتاحي',
      );
      expect(describeEntry(ar, entry(DebtEntryType.manualDebt), locale: 'ar'),
          'دين');
      expect(describeEntry(ar, entry(DebtEntryType.adjustment), locale: 'ar'),
          'تسوية');
      expect(
        describeEntry(en, entry(DebtEntryType.debt, invoiceNo: 152),
            locale: 'en'),
        'Invoice 152',
      );
      expect(
        describeEntry(
          en,
          entry(DebtEntryType.payment, direction: -1, receiptNo: 37),
          locale: 'en',
        ),
        'Receipt 37',
      );
    });

    test('a debt carried over without an invoice number, a payment without '
        'a receipt', () {
      expect(describeEntry(en, entry(DebtEntryType.debt), locale: 'en'), 'Debt');
      expect(
        describeEntry(en, entry(DebtEntryType.payment, direction: -1),
            locale: 'en'),
        'Payment',
      );
    });

    test('a reversal says what it cancels, and links back to it', () {
      final reversal = entry(
        DebtEntryType.reversal,
        reversedType: DebtEntryType.payment,
        reversedReceiptNo: 37,
      );
      expect(describeEntry(ar, reversal, locale: 'ar'), 'عكس: سند قبض 37');
      expect(describeEntry(en, reversal, locale: 'en'), 'Reversal: Receipt 37');
      expect(describeReversedOriginal(en, reversal, locale: 'en'), 'Receipt 37');
      final ofInvoice = entry(
        DebtEntryType.reversal,
        direction: -1,
        reversedType: DebtEntryType.debt,
        reversedInvoiceNo: 152,
      );
      expect(describeEntry(ar, ofInvoice, locale: 'ar'), 'عكس: فاتورة 152');
      expect(describeReversedOriginal(ar, ofInvoice, locale: 'ar'), 'فاتورة 152');
    });
  });

  group('the WhatsApp reminder', () {
    test('the default text, filled in, in both languages', () {
      final arabic = buildDebtReminderText(
        template: '',
        name: 'أحمد',
        balance: '25,000 ل.س',
        language: 'ar',
        shopName: 'بقالة البركة',
        lastPaymentAt: DateTime(2026, 11, 3),
      );
      expect(arabic, contains('مرحباً أحمد'));
      expect(arabic, contains('بقالة البركة'));
      expect(arabic, contains('25,000 ل.س'));
      expect(arabic, contains('2026/11/03'));
      expect(arabic, isNot(contains('{')));

      final english = buildDebtReminderText(
        template: '',
        name: 'Ahmad',
        balance: '25,000 SYP',
        language: 'en',
        shopName: 'Al-Baraka',
        lastPaymentAt: DateTime(2026, 11, 3),
      );
      expect(
        english,
        'Hello Ahmad, a reminder from Al-Baraka: your balance is 25,000 SYP. '
        'Last payment: 2026/11/03. Thank you.',
      );
    });

    test('the default lists the four placeholders', () {
      for (final language in ['ar', 'en']) {
        final text = defaultDebtReminderTemplate(language);
        for (final placeholder in debtReminderPlaceholders) {
          expect(text, contains(placeholder), reason: '$language $placeholder');
        }
      }
    });

    test('a customer who never paid, a shop without a name: no dangling '
        'sentence', () {
      final text = buildDebtReminderText(
        template: '',
        name: 'Ahmad',
        balance: '500 SYP',
        language: 'en',
      );
      expect(text, 'Hello Ahmad, a reminder: your balance is 500 SYP. Thank you.');
      final arabic = buildDebtReminderText(
        template: '',
        name: 'أحمد',
        balance: '500 ل.س',
        language: 'ar',
      );
      expect(arabic, 'مرحباً أحمد، تذكير: رصيدكم المستحق 500 ل.س. شكراً لكم.');
    });

    test('the shop\'s own text is used as written', () {
      final text = buildDebtReminderText(
        template: 'يا {name}، عليك {balance} ({last_payment_date}) — {shop}',
        name: 'سارة',
        balance: '1,000',
        language: 'ar',
        shopName: 'المحل',
        lastPaymentAt: DateTime(2026, 1, 5),
      );
      expect(text, 'يا سارة، عليك 1,000 (2026/01/05) — المحل');
      // An empty placeholder leaves no empty brackets behind.
      expect(
        buildDebtReminderText(
          template: '{name}: {balance} ({last_payment_date})',
          name: 'Sara',
          balance: '1,000',
          language: 'en',
        ),
        'Sara: 1,000',
      );
    });
  });

  group('the order of the debtors list', () {
    Debtor debtor(
      int id,
      String name,
      int balance, {
      String? phone,
      int? limit,
      int overdue = 0,
      DateTime? oldest,
      DateTime? lastPayment,
    }) =>
        Debtor(
          customerId: id,
          name: name,
          nameNorm: name.toLowerCase(),
          phone: phone,
          phoneNorm: phone,
          isActive: true,
          creditLimitBaseMinor: limit,
          account: AccountSummary(
            balanceBaseMinor: balance,
            overdueBaseMinor: overdue,
            oldestUnpaidAt: oldest,
            lastPaymentAt: lastPayment,
          ),
        );

    final snapshot = DebtorsSnapshot(
      at: DateTime(2026, 11, 25),
      debtors: [
        debtor(1, 'Ahmad', 5000,
            phone: '0944111222',
            oldest: DateTime(2026, 10, 1),
            lastPayment: DateTime(2026, 11, 1)),
        debtor(2, 'Sara', 9000,
            limit: 8000,
            overdue: 4000,
            oldest: DateTime(2026, 6, 1),
            lastPayment: DateTime(2026, 9, 1)),
        debtor(3, 'Omar', 700, overdue: 700, oldest: DateTime(2026, 8, 1)),
        debtor(4, 'Layla', -3000, lastPayment: DateTime(2026, 11, 20)),
        debtor(5, 'Zaid', 5000, oldest: DateTime(2026, 10, 1)),
      ],
    );
    List<String> names(List<Debtor> list) => [for (final d in list) d.name];

    test('by amount: the largest first, ties by name', () {
      expect(names(arrangeDebtors(snapshot)), ['Sara', 'Ahmad', 'Zaid', 'Omar']);
    });

    test('by oldest debt: the longest unpaid first', () {
      expect(
        names(arrangeDebtors(snapshot, sort: DebtorSort.oldestDebt)),
        ['Sara', 'Omar', 'Ahmad', 'Zaid'],
      );
    });

    test('by last payment: never paid first, then the longest ago', () {
      expect(
        names(arrangeDebtors(snapshot, sort: DebtorSort.lastPayment)),
        ['Zaid', 'Omar', 'Sara', 'Ahmad'],
      );
    });

    test('the filters', () {
      expect(
        names(arrangeDebtors(snapshot, filter: DebtorFilter.overdue)),
        ['Sara', 'Omar'],
      );
      expect(
        names(arrangeDebtors(snapshot, filter: DebtorFilter.overLimit)),
        ['Sara'],
      );
      expect(
        names(arrangeDebtors(snapshot, filter: DebtorFilter.credit)),
        ['Layla'],
      );
    });

    test('the search: by name or by phone, in any digits', () {
      expect(names(arrangeDebtors(snapshot, query: 'sar')), ['Sara']);
      expect(names(arrangeDebtors(snapshot, query: '0944 111')), ['Ahmad']);
      expect(names(arrangeDebtors(snapshot, query: '٠٩٤٤١١١')), ['Ahmad']);
      expect(arrangeDebtors(snapshot, query: 'nobody'), isEmpty);
      // A search stays inside the filter.
      expect(
        arrangeDebtors(snapshot, query: 'ahmad', filter: DebtorFilter.overdue),
        isEmpty,
      );
    });

    test('the totals of a snapshot', () {
      expect(snapshot.totalOutstandingBaseMinor, 19700);
      expect(snapshot.totalCreditBaseMinor, 3000);
      expect(snapshot.owingCount, 4);
      expect(snapshot.overdueCount, 2);
    });
  });

  group('the numbers of the payment sheet', () {
    CartTotals totals({int total = 8000, String currency = 'SYP'}) {
      final ctx = CurrencyContext.of([syp, usd], baseCode: 'SYP');
      return computeCartTotals(
        const Cart().withInvoiceCurrency(currency).add(CartLine(
              name: 'Sugar',
              unitPriceMinor: total,
              priceCurrencyCode: currency,
              qtyThousandths: 1000,
            )),
        ctx,
      );
    }

    PaymentMath math({
      PayMode mode = PayMode.full,
      int balance = 0,
      int? limit,
      bool useCredit = false,
      int? paid,
      int total = 8000,
      String currency = 'SYP',
    }) =>
        PaymentMath(
          totals: totals(total: total, currency: currency),
          mode: mode,
          balanceBaseMinor: balance,
          limitBaseMinor: limit,
          useCredit: useCredit,
          partialPaidMinor: paid,
        );

    test('paid in full: everything now, nothing on the account', () {
      final m = math();
      expect(m.paidMinor, 8000);
      expect(m.remainingMinor, 0);
      expect(m.needsCustomer, isFalse);
      expect(m.overLimit, isFalse);
      final payment = m.payment(dueAt: DateTime(2026, 12, 1));
      expect(payment.paidMinor, 8000);
      expect(payment.creditUsedMinor, 0);
      expect(payment.dueAt, isNull, reason: 'nothing is due later');
    });

    test('partial: the rest becomes debt and needs a customer', () {
      final m = math(mode: PayMode.partial, paid: 3000, balance: 1000);
      expect(m.partialIsValid, isTrue);
      expect(m.paidMinor, 3000);
      expect(m.remainingMinor, 5000);
      expect(m.chargedBaseMinor, 5000);
      expect(m.newBalanceBaseMinor, 6000);
      expect(m.needsCustomer, isTrue);
      expect(m.payment(dueAt: DateTime(2026, 12, 1)).dueAt, DateTime(2026, 12, 1));
    });

    test('partial needs an amount strictly between nothing and everything',
        () {
      for (final paid in [null, 0, 8000, 9000]) {
        expect(math(mode: PayMode.partial, paid: paid).partialIsValid, isFalse,
            reason: '$paid');
      }
      expect(math(mode: PayMode.partial, paid: 1).partialIsValid, isTrue);
      expect(math(mode: PayMode.partial, paid: 7999).partialIsValid, isTrue);
    });

    test('on credit: all of it', () {
      final m = math(mode: PayMode.credit);
      expect(m.paidMinor, 0);
      expect(m.remainingMinor, 8000);
      expect(m.needsCustomer, isTrue);
    });

    test('the credit limit: at the limit is fine, one over is not; cash never '
        'trips it', () {
      expect(math(mode: PayMode.credit, balance: 2000, limit: 10000).overLimit,
          isFalse);
      expect(math(mode: PayMode.credit, balance: 2001, limit: 10000).overLimit,
          isTrue);
      expect(math(balance: 50000, limit: 10000).overLimit, isFalse);
      expect(math(mode: PayMode.credit, balance: 99999).overLimit, isFalse,
          reason: 'no limit set');
    });

    test('a credit balance pays part of the invoice', () {
      // The shop owes the customer 5,000.
      final unused = math(balance: -5000);
      expect(unused.creditAvailableMinor, 5000);
      expect(unused.creditUsedMinor, 0);
      expect(unused.paidMinor, 8000);

      final used = math(balance: -5000, useCredit: true);
      expect(used.creditUsedMinor, 5000);
      expect(used.dueNowMinor, 3000);
      expect(used.paidMinor, 3000);
      expect(used.remainingMinor, 0);
      expect(used.chargedBaseMinor, 5000);
      expect(used.newBalanceBaseMinor, 0);
      expect(used.needsCustomer, isTrue);

      // More credit than the invoice: only the invoice is taken from it.
      final plenty = math(balance: -20000, useCredit: true);
      expect(plenty.creditUsedMinor, 8000);
      expect(plenty.paidMinor, 0);
      expect(plenty.newBalanceBaseMinor, -12000);

      // Credit, and the rest on credit.
      final both = math(mode: PayMode.credit, balance: -5000, useCredit: true);
      expect(both.remainingMinor, 3000);
      expect(both.newBalanceBaseMinor, 3000);
      expect(both.payment().creditUsedMinor, 5000);
    });

    test('an invoice in another currency: the limit is judged in base', () {
      // 10.50 USD at 13,000: 4.00 paid, 6.50 USD = 84,500 SYP on credit.
      final m = math(
        mode: PayMode.partial,
        paid: 400,
        total: 1050,
        currency: 'USD',
        balance: 20000,
        limit: 100000,
      );
      expect(m.remainingMinor, 650);
      expect(m.chargedBaseMinor, 84500);
      expect(m.newBalanceBaseMinor, 104500);
      expect(m.overLimit, isTrue);
      // A credit balance of 26,000 SYP is 2.00 USD of this invoice.
      expect(
        math(total: 1050, currency: 'USD', balance: -26000)
            .creditAvailableMinor,
        200,
      );
    });

    test('exact rate fractions all the way: no double, one rounding', () {
      final ctx = CurrencyContext.of(
        [
          syp,
          usd.copyWithRate(const RateFraction(24691, 2)),
        ],
        baseCode: 'SYP',
      );
      final totals = computeCartTotals(
        const Cart().withInvoiceCurrency('USD').add(const CartLine(
              name: 'Oil',
              unitPriceMinor: 3,
              priceCurrencyCode: 'USD',
              qtyThousandths: 1000,
            )),
        ctx,
      );
      final m = PaymentMath(
        totals: totals,
        mode: PayMode.credit,
        balanceBaseMinor: 0,
        limitBaseMinor: null,
        useCredit: false,
        partialPaidMinor: null,
      );
      // 0.03 USD × 12,345.5 = 370.365 → 370.
      expect(m.chargedBaseMinor, 370);
    });
  });
}

extension on Currency {
  Currency copyWithRate(RateFraction rate) => Currency(
        code: code,
        nameAr: nameAr,
        nameEn: nameEn,
        symbol: symbol,
        decimalPlaces: decimalPlaces,
        rate: rate,
        rateUpdatedAt: rateUpdatedAt,
        sortOrder: sortOrder,
      );
}
