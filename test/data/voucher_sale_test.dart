import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/domain/models/voucher.dart';
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

/// Selling prepaid card codes: the codes are taken inside the invoice's own
/// transaction, in the brief's order, and nothing is sold when anything
/// fails.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late CodeCipher cipher;
  late VoucherRepository vouchers;
  late InvoiceRepository invoices;
  late int cardId;
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
    await database.db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
    cipher = CodeCipher(InMemoryKeyStore());
    vouchers = VoucherRepository(database.db, cipher);
    invoices = InvoiceRepository(database.db, codeCipher: cipher);
    cardId = await insertProduct(
      database.db,
      name: 'Card 5000',
      kind: 'SERVICE',
      soldFromCodeStock: 1,
    );
    sugarId = await insertProduct(database.db, name: 'Sugar');
  });

  tearDown(() async => database.close());

  Future<ImportReport> load(
    String text, {
    int? productId,
    DateTime? expiryAt,
    int? cost,
    String costCurrency = 'SYP',
    DateTime? at,
  }) =>
      vouchers.addBatch(
        productId: productId ?? cardId,
        parsed: parseCodeList(text, columns: CodeColumns.codeOnly),
        expiryAt: expiryAt,
        costPerCardMinor: cost,
        costCurrencyCode: cost == null ? null : costCurrency,
        now: at ?? DateTime(2026, 11, 1),
      );

  CartLine cardLine({int qty = 1, int price = 5000, int? productId}) => CartLine(
        productId: productId ?? cardId,
        name: 'Card 5000',
        kind: ProductKind.service,
        unitPriceMinor: price,
        priceCurrencyCode: 'SYP',
        qtyThousandths: qty * 1000,
        codeStock: true,
      );

  Invoice draft(
    List<CartLine> lines, {
    DateTime? at,
    String? invoiceCurrency,
    int? customerId,
    String? customerName,
    String? accountNumber,
  }) {
    var cart = const Cart();
    for (final line in lines) {
      cart = cart.add(line);
    }
    return Invoice.fromCart(
      cart: cart.withInvoiceCurrency(invoiceCurrency),
      ctx: ctx,
      createdAt: (at ?? saleTime).toUtc(),
      customerId: customerId,
      customerName: customerName,
      accountNumber: accountNumber,
    );
  }

  Future<List<String>> printed(Invoice invoice) async => [
        for (final code in await vouchers.printableCodes(invoice.id!))
          code.code!,
      ];

  Future<int> available() async =>
      (await vouchers.availableByProduct(now: saleTime))[cardId] ?? 0;

  group('saving a sale takes the codes', () {
    test('N cards take N codes and mark them SOLD', () async {
      await load('1111\n2222\n3333');
      final customerId = await insertCustomer(database.db, name: 'Ahmad');
      final saved = await invoices.save(draft(
        [cardLine(qty: 2)],
        customerId: customerId,
        customerName: 'Ahmad',
      ));

      expect(await printed(saved), ['1111', '2222']);
      expect(await available(), 1);

      final sold = await database.db.query('voucher_codes',
          where: "status = 'SOLD'", orderBy: 'id');
      expect(sold, hasLength(2));
      for (final row in sold) {
        expect(row['invoice_id'], saved.id);
        expect(row['invoice_item_id'], saved.items.single.id);
        expect(row['sold_invoice_no'], saved.invoiceNo);
        expect(row['sold_at'], saleTime.toUtc().millisecondsSinceEpoch);
        expect(row['status_changed_at'],
            saleTime.toUtc().millisecondsSinceEpoch);
        expect(row['sold_customer_id'], customerId);
        expect(row['sold_customer_name'], 'Ahmad');
        expect(row['sold_price_base_minor'], 5000);
      }
    });

    test('a product NOT sold from code stock takes nothing', () async {
      await load('1111');
      final plain = await insertProduct(database.db,
          name: 'ADSL renewal', kind: 'SERVICE');
      final saved =
          await invoices.save(draft([cardLine(productId: plain)]));
      expect(await printed(saved), isEmpty);
      expect(await available(), 1);
    });

    test('with the feature off the product sells like any service', () async {
      await load('1111');
      final saved =
          await InvoiceRepository(database.db).save(draft([cardLine()]));
      expect(await printed(saved), isEmpty);
      expect(await available(), 1);
    });

    test('goods on the same invoice are untouched', () async {
      await load('1111');
      final saved = await invoices.save(draft([
        CartLine(
          productId: sugarId,
          name: 'Sugar',
          unitPriceMinor: 1500,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 500,
        ),
        cardLine(),
      ]));
      expect(saved.items, hasLength(2));
      expect(await printed(saved), ['1111']);
    });

    test('the snapshots carry the account, and base-currency price and cost',
        () async {
      // Bought at 0.30 USD each; sold at 5,000 SYP on a USD invoice.
      await load('1111', cost: 30, costCurrency: 'USD');
      final saved = await invoices.save(draft(
        [cardLine()],
        invoiceCurrency: 'USD',
        accountNumber: '0011-2233',
      ));
      final row = (await database.db.query('voucher_codes')).single;
      expect(row['sold_account_number'], '0011-2233');
      expect(row['sold_price_base_minor'], 5000);
      expect(row['sold_cost_base_minor'], 3900);
      expect(saved.currencyCode, 'USD');
    });
  });

  group('which codes are picked', () {
    test('earliest expiry first, codes with no expiry last', () async {
      await load('NOEXP1\nNOEXP2', at: DateTime(2026, 10, 1));
      await load('LATE', expiryAt: expiryFromDate(DateTime(2027, 6, 30)),
          at: DateTime(2026, 10, 2));
      await load('SOON', expiryAt: expiryFromDate(DateTime(2026, 12, 31)),
          at: DateTime(2026, 10, 3));

      final saved = await invoices.save(draft([cardLine(qty: 3)]));
      expect(await printed(saved), unorderedEquals(['SOON', 'LATE', 'NOEXP1']));
      final order = await database.db.query('voucher_codes',
          where: "status = 'AVAILABLE'");
      expect(await cipher.decrypt(order.single['code_cipher'] as List<int>),
          'NOEXP2');
    });

    test('then the oldest batch, then the lowest id', () async {
      await load('A1\nA2');
      await load('B1\nB2');
      expect(await printed(await invoices.save(draft([cardLine()]))), ['A1']);
      expect(await printed(await invoices.save(draft([cardLine(qty: 2)]))),
          ['A2', 'B1']);
      expect(await printed(await invoices.save(draft([cardLine()]))), ['B2']);
    });

    test('expired codes are never sold automatically', () async {
      await load('OLD', expiryAt: expiryFromDate(DateTime(2026, 11, 24)));
      await load('GOOD');
      expect(await printed(await invoices.save(draft([cardLine()]))), ['GOOD']);
      await expectLater(
        invoices.save(draft([cardLine()])),
        throwsA(isA<InsufficientCodeStockException>()),
      );
      expect(await vouchers.expiredCodes(now: saleTime), hasLength(1));
    });

    test('a code expiring today is still sold today', () async {
      await load('TODAY', expiryAt: expiryFromDate(DateTime(2026, 11, 25)));
      expect(await printed(await invoices.save(draft([cardLine()]))),
          ['TODAY']);
    });

    test('voided codes are skipped; one returned to stock sells again',
        () async {
      await load('1111\n2222');
      final first = await invoices.save(draft([cardLine()]));
      final id = (await vouchers.codesOfInvoice(first.id!)).single.id;

      await vouchers.voidCode(id, reason: 'defective', now: saleTime);
      expect(await printed(first), isEmpty,
          reason: 'a voided code is not printed again');
      expect(await printed(await invoices.save(draft([cardLine()]))), ['2222']);

      await vouchers.returnToStock(id, reason: 'not defective', now: saleTime);
      expect(await printed(await invoices.save(draft([cardLine()]))), ['1111']);
    });
  });

  group('transaction safety', () {
    test('two quick sales never share a code', () async {
      await load([for (var i = 0; i < 6; i++) 'CODE$i'].join('\n'));
      // Fired together, the way two fast taps on Save would be.
      final saved = await Future.wait([
        for (var i = 0; i < 3; i++) invoices.save(draft([cardLine(qty: 2)])),
      ]);
      final all = <String>[];
      for (final invoice in saved) {
        final codes = await printed(invoice);
        expect(codes, hasLength(2));
        all.addAll(codes);
      }
      expect(all.toSet(), hasLength(6), reason: 'six different cards');
      expect(await available(), 0);
      expect({for (final i in saved) i.invoiceNo}, hasLength(3));
    });

    test('more buyers than cards: the extra sale fails whole', () async {
      await load('1111\n2222\n3333');
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          invoices
              .save(draft([cardLine(qty: 2)]))
              .then<Object>((invoice) => invoice)
              .catchError((Object error) => error),
      ]);
      expect(results.whereType<Invoice>(), hasLength(1));
      expect(results.whereType<InsufficientCodeStockException>(), hasLength(1));
      expect(await available(), 1);
      expect(await database.db.query('invoices'), hasLength(1));
    });

    test('not enough stock: nothing is sold and nothing is saved', () async {
      await load('1111\n2222');
      Object? error;
      try {
        await invoices.save(draft([
          CartLine(
            productId: sugarId,
            name: 'Sugar',
            unitPriceMinor: 1500,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
          ),
          cardLine(qty: 3),
        ]));
      } on InsufficientCodeStockException catch (e) {
        error = e;
      }
      final shortage = error! as InsufficientCodeStockException;
      expect(shortage.requested, 3);
      expect(shortage.available, 2);
      expect(shortage.productName, 'Card 5000');

      expect(await database.db.query('invoices'), isEmpty);
      expect(await database.db.query('invoice_items'), isEmpty);
      expect(await available(), 2);
      // The invoice number was not consumed either.
      expect(await invoices.peekNextInvoiceNo(), 1);
    });

    test('a failure AFTER the codes were taken puts them back', () async {
      await load('1111\n2222');
      final other = await insertProduct(
        database.db,
        name: 'Card 10000',
        kind: 'SERVICE',
        soldFromCodeStock: 1,
      );
      // Line 1 gets its code; line 2 has no stock and fails the save.
      await expectLater(
        invoices.save(draft([
          cardLine(),
          CartLine(
            productId: other,
            name: 'Card 10000',
            kind: ProductKind.service,
            unitPriceMinor: 10000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 1000,
            codeStock: true,
          ),
        ])),
        throwsA(isA<InsufficientCodeStockException>()),
      );
      expect(await available(), 2);
      expect(
        await database.db.query('voucher_codes', where: "status != 'AVAILABLE'"),
        isEmpty,
      );
      expect(await database.db.query('invoices'), isEmpty);
    });

    test('a card that cannot be decrypted is not sold', () async {
      await load('1111');
      // The database on a phone that does not hold the key.
      final elsewhere = InvoiceRepository(
        database.db,
        codeCipher: CodeCipher(InMemoryKeyStore()),
      );
      await expectLater(
        elsewhere.save(draft([cardLine()])),
        throwsA(isA<CodeUnreadableException>()),
      );
      expect(await available(), 1);
      expect(await database.db.query('invoices'), isEmpty);
    });

    test('half a card cannot be sold', () async {
      await load('1111');
      await expectLater(
        invoices.save(draft([
          CartLine(
            productId: cardId,
            name: 'Card 5000',
            kind: ProductKind.service,
            unitPriceMinor: 5000,
            priceCurrencyCode: 'SYP',
            qtyThousandths: 500,
          ),
        ])),
        throwsA(isA<CodeQuantityException>()),
      );
      expect(await available(), 1);
    });

    test('a typed item that turns out to be a card product takes a code',
        () async {
      await load('1111');
      // "Card 5000" typed into the sale instead of picked: on save it is
      // linked to the existing product by name — and sold from its stock.
      final saved = await invoices.save(draft([
        const CartLine(
          name: 'card 5000',
          kind: ProductKind.service,
          unitPriceMinor: 5000,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
          saveAsProduct: true,
        ),
      ]));
      expect(saved.items.single.productId, cardId);
      expect(await printed(saved), ['1111']);
    });
  });

  group('archive deletion keeps the sold-code record', () {
    test('delete one invoice: status, date and invoice number stay', () async {
      await load('1111222233334444');
      final saved = await invoices
          .save(draft([cardLine()], customerName: 'Ahmad'));
      await ArchiveRepository(database.db).deleteInvoice(saved.id!);

      final row = (await database.db.query('voucher_codes')).single;
      expect(row['status'], 'SOLD');
      expect(row['invoice_id'], isNull);
      expect(row['invoice_item_id'], isNull);
      expect(row['sold_invoice_no'], saved.invoiceNo);
      expect(row['sold_at'], saleTime.toUtc().millisecondsSinceEpoch);

      // "Was this code sold?" still answers.
      final found = (await vouchers.lookup('1111 2222 3333 4444')).single;
      expect(found.status, VoucherStatus.sold);
      expect(found.soldInvoiceNo, saved.invoiceNo);
      expect(found.soldCustomerName, 'Ahmad');
      expect(found.invoiceId, isNull);
      // And it is not stock again.
      expect(await available(), 0);
    });

    test('delete a date range (the retention sweep): the same', () async {
      await load('1111\n2222\n3333');
      await invoices.save(draft([cardLine()], at: DateTime(2026, 1, 5)));
      await invoices.save(draft([cardLine()], at: DateTime(2026, 1, 6)));
      final kept = await invoices.save(draft([cardLine()]));

      final deleted = await ArchiveRepository(database.db).deleteMatchingChunk(
        ArchiveFilter(to: DateTime(2026, 2, 1)),
      );
      expect(deleted, 2);

      final rows = await database.db.query('voucher_codes', orderBy: 'id');
      expect([for (final r in rows) r['status']], ['SOLD', 'SOLD', 'SOLD']);
      expect([for (final r in rows) r['sold_invoice_no']], [1, 2, 3]);
      expect([for (final r in rows) r['invoice_id']], [null, null, kept.id]);
      expect(await printed(kept), ['3333']);
    });

    test('a sold code keeps its batch from being deleted afterwards',
        () async {
      final report = await load('1111');
      final saved = await invoices.save(draft([cardLine()]));
      await ArchiveRepository(database.db).deleteInvoice(saved.id!);
      expect(await vouchers.deleteUnsoldBatch(report.batchId!), isNull);
    });
  });

  group('statistics', () {
    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 12, 1);
    late StatsRepository stats;

    setUp(() => stats = StatsRepository(database.db));

    test('cards sold per product, with profit where the cost is known',
        () async {
      await load('1111\n2222', cost: 4500);
      await load('3333'); // no cost entered
      final other = await insertProduct(
        database.db,
        name: 'Card 10000',
        kind: 'SERVICE',
        soldFromCodeStock: 1,
      );
      await load('9999', productId: other, cost: 9000);

      await invoices.save(draft([cardLine(qty: 3)]));
      await invoices.save(draft([cardLine(productId: other, price: 10000)]));

      final rows = await stats.cardSales(from: from, to: to);
      expect([for (final r in rows) r.name], ['Card 5000', 'Card 10000']);
      final first = rows.first;
      expect(first.count, 3);
      expect(first.revenueBaseMinor, 15000);
      expect(first.costKnownCount, 2);
      expect(first.profitBaseMinor, 1000); // 2 × (5,000 − 4,500)
      expect(first.profitIsPartial, isTrue);
      expect(rows.last.profitBaseMinor, 1000);
      expect(rows.last.profitIsPartial, isFalse);
    });

    test('only the period asked for', () async {
      await load('1111\n2222');
      await invoices.save(draft([cardLine()], at: DateTime(2026, 10, 31, 23)));
      await invoices.save(draft([cardLine()]));
      expect((await stats.cardSales(from: from, to: to)).single.count, 1);
    });

    test('a voided or returned card no longer counts as sold', () async {
      await load('1111\n2222\n3333', cost: 4000);
      final saved = await invoices.save(draft([cardLine(qty: 3)]));
      final codes = await vouchers.codesOfInvoice(saved.id!);
      await vouchers.voidCode(codes[0].id, reason: 'x', now: saleTime);
      await vouchers.returnToStock(codes[1].id, reason: 'y', now: saleTime);

      final row = (await stats.cardSales(from: from, to: to)).single;
      expect(row.count, 1);
      expect(row.profitBaseMinor, 1000);
    });

    test('survives the invoices being deleted', () async {
      await load('1111', cost: 4000);
      final saved = await invoices.save(draft([cardLine()]));
      await ArchiveRepository(database.db).deleteInvoice(saved.id!);
      final row = (await stats.cardSales(from: from, to: to)).single;
      expect(row.count, 1);
      expect(row.revenueBaseMinor, 5000);
      expect(row.profitBaseMinor, 1000);
    });

    test('a loss is a negative profit, not zero', () async {
      await load('1111', cost: 6000);
      await invoices.save(draft([cardLine()]));
      expect((await stats.cardSales(from: from, to: to)).single.profitBaseMinor,
          -1000);
    });
  });
}
