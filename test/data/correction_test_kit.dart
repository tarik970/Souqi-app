import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/invoice_correction_repository.dart';
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

Currency _currency(
  String code, {
  int decimals = 0,
  RateFraction rate = RateFraction.one,
}) =>
    Currency(
      code: code,
      nameAr: code,
      nameEn: code,
      decimalPlaces: decimals,
      rate: rate,
      rateUpdatedAt: DateTime.utc(2026),
    );

/// A license that has run out: every write is refused.
class RefusingGuard implements LicenseGuard {
  static const _status = LicenseStatus(
    mode: LicenseMode.unlicensed,
    reason: UnlicensedReason.trialDaysOver,
    featureMask: 0,
    canSell: false,
    canPrint: false,
  );

  Never _refuse(LicensedAction action) =>
      throw LicenseRequiredException(action, _status);

  @override
  Future<void> ensureCanSell() async => _refuse(LicensedAction.sell);

  @override
  Future<void> ensureCanPrint() async => _refuse(LicensedAction.print);

  @override
  Future<void> ensureCanRecordDebt() async =>
      _refuse(LicensedAction.recordDebt);

  @override
  Future<void> saleSaved() async {}
}

/// A small shop for the void and return tests: sugar and tea (goods), a
/// card sold from code stock, an ADSL package, the customer Ahmad with one
/// account, dollars at 13,000 — and every repository on one database.
class TestShop {
  TestShop._(this.database);

  final AppDatabase database;

  Database get db => database.db;

  /// Where the card-code keys live (the Android Keystore in the app). A
  /// widget test hands the same store to the app, so both read the codes.
  final InMemoryKeyStore keyStore = InMemoryKeyStore();

  late final CodeCipher cipher = CodeCipher(keyStore);
  late final InvoiceRepository invoices =
      InvoiceRepository(db, codeCipher: cipher);
  late final InvoiceCorrectionRepository corrections =
      InvoiceCorrectionRepository(db, codeCipher: cipher);
  late final DebtRepository debts = DebtRepository(db);
  late final VoucherRepository vouchers = VoucherRepository(db, cipher);
  late final CustomerRepository customers = CustomerRepository(db);

  late final int sugarId;
  late final int teaId;
  late final int cardId;
  late final int packageId;
  late final int ahmad;
  late final int accountId;

  /// The account's dates before any sale of the tests renews it.
  static final accountLastRenewal = DateTime(2026, 10, 20, 11);
  static final accountDue = DateTime(2026, 11, 19);

  /// When the sales of the tests are made, unless they say otherwise.
  static final saleTime = DateTime(2026, 11, 25, 12);

  final ctx = CurrencyContext.of(
    [
      _currency('SYP'),
      _currency('USD', decimals: 2, rate: const RateFraction(13000, 1)),
    ],
    baseCode: 'SYP',
  );

  static Future<TestShop> open() async {
    final shop = TestShop._(await openTestDb());
    final db = shop.db;
    // The sales of these tests are dated in November 2026 and voided at
    // whatever "now" the test machine has: the age limit of a void is off
    // here, and the tests of the limit itself put it back.
    await db.insert('settings', {
      'key': 'void_max_age_days',
      'value': '0',
      'updated_at': 0,
    });
    await db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
    shop.sugarId = await insertProduct(db, name: 'Sugar');
    shop.teaId = await insertProduct(db, name: 'Tea');
    shop.cardId = await insertProduct(
      db,
      name: 'Card 5000',
      kind: 'SERVICE',
      soldFromCodeStock: 1,
    );
    shop.packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
    shop.ahmad = await shop.customers
        .insert(const Customer(name: 'Ahmad', phone: '0944 111 222'));
    shop.accountId = await shop.customers.insertAccount(CustomerAccount(
      customerId: shop.ahmad,
      accountNumber: '0011-2233',
      provider: 'MTN',
      defaultProductId: shop.packageId,
      renewalDays: 30,
      lastRenewalAt: accountLastRenewal,
      nextDueAt: accountDue,
    ));
    return shop;
  }

  Future<void> close() => database.close();

  CartLine sugar({int qty = 1000, int price = 8000, String currency = 'SYP'}) =>
      CartLine(
        productId: sugarId,
        name: 'Sugar',
        unitName: 'kg',
        unitPriceMinor: price,
        priceCurrencyCode: currency,
        qtyThousandths: qty,
      );

  CartLine tea({int qty = 1000, int price = 3000}) => CartLine(
        productId: teaId,
        name: 'Tea',
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: qty,
      );

  CartLine card({int cards = 1, int price = 5000}) => CartLine(
        productId: cardId,
        name: 'Card 5000',
        kind: ProductKind.service,
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: cards * 1000,
        codeStock: true,
      );

  CartLine package({int price = 35000}) => CartLine(
        productId: packageId,
        name: 'ADSL',
        kind: ProductKind.service,
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
        requiresAccount: true,
      );

  /// Loads [codes] (one per line) as a batch of the card product.
  Future<void> loadCodes(String codes) => vouchers.addBatch(
        productId: cardId,
        parsed: parseCodeList(codes, columns: CodeColumns.codeOnly),
        now: DateTime(2026, 11, 1),
      );

  /// Saves a sale of [lines]. With [customer] it is Ahmad's; [withAccount]
  /// attaches his account (a renewal, when a SERVICE line is sold). [paid]
  /// null = saved without the payment sheet (paid in full, no ledger).
  Future<Invoice> sell(
    List<CartLine> lines, {
    bool customer = false,
    bool withAccount = false,
    int? paid,
    int creditUsed = 0,
    Discount? discount,
    String? currency,
    DateTime? at,
  }) {
    var cart = const Cart();
    for (final line in lines) {
      cart = cart.add(line);
    }
    cart = cart.withInvoiceCurrency(currency).withDiscount(discount);
    final attach = customer || withAccount;
    final draft = Invoice.fromCart(
      cart: cart,
      ctx: ctx,
      createdAt: (at ?? saleTime).toUtc(),
      customerId: attach ? ahmad : null,
      customerName: attach ? 'Ahmad' : null,
      customerPhone: attach ? '0944 111 222' : null,
      accountId: withAccount ? accountId : null,
      accountNumber: withAccount ? '0011-2233' : null,
      accountProvider: withAccount ? 'MTN' : null,
    );
    return invoices.save(
      draft,
      payment: paid == null
          ? null
          : SalePayment(paidMinor: paid, creditUsedMinor: creditUsed),
    );
  }

  Future<CustomerAccount> account() async =>
      (await customers.getAccount(accountId))!;

  Future<List<Map<String, Object?>>> ledgerRows() =>
      db.query('debt_transactions', orderBy: 'id');

  Future<List<Map<String, Object?>>> audit(String action) => db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: [action],
        orderBy: 'id',
      );

  Future<List<String>> codeStatuses() async => [
        for (final row in await db.query('voucher_codes', orderBy: 'id'))
          row['status'] as String,
      ];

  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']!
          as int;
}
