import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late CodeCipher cipher;
  late VoucherRepository vouchers;
  late AuditRepository audit;
  late int cardId;

  final now = DateTime(2026, 11, 25, 12);

  setUp(() async {
    database = await openTestDb();
    cipher = CodeCipher(InMemoryKeyStore());
    vouchers = VoucherRepository(database.db, cipher);
    audit = AuditRepository(database.db);
    cardId = await insertProduct(
      database.db,
      name: 'Card 5000',
      kind: 'SERVICE',
      soldFromCodeStock: 1,
    );
  });

  tearDown(() async => database.close());

  CodeParseResult parse(String text,
          {CodeColumns columns = CodeColumns.codeOnly}) =>
      parseCodeList(text, columns: columns);

  Future<ImportReport> load(
    String text, {
    int? productId,
    DateTime? expiryAt,
    int? cost,
    CodeColumns columns = CodeColumns.codeOnly,
    DateTime? at,
  }) =>
      vouchers.addBatch(
        productId: productId ?? cardId,
        parsed: parse(text, columns: columns),
        expiryAt: expiryAt,
        costPerCardMinor: cost,
        costCurrencyCode: cost == null ? null : 'SYP',
        now: at ?? now,
      );

  Future<ProductStock> stock([int? productId]) async =>
      (await vouchers.stockOverview(now: now))
          .firstWhere((s) => s.product.id == (productId ?? cardId));

  Future<List<Map<String, Object?>>> codeRows() =>
      database.db.query('voucher_codes', orderBy: 'id');

  group('loading a batch', () {
    test('saves the codes encrypted, with their hash and serial', () async {
      final report = await load(
        'SN1,1111222233334444\nSN2,5555666677778888',
        columns: CodeColumns.serialThenCode,
        cost: 4500,
      );
      expect(report.added, 2);
      expect(report.batchId, isNotNull);

      final rows = await codeRows();
      expect(rows, hasLength(2));
      expect(rows.first['serial'], 'SN1');
      expect(rows.first['status'], 'AVAILABLE');
      expect(rows.first['code_hash'], await cipher.hash('1111222233334444'));
      final blob = rows.first['code_cipher'] as Uint8List;
      expect(latin1.decode(blob).contains('1111222233334444'), isFalse);
      expect(await cipher.decrypt(blob), '1111222233334444');

      final batch = (await vouchers.batches(cardId, now: now)).single;
      expect(batch.codeCount, 2);
      expect(batch.costPerCardMinor, 4500);
      expect(batch.costCurrencyCode, 'SYP');
      expect(batch.available, 2);
    });

    test('nothing in the database holds a code in the clear', () async {
      await load('SN1,9988776655443322', columns: CodeColumns.serialThenCode);
      await vouchers.lookup('9988776655443322');
      for (final table in ['voucher_codes', 'voucher_batches', 'audit_log']) {
        for (final row in await database.db.query(table)) {
          for (final value in row.values) {
            if (value is String) {
              expect(value.contains('9988776655443322'), isFalse,
                  reason: table);
            }
          }
        }
      }
    });

    test('the report: added, duplicates in the batch, empty lines', () async {
      final report = await load('1111\n2222\n\n11-11\n3333\n٢٢٢٢');
      expect(report.added, 3);
      expect(report.duplicatesInBatch, 2);
      expect(report.duplicatesExisting, 0);
      expect(report.emptyLines, 1);
      expect((await stock()).available, 3);
    });

    test('codes the product already has are rejected, by hash', () async {
      await load('1111-2222\n3333-4444');
      // The same cards again, spelled differently, plus one new.
      expect(
        await vouchers.countExisting(
          cardId,
          parse('11112222\n3333 4444\n5555-6666').codes,
        ),
        2,
      );
      final report = await load('11112222\n3333 4444\n5555-6666');
      expect(report.added, 1);
      expect(report.duplicatesExisting, 2);
      expect(report.duplicates, 2);
      expect((await stock()).available, 3);
      expect(await vouchers.batches(cardId, now: now), hasLength(2));
    });

    test('a sold code is still a duplicate: it cannot come back as stock',
        () async {
      await load('1111');
      await database.db.update('voucher_codes', {'status': 'SOLD'});
      final report = await load('1111');
      expect(report.added, 0);
      expect(report.duplicatesExisting, 1);
    });

    test('nothing new: no batch is created', () async {
      await load('1111');
      final report = await load('1111\n11-11');
      expect(report.added, 0);
      expect(report.batchId, isNull);
      expect(await vouchers.batches(cardId, now: now), hasLength(1));
    });

    test('the same code may belong to another product', () async {
      final other = await insertProduct(
        database.db,
        name: 'Card 10000',
        kind: 'SERVICE',
        soldFromCodeStock: 1,
      );
      await load('1111');
      final report = await load('1111', productId: other);
      expect(report.added, 1);
    });

    test('a GOODS product cannot hold codes', () async {
      final sugar = await insertProduct(database.db, name: 'Sugar');
      expect(() => load('1111', productId: sugar), throwsArgumentError);
      expect(await codeRows(), isEmpty);
    });

    test('is one transaction: a failure leaves no batch and no codes',
        () async {
      // The very last write of the transaction — the audit line — fails,
      // after the batch and both codes were inserted.
      await database.db.execute(
        'CREATE TRIGGER fail_audit BEFORE INSERT ON audit_log '
        "BEGIN SELECT RAISE(ABORT, 'no audit'); END",
      );
      await expectLater(load('1111\n2222'), throwsA(isA<DatabaseException>()));
      await database.db.execute('DROP TRIGGER fail_audit');
      expect(await codeRows(), isEmpty);
      expect(await database.db.query('voucher_batches'), isEmpty);
      expect(await database.db.query('audit_log'), isEmpty);
    });

    test('is written to the audit log, without the codes', () async {
      await load('1111\n2222\n1111');
      final entry = (await audit.list()).single;
      expect(entry.action, AuditAction.codeImport.db);
      expect(entry.productId, cardId);
      expect(entry.productName, 'Card 5000');
      expect(entry.details['count'], 2);
      expect(entry.details['duplicates'], 1);
    });
  });

  group('stock counts', () {
    test('available / sold / void / expired per product', () async {
      await load('1111\n2222\n3333\n4444');
      await load('8888\n9999', expiryAt: expiryFromDate(DateTime(2026, 11, 20)));
      final ids = [for (final row in await codeRows()) row['id'] as int];
      await database.db.update('voucher_codes', {'status': 'SOLD'},
          where: 'id = ?', whereArgs: [ids[0]]);
      await vouchers.voidCode(ids[1], reason: 'scratched', now: now);

      final s = await stock();
      expect(s.available, 2);
      expect(s.sold, 1);
      expect(s.voided, 1);
      expect(s.expired, 2);
      expect((await vouchers.availableByProduct(now: now))[cardId], 2);
    });

    test('an expiry date is sellable through that whole day', () async {
      await load('1111', expiryAt: expiryFromDate(DateTime(2026, 11, 25)));
      expect(
        (await vouchers.availableByProduct(
            now: DateTime(2026, 11, 25, 23, 59)))[cardId],
        1,
      );
      expect(
        (await vouchers.availableByProduct(now: DateTime(2026, 11, 26)))[cardId],
        isNull,
      );
      expect(expiryLastDay(expiryFromDate(DateTime(2026, 11, 25))),
          DateTime(2026, 11, 25));
    });

    test('low stock: at or under the threshold, or out', () async {
      await database.db.update('products', {'low_stock_threshold': 2},
          where: 'id = ?', whereArgs: [cardId]);
      expect((await stock()).isOut, isTrue);
      expect(await vouchers.lowStockCount(now: now), 1);

      await load('1111\n2222');
      expect((await stock()).isLow, isTrue);
      expect(await vouchers.lowStockCount(now: now), 1);

      await load('3333');
      expect((await stock()).needsAttention, isFalse);
      expect(await vouchers.lowStockCount(now: now), 0);
    });

    test('without a threshold a product is only ever "out"', () async {
      expect(await vouchers.lowStockCount(now: now), 1);
      await load('1111');
      expect((await stock()).isLow, isFalse);
      expect(await vouchers.lowStockCount(now: now), 0);
    });

    test('a deactivated product is not counted as low', () async {
      await database.db.update('products', {'is_active': 0},
          where: 'id = ?', whereArgs: [cardId]);
      expect(await vouchers.lowStockCount(now: now), 0);
      expect((await stock()).needsAttention, isFalse);
    });

    test('per batch', () async {
      await load('1111\n2222', at: DateTime(2026, 11, 1));
      await load('3333', at: DateTime(2026, 11, 2));
      final batches = await vouchers.batches(cardId, now: now);
      // Newest first.
      expect([for (final b in batches) b.codeCount], [1, 2]);
      expect(batches.last.available, 2);
    });
  });

  group('void and return to stock', () {
    Future<int> soldCode() async {
      await load('SN7,1111222233334444', columns: CodeColumns.serialThenCode);
      final id = (await codeRows()).single['id'] as int;
      await database.db.update(
        'voucher_codes',
        {
          'status': 'SOLD',
          'sold_at': now.millisecondsSinceEpoch,
          'sold_invoice_no': 12,
          'sold_customer_name': 'Ahmad',
          'sold_price_base_minor': 5000,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    test('void: the status changes, the sale snapshot stays', () async {
      final id = await soldCode();
      expect(await vouchers.voidCode(id, reason: 'defective', now: now), isTrue);

      final row = (await codeRows()).single;
      expect(row['status'], 'VOID');
      expect(row['status_note'], 'defective');
      expect(row['sold_invoice_no'], 12);
      expect(row['sold_customer_name'], 'Ahmad');

      final s = await stock();
      expect((s.available, s.sold, s.voided), (0, 0, 1));
    });

    test('return to stock: available again, the sale forgotten', () async {
      final id = await soldCode();
      expect(
        await vouchers.returnToStock(id, reason: 'sold by mistake', now: now),
        isTrue,
      );

      final row = (await codeRows()).single;
      expect(row['status'], 'AVAILABLE');
      expect(row['sold_at'], isNull);
      expect(row['sold_invoice_no'], isNull);
      expect(row['sold_customer_name'], isNull);
      expect(row['sold_price_base_minor'], isNull);
      expect(row['invoice_id'], isNull);

      final s = await stock();
      expect((s.available, s.sold, s.voided), (1, 0, 0));
    });

    test('a voided code can be returned to stock, and voided again',
        () async {
      final id = await soldCode();
      await vouchers.voidCode(id, reason: 'a', now: now);
      await vouchers.returnToStock(id, reason: 'b', now: now);
      expect((await stock()).available, 1);
      await vouchers.voidCode(id, reason: 'c', now: now);
      final s = await stock();
      expect((s.available, s.sold, s.voided), (0, 0, 1));
    });

    test('doing it twice changes nothing and logs nothing', () async {
      final id = await soldCode();
      await vouchers.voidCode(id, reason: 'x', now: now);
      final logged = (await audit.list()).length;
      expect(await vouchers.voidCode(id, reason: 'x', now: now), isFalse);
      expect(await audit.list(), hasLength(logged));
    });

    test('both are logged with the reason and never the code', () async {
      final id = await soldCode();
      await vouchers.voidCode(id, reason: 'defective', now: now);
      await vouchers.returnToStock(id, reason: 'my mistake', now: now);

      final entries = await audit.list();
      expect(entries[0].action, AuditAction.codeRestore.db);
      expect(entries[0].details['reason'], 'my mistake');
      expect(entries[1].action, AuditAction.codeVoid.db);
      expect(entries[1].details['reason'], 'defective');
      expect(entries[1].details['invoice_no'], 12);
      expect(entries[1].details['tail'], '4444');
      expect(entries[1].details['serial'], 'SN7');
      expect(entries[1].productName, 'Card 5000');
      for (final row in await database.db.query('audit_log')) {
        expect('${row['details']}'.contains('1111222233334444'), isFalse);
      }
    });
  });

  group('deleting a batch', () {
    test('an unsold batch goes, with its codes', () async {
      final report = await load('1111\n2222');
      expect(await vouchers.deleteUnsoldBatch(report.batchId!), 2);
      expect(await codeRows(), isEmpty);
      expect(await vouchers.batches(cardId, now: now), isEmpty);
      expect((await audit.list()).first.action, AuditAction.batchDelete.db);
    });

    test('a batch with a sold code is never deleted', () async {
      final report = await load('1111\n2222');
      await database.db.update('voucher_codes', {'status': 'SOLD', 'sold_at': 1},
          where: 'code_hash = ?', whereArgs: [await cipher.hash('1111')]);
      expect(await vouchers.deleteUnsoldBatch(report.batchId!), isNull);
      expect(await codeRows(), hasLength(2));
    });

    test('nor one whose sold code was voided since', () async {
      final report = await load('1111');
      final id = (await codeRows()).single['id'] as int;
      await database.db.update('voucher_codes', {'status': 'SOLD', 'sold_at': 1});
      await vouchers.voidCode(id, reason: 'x', now: now);
      expect(await vouchers.deleteUnsoldBatch(report.batchId!), isNull);
      expect(await codeRows(), hasLength(1));
    });
  });

  group('expiry', () {
    test('expired codes are listed apart, the longest expired first',
        () async {
      await load('1111', expiryAt: expiryFromDate(DateTime(2026, 11, 20)));
      await load('2222', expiryAt: expiryFromDate(DateTime(2026, 11, 10)));
      await load('3333', expiryAt: expiryFromDate(DateTime(2026, 12, 31)));
      await load('4444');

      final expired = await vouchers.expiredCodes(now: now);
      expect([for (final c in expired) c.masked],
          ['•••• ••••', '•••• ••••']);
      expect(expired.first.expiryAt!.toLocal(), DateTime(2026, 11, 11));
      expect(expired.every((c) => c.isExpired(now)), isTrue);
      expect((await stock()).available, 2);
    });

    test('voiding the expired ones leaves the rest alone', () async {
      await load('1111\n2222',
          expiryAt: expiryFromDate(DateTime(2026, 11, 20)));
      await load('3333');
      expect(
        await vouchers.voidExpired(
            productId: cardId, reason: 'written off', now: now),
        2,
      );
      final s = await stock();
      expect((s.available, s.expired, s.voided), (1, 0, 2));
      final entry = (await audit.list()).first;
      expect(entry.action, AuditAction.codeVoid.db);
      expect(entry.details['count'], 2);
    });

    test('a corrected expiry date puts the batch back on sale', () async {
      final report = await load('1111\n2222',
          expiryAt: expiryFromDate(DateTime(2026, 11, 20)));
      expect((await stock()).available, 0);
      expect(
        await vouchers.setBatchExpiry(
            report.batchId!, expiryFromDate(DateTime(2027, 1, 31))),
        2,
      );
      expect((await stock()).available, 2);
      expect((await vouchers.batches(cardId, now: now)).single.expiryAt!.toLocal(),
          DateTime(2027, 2, 1));
      expect((await audit.list()).first.action,
          AuditAction.codeExpiryChange.db);
    });
  });

  group('masking, reveal and lookup', () {
    test('lists only ever carry the masked form', () async {
      final report = await load('1111222233334444\n5555666677778888');
      final codes = await vouchers.codesOfBatch(report.batchId!);
      expect([for (final c in codes) c.masked],
          ['•••• •••• 4444', '•••• •••• 8888']);
      expect(codes.every((c) => !c.unreadable), isTrue);
    });

    test('reveal returns the code and logs that it was shown', () async {
      await load('1111222233334444');
      final id = (await codeRows()).single['id'] as int;
      expect(await vouchers.reveal(id), '1111222233334444');
      final entry = (await audit.list()).first;
      expect(entry.action, AuditAction.codeReveal.db);
      expect(entry.details['tail'], '4444');
    });

    test('lookup by full code finds it however it is typed', () async {
      await load('1111-2222-3333-4444');
      await database.db.update('voucher_codes', {
        'status': 'SOLD',
        'sold_at': now.toUtc().millisecondsSinceEpoch,
        'sold_invoice_no': 31,
        'sold_customer_name': 'Ahmad',
      });

      final found = await vouchers.lookup(' 1111 2222 3333 4444 ');
      expect(found.single.status, VoucherStatus.sold);
      expect(found.single.soldInvoiceNo, 31);
      expect(found.single.soldCustomerName, 'Ahmad');
      expect(found.single.soldAt!.toLocal(), now);
      expect(found.single.productName, 'Card 5000');

      expect(await vouchers.lookup('١١١١٢٢٢٢٣٣٣٣٤٤٤٤'), hasLength(1));
      expect(await vouchers.lookup('1111222233334445'), isEmpty);
    });

    test('every lookup is logged, found or not', () async {
      await load('1111222233334444');
      await vouchers.lookup('1111222233334444');
      await vouchers.lookup('0000');
      final entries = await audit.list();
      expect(entries[0].action, AuditAction.codeLookup.db);
      expect(entries[0].details['found'], 0);
      expect(entries[1].details['found'], 1);
      expect(entries[1].productName, 'Card 5000');
    });

    test('a database moved to another phone: unreadable, not a crash',
        () async {
      final report = await load('1111222233334444');
      final elsewhere =
          VoucherRepository(database.db, CodeCipher(InMemoryKeyStore()));
      final codes = await elsewhere.codesOfBatch(report.batchId!);
      expect(codes.single.unreadable, isTrue);
      expect(codes.single.masked, '•••• ••••');
      expect(() => elsewhere.reveal(codes.single.id),
          throwsA(isA<CodeUnreadableException>()));
    });
  });

  group('export', () {
    test('the unsold codes as lines the import reads back', () async {
      await load('SN1,1111\nSN2,2222', columns: CodeColumns.serialThenCode);
      await load('3333');
      await database.db.update('voucher_codes', {'status': 'SOLD'},
          where: 'serial = ?', whereArgs: ['SN2']);

      final export = await vouchers.exportAvailable(productId: cardId);
      expect(export.lines, ['SN1,1111', '3333']);
      expect(export.unreadable, 0);

      final entry = (await audit.list()).first;
      expect(entry.action, AuditAction.codeExport.db);
      expect(entry.details['count'], 2);
    });
  });

  group('the audit log', () {
    test('lists newest first and filters by date', () async {
      await audit.log(AuditAction.pinSet, at: DateTime(2026, 11, 1, 9));
      await audit.log(AuditAction.codeReveal,
          productName: 'Card 5000', at: DateTime(2026, 11, 10, 9));
      await audit.log(AuditAction.codeVoid, at: DateTime(2026, 11, 20, 9));

      expect([for (final e in await audit.list()) e.action],
          ['CODE_VOID', 'CODE_REVEAL', 'PIN_SET']);
      final middle = await audit.list(
        from: DateTime(2026, 11, 5),
        to: DateTime(2026, 11, 15),
      );
      expect(middle.single.action, 'CODE_REVEAL');
      expect(middle.single.productName, 'Card 5000');
      expect(middle.single.createdAt.toLocal(), DateTime(2026, 11, 10, 9));
    });

    test('pages below the last row shown', () async {
      for (var i = 0; i < 5; i++) {
        await audit.log(AuditAction.codeReveal, details: {'n': i});
      }
      final first = await audit.list(limit: 2);
      final next = await audit.list(limit: 2, beforeId: first.last.id);
      expect([for (final e in [...first, ...next]) e.details['n']],
          [4, 3, 2, 1]);
    });
  });
}
