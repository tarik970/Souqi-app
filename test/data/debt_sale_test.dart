import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

Currency _currency(String code,
        {int decimals = 0, RateFraction rate = RateFraction.one}) =>
    Currency(
      code: code,
      nameAr: code,
      nameEn: code,
      decimalPlaces: decimals,
      rate: rate,
      rateUpdatedAt: DateTime.utc(2026),
    );

/// A sale that goes (partly) on credit: the invoice, its items, the card
/// codes it hands out, the renewal dates and the ledger entry all land in
/// ONE transaction — or none of them does.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late Database db;
  late InvoiceRepository invoices;
  late DebtRepository debts;
  late CodeCipher cipher;
  late int ahmad;
  late int sugarId;

  final ctx = CurrencyContext.of(
    [
      _currency('SYP'),
      _currency('USD', decimals: 2, rate: const RateFraction(13000, 1)),
    ],
    baseCode: 'SYP',
  );
  final saleTime = DateTime(2026, 11, 25, 12);

  setUp(() async {
    database = await openTestDb();
    db = database.db;
    await db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
    cipher = CodeCipher(InMemoryKeyStore());
    invoices = InvoiceRepository(db, codeCipher: cipher);
    debts = DebtRepository(db);
    ahmad = await CustomerRepository(db)
        .insert(const Customer(name: 'Ahmad', phone: '0944 111 222'));
    sugarId = await insertProduct(db, name: 'Sugar');
  });

  tearDown(() => database.close());

  /// A draft worth [total] in [currency] (one line of sugar).
  Invoice draft({
    int total = 8000,
    String currency = 'SYP',
    int? customerId,
    int? accountId,
    List<CartLine>? lines,
  }) {
    var cart = const Cart().withInvoiceCurrency(currency);
    for (final line in lines ??
        [
          CartLine(
            productId: sugarId,
            name: 'Sugar',
            unitPriceMinor: total,
            priceCurrencyCode: currency,
            qtyThousandths: 1000,
          ),
        ]) {
      cart = cart.add(line);
    }
    return Invoice.fromCart(
      cart: cart,
      ctx: ctx,
      createdAt: saleTime,
      customerId: customerId,
      customerName: customerId == null ? null : 'Ahmad',
      customerPhone: customerId == null ? null : '0944 111 222',
      accountId: accountId,
      accountNumber: accountId == null ? null : '0011',
    );
  }

  Future<Map<String, int>> counts() async => {
        for (final table in [
          'invoices',
          'invoice_items',
          'debt_transactions',
          'audit_log',
          'products',
        ])
          table: (await db.rawQuery('SELECT COUNT(*) FROM $table'))
              .first
              .values
              .first! as int,
      };

  Future<int> invoiceCounter() async => (await db.query('counters',
          where: 'name = ?', whereArgs: ['invoice_no']))
      .single['value'] as int;

  group('paid in full', () {
    test('writes no ledger entry, with or without a customer', () async {
      final anonymous = await invoices.save(draft(),
          payment: const SalePayment(paidMinor: 8000));
      expect(anonymous.paidMinor, 8000);
      expect(anonymous.chargedMinor, 0);
      expect(anonymous.hasDebtLines, isFalse);
      expect(anonymous.prevBalanceBaseMinor, isNull);

      final known = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 8000));
      expect(known.prevBalanceBaseMinor, 0);
      expect(known.newBalanceBaseMinor, 0);
      expect(await debts.hasEntries(), isFalse);
    });

    test('keeps the customer\'s existing balance on the invoice', () async {
      await debts.addManualDebt(customerId: ahmad, amountBaseMinor: 3000);
      final saved = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 8000));
      expect(saved.prevBalanceBaseMinor, 3000);
      expect(saved.newBalanceBaseMinor, 3000);
      final stored = (await invoices.getById(saved.id!))!;
      expect(stored.prevBalanceBaseMinor, 3000);
      expect(stored.paidMinor, 8000);
    });

    test('without a payment (the feature off) the invoice is as before',
        () async {
      final saved = await invoices.save(draft(customerId: ahmad));
      final row =
          (await db.query('invoices', where: 'id = ?', whereArgs: [saved.id]))
              .single;
      expect(row['paid_minor'], isNull);
      expect(row['credit_used_minor'], isNull);
      expect(row['prev_balance_base_minor'], isNull);
      expect(row['new_balance_base_minor'], isNull);
      expect(saved.hasDebtLines, isFalse);
      expect(await debts.hasEntries(), isFalse);
    });
  });

  group('partial and on credit', () {
    test('partial: the rest becomes one DEBT entry linked to the invoice',
        () async {
      final saved = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 3000));
      expect(saved.paidMinor, 3000);
      expect(saved.chargedMinor, 5000);
      expect(saved.remainingMinor, 5000);
      expect(saved.prevBalanceBaseMinor, 0);
      expect(saved.newBalanceBaseMinor, 5000);

      final entry = (await debts.ledger(ahmad)).single.entry;
      expect(entry.type, DebtEntryType.debt);
      expect(entry.direction, 1);
      expect(entry.amountBaseMinor, 5000);
      expect(entry.invoiceId, saved.id);
      expect(entry.invoiceNo, saved.invoiceNo);
      expect(entry.createdAt, saleTime.toUtc());
      expect(entry.dueAt!.toLocal(), DateTime(2026, 12, 25));
      expect(entry.origAmountMinor, isNull);
      expect(await debts.balanceOf(ahmad), 5000);

      final stored = (await invoices.getById(saved.id!))!;
      expect(stored.paidMinor, 3000);
      expect(stored.newBalanceBaseMinor, 5000);
      expect(stored.hasDebtLines, isTrue);
    });

    test('on credit: all of it, on the due date chosen', () async {
      final saved = await invoices.save(
        draft(customerId: ahmad),
        payment: SalePayment(paidMinor: 0, dueAt: DateTime(2026, 12, 5)),
      );
      expect(saved.chargedMinor, 8000);
      final entry = (await debts.ledger(ahmad)).single.entry;
      expect(entry.amountBaseMinor, 8000);
      expect(entry.dueAt!.toLocal(), DateTime(2026, 12, 5));
    });

    test('a second sale carries the balance forward', () async {
      await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 3000));
      final second = await invoices.save(draft(total: 2000, customerId: ahmad),
          payment: const SalePayment(paidMinor: 500));
      expect(second.prevBalanceBaseMinor, 5000);
      expect(second.newBalanceBaseMinor, 6500);
      expect(await debts.balanceOf(ahmad), 6500);
    });

    test('an invoice in another currency: the debt is in base, with the '
        'amount and the rate of the sale', () async {
      // 10.50 USD, 4.00 paid: 6.50 USD on credit = 84,500 SYP at 13,000.
      final saved = await invoices.save(
        draft(total: 1050, currency: 'USD', customerId: ahmad),
        payment: const SalePayment(paidMinor: 400),
      );
      expect(saved.chargedMinor, 650);
      expect(saved.newBalanceBaseMinor, 84500);
      final entry = (await debts.ledger(ahmad)).single.entry;
      expect(entry.amountBaseMinor, 84500);
      expect(entry.origAmountMinor, 650);
      expect(entry.origCurrencyCode, 'USD');
      expect(entry.origRate, const RateFraction(13000, 1));
    });

    test('needs a customer — and without one nothing is saved', () async {
      final before = await counts();
      final counter = await invoiceCounter();
      await expectLater(
        invoices.save(draft(), payment: const SalePayment(paidMinor: 3000)),
        throwsA(isA<DebtCustomerRequiredException>()),
      );
      expect(await counts(), before);
      expect(await invoiceCounter(), counter);
    });

    test('a payment that does not fit the invoice is refused', () async {
      final before = await counts();
      for (final payment in const [
        SalePayment(paidMinor: -1),
        SalePayment(paidMinor: 8001),
        SalePayment(paidMinor: 3000, creditUsedMinor: 5001),
        SalePayment(paidMinor: 3000, creditUsedMinor: -1),
      ]) {
        await expectLater(
          invoices.save(draft(customerId: ahmad), payment: payment),
          throwsA(isA<InvalidSalePaymentException>()),
        );
      }
      expect(await counts(), before);
    });
  });

  group('using a credit balance', () {
    setUp(() async {
      // The shop owes Ahmad 5,000.
      await debts.addOpeningBalance(
        customerId: ahmad,
        amountBaseMinor: 5000,
        customerOwes: false,
        at: DateTime(2026, 11, 1),
      );
    });

    test('pays part of the invoice from the credit', () async {
      final saved = await invoices.save(
        draft(customerId: ahmad),
        payment: const SalePayment(paidMinor: 3000, creditUsedMinor: 5000),
      );
      expect(saved.prevBalanceBaseMinor, -5000);
      expect(saved.newBalanceBaseMinor, 0);
      expect(saved.creditUsedMinor, 5000);
      expect(saved.remainingMinor, 0);
      expect(saved.hasDebtLines, isTrue);
      expect(await debts.balanceOf(ahmad), 0);
      final entry = (await debts.ledger(ahmad)).first.entry;
      expect(entry.type, DebtEntryType.debt);
      expect(entry.amountBaseMinor, 5000);
    });

    test('credit, then the rest on credit: the balance turns positive',
        () async {
      final saved = await invoices.save(
        draft(customerId: ahmad),
        payment: const SalePayment(paidMinor: 0, creditUsedMinor: 5000),
      );
      expect(saved.remainingMinor, 3000);
      expect(saved.newBalanceBaseMinor, 3000);
      expect(await debts.balanceOf(ahmad), 3000);
    });

    test('paying cash leaves the credit where it was', () async {
      final saved = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 8000));
      expect(saved.newBalanceBaseMinor, -5000);
      expect(await debts.balanceOf(ahmad), -5000);
    });
  });

  group('credit limit', () {
    setUp(() async {
      await db.update('customers', {'credit_limit_base_minor': 10000},
          where: 'id = ?', whereArgs: [ahmad]);
      await debts.addManualDebt(customerId: ahmad, amountBaseMinor: 6000);
    });

    test('a sale that stays within the limit goes through', () async {
      final saved = await invoices.save(draft(total: 4000, customerId: ahmad),
          payment: const SalePayment(paidMinor: 0));
      expect(saved.newBalanceBaseMinor, 10000);
      expect(await AuditRepository(db).list(), isEmpty);
    });

    test('going over it is refused with the numbers, and nothing is saved',
        () async {
      final before = await counts();
      final counter = await invoiceCounter();
      await expectLater(
        invoices.save(draft(customerId: ahmad),
            payment: const SalePayment(paidMinor: 3000)),
        throwsA(isA<CreditLimitExceededException>()
            .having((e) => e.balanceBaseMinor, 'balance', 6000)
            .having((e) => e.newBalanceBaseMinor, 'new balance', 11000)
            .having((e) => e.limitBaseMinor, 'limit', 10000)),
      );
      expect(await counts(), before);
      expect(await invoiceCounter(), counter);
      expect(await debts.balanceOf(ahmad), 6000);
    });

    test('an override saves the sale and writes it to the audit log',
        () async {
      final saved = await invoices.save(
        draft(customerId: ahmad),
        payment: const SalePayment(paidMinor: 3000, overrideCreditLimit: true),
      );
      expect(saved.newBalanceBaseMinor, 11000);
      expect(await debts.balanceOf(ahmad), 11000);
      final log = (await AuditRepository(db).list()).single;
      expect(log.action, 'CREDIT_LIMIT_OVERRIDE');
      expect(log.details['customer'], 'Ahmad');
      expect(log.details['invoice_no'], saved.invoiceNo);
      expect(log.details['balance'], 6000);
      expect(log.details['new_balance'], 11000);
      expect(log.details['limit'], 10000);
    });

    test('an override that was not needed logs nothing', () async {
      await invoices.save(
        draft(total: 1000, customerId: ahmad),
        payment: const SalePayment(paidMinor: 0, overrideCreditLimit: true),
      );
      expect(await AuditRepository(db).list(), isEmpty);
    });

    test('the limit only stops NEW debt: a cash sale is never blocked',
        () async {
      await debts.addManualDebt(customerId: ahmad, amountBaseMinor: 9000);
      final saved = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 8000));
      expect(saved.newBalanceBaseMinor, 15000);
    });
  });

  group('one transaction', () {
    test('a sale on credit that fails later (no card codes left) leaves no '
        'debt behind', () async {
      final cardId = await insertProduct(db,
          name: 'Card 5000', kind: 'SERVICE', soldFromCodeStock: 1);
      await VoucherRepository(db, cipher).addBatch(
        productId: cardId,
        parsed: parseCodeList('1111222233334444', columns: CodeColumns.codeOnly),
        now: DateTime(2026, 11, 1),
      );
      final before = await counts();
      final counter = await invoiceCounter();
      // Two cards wanted, one in stock: the item loop throws AFTER the
      // invoice row and its DEBT entry were written.
      await expectLater(
        invoices.save(
          draft(
            customerId: ahmad,
            lines: [
              CartLine(
                productId: cardId,
                name: 'Card 5000',
                kind: ProductKind.service,
                unitPriceMinor: 5000,
                priceCurrencyCode: 'SYP',
                qtyThousandths: 2000,
                codeStock: true,
              ),
            ],
          ),
          payment: const SalePayment(paidMinor: 0),
        ),
        throwsA(anything),
      );
      expect(await counts(), before);
      expect(await invoiceCounter(), counter);
      expect(await debts.balanceOf(ahmad), 0);
      expect(
        (await db.rawQuery(
                "SELECT COUNT(*) FROM voucher_codes WHERE status = 'AVAILABLE'"))
            .first
            .values
            .first,
        1,
      );
    });

    test('a renewal on credit moves the account dates and the ledger '
        'together', () async {
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final accountId = await CustomerRepository(db).insertAccount(
        CustomerAccount(
          customerId: ahmad,
          accountNumber: '0011',
          renewalDays: 30,
        ),
      );
      final saved = await invoices.save(
        draft(
          customerId: ahmad,
          accountId: accountId,
          lines: [
            CartLine(
              productId: packageId,
              name: 'ADSL',
              kind: ProductKind.service,
              unitPriceMinor: 35000,
              priceCurrencyCode: 'SYP',
              qtyThousandths: 1000,
            ),
          ],
        ),
        payment: const SalePayment(paidMinor: 10000),
      );
      final account = (await CustomerRepository(db).getAccount(accountId))!;
      expect(account.lastRenewalAt, saleTime.toUtc());
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 25));
      expect(await debts.balanceOf(ahmad), 25000);
      expect(saved.newBalanceBaseMinor, 25000);
    });

    test('a typed item becomes a product only if the credit sale is saved',
        () async {
      await db.update('customers', {'credit_limit_base_minor': 100},
          where: 'id = ?', whereArgs: [ahmad]);
      final typed = [
        const CartLine(
          name: 'Brand new item',
          unitPriceMinor: 900,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
          saveAsProduct: true,
        ),
      ];
      final before = await counts();
      await expectLater(
        invoices.save(draft(customerId: ahmad, lines: typed),
            payment: const SalePayment(paidMinor: 0)),
        throwsA(isA<CreditLimitExceededException>()),
      );
      expect(await counts(), before);
    });
  });

  group('deleting invoices never touches the ledger', () {
    late Invoice credit;
    late Invoice cash;

    setUp(() async {
      credit = await invoices.save(draft(customerId: ahmad),
          payment: const SalePayment(paidMinor: 3000));
      cash = await invoices.save(draft(total: 1000, customerId: ahmad),
          payment: const SalePayment(paidMinor: 1000));
    });

    test('deleting one invoice keeps its debt, with the number snapshot',
        () async {
      final archive = ArchiveRepository(db);
      expect(await archive.invoiceCarriesDebt(credit.id!), isTrue);
      expect(await archive.invoiceCarriesDebt(cash.id!), isFalse);
      expect(await archive.deleteInvoice(credit.id!), isTrue);

      final entry = (await debts.ledger(ahmad)).single.entry;
      expect(entry.invoiceId, isNull);
      expect(entry.invoiceNo, credit.invoiceNo);
      expect(entry.amountBaseMinor, 5000);
      expect(entry.type, DebtEntryType.debt);
      expect(await debts.balanceOf(ahmad), 5000);
    });

    test('deleting a date range keeps every debt and counts them first',
        () async {
      final archive = ArchiveRepository(db);
      const everything = ArchiveFilter();
      expect(await archive.countCarryingDebt(everything), 1);
      final before = await db.query('debt_transactions', orderBy: 'id');
      expect(await archive.deleteMatchingChunk(everything), 2);
      expect(await db.query('invoices'), isEmpty);

      final after = await db.query('debt_transactions', orderBy: 'id');
      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        for (final column in before[i].keys) {
          expect(
            after[i][column],
            column == 'invoice_id' ? isNull : before[i][column],
            reason: 'debt_transactions.$column',
          );
        }
      }
      expect(await debts.balanceOf(ahmad), 5000);
      expect(await archive.countCarryingDebt(everything), 0);
    });

    test('a debt that was reversed no longer counts as carried', () async {
      final archive = ArchiveRepository(db);
      final entry = (await debts.ledger(ahmad)).single.entry;
      await debts.reverse(entry.id, reason: 'paid at the till after all');
      expect(await archive.invoiceCarriesDebt(credit.id!), isFalse);
      expect(await archive.countCarryingDebt(const ArchiveFilter()), 0);
      // Both rows stay when the invoice goes.
      await archive.deleteInvoice(credit.id!);
      expect(await db.query('debt_transactions'), hasLength(2));
      expect(await debts.balanceOf(ahmad), 0);
    });
  });
}
