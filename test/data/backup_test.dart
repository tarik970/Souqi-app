import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:souqi/core/backup/backup_crypto.dart';
import 'package:souqi/core/backup/backup_file.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/backup/backup_service.dart';
import 'package:souqi/data/backup/restore_journal.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:souqi/features/backup/backup_actions.dart';
import 'package:souqi/features/backup/backup_providers.dart';
import 'package:souqi/features/debts/report/report_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../features/report_test_utils.dart';
import 'db_test_utils.dart';

/// Backup and restore, end to end on real database FILES: a populated shop
/// on "phone A" is backed up and restored onto "phone B", which has its own
/// data and its own card-code keys.
void main() {
  setUpAll(sqfliteFfiInit);

  /// Fast for the tests; the app uses [backupKdfIterations].
  const iterations = 1000;
  const password = 'souq-2026';

  late Directory root;

  final ctx = CurrencyContext.of(
    [
      Currency(
        code: 'SYP',
        nameAr: 'SYP',
        nameEn: 'SYP',
        decimalPlaces: 0,
        rate: RateFraction.one,
        rateUpdatedAt: DateTime.utc(2026),
      ),
    ],
    baseCode: 'SYP',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('souqi-backup-test-');
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle for a moment.
    }
  });

  /// One phone: a database file, a Keystore, a temporary folder.
  Future<({AppDatabase db, InMemoryKeyStore keys, BackupService service})>
      phone(String name) async {
    final dir = Directory(p.join(root.path, name, 'databases'));
    await dir.create(recursive: true);
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, AppDatabase.fileName),
    );
    final keys = InMemoryKeyStore();
    final service = BackupService(
      factory: databaseFactoryFfi,
      keys: keys,
      workDir: () async => Directory(p.join(root.path, name, 'work')),
    );
    return (db: db, keys: keys, service: service);
  }

  Future<int> count(Database db, String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']
          as int;

  /// Phone A's shop: card codes (one sold), customers, invoices (one
  /// deleted), debts with receipts and a reversal, a logo, settings.
  Future<
      ({
        int cardId,
        int ahmad,
        int soldInvoiceId,
        int deletedInvoiceId,
        int reversedPaymentId,
        int balance,
      })> populate(AppDatabase database, SecretKeyStore keys) async {
    final db = database.db;
    final cipher = CodeCipher(keys);
    final cardId = await insertProduct(
      db,
      name: 'Card 5000',
      code: '50',
      kind: 'SERVICE',
      soldFromCodeStock: 1,
    );
    await insertProduct(db, name: 'Sugar', code: '101');
    await VoucherRepository(db, cipher).addBatch(
      productId: cardId,
      parsed: parseCodeList(
        '1111-2222-3333\n4444-5555-6666\n7777-8888-9999',
        columns: CodeColumns.codeOnly,
      ),
      now: DateTime(2026, 11, 1),
    );
    final ahmad = await insertCustomer(db, name: 'Ahmad');
    await insertCustomer(db, name: 'Sara');

    final invoices = InvoiceRepository(db, codeCipher: cipher);
    Future<Invoice> sell(List<CartLine> lines) {
      var cart = const Cart();
      for (final line in lines) {
        cart = cart.add(line);
      }
      return invoices.save(Invoice.fromCart(
        cart: cart,
        ctx: ctx,
        createdAt: DateTime.utc(2026, 11, 20, 10),
        customerId: ahmad,
        customerName: 'Ahmad',
      ));
    }

    final sold = await sell([
      CartLine(
        productId: cardId,
        name: 'Card 5000',
        kind: ProductKind.service,
        unitPriceMinor: 5000,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
        codeStock: true,
      ),
    ]);
    final deleted = await sell([
      const CartLine(
        name: 'Bread',
        unitPriceMinor: 700,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
      ),
    ]);
    await ArchiveRepository(db).deleteInvoice(deleted.id!);

    final debts = DebtRepository(db);
    await debts.addManualDebt(customerId: ahmad, amountBaseMinor: 9000);
    Future<DebtEntry> pay(int amount) => debts.recordPayment(
          customerId: ahmad,
          amountMinor: amount,
          currencyCode: 'SYP',
          currencyDecimals: 0,
          baseCode: 'SYP',
          baseDecimals: 0,
        );
    final first = await pay(2000); // receipt 1
    await pay(1500); // receipt 2
    await debts.reverse(first.id, reason: 'entered twice');

    final settings = SettingsRepository(db);
    await settings.setMany({
      SettingsKeys.shopName: 'Al-Baraka',
      SettingsKeys.shopLogoBase64: base64Encode([137, 80, 78, 71, 1, 2, 3]),
      // On here; phone B has no password key, so it must come back off.
      SettingsKeys.backupAutoEnabled: '1',
    });
    return (
      cardId: cardId,
      ahmad: ahmad,
      soldInvoiceId: sold.id!,
      deletedInvoiceId: deleted.id!,
      reversedPaymentId: first.id,
      balance: await debts.balanceOf(ahmad),
    );
  }

  Future<(CreatedBackup, BackupKey)> backUp(
    ({AppDatabase db, InMemoryKeyStore keys, BackupService service}) from, {
    String secret = password,
  }) async {
    final key = await newBackupKey(secret, iterations: iterations);
    final created = await from.service.create(
      from.db.db,
      key: key,
      appVersion: '1.0.0+1',
      outPath: p.join(root.path, 'out', manualBackupName(DateTime.now())),
    );
    return (created, key);
  }

  /// Phone B's own shop and its own card-code key.
  Future<String> ownData(
    ({AppDatabase db, InMemoryKeyStore keys, BackupService service}) b,
  ) async {
    await insertProduct(b.db.db, name: 'Only on B', code: 'B1');
    await CodeCipher(b.keys).encrypt('make a key');
    return b.keys.values[CodeCipher.keyName]!;
  }

  List<String> leftovers(AppDatabase database) {
    final dir = Directory(p.dirname(database.path));
    return [
      for (final f in dir.listSync())
        if (!p.basename(f.path).startsWith(AppDatabase.fileName)) p.basename(f.path),
    ];
  }

  group('round trip onto a second phone', () {
    test('everything comes back: invoices, customers, codes (decrypted and '
        'found by hash), debts, receipt and invoice counters', () async {
      final a = await phone('a');
      final shop = await populate(a.db, a.keys);
      final countsA = {
        for (final t in [
          'invoices',
          'invoice_items',
          'customers',
          'products',
          'voucher_codes',
          'voucher_batches',
          'debt_transactions',
          'audit_log',
        ])
          t: await count(a.db.db, t),
      };
      final (created, _) = await backUp(a);
      expect(created.manifest.counts.invoices, 1);
      expect(created.manifest.counts.customers, 2);
      expect(created.manifest.counts.codes, 3);
      expect(created.manifest.counts.debtEntries, 4);
      expect(created.manifest.schemaVersion, AppDatabase.schemaVersion);
      expect(created.name, matches(RegExp(r'^souqi-backup-\d{4}-\d\d-\d\d-\d{4}\.souqi$')));

      // The keys are in the file, but never in the clear.
      final zip = ZipDecoder().decodeBytes(File(created.path).readAsBytesSync());
      final aKey = a.keys.values[CodeCipher.keyName]!;
      for (final entry in zip) {
        final bytes = entry.readBytes()!;
        expect(latin1.decode(bytes, allowInvalid: true), isNot(contains(aKey)),
            reason: entry.name);
      }
      expect(zip.find(BackupEntry.logo)!.readBytes(), [137, 80, 78, 71, 1, 2, 3]);
      await a.db.close();

      final b = await phone('b');
      final bKey = await ownData(b);
      expect(bKey, isNot(aKey));

      final extracted = await b.service.inspect(created.path);
      final unlocked = await b.service.unlock(extracted, password);
      final restored = await b.service.restore(
        unlocked,
        live: b.db,
        closeLive: b.db.close,
      );
      final db = restored.db;

      // The data is A's — B's own product is gone.
      for (final entry in countsA.entries) {
        final expected =
            entry.key == 'audit_log' ? entry.value + 1 : entry.value;
        expect(await count(db, entry.key), expected, reason: entry.key);
      }
      expect(
        await db.query('products', where: 'code = ?', whereArgs: ['B1']),
        isEmpty,
      );
      final settings = SettingsRepository(db);
      expect(await settings.getString(SettingsKeys.shopName), 'Al-Baraka');
      expect(await settings.getString(SettingsKeys.backupAutoEnabled), '0',
          reason: 'no daily-backup password on phone B');
      expect(
        (await db.query('audit_log', orderBy: 'id DESC', limit: 1))
            .single['action'],
        'BACKUP_RESTORE',
      );

      // BOTH keys came back: the codes decrypt, and lookups by hash match.
      expect(b.keys.values[CodeCipher.keyName], aKey);
      final cipher = CodeCipher(b.keys);
      final vouchers = VoucherRepository(db, cipher);
      final sold = await vouchers.printableCodes(shop.soldInvoiceId);
      expect(sold.single.code, '1111-2222-3333');
      final hit = await vouchers.lookup('111122223333');
      expect(hit.single.status, VoucherStatus.sold);
      expect(hit.single.unreadable, isFalse);
      expect((await vouchers.lookup('4444 5555 6666')).single.status,
          VoucherStatus.available);
      // The duplicate guard still works: a code already in stock is refused.
      final again = await vouchers.addBatch(
        productId: shop.cardId,
        parsed: parseCodeList('7777-8888-9999', columns: CodeColumns.codeOnly),
      );
      expect(again.added, 0);

      // The ledger: balance, receipts, the reversal.
      final debts = DebtRepository(db);
      expect(await debts.balanceOf(shop.ahmad), shop.balance);
      expect(shop.balance, 9000 - 1500);
      final reversed = (await debts.entryByReceiptNo(1))!;
      expect(reversed.id, shop.reversedPaymentId);
      final reversal = await db.query('debt_transactions',
          where: 'reverses_id = ?', whereArgs: [reversed.id]);
      expect(reversal.single['type'], 'REVERSAL');
      final next = await debts.recordPayment(
        customerId: shop.ahmad,
        amountMinor: 500,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
      );
      expect(next.receiptNo, 3, reason: 'receipt numbers are never reused');
      // The ledger still refuses edits after a restore.
      await expectLater(
        db.delete('debt_transactions'),
        throwsA(anything),
      );

      // Invoice numbers and ids continue — the deleted one is not reused.
      final invoice = await InvoiceRepository(db).save(Invoice.fromCart(
        cart: const Cart().add(const CartLine(
          name: 'Tea',
          unitPriceMinor: 100,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
        )),
        ctx: ctx,
        createdAt: DateTime.utc(2026, 11, 27),
      ));
      expect(invoice.invoiceNo, 3);
      expect(invoice.id, greaterThan(shop.deletedInvoiceId));

      expect(leftovers(restored), isEmpty, reason: 'no journal left behind');
      expect(b.keys.values.containsKey(RestoreJournal.keptKeysName), isFalse);
      await restored.close();
    });

    test('a backup of a phone that never had card codes: no key comes back',
        () async {
      final a = await phone('a');
      await insertProduct(a.db.db, name: 'Rice');
      final (created, _) = await backUp(a);
      await a.db.close();

      final b = await phone('b');
      await ownData(b);
      final unlocked = await b.service
          .unlock(await b.service.inspect(created.path), password);
      expect(unlocked.voucherKeys, isNull);
      final restored = await b.service
          .restore(unlocked, live: b.db, closeLive: b.db.close);
      expect(b.keys.values.containsKey(CodeCipher.keyName), isFalse);
      expect(await count(restored.db, 'products'), 1);
      await restored.close();
    });
  });

  group('refused safely — nothing changes', () {
    late ({AppDatabase db, InMemoryKeyStore keys, BackupService service}) b;
    late String bKey;

    setUp(() async {
      b = await phone('b');
      bKey = await ownData(b);
    });

    Future<void> untouched() async {
      expect(
        await b.db.db.query('products', where: 'code = ?', whereArgs: ['B1']),
        hasLength(1),
      );
      expect(b.keys.values[CodeCipher.keyName], bKey);
    }

    tearDown(() async {
      try {
        await b.db.close();
      } on Object {
        // Closed by the test.
      }
    });

    test('a wrong password: an error, and the right one still works',
        () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, _) = await backUp(a);
      await a.db.close();

      final extracted = await b.service.inspect(created.path);
      await expectLater(
        b.service.unlock(extracted, 'not the password'),
        throwsA(isA<WrongBackupPasswordException>()),
      );
      await untouched();
      // Arabic-Indic digits are the same password.
      final a2 = await phone('a2');
      await insertProduct(a2.db.db, name: 'x');
      final (digits, _) = await backUp(a2, secret: '123456');
      await a2.db.close();
      final unlocked = await b.service
          .unlock(await b.service.inspect(digits.path), '١٢٣٤٥٦');
      expect(unlocked.manifest.counts.products, 1);
      expect(await b.service.unlock(extracted, password), isA<UnlockedBackup>());
    });

    test('a corrupted file: cut short, a byte changed, not a zip at all',
        () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, _) = await backUp(a);
      await a.db.close();
      final bytes = File(created.path).readAsBytesSync();

      final cut = File(p.join(root.path, 'cut.souqi'))
        ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await expectLater(
        b.service.inspect(cut.path),
        throwsA(isA<CorruptBackupException>()),
      );

      // One byte flipped inside the database entry's data.
      final zip = ZipDecoder().decodeBytes(bytes);
      final dbEntry = zip.find(BackupEntry.database)!;
      final damaged = Uint8List.fromList(bytes);
      final at = _indexOf(bytes, utf8.encode(BackupEntry.database), from: 30) + 400;
      damaged[at] ^= 0xFF;
      final flipped = File(p.join(root.path, 'flipped.souqi'))
        ..writeAsBytesSync(damaged);
      expect(dbEntry.size, greaterThan(0));
      await expectLater(
        b.service.inspect(flipped.path),
        throwsA(isA<CorruptBackupException>()),
      );

      final photo = File(p.join(root.path, 'photo.souqi'))
        ..writeAsBytesSync(List.filled(5000, 7));
      await expectLater(
        b.service.inspect(photo.path),
        throwsA(isA<CorruptBackupException>()),
      );

      // Another zip, with no manifest.
      final other = File(p.join(root.path, 'other.souqi'))
        ..writeAsBytesSync(ZipEncoder()
            .encodeBytes(Archive()..add(ArchiveFile.string('a.txt', 'hi'))));
      await expectLater(
        b.service.inspect(other.path),
        throwsA(isA<CorruptBackupException>()),
      );
      await untouched();
    });

    test('a file altered after it was made (checksums recomputed): the '
        'password is right but the signature is not', () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, _) = await backUp(a);
      await a.db.close();

      final extracted = await b.service.inspect(created.path);
      // Change the data and repack it with fresh checksums — without the
      // password there is no way to sign the new manifest.
      final raw = await databaseFactoryFfi.openDatabase(extracted.database.path);
      await raw.update('settings', {'value': 'Someone else'},
          where: 'key = ?', whereArgs: [SettingsKeys.shopName]);
      await raw.close();
      final forged = await _repack(
        extracted,
        p.join(root.path, 'forged.souqi'),
        sign: (bytes) => 'f' * 64,
      );
      await extracted.discard();

      final reopened = await b.service.inspect(forged);
      await expectLater(
        b.service.unlock(reopened, password),
        throwsA(isA<CorruptBackupException>()),
      );
      await untouched();
    });

    test('a backup from a NEWER version is refused before the password',
        () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, key) = await backUp(a);
      await a.db.close();

      final extracted = await b.service.inspect(created.path);
      final newer = await _repack(
        extracted,
        p.join(root.path, 'newer.souqi'),
        schemaVersion: AppDatabase.schemaVersion + 1,
        sign: key.sign,
      );
      await extracted.discard();
      await expectLater(
        b.service.inspect(newer),
        throwsA(isA<NewerBackupException>().having(
          (e) => e.backupSchema,
          'backupSchema',
          AppDatabase.schemaVersion + 1,
        )),
      );
      await untouched();
    });

    test('a database file newer than its manifest says is refused at the '
        'restore, and the live data stays open and untouched', () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, key) = await backUp(a);
      await a.db.close();

      final extracted = await b.service.inspect(created.path);
      final raw = await databaseFactoryFfi.openDatabase(extracted.database.path);
      await raw.execute('PRAGMA user_version = 99');
      await raw.close();
      final lying = await _repack(
        extracted,
        p.join(root.path, 'lying.souqi'),
        sign: key.sign,
      );
      await extracted.discard();

      final unlocked =
          await b.service.unlock(await b.service.inspect(lying), password);
      await expectLater(
        b.service.restore(unlocked, live: b.db, closeLive: b.db.close),
        throwsA(isA<NewerBackupException>()),
      );
      await untouched();
      expect(leftovers(b.db), isEmpty);
    });
  });

  test('a backup made by an OLDER version (schema 5) is migrated after the '
      'restore', () async {
    final oldPath = p.join(root.path, 'old', 'souqi.db');
    await Directory(p.dirname(oldPath)).create(recursive: true);
    final old = await databaseFactoryFfi.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final m in AppDatabase.migrations) {
            if (m.version <= 5) await m.apply(db);
          }
        },
      ),
    );
    final sugar = await insertProduct(old, name: 'Sugar', code: '101');
    final ahmad = await insertCustomer(old);
    final invoice = await insertInvoice(old, invoiceNo: 1);
    await insertInvoiceItem(old, invoiceId: invoice, productId: sugar);
    await DebtRepository(old).addManualDebt(customerId: ahmad, amountBaseMinor: 700);
    final keys = InMemoryKeyStore();
    final service = BackupService(
      factory: databaseFactoryFfi,
      keys: keys,
      workDir: () async => Directory(p.join(root.path, 'old-work')),
    );
    final key = await newBackupKey(password, iterations: iterations);
    final created = await service.create(
      old,
      key: key,
      appVersion: '0.9.0+1',
      outPath: p.join(root.path, 'out', 'old.souqi'),
    );
    await old.close();
    expect(created.manifest.schemaVersion, 5);

    final b = await phone('b');
    await ownData(b);
    final unlocked =
        await b.service.unlock(await b.service.inspect(created.path), password);
    final restored =
        await b.service.restore(unlocked, live: b.db, closeLive: b.db.close);
    final db = restored.db;
    expect(
      (await db.rawQuery('PRAGMA user_version')).first.values.first,
      AppDatabase.schemaVersion,
    );
    expect(await db.query('price_changes'), isEmpty, reason: 'v6 table there');
    expect(await count(db, 'invoices'), 1);
    expect(await DebtRepository(db).balanceOf(ahmad), 700);
    await restored.close();
  });

  group('atomic: a failure at any step of the swap puts everything back', () {
    for (final step in ['prepared', 'moved-old', 'moved-new', 'keys', 'opened']) {
      test('fails at "$step"', () async {
        final a = await phone('a');
        await populate(a.db, a.keys);
        final (created, _) = await backUp(a);
        await a.db.close();

        final b = await phone('b');
        final bKey = await ownData(b);
        final unlocked = await b.service
            .unlock(await b.service.inspect(created.path), password);

        AppDatabase? reopened;
        try {
          await b.service.restore(
            unlocked,
            live: b.db,
            closeLive: b.db.close,
            fault: (at) {
              if (at == step) throw const FileSystemException('power cut');
            },
          );
          fail('the restore should have failed');
        } on RestoreFailedException<AppDatabase> catch (e) {
          reopened = e.database;
        } on FileSystemException {
          // Before the swap: the live database was never closed.
          expect(step, 'prepared');
          reopened = b.db;
        }
        final db = reopened.db;
        expect(
          await db.query('products', where: 'code = ?', whereArgs: ['B1']),
          hasLength(1),
          reason: "phone B's own data",
        );
        expect(await count(db, 'invoices'), 0);
        expect(b.keys.values[CodeCipher.keyName], bKey, reason: 'its own key');
        expect(b.keys.values.containsKey(RestoreJournal.keptKeysName), isFalse);
        expect(leftovers(reopened), isEmpty);
        // And it is a working database.
        await insertProduct(db, name: 'After', code: 'B2');
        await reopened.close();
      });
    }
  });

  group('a restore the app was killed in the middle of', () {
    test('"swapping": the next start puts the old shop back', () async {
      final b = await phone('b');
      final bKey = await ownData(b);
      final path = b.db.path;
      await b.db.close();
      final journal = RestoreJournal(dbPath: path, keys: b.keys);

      // The state right after step 5 — new file in place, new key written.
      await b.keys.write(RestoreJournal.keptKeysName, bKey);
      File(journal.markerPath).writeAsStringSync('{"stage":"swapping"}');
      File(path).renameSync(journal.beforePath);
      final other = await phone('other');
      await insertProduct(other.db.db, name: 'Restored', code: 'R1');
      await other.db.close();
      File(other.db.path).copySync(path);
      await b.keys.write(CodeCipher.keyName, 'the restored key');
      expect(await RestoreJournal.pending(path), isTrue);

      expect(await journal.recover(), RestoreRecovery.rolledBack);
      expect(await RestoreJournal.pending(path), isFalse);
      expect(b.keys.values[CodeCipher.keyName], bKey);
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      expect(
        await db.db.query('products', where: 'code = ?', whereArgs: ['B1']),
        hasLength(1),
      );
      expect(File(journal.beforePath).existsSync(), isFalse);
      await db.close();
    });

    test('"committed": the next start only tidies up', () async {
      final b = await phone('b');
      await ownData(b);
      final path = b.db.path;
      await b.db.close();
      final journal = RestoreJournal(dbPath: path, keys: b.keys);
      File(journal.beforePath).writeAsStringSync('old');
      await b.keys.write(RestoreJournal.keptKeysName, 'old key');
      File(journal.markerPath).writeAsStringSync('{"stage":"committed"}');

      expect(await journal.recover(), RestoreRecovery.completed);
      expect(File(journal.beforePath).existsSync(), isFalse);
      expect(b.keys.values.containsKey(RestoreJournal.keptKeysName), isFalse);
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('restoreBackup (the app side)', () {
    test('waits for nobody: refused while the daily job holds the lock; '
        'otherwise restores and restarts the app on the new database',
        () async {
      final a = await phone('a');
      await populate(a.db, a.keys);
      final (created, _) = await backUp(a);
      await a.db.close();

      final b = await phone('b');
      await ownData(b);
      final platform = FakeReportPlatform()..locked = true;
      AppDatabase? restartedOn;
      AppRestartNotice? notice;
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(b.db),
        databaseFactoryProvider.overrideWithValue(databaseFactoryFfi),
        secretKeyStoreProvider.overrideWithValue(b.keys),
        backupWorkDirProvider
            .overrideWithValue(() async => Directory(p.join(root.path, 'b', 'work'))),
        reportPlatformProvider.overrideWithValue(platform),
        appRestartProvider.overrideWithValue((db, n) async {
          restartedOn = db;
          notice = n;
        }),
      ]);
      addTearDown(container.dispose);
      final service = container.read(backupServiceProvider);
      final unlocked =
          await service.unlock(await service.inspect(created.path), password);

      await expectLater(
        restoreBackup(container, unlocked),
        throwsA(isA<BackupBusyException>()),
      );
      expect(restartedOn, isNull);

      platform.locked = false;
      await restoreBackup(container, unlocked);
      expect(notice, AppRestartNotice.restored);
      expect(await count(restartedOn!.db, 'invoices'), 1);
      expect(platform.locked, isFalse, reason: 'the lock is given back');
      await restartedOn!.close();
    });
  });
}

int _indexOf(List<int> haystack, List<int> needle, {int from = 0}) {
  for (var i = from; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  throw StateError('not found');
}

/// Packs [extracted] again with fresh checksums — what someone without the
/// password could do — optionally claiming another schema version.
Future<String> _repack(
  ExtractedBackup extracted,
  String out, {
  int? schemaVersion,
  required String Function(List<int> bytes) sign,
}) async {
  final m = extracted.manifest;
  final files = <String, File>{
    BackupEntry.database: extracted.database,
    BackupEntry.secrets: extracted.secrets,
    if (extracted.logo != null) BackupEntry.logo: extracted.logo!,
  };
  final manifest = BackupManifest(
    appVersion: m.appVersion,
    schemaVersion: schemaVersion ?? m.schemaVersion,
    createdAt: m.createdAt,
    counts: m.counts,
    files: [
      for (final e in files.entries) await describeFile(e.key, e.value),
    ],
    kdf: m.kdf,
  );
  final bytes = manifest.toBytes();
  await writeBackupZip(out, manifest: bytes, signature: sign(bytes), files: files);
  return out;
}
