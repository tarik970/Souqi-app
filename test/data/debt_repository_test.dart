import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/counter_repository.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// The ledger itself: balances, running balances, statements, FIFO aging,
/// reversals, receipts, currencies — and the two things the database
/// refuses outright, editing and deleting an entry.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late DebtRepository debts;
  late int ahmad;

  final now = DateTime(2026, 11, 25, 12);
  DateTime daysAgo(int days) => DateTime(2026, 11, 25 - days, 10);

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    debts = DebtRepository(db);
    ahmad = await insertCustomer(db, name: 'Ahmad');
  });

  tearDown(() => appDb.close());

  Future<DebtEntry> pay(
    int amount, {
    int? customer,
    DateTime? at,
    PaymentMethod method = PaymentMethod.cash,
    String? note,
  }) =>
      debts.recordPayment(
        customerId: customer ?? ahmad,
        amountMinor: amount,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
        method: method,
        note: note,
        at: at,
      );

  Future<DebtEntry> owe(int amount, {int? customer, DateTime? at, DateTime? due}) =>
      debts.addManualDebt(
        customerId: customer ?? ahmad,
        amountBaseMinor: amount,
        at: at,
        dueAt: due,
      );

  group('balance', () {
    test('is zero for a customer with no entries', () async {
      expect(await debts.balanceOf(ahmad), 0);
      expect(await debts.hasEntries(), isFalse);
    });

    test('debts add, payments subtract', () async {
      await owe(10000, at: daysAgo(10));
      await owe(5000, at: daysAgo(5));
      await pay(4000, at: daysAgo(3));
      expect(await debts.balanceOf(ahmad), 11000);
      expect(await debts.hasEntries(), isTrue);
    });

    test('a payment larger than the debt leaves a credit balance', () async {
      await owe(3000, at: daysAgo(2));
      await pay(5000, at: daysAgo(1));
      expect(await debts.balanceOf(ahmad), -2000);
      final summary = await debts.accountSummary(ahmad, now: now);
      expect(summary.hasCredit, isTrue);
      expect(summary.creditBaseMinor, 2000);
      expect(summary.owes, isFalse);
      expect(summary.isOverdue, isFalse);
      expect(summary.aging.total, 0);
    });

    test('opening balances go both ways', () async {
      final other = await insertCustomer(db, name: 'Sara');
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 7000, at: daysAgo(40));
      await debts.addOpeningBalance(
        customerId: other,
        amountBaseMinor: 2500,
        customerOwes: false,
        at: daysAgo(40),
      );
      expect(await debts.balanceOf(ahmad), 7000);
      expect(await debts.balanceOf(other), -2500);
      // A credit has no due date; a debit gets the default 30 days.
      final credit = (await debts.ledger(other)).single.entry;
      expect(credit.dueAt, isNull);
      expect(credit.direction, -1);
      final debit = (await debts.ledger(ahmad)).single.entry;
      expect(debit.dueAt!.toLocal(), DateTime(2026, 11, 25 - 40 + 30));
    });

    test('adjustments go both ways, need a reason and are logged', () async {
      await owe(10000, at: daysAgo(3));
      await debts.addAdjustment(
        customerId: ahmad,
        amountBaseMinor: 1500,
        increasesDebt: false,
        reason: 'price mistake',
      );
      expect(await debts.balanceOf(ahmad), 8500);
      await debts.addAdjustment(
        customerId: ahmad,
        amountBaseMinor: 200,
        increasesDebt: true,
        reason: 'delivery',
      );
      expect(await debts.balanceOf(ahmad), 8700);
      expect(
        () => debts.addAdjustment(
          customerId: ahmad,
          amountBaseMinor: 1,
          increasesDebt: true,
          reason: '  ',
        ),
        throwsArgumentError,
      );
      final log = await AuditRepository(db).list();
      expect(log.map((e) => e.action),
          ['DEBT_ADJUSTMENT', 'DEBT_ADJUSTMENT']);
      expect(log.last.details['amount'], -1500);
      expect(log.last.details['reason'], 'price mistake');
      expect(log.last.details['customer'], 'Ahmad');
      expect(log.first.details['amount'], 200);
    });

    test('an amount must be greater than zero', () async {
      expect(() => owe(0), throwsArgumentError);
      expect(() => pay(0), throwsArgumentError);
      expect(() => pay(-5), throwsArgumentError);
      expect(await debts.hasEntries(), isFalse);
    });

    test('the due date: explicit, else the customer\'s days, else the '
        'setting, else 30', () async {
      final at = DateTime(2026, 11, 1, 23, 50);
      expect((await owe(1, at: at)).dueAt!.toLocal(), DateTime(2026, 12, 1));
      await db.insert('settings', {
        'key': 'debt_default_due_days',
        'value': '7',
        'updated_at': 1,
      });
      expect((await owe(1, at: at)).dueAt!.toLocal(), DateTime(2026, 11, 8));
      await db.update('customers', {'default_due_days': 14},
          where: 'id = ?', whereArgs: [ahmad]);
      expect((await owe(1, at: at)).dueAt!.toLocal(), DateTime(2026, 11, 15));
      expect(await debts.defaultDueDate(ahmad, at), DateTime(2026, 11, 15));
      final explicit = await owe(1, at: at, due: DateTime(2026, 11, 3));
      expect(explicit.dueAt!.toLocal(), DateTime(2026, 11, 3));
      // A payment is never "due".
      expect((await pay(1)).dueAt, isNull);
    });
  });

  group('running balance', () {
    test('the ledger is newest first, each line with the balance after it',
        () async {
      await owe(10000, at: daysAgo(10));
      await pay(4000, at: daysAgo(8));
      await owe(2500, at: daysAgo(5));
      await pay(8500, at: daysAgo(1));
      final lines = await debts.ledger(ahmad);
      expect(lines.map((l) => l.entry.signedBaseMinor),
          [-8500, 2500, -4000, 10000]);
      expect(lines.map((l) => l.balanceAfterBaseMinor), [0, 8500, 6000, 10000]);
    });

    test('a limit or a date range still gives true balances', () async {
      await owe(10000, at: daysAgo(10));
      await pay(4000, at: daysAgo(8));
      await owe(2500, at: daysAgo(5));
      await pay(1000, at: daysAgo(1));
      final newest = await debts.ledger(ahmad, limit: 2);
      expect(newest.map((l) => l.balanceAfterBaseMinor), [7500, 8500]);
      final middle = await debts.ledger(
        ahmad,
        from: DateTime(2026, 11, 25 - 9),
        to: DateTime(2026, 11, 25 - 4),
      );
      expect(middle.map((l) => l.entry.signedBaseMinor), [2500, -4000]);
      expect(middle.map((l) => l.balanceAfterBaseMinor), [8500, 6000]);
    });

    test('a backdated entry takes its place by date, and later balances '
        'follow', () async {
      await owe(1000, at: daysAgo(5));
      await pay(400, at: daysAgo(2));
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 9000, at: daysAgo(60));
      final lines = await debts.ledger(ahmad);
      expect(lines.map((l) => l.entry.type), [
        DebtEntryType.payment,
        DebtEntryType.manualDebt,
        DebtEntryType.openingBalance,
      ]);
      expect(lines.map((l) => l.balanceAfterBaseMinor), [9600, 10000, 9000]);
    });

    test('two entries in the same millisecond keep the order they were '
        'written in', () async {
      final at = daysAgo(1);
      await owe(100, at: at);
      await pay(30, at: at);
      await owe(7, at: at);
      final lines = await debts.ledger(ahmad);
      expect(lines.map((l) => l.balanceAfterBaseMinor), [77, 70, 100]);
    });
  });

  group('statement', () {
    setUp(() async {
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 20000, at: daysAgo(100));
      await pay(5000, at: daysAgo(70));
      await owe(8000, at: daysAgo(20));
      await pay(3000, at: daysAgo(10));
      await owe(1000, at: daysAgo(2));
    });

    test('opening balance, running balance, totals and closing balance',
        () async {
      final statement = await debts.statement(
        ahmad,
        from: DateTime(2026, 11, 25 - 30),
        to: DateTime(2026, 11, 26),
      );
      expect(statement.openingBalanceBaseMinor, 15000);
      expect(statement.lines.map((l) => l.entry.signedBaseMinor),
          [8000, -3000, 1000]);
      expect(statement.lines.map((l) => l.balanceAfterBaseMinor),
          [23000, 20000, 21000]);
      expect(statement.totalDebitsBaseMinor, 9000);
      expect(statement.totalCreditsBaseMinor, 3000);
      expect(statement.closingBalanceBaseMinor, 21000);
      expect(statement.closingBalanceBaseMinor, await debts.balanceOf(ahmad));
    });

    test('an empty range closes on its opening balance', () async {
      final statement = await debts.statement(
        ahmad,
        from: DateTime(2026, 11, 25 - 60),
        to: DateTime(2026, 11, 25 - 50),
      );
      expect(statement.lines, isEmpty);
      expect(statement.openingBalanceBaseMinor, 15000);
      expect(statement.closingBalanceBaseMinor, 15000);
      expect(statement.totalDebitsBaseMinor, 0);
    });

    test('the end of the range is exclusive; no range is the whole account',
        () async {
      final upTo = await debts.statement(ahmad, to: DateTime(2026, 11, 25 - 10));
      expect(upTo.openingBalanceBaseMinor, 0);
      expect(upTo.closingBalanceBaseMinor, 23000);
      final all = await debts.statement(ahmad);
      expect(all.lines, hasLength(5));
      expect(all.closingBalanceBaseMinor, 21000);
      expect(all.totalDebitsBaseMinor - all.totalCreditsBaseMinor, 21000);
    });
  });

  group('reversal', () {
    test('cancels the entry with a new one, touches nothing, logs the reason',
        () async {
      await owe(10000, at: daysAgo(4));
      final payment = await pay(6000, at: daysAgo(2), note: 'cash');
      expect(await debts.balanceOf(ahmad), 4000);

      final before = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [payment.id]))
          .single;
      final reversal = await debts.reverse(payment.id, reason: 'wrong customer');
      expect(await debts.balanceOf(ahmad), 10000);
      expect(reversal.type, DebtEntryType.reversal);
      expect(reversal.direction, 1);
      expect(reversal.amountBaseMinor, 6000);
      expect(reversal.reversesId, payment.id);
      expect(reversal.note, 'wrong customer');
      expect(reversal.reversedType, DebtEntryType.payment);
      expect(reversal.reversedReceiptNo, payment.receiptNo);
      expect(reversal.receiptNo, isNull);

      // The cancelled row is byte for byte what it was.
      final after = (await db.query('debt_transactions',
              where: 'id = ?', whereArgs: [payment.id]))
          .single;
      expect(after, before);

      // …and the ledger shows it struck through, linked to its reversal.
      final lines = await debts.ledger(ahmad);
      final cancelled = lines.firstWhere((l) => l.entry.id == payment.id).entry;
      expect(cancelled.isReversed, isTrue);
      expect(cancelled.reversedById, reversal.id);
      expect(cancelled.isEffective, isFalse);
      expect(lines.first.entry.id, reversal.id);
      expect(lines.first.entry.isEffective, isFalse);

      final log = (await AuditRepository(db).list()).single;
      expect(log.action, 'DEBT_REVERSAL');
      expect(log.details['reason'], 'wrong customer');
      expect(log.details['customer'], 'Ahmad');
      expect(log.details['entry'], 'PAYMENT');
      expect(log.details['amount'], -6000);
      expect(log.details['receipt_no'], payment.receiptNo);
    });

    test('nothing is reversed twice, and a reversal cannot be reversed',
        () async {
      final debt = await owe(500);
      final reversal = await debts.reverse(debt.id, reason: 'typo');
      expect(() => debts.reverse(debt.id, reason: 'again'),
          throwsA(isA<NotReversibleException>()));
      expect(() => debts.reverse(reversal.id, reason: 'undo'),
          throwsA(isA<NotReversibleException>()));
      expect(() => debts.reverse(9999, reason: 'none'),
          throwsA(isA<NotReversibleException>()));
      expect(await debts.balanceOf(ahmad), 0);
      expect(await db.query('debt_transactions'), hasLength(2));
      expect(await AuditRepository(db).list(), hasLength(1));
    });

    test('a reason is required, and without one nothing is written', () async {
      final debt = await owe(500);
      expect(() => debts.reverse(debt.id, reason: ' '), throwsArgumentError);
      expect(await db.query('debt_transactions'), hasLength(1));
      expect(await AuditRepository(db).list(), isEmpty);
    });

    test('a reversed payment is not the "last payment", a reversed debt is '
        'not aged', () async {
      await owe(10000, at: daysAgo(50));
      final old = await owe(7000, at: daysAgo(100));
      await pay(2000, at: daysAgo(40));
      final wrong = await pay(3000, at: daysAgo(5));
      await debts.reverse(wrong.id, reason: 'bounced');
      await debts.reverse(old.id, reason: 'not his');

      final summary = await debts.accountSummary(ahmad, now: now);
      expect(summary.balanceBaseMinor, 8000);
      expect(summary.lastPaymentAt, daysAgo(40).toUtc());
      expect(summary.oldestUnpaidAt, daysAgo(50).toUtc());
      expect(summary.aging, const AgingSummary([0, 8000, 0, 0]));

      final debtor = (await debts.debtors(now: now)).debtors.single;
      expect(debtor.account.balanceBaseMinor, 8000);
      expect(debtor.account.lastPaymentAt, daysAgo(40).toUtc());
      expect(debtor.account.oldestUnpaidAt, daysAgo(50).toUtc());
      expect(debtor.account.aging, const AgingSummary([0, 8000, 0, 0]));
    });
  });

  group('the database refuses to edit or delete an entry', () {
    late int id;

    setUp(() async => id = (await owe(1000)).id);

    test('no column can be changed', () async {
      for (final change in <Map<String, Object?>>[
        {'amount_base_minor': 1},
        {'direction': -1},
        {'note': 'edited'},
        {'created_at': 5},
        {'customer_id': await insertCustomer(db, name: 'Other')},
        {'type': 'PAYMENT', 'direction': -1},
        {'due_at': null},
        {'invoice_no': 7},
      ]) {
        await expectLater(
          db.update('debt_transactions', change,
              where: 'id = ?', whereArgs: [id]),
          throwsA(isA<DatabaseException>()),
          reason: '$change',
        );
      }
      expect(await debts.balanceOf(ahmad), 1000);
    });

    test('no entry can be deleted', () async {
      await expectLater(
        db.delete('debt_transactions', where: 'id = ?', whereArgs: [id]),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete('debt_transactions'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('debt_transactions'), hasLength(1));
    });

    test('a customer with entries cannot be deleted', () async {
      await expectLater(
        db.delete('customers', where: 'id = ?', whereArgs: [ahmad]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('the schema itself rejects impossible entries', () async {
      Future<int> raw(Map<String, Object?> row) => db.insert(
            'debt_transactions',
            {
              'customer_id': ahmad,
              'created_at': 1,
              'recorded_at': 1,
              ...row,
            },
          );
      for (final bad in <Map<String, Object?>>[
        {'type': 'DEBT', 'direction': -1, 'amount_base_minor': 5},
        {'type': 'PAYMENT', 'direction': 1, 'amount_base_minor': 5},
        {'type': 'DEBT', 'direction': 1, 'amount_base_minor': 0},
        {'type': 'DEBT', 'direction': 1, 'amount_base_minor': -5},
        {'type': 'REFUND', 'direction': 1, 'amount_base_minor': 5},
        {'type': 'DEBT', 'direction': 2, 'amount_base_minor': 5},
        // A reversal must point at an entry; nothing else may.
        {'type': 'REVERSAL', 'direction': 1, 'amount_base_minor': 5},
        {
          'type': 'DEBT',
          'direction': 1,
          'amount_base_minor': 5,
          'reverses_id': id,
        },
        // Only a payment has a receipt.
        {
          'type': 'DEBT',
          'direction': 1,
          'amount_base_minor': 5,
          'receipt_no': 1,
        },
        {
          'type': 'PAYMENT',
          'direction': -1,
          'amount_base_minor': 5,
          'payment_method': 'CHEQUE',
        },
      ]) {
        await expectLater(raw(bad), throwsA(isA<DatabaseException>()),
            reason: '$bad');
      }
    });
  });

  group('receipts', () {
    test('numbers are sequential across customers', () async {
      final sara = await insertCustomer(db, name: 'Sara');
      final first = await pay(100);
      final second = await pay(100, customer: sara);
      final third = await pay(100);
      expect([first.receiptNo, second.receiptNo, third.receiptNo], [1, 2, 3]);
      expect((await debts.entryByReceiptNo(2))!.customerId, sara);
      expect(await debts.entryByReceiptNo(9), isNull);
    });

    test('a number is never reused: not after a reversal, not after a failed '
        'payment', () async {
      final first = await pay(100);
      await debts.reverse(first.id, reason: 'mistake');
      expect((await pay(100)).receiptNo, 2);

      // A payment that fails inside its transaction (no such customer) rolls
      // its number back with it — and the next one continues the sequence.
      await expectLater(pay(100, customer: 987654),
          throwsA(isA<DatabaseException>()));
      expect((await pay(100)).receiptNo, 3);
      final counter = (await db.query('counters',
              where: 'name = ?', whereArgs: [CounterRepository.receiptNo]))
          .single;
      expect(counter['value'], 3);

      // The unique index is the last line of defence.
      await expectLater(
        db.insert('debt_transactions', {
          'customer_id': ahmad,
          'type': 'PAYMENT',
          'direction': -1,
          'amount_base_minor': 5,
          'receipt_no': 3,
          'created_at': 1,
          'recorded_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a receipt keeps the balance before and after it', () async {
      await owe(10000, at: daysAgo(3));
      final payment = await pay(4000, method: PaymentMethod.transfer);
      expect(payment.balanceBeforeBaseMinor, 10000);
      expect(payment.balanceAfterBaseMinor, 6000);
      expect(payment.paymentMethod, PaymentMethod.transfer);
      // Entered later, dated earlier: the receipt still says what it said.
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 500, at: daysAgo(30));
      final again = (await debts.entryById(payment.id))!;
      expect(again.balanceBeforeBaseMinor, 10000);
      expect(again.balanceAfterBaseMinor, 6000);
    });
  });

  group('payment in another currency', () {
    Future<DebtEntry> payUsd(int cents, RateFraction rate) =>
        debts.recordPayment(
          customerId: ahmad,
          amountMinor: cents,
          currencyCode: 'USD',
          currencyDecimals: 2,
          rate: rate,
          baseCode: 'SYP',
          baseDecimals: 0,
        );

    test('is converted to base with the rate entered, both snapshotted',
        () async {
      await owe(200000);
      final payment = await payUsd(1050, const RateFraction(13000, 1));
      expect(payment.amountBaseMinor, 136500);
      expect(payment.origAmountMinor, 1050);
      expect(payment.origCurrencyCode, 'USD');
      expect(payment.origRate, const RateFraction(13000, 1));
      expect(await debts.balanceOf(ahmad), 63500);
    });

    test('rounds half-up once, with the exact fraction', () async {
      // 0.01 USD at 12345.5 SYP = 123.455 → 123; 0.03 USD = 370.365 → 370.
      expect((await payUsd(1, const RateFraction(24691, 2))).amountBaseMinor, 123);
      expect((await payUsd(3, const RateFraction(24691, 2))).amountBaseMinor, 370);
      // 0.05 USD at 12350 = 617.5 → 618 (half goes up).
      expect((await payUsd(5, const RateFraction(12350, 1))).amountBaseMinor, 618);
    });

    test('a later rate change does not move an old payment', () async {
      final payment = await payUsd(1000, const RateFraction(13000, 1));
      await db.update('currencies', {'rate_num': 15000, 'rate_den': 1},
          where: 'code = ?', whereArgs: ['USD']);
      final again = (await debts.entryById(payment.id))!;
      expect(again.amountBaseMinor, 130000);
      expect(again.origRate, const RateFraction(13000, 1));
      expect(await debts.balanceOf(ahmad), -130000);
    });

    test('the base currency stores no original amount', () async {
      final payment = await pay(700);
      expect(payment.origAmountMinor, isNull);
      expect(payment.origCurrencyCode, isNull);
      expect(payment.origRate, isNull);
    });

    test('an amount worth nothing in base is refused', () async {
      // 0.01 of a currency worth 1/1000 of the base unit rounds to zero.
      expect(() => payUsd(1, const RateFraction(1, 1000)), throwsArgumentError);
      expect(await debts.hasEntries(), isFalse);
    });

    test('a reversal carries the original amount and rate', () async {
      final payment = await payUsd(1050, const RateFraction(13000, 1));
      final reversal = await debts.reverse(payment.id, reason: 'fake note');
      expect(reversal.origAmountMinor, 1050);
      expect(reversal.origCurrencyCode, 'USD');
      expect(reversal.origRate, const RateFraction(13000, 1));
      expect(await debts.balanceOf(ahmad), 0);
    });
  });

  group('FIFO aging (the pure function)', () {
    FifoDebit debit(int amount, int ageDays, {int? dueInDays}) => FifoDebit(
          amountBaseMinor: amount,
          createdAt: daysAgo(ageDays),
          dueAt: dueInDays == null
              ? null
              : DateTime(2026, 11, 25 + dueInDays),
        );

    test('payments pay off the oldest debts first', () {
      final unpaid = fifoUnpaid(
        [debit(1000, 100), debit(2000, 50), debit(3000, 10)],
        2500,
      );
      expect(unpaid.map((u) => u.unpaidBaseMinor), [500, 3000]);
      expect(unpaid.first.debit.createdAt, daysAgo(50));
      expect(agingOf(unpaid, now), const AgingSummary([3000, 500, 0, 0]));
    });

    test('nothing paid, everything paid, overpaid', () {
      final debits = [debit(1000, 95), debit(2000, 61), debit(4000, 31)];
      expect(agingOf(fifoUnpaid(debits, 0), now),
          const AgingSummary([0, 4000, 2000, 1000]));
      expect(fifoUnpaid(debits, 7000), isEmpty);
      expect(fifoUnpaid(debits, 9000), isEmpty);
      expect(fifoUnpaid(const [], 100), isEmpty);
    });

    test('bucket edges: 30, 31, 60, 61, 90, 91 days', () {
      expect(AgingBucket.forAgeDays(0), AgingBucket.current);
      expect(AgingBucket.forAgeDays(30), AgingBucket.current);
      expect(AgingBucket.forAgeDays(31), AgingBucket.days31to60);
      expect(AgingBucket.forAgeDays(60), AgingBucket.days31to60);
      expect(AgingBucket.forAgeDays(61), AgingBucket.days61to90);
      expect(AgingBucket.forAgeDays(90), AgingBucket.days61to90);
      expect(AgingBucket.forAgeDays(91), AgingBucket.over90);
      // A debt dated in the future is simply current.
      expect(AgingBucket.forAgeDays(-3), AgingBucket.current);
    });

    test('the clock that buckets by comparing instants agrees with counting '
        'calendar days, minute by minute around every edge', () {
      final clock = AgingClock(now);
      for (final days in [0, 1, 29, 30, 31, 59, 60, 61, 89, 90, 91, 200]) {
        for (final at in [
          DateTime(2026, 11, 25 - days),
          DateTime(2026, 11, 25 - days, 0, 1),
          DateTime(2026, 11, 25 - days, 12),
          DateTime(2026, 11, 25 - days, 23, 59),
        ]) {
          expect(
            clock.bucketOf(at.toUtc()),
            AgingBucket.forAgeDays(ageInDays(at, now)),
            reason: '$at',
          );
        }
      }
      expect(clock.isOverdue(null), isFalse);
      expect(clock.isOverdue(DateTime(2026, 11, 25)), isFalse);
      expect(clock.isOverdue(DateTime(2026, 11, 24, 23, 59)), isTrue);
      expect(clock.isOverdue(DateTime(2026, 11, 26)), isFalse);
    });

    test('age counts calendar days, not 24-hour blocks', () {
      expect(ageInDays(DateTime(2026, 11, 24, 23, 59), DateTime(2026, 11, 25, 0, 1)), 1);
      expect(ageInDays(DateTime(2026, 11, 25, 0, 1), DateTime(2026, 11, 25, 23, 59)), 0);
    });
  });

  group('debtors', () {
    test('lists every non-zero balance with its FIFO view', () async {
      final sara = await insertCustomer(db, name: 'Sara');
      final omar = await insertCustomer(db, name: 'Omar');
      final paid = await insertCustomer(db, name: 'Paid Up');
      await insertCustomer(db, name: 'Never Owed');
      await db.update('customers', {'credit_limit_base_minor': 5000},
          where: 'id = ?', whereArgs: [ahmad]);

      await owe(1000, at: daysAgo(100)); // paid off by FIFO
      await owe(2000, at: daysAgo(50)); // 500 left
      await owe(3000, at: daysAgo(10)); // all left
      await pay(2500, at: daysAgo(7));
      await owe(4000, customer: sara, at: daysAgo(95));
      await pay(9000, customer: omar, at: daysAgo(1));
      await owe(700, customer: paid, at: daysAgo(3));
      await pay(700, customer: paid, at: daysAgo(2));

      final snapshot = await debts.debtors(now: now);
      final byName = {for (final d in snapshot.debtors) d.name: d};
      expect(byName.keys.toSet(), {'Ahmad', 'Sara', 'Omar'});

      final a = byName['Ahmad']!;
      expect(a.balanceBaseMinor, 3500);
      expect(a.account.oldestUnpaidAt, daysAgo(50).toUtc());
      expect(a.account.lastPaymentAt, daysAgo(7).toUtc());
      expect(a.account.aging, const AgingSummary([3000, 500, 0, 0]));
      // Due after 30 days: the 50-day-old debt is late, the 10-day one not.
      expect(a.account.overdueBaseMinor, 500);
      expect(a.account.isOverdue, isTrue);
      expect(a.creditLimitBaseMinor, 5000);
      expect(a.isOverLimit, isFalse);

      final s = byName['Sara']!;
      expect(s.account.aging, const AgingSummary([0, 0, 0, 4000]));
      expect(s.account.overdueBaseMinor, 4000);
      expect(s.account.lastPaymentAt, isNull);

      final o = byName['Omar']!;
      expect(o.balanceBaseMinor, -9000);
      expect(o.account.hasCredit, isTrue);
      expect(o.account.oldestUnpaidAt, isNull);
      expect(o.account.isOverdue, isFalse);

      expect(snapshot.totalOutstandingBaseMinor, 7500);
      expect(snapshot.totalCreditBaseMinor, 9000);
      expect(snapshot.owingCount, 2);
      expect(snapshot.overdueCount, 2);
      expect(snapshot.aging, const AgingSummary([3000, 500, 0, 4000]));
      expect(snapshot.aging.total, snapshot.totalOutstandingBaseMinor);
    });

    test('an empty ledger is an empty snapshot', () async {
      final snapshot = await debts.debtors(now: now);
      expect(snapshot.debtors, isEmpty);
      expect(snapshot.totalOutstandingBaseMinor, 0);
      expect(snapshot.overdueCount, 0);
    });

    test('over the limit is flagged', () async {
      await db.update('customers', {'credit_limit_base_minor': 5000},
          where: 'id = ?', whereArgs: [ahmad]);
      await owe(5000);
      expect((await debts.debtors(now: now)).debtors.single.isOverLimit, isFalse);
      await owe(1);
      expect((await debts.debtors(now: now)).debtors.single.isOverLimit, isTrue);
    });

    test('a debt due today is not overdue; one due yesterday is', () async {
      await owe(100, at: daysAgo(5), due: DateTime(2026, 11, 25));
      expect((await debts.debtors(now: now)).overdueCount, 0);
      expect((await debts.accountSummary(ahmad, now: now)).isOverdue, isFalse);
      await owe(40, at: daysAgo(4), due: DateTime(2026, 11, 24));
      final debtor = (await debts.debtors(now: now)).debtors.single;
      expect(debtor.account.overdueBaseMinor, 40);
      expect((await debts.accountSummary(ahmad, now: now)).overdueBaseMinor, 40);
    });

    test('the SQL aging agrees with the Dart FIFO on a thousand random '
        'entries', () async {
      final random = Random(20261125);
      final customers = [
        ahmad,
        for (var i = 0; i < 24; i++) await insertCustomer(db, name: 'C$i'),
      ];
      final reversible = <int>[];
      for (var i = 0; i < 1000; i++) {
        final customer = customers[random.nextInt(customers.length)];
        final at = now.subtract(Duration(
          days: random.nextInt(140),
          minutes: random.nextInt(600),
        ));
        final amount = 100 + random.nextInt(9000);
        final DebtEntry entry;
        switch (random.nextInt(10)) {
          case 0:
            entry = await debts.addOpeningBalance(
              customerId: customer,
              amountBaseMinor: amount,
              customerOwes: random.nextBool(),
              at: at,
            );
          case 1 || 2 || 3:
            entry = await pay(amount, customer: customer, at: at);
          default:
            entry = await owe(amount, customer: customer, at: at);
        }
        if (random.nextInt(12) == 0) reversible.add(entry.id);
      }
      for (final id in reversible) {
        await debts.reverse(id, reason: 'test');
      }

      final snapshot = await debts.debtors(now: now);
      final byId = {for (final d in snapshot.debtors) d.customerId: d};
      var owing = 0;
      for (final customer in customers) {
        final expected = await debts.accountSummary(customer, now: now);
        final actual = byId[customer]?.account;
        if (expected.balanceBaseMinor == 0) {
          expect(actual, isNull, reason: 'customer $customer');
          continue;
        }
        expect(actual, isNotNull, reason: 'customer $customer');
        expect(actual!.balanceBaseMinor, expected.balanceBaseMinor);
        expect(actual.lastPaymentAt, expected.lastPaymentAt);
        expect(actual.oldestUnpaidAt, expected.oldestUnpaidAt,
            reason: 'customer $customer');
        expect(actual.overdueBaseMinor, expected.overdueBaseMinor);
        expect(actual.aging, expected.aging, reason: 'customer $customer');
        if (expected.owes) {
          owing++;
          // What is unpaid adds up to exactly what is owed.
          expect(actual.aging.total, expected.balanceBaseMinor);
        }
      }
      expect(owing, greaterThan(5));
    });
  });

  group('opening balances with customers made on the fly', () {
    test('a new name creates the customer and the entry together', () async {
      final result = await debts.addOpeningBalanceFor(const OpeningBalanceDraft(
        name: ' خالد النجار ',
        phone: '0944 123 456',
        amountBaseMinor: 15000,
      ));
      expect(result.createdCustomer, isTrue);
      expect(result.customerName, 'خالد النجار');
      final customer =
          (await CustomerRepository(db).getById(result.customerId))!;
      expect(customer.phone, '0944 123 456');
      expect(await debts.balanceOf(result.customerId), 15000);
      expect(result.entry.type, DebtEntryType.openingBalance);
    });

    test('the same name is the same customer (the duplicate guard)', () async {
      final first = await debts.addOpeningBalanceFor(
          const OpeningBalanceDraft(name: 'أحمد الحسن', amountBaseMinor: 1000));
      // Another spelling of the same name, now with a phone.
      final second = await debts.addOpeningBalanceFor(const OpeningBalanceDraft(
        name: 'احمد  الحسن',
        phone: '0955 111 222',
        amountBaseMinor: 500,
      ));
      expect(second.createdCustomer, isFalse);
      expect(second.customerId, first.customerId);
      expect(await debts.balanceOf(first.customerId), 1500);
      expect(
        await db.query('customers',
            where: 'name_norm = ?', whereArgs: ['احمد حسن']),
        hasLength(1),
      );
    });

    test('the same name with a different phone is somebody else', () async {
      final first = await debts.addOpeningBalanceFor(const OpeningBalanceDraft(
          name: 'Omar', phone: '0944000111', amountBaseMinor: 1000));
      final second = await debts.addOpeningBalanceFor(const OpeningBalanceDraft(
          name: 'omar', phone: '0944000222', amountBaseMinor: 2000));
      expect(second.createdCustomer, isTrue);
      expect(second.customerId, isNot(first.customerId));
      // …and the phone written another way is the same phone.
      final third = await debts.addOpeningBalanceFor(const OpeningBalanceDraft(
          name: 'OMAR', phone: '٠٩٤٤ ٠٠٠ ١١١', amountBaseMinor: 1));
      expect(third.customerId, first.customerId);
    });

    test('a picked customer is used as is; a deactivated one comes back',
        () async {
      await CustomerRepository(db).setActive(ahmad, false);
      final result = await debts.addOpeningBalanceFor(OpeningBalanceDraft(
        customerId: ahmad,
        name: 'ignored',
        amountBaseMinor: 300,
        customerOwes: false,
        date: daysAgo(200),
      ));
      expect(result.customerId, ahmad);
      expect(result.customerName, 'Ahmad');
      expect(result.createdCustomer, isFalse);
      expect(await debts.balanceOf(ahmad), -300);
      expect(result.entry.createdAt, daysAgo(200).toUtc());
      expect((await CustomerRepository(db).getById(ahmad))!.isActive, isTrue);
    });

    test('a bad row creates nothing: no customer without their balance',
        () async {
      final before = await db.query('customers');
      await expectLater(
        debts.addOpeningBalanceFor(
            const OpeningBalanceDraft(name: 'Nobody', amountBaseMinor: 0)),
        throwsArgumentError,
      );
      await expectLater(
        debts.addOpeningBalanceFor(
            const OpeningBalanceDraft(name: '  ', amountBaseMinor: 10)),
        throwsArgumentError,
      );
      expect(await db.query('customers'), hasLength(before.length));
      expect(await debts.hasEntries(), isFalse);
    });
  });

  group('statistics', () {
    test('new debt, collected, collection rate, top debtors, aging', () async {
      final sara = await insertCustomer(db, name: 'Sara');
      // Before the period.
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 10000, at: daysAgo(40));
      await pay(2000, at: daysAgo(35));
      // In the period (the last 7 days).
      await owe(5000, at: daysAgo(6));
      await owe(3000, customer: sara, at: daysAgo(5));
      await pay(4000, at: daysAgo(4));
      final bounced = await pay(1000, customer: sara, at: daysAgo(3));
      await debts.reverse(bounced.id, reason: 'bounced');
      final mistake = await owe(999, customer: sara, at: daysAgo(2));
      await debts.reverse(mistake.id, reason: 'mistake');

      final stats = await debts.stats(
        from: DateTime(2026, 11, 25 - 7),
        to: DateTime(2026, 11, 26),
        now: now,
      );
      expect(stats.owedAtStartBaseMinor, 8000);
      expect(stats.newDebtBaseMinor, 8000);
      expect(stats.collectedBaseMinor, 4000);
      expect(stats.outstandingBaseMinor, 12000);
      // 4000 collected of 8000 owed + 8000 new = 25%.
      expect(stats.collectionRateBasisPoints, 2500);
      expect(stats.topDebtors.map((d) => d.name), ['Ahmad', 'Sara']);
      expect(stats.topDebtors.first.balanceBaseMinor, 9000);
      expect(stats.aging.total, 12000);
    });

    test('opening balances are not new debt but can be collected', () async {
      await debts.addOpeningBalance(
          customerId: ahmad, amountBaseMinor: 10000, at: daysAgo(2));
      await pay(2500, at: daysAgo(1));
      final stats = await debts.stats(
        from: DateTime(2026, 11, 25 - 7),
        to: DateTime(2026, 11, 26),
        now: now,
      );
      expect(stats.newDebtBaseMinor, 0);
      expect(stats.debitsBaseMinor, 10000);
      expect(stats.collectionRateBasisPoints, 2500);
    });

    test('nothing to collect: no rate; never above 100%', () async {
      var stats = await debts.stats(
          from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 26), now: now);
      expect(stats.collectionRateBasisPoints, isNull);
      expect(stats.topDebtors, isEmpty);
      await owe(100, at: daysAgo(3));
      await pay(500, at: daysAgo(2));
      stats = await debts.stats(
          from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 26), now: now);
      expect(stats.collectionRateBasisPoints, 10000);
      expect(stats.outstandingBaseMinor, 0);
    });

    test('only the ten largest balances are listed', () async {
      for (var i = 0; i < 14; i++) {
        final id = await insertCustomer(db, name: 'D$i');
        await owe(1000 + i, customer: id);
      }
      final stats = await debts.stats(
          from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 26), now: now);
      expect(stats.topDebtors, hasLength(10));
      expect(stats.topDebtors.first.name, 'D13');
      expect(stats.topDebtors.last.name, 'D4');
    });
  });
}
