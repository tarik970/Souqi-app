import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:souqi/app_root.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/backup/backup_crypto.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/licensing/license_service.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/data/backup/backup_service.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/features/backup/auto_backup.dart';
import 'package:souqi/features/debts/report/daily_job.dart';
import 'package:souqi/features/debts/report/report_settings.dart';
import 'package:souqi/features/license/background_license.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/licensing/license_test_kit.dart';
import '../features/invoice_test_utils.dart';
import '../features/report_test_utils.dart';
import 'db_test_utils.dart';

/// LICENSING WHERE THE DATA IS WRITTEN — not on the screens: what a phone
/// without a license can and cannot do with the shop's database, what a
/// backup carries to another phone, and what the background job makes.
///
/// Real database FILES, an in-memory Keystore per phone, a fake device
/// identity per phone, and a developer key made for this run.
void main() {
  setUpAll(sqfliteFfiInit);
  tearDown(FeatureGate.reset);

  late TestDeveloper developer;
  late Directory root;
  late TestClock clock;

  final t0 = DateTime.utc(2026, 11, 26, 10);
  const password = 'souq-2026';

  setUpAll(() async => developer = await TestDeveloper.create());

  setUp(() async {
    root = await Directory.systemTemp.createTemp('souqi-license-test-');
    clock = TestClock(t0);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle for a moment.
    }
  });

  /// One phone: its identity, its Keystore, its database file — and the
  /// licensing service an app start would make on them.
  Future<_Phone> phone(String name, {required String androidId}) async {
    final dir = Directory(p.join(root.path, name, 'databases'));
    await dir.create(recursive: true);
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, AppDatabase.fileName),
    );
    return _Phone(
      name: name,
      root: root,
      db: db,
      keys: InMemoryKeyStore(),
      platform: FakeLicensePlatform(androidId: androidId),
      clock: clock,
      developer: developer,
    );
  }

  Future<_Phone> phoneA() => phone('a', androidId: 'aaaaaaaa11111111');

  Future<_Phone> phoneB() => phone('b', androidId: 'bbbbbbbb22222222');

  /// Seven days and a bit: the trial of a phone started at [t0] is over.
  void endTrial() => clock.now = t0.add(const Duration(days: 8));

  group('every app start', () {
    test('makes the license check before the first screen exists',
        () async {
      final a = await phoneA();
      // The app itself: its own clock, its own (public) key.
      final first = await AppStart.load(
        a.db,
        keys: a.keys,
        platform: a.platform,
      );
      expect(first.license.status.mode, LicenseMode.trial);
      expect(first.license.requestCode, a.platform.requestCode);
      expect(FeatureGate.mask, first.license.status.featureMask);
      // The trial began with that first start, and is on record twice.
      final settings = SettingsRepository(a.db.db);
      final state = jsonDecode(
        (await settings.getStringOrNull(SettingsKeys.licenseState))!,
      ) as Map;
      expect(state['trial'], greaterThan(0));
      expect(a.keys.values.values.join(), contains('"trial":${state['trial']}'));

      // The same phone a month later: the next start finds the trial over
      // and the app is closed for selling from its first frame.
      final monthAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      await settings.setString(
        SettingsKeys.licenseState,
        jsonEncode({...state, 'trial': monthAgo}),
      );
      a.keys.values.clear();
      final later = await AppStart.load(
        a.db,
        keys: a.keys,
        platform: a.platform,
      );
      expect(later.license.status.mode, LicenseMode.unlicensed);
      expect(later.license.status.reason, UnlicensedReason.trialDaysOver);
      await expectLater(
        InvoiceRepository(a.db.db, guard: later.license).save(sypInvoice()),
        throwsA(isA<LicenseRequiredException>()),
      );
      await a.db.close();
    });
  });

  group('selling', () {
    test('a sale is refused without a license, and nothing is saved',
        () async {
      final a = await phoneA();
      final licensing = await a.start();
      final invoices = InvoiceRepository(a.db.db, guard: licensing);

      // On the trial: saved.
      final first = await invoices.save(sypInvoice());
      expect(first.invoiceNo, 1);

      endTrial();
      await expectLater(
        invoices.save(sypInvoice()),
        throwsA(isA<LicenseRequiredException>()
            .having((e) => e.action, 'action', LicensedAction.sell)),
      );
      expect(await a.count('invoices'), 1);
      expect(await a.count('invoice_items'), first.items.length);
      // The number was not used up either.
      expect(await invoices.peekNextInvoiceNo(), 2);

      // Activated: selling again.
      expect((await licensing.activate(await a.license())).ok, isTrue);
      expect((await invoices.save(sypInvoice())).invoiceNo, 2);
      await a.db.close();
    });

    test('the thirty-first invoice of a trial is refused by the repository',
        () async {
      final a = await phoneA();
      final licensing = await a.start();
      final invoices = InvoiceRepository(a.db.db, guard: licensing);
      for (var i = 0; i < 30; i++) {
        await invoices.save(sypInvoice(lines: 1));
      }
      expect(licensing.status.mode, LicenseMode.unlicensed);
      expect(licensing.status.reason, UnlicensedReason.trialInvoicesOver);
      await expectLater(
        invoices.save(sypInvoice(lines: 1)),
        throwsA(isA<LicenseRequiredException>()),
      );
      expect(await a.count('invoices'), 30);
      // The thirtieth can still be printed; a thirty-first cannot be made.
      await licensing.ensureCanPrint();
      await a.db.close();
    });

    test('a repository without a guard is a test\'s: it checks nothing',
        () async {
      final a = await phoneA();
      await a.start();
      endTrial();
      expect((await InvoiceRepository(a.db.db).save(sypInvoice())).id, isNotNull);
      await a.db.close();
    });
  });

  group('without a license the shop\'s data is still its own', () {
    test('new debt entries are refused; balances and statements are read',
        () async {
      final a = await phoneA();
      final licensing = await a.start();
      final debts = DebtRepository(a.db.db, guard: licensing);
      final ahmad = await insertCustomer(a.db.db, name: 'Ahmad');
      await debts.addManualDebt(customerId: ahmad, amountBaseMinor: 50000);
      final payment = await debts.recordPayment(
        customerId: ahmad,
        amountMinor: 20000,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
      );
      expect(await debts.balanceOf(ahmad), 30000);

      endTrial();
      final refused = throwsA(isA<LicenseRequiredException>()
          .having((e) => e.action, 'action', LicensedAction.recordDebt));
      await expectLater(
        debts.addManualDebt(customerId: ahmad, amountBaseMinor: 1000),
        refused,
      );
      await expectLater(
        debts.recordPayment(
          customerId: ahmad,
          amountMinor: 1000,
          currencyCode: 'SYP',
          currencyDecimals: 0,
          baseCode: 'SYP',
          baseDecimals: 0,
        ),
        refused,
      );
      await expectLater(
        debts.addOpeningBalance(customerId: ahmad, amountBaseMinor: 1000),
        refused,
      );
      await expectLater(
        debts.addAdjustment(
          customerId: ahmad,
          amountBaseMinor: 1000,
          increasesDebt: true,
          reason: 'x',
        ),
        refused,
      );
      await expectLater(debts.reverse(payment.id, reason: 'x'), refused);
      expect(await a.count('debt_transactions'), 2, reason: 'nothing written');

      // READ-ONLY: every figure is still there.
      expect(await debts.balanceOf(ahmad), 30000);
      final snapshot = await debts.debtors(now: clock.now);
      expect(snapshot.debtors.single.balanceBaseMinor, 30000);
      expect((await debts.ledger(ahmad)).length, 2);
      expect(await debts.hasEntries(), isTrue);
      await a.db.close();
    });

    test('the archive opens, and nothing in it is locked or deleted',
        () async {
      final a = await phoneA();
      final licensing = await a.start();
      final invoices = InvoiceRepository(a.db.db, guard: licensing);
      final saved = [
        for (var i = 0; i < 3; i++) await invoices.save(sypInvoice()),
      ];
      endTrial();
      expect((await licensing.refresh()).isUnlicensed, isTrue);

      final archive = ArchiveRepository(a.db.db);
      expect(await archive.countMatching(const ArchiveFilter()), 3);
      final page = await archive.page(filter: const ArchiveFilter());
      expect(page.map((e) => e.invoiceNo), containsAll([1, 2, 3]));
      final whole = await archive.getById(saved.first.id!);
      expect(whole!.items, hasLength(saved.first.items.length));
      expect(whole.totalMinor, saved.first.totalMinor);
      expect(await invoices.getByNumber(2), isNotNull);
      await a.db.close();
    });

    test('a backup can be made — and restored — on a phone without a license',
        () async {
      final a = await phoneA();
      final licensing = await a.start();
      await InvoiceRepository(a.db.db, guard: licensing).save(sypInvoice());
      await insertCustomer(a.db.db, name: 'Ahmad');
      endTrial();
      expect((await licensing.refresh()).isUnlicensed, isTrue);

      final created = await a.backUp(password);
      expect(created.manifest.counts.invoices, 1);
      expect(created.manifest.counts.customers, 1);

      // …and put back on the same, still unlicensed, phone.
      await insertCustomer(a.db.db, name: 'Added after the backup');
      final unlocked = await a.service
          .unlock(await a.service.inspect(created.path), password);
      final restored =
          await a.service.restore(unlocked, live: a.db, closeLive: a.db.close);
      a.db = restored;
      expect(await a.count('customers'), 1);
      expect(await a.count('invoices'), 1);
      expect((await a.start()).status.isUnlicensed, isTrue);
      await restored.close();
    });
  });

  group('a license belongs to the device', () {
    test('a backup does not carry the activation code', () async {
      final a = await phoneA();
      final licensing = await a.start();
      await licensing.activate(await a.license(shop: 'Shop A'));
      final settings = SettingsRepository(a.db.db);
      expect(await settings.getStringOrNull(SettingsKeys.licenseCode), isNotNull);

      final created = await a.backUp(password);
      // Looked at where it will land: on another phone.
      final b = await phoneB();
      final unlocked = await b.service
          .unlock(await b.service.inspect(created.path), password);
      final restored =
          await b.service.restore(unlocked, live: b.db, closeLive: b.db.close);
      expect(
        await SettingsRepository(restored.db)
            .getStringOrNull(SettingsKeys.licenseCode),
        isNull,
      );
      // The live database of A still has its own.
      expect(await settings.getStringOrNull(SettingsKeys.licenseCode), isNotNull);
      await a.db.close();
      await restored.close();
    });

    test('restore on another device needs a new activation', () async {
      // Phone A: licensed, with a month of history.
      final a = await phoneA();
      final licensingA = await a.start();
      await licensingA.activate(await a.license(shop: 'Shop A'));
      await InvoiceRepository(a.db.db, guard: licensingA).save(sypInvoice());
      clock.advance(const Duration(days: 30));
      await licensingA.refresh();
      final created = await a.backUp(password);
      await a.db.close();

      // Phone B: a fresh install, on its own trial.
      final b = await phoneB();
      expect((await b.start()).status.mode, LicenseMode.trial);

      final unlocked = await b.service
          .unlock(await b.service.inspect(created.path), password);
      b.db = await b.service
          .restore(unlocked, live: b.db, closeLive: b.db.close);

      // The app starts over on the restored data.
      final licensingB = await b.start();
      expect(licensingB.status.isLicensed, isFalse,
          reason: "A's license did not travel");
      expect(licensingB.status.mode, LicenseMode.unlicensed);
      expect(licensingB.status.license, isNull);
      expect(licensingB.requestCode, b.platform.requestCode);
      expect(licensingB.requestCode, isNot(a.platform.requestCode));
      await expectLater(
        InvoiceRepository(b.db.db, guard: licensingB).save(sypInvoice()),
        throwsA(isA<LicenseRequiredException>()),
      );
      // The data itself is all there.
      expect(await b.count('invoices'), 1);

      // A's code is worth nothing on B…
      expect(
        (await licensingB.activate(await a.license(shop: 'Shop A'))).error,
        ActivationError.wrongDevice,
      );
      // …B's own code is what it needs.
      expect((await licensingB.activate(await b.license(shop: 'Shop A'))).ok,
          isTrue);
      expect(
        (await InvoiceRepository(b.db.db, guard: licensingB).save(sypInvoice()))
            .invoiceNo,
        2,
      );
      await b.db.close();
    });

    test('a restore does not replace the license the phone already has',
        () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license(shop: 'Shop A'));
      final created = await a.backUp(password);
      await a.db.close();

      final b = await phoneB();
      final licensingB = await b.start();
      await licensingB.activate(
        await b.license(shop: 'Shop B', features: [Feature.barcode]),
      );

      final unlocked = await b.service
          .unlock(await b.service.inspect(created.path), password);
      b.db = await b.service
          .restore(unlocked, live: b.db, closeLive: b.db.close);

      final after = await b.start();
      expect(after.status.isLicensed, isTrue);
      expect(after.status.shopName, 'Shop B', reason: "B's own license");
      expect(after.status.featureMask, Feature.barcode.bit);
      // Written back into the restored database: its copy and the shop name.
      final settings = SettingsRepository(b.db.db);
      expect(await settings.getStringOrNull(SettingsKeys.licenseCode), isNotNull);
      expect(await settings.getString(SettingsKeys.shopName), 'Shop B');
      await b.db.close();
    });

    test('a trial that is used up stays used up after backup, wipe and '
        'restore', () async {
      final a = await phoneA();
      await a.start();
      clock.advance(const Duration(days: 6));
      await (await a.start()).refresh();
      final created = await a.backUp(password);
      await a.db.close();

      // "Clear data" and a fresh start: a new trial would begin…
      clock.advance(const Duration(days: 5));
      final wiped = await phone('a-again', androidId: 'aaaaaaaa11111111');
      expect((await wiped.start()).status.mode, LicenseMode.trial);
      // …but the shop's data brings its own back.
      final unlocked = await wiped.service
          .unlock(await wiped.service.inspect(created.path), password);
      wiped.db = await wiped.service
          .restore(unlocked, live: wiped.db, closeLive: wiped.db.close);
      final status = (await wiped.start()).status;
      expect(status.mode, LicenseMode.unlicensed);
      expect(status.reason, UnlicensedReason.trialDaysOver);
      await wiped.db.close();
    });
  });

  group('the background job checks the license itself', () {
    const folder =
        'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3ASouqi';

    /// The daily report and the daily backup both turned on.
    Future<void> turnOn(_Phone a) async {
      final key = await newBackupKey(password, iterations: 1000);
      await a.keys.write(autoBackupKeyName, key.toStored());
      await SettingsRepository(a.db.db).setMany({
        ...const DebtReportSettings(
          enabled: true,
          folderUri: folder,
          notify: false,
        ).toMap(),
        ...const AutoBackupSettings(enabled: true).toMap(),
      });
      final ahmad = await insertCustomer(a.db.db, name: 'Ahmad');
      await DebtRepository(a.db.db)
          .addManualDebt(customerId: ahmad, amountBaseMinor: 50000);
    }

    /// One night's run of the background engine; returns the file names it
    /// wrote.
    Future<List<String>> night(_Phone a) async {
      final platform = FakeReportPlatform();
      final result = await runDailyJobInBackground(
        db: a.db.db,
        platform: platform,
        // The engine's own service: it never saw the app's check.
        license: a.newService(),
        stagingDir: () async => Directory(p.join(root.path, a.name, 'reports')),
        loadFonts: testReportFonts,
        clock: clock.call,
        backupOutput: (stored) => autoBackupOutput(
          stored,
          keys: a.keys,
          factory: databaseFactoryFfi,
          workDir: () async => Directory(p.join(root.path, a.name, 'work')),
          appVersion: () async => '1.0.0+1',
        ),
      );
      expect(result.busy, isFalse);
      return platform.folder(folder).keys.toList()..sort();
    }

    bool isReport(String name) => name.startsWith('souqi-debts-');
    bool isBackup(String name) => name.endsWith('.souqi');

    test('every feature licensed: the report and the backup', () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license());
      await turnOn(a);
      final files = await night(a);
      expect(files.where(isReport), hasLength(2), reason: 'xlsx + pdf');
      expect(files.where(isBackup), hasLength(1));
      await a.db.close();
    });

    test('a license without the daily report: no report, the backup still',
        () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license(
        features: [Feature.debt, Feature.backup],
      ));
      await turnOn(a);
      final files = await night(a);
      expect(files.where(isReport), isEmpty);
      expect(files.where(isBackup), hasLength(1));
      expect(featureOn(Feature.dailyReport), isFalse,
          reason: 'featureOn answers by the license in this engine too');
      expect(featureOn(Feature.debt), isTrue);
      await a.db.close();
    });

    test('a license without the ledger: no report either', () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license(
        features: [Feature.customers, Feature.backup, Feature.barcode],
      ));
      await turnOn(a);
      final files = await night(a);
      expect(files.where(isReport), isEmpty);
      expect(files.where(isBackup), hasLength(1));
      await a.db.close();
    });

    test('a license without backups: the report, no backup', () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license(
        features: [Feature.dailyReport],
      ));
      await turnOn(a);
      final files = await night(a);
      expect(files.where(isReport), hasLength(2));
      expect(files.where(isBackup), isEmpty);
      await a.db.close();
    });

    test('NOT licensed (the trial is over): the report and the backup go on',
        () async {
      final a = await phoneA();
      await a.start();
      await turnOn(a);
      endTrial();
      final files = await night(a);
      expect(files.where(isReport), hasLength(2));
      expect(files.where(isBackup), hasLength(1));
      await a.db.close();
    });

    test('an expired license keeps its own features, no more', () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license(
        features: [Feature.debt, Feature.backup],
        expiresAt: t0.add(const Duration(days: 30)),
      ));
      await turnOn(a);
      clock.advance(const Duration(days: 60));
      final files = await night(a);
      expect(files.where(isReport), isEmpty);
      expect(files.where(isBackup), hasLength(1));
      await a.db.close();
    });

    test('the engine only reads: it writes neither store', () async {
      final a = await phoneA();
      await (await a.start()).activate(await a.license());
      await turnOn(a);
      final settings = SettingsRepository(a.db.db);
      final stateBefore =
          await settings.getStringOrNull(SettingsKeys.licenseState);
      final keysBefore = Map.of(a.keys.values);
      clock.advance(const Duration(days: 3));
      await night(a);
      expect(await settings.getStringOrNull(SettingsKeys.licenseState),
          stateBefore);
      expect(a.keys.values, keysBefore);
      await a.db.close();
    });

    test('the daily job of the app itself follows the license too', () async {
      final a = await phoneA();
      await a.start();
      await turnOn(a);
      Future<DailyJobResult> run() => DailyReportJob(
            db: a.db.db,
            platform: FakeReportPlatform(),
            stagingDir: () async => Directory(p.join(root.path, 'r')),
            loadFonts: testReportFonts,
            featureOn: featureOn(Feature.dailyReport),
            clock: clock.call,
          ).run(ReportTrigger.scheduled);
      expect((await run()).skipped, isFalse);
      FeatureGate.applyWithout([Feature.dailyReport]);
      expect((await run()).skipped, isTrue);
      await a.db.close();
    });
  });
}

class _Phone {
  _Phone({
    required this.name,
    required this.root,
    required this.db,
    required this.keys,
    required this.platform,
    required this.clock,
    required this.developer,
  });

  final String name;
  final Directory root;
  AppDatabase db;
  final InMemoryKeyStore keys;
  final FakeLicensePlatform platform;
  final TestClock clock;
  final TestDeveloper developer;
  int _nextLicense = 1;

  late final BackupService service = BackupService(
    factory: databaseFactoryFfi,
    keys: keys,
    workDir: () async => Directory(p.join(root.path, name, 'work')),
  );

  LicenseService newService() => testLicenseService(
        db: db.db,
        keys: keys,
        platform: platform,
        clock: clock,
        developer: developer,
      );

  /// An app start (or start-over) on the current database.
  Future<LicenseService> start() async {
    final licensing = newService();
    await licensing.start();
    return licensing;
  }

  /// An activation code issued now for THIS phone.
  Future<String> license({
    String shop = 'Al Noor',
    Iterable<Feature>? features,
    DateTime? expiresAt,
  }) =>
      developer.license(
        device: platform.device,
        id: _nextLicense++,
        features: features,
        issuedAt: clock.now,
        expiresAt: expiresAt,
        shop: shop,
      );

  Future<CreatedBackup> backUp(String password) async => service.create(
        db.db,
        key: await newBackupKey(password, iterations: 1000),
        appVersion: '1.0.0+1',
        outPath: p.join(
          root.path,
          'out-$name',
          manualBackupName(DateTime(2026, 11, 26, 12)),
        ),
      );

  Future<int> count(String table) async =>
      (await db.db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']
          as int;
}
