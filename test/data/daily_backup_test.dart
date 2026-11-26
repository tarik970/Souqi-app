import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:souqi/core/backup/backup_crypto.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/data/backup/backup_service.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/features/backup/auto_backup.dart';
import 'package:souqi/features/backup/backup_providers.dart';
import 'package:souqi/features/customers/customers_providers.dart';
import 'package:souqi/features/debts/report/daily_job.dart';
import 'package:souqi/features/debts/report/report_providers.dart';
import 'package:souqi/features/debts/report/report_schedule.dart';
import 'package:souqi/features/debts/report/report_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../features/report_test_utils.dart';
import 'db_test_utils.dart';

/// The daily automatic backup as the SECOND output of the daily job: same
/// run, same folder, its own on/off and its own keep-N.
void main() {
  setUpAll(sqfliteFfiInit);

  const password = 'nightly-1';
  const folder =
      'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3ASouqi';

  late AppDatabase database;
  late FakeReportPlatform platform;
  late Directory root;
  late Directory staging;
  late InMemoryKeyStore keys;
  final today = DateTime.now();

  setUp(() async {
    database = await openTestDb();
    platform = FakeReportPlatform();
    root = await Directory.systemTemp.createTemp('souqi-daily-backup-');
    staging = Directory(p.join(root.path, 'reports'));
    keys = InMemoryKeyStore();
    await insertProduct(database.db, name: 'Sugar');
    await insertCustomer(database.db, name: 'Ahmad');
  });

  tearDown(() async {
    await database.close();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // A handle still closing on Windows.
    }
  });

  Future<Directory> work() async => Directory(p.join(root.path, 'work'));

  Future<void> setPassword() async {
    final key = await newBackupKey(password, iterations: 1000);
    await keys.write(autoBackupKeyName, key.toStored());
  }

  Future<void> configure({
    required bool report,
    required bool backup,
    int reportKeep = 30,
    int backupKeep = 3,
    String? folderUri = folder,
  }) =>
      SettingsRepository(database.db).setMany({
        ...DebtReportSettings(
          enabled: report,
          keepDays: reportKeep,
          folderUri: folderUri,
          notify: false,
        ).toMap(),
        ...AutoBackupSettings(enabled: backup, keepDays: backupKeep).toMap(),
      });

  DailyReportJob job({bool featureOn = true}) => DailyReportJob(
        db: database.db,
        platform: platform,
        stagingDir: () async => staging,
        loadFonts: testReportFonts,
        featureOn: featureOn,
        backupOutput: (stored) => autoBackupOutput(
          stored,
          keys: keys,
          factory: databaseFactoryFfi,
          workDir: work,
          appVersion: () async => '1.0.0+1',
        ),
      );

  String backupName([DateTime? day]) =>
      autoBackupFiles.nameFor(day ?? today, 'souqi');
  String reportName(String ext, [DateTime? day]) =>
      debtReportFiles.nameFor(day ?? today, ext);

  test('one run, one folder, two keep-N rules that never touch each other',
      () async {
    await setPassword();
    await configure(report: true, backup: true, reportKeep: 30, backupKeep: 3);
    final mine = platform.folder(folder);
    for (var day = 1; day <= 40; day++) {
      final at = today.subtract(Duration(days: day));
      mine[reportName('xlsx', at)] = Uint8List(1);
      mine[reportName('pdf', at)] = Uint8List(1);
      if (day <= 6) mine[backupName(at)] = Uint8List(1);
    }
    // A backup made by hand, and a stranger's file: never rotated.
    mine['souqi-backup-2026-01-02-1430.souqi'] = Uint8List(1);
    mine['family photos.zip'] = Uint8List(1);

    final result = await job().run(ReportTrigger.scheduled);
    expect(result.outcome, ReportOutcome.ok);

    final backupDays = {for (final n in mine.keys) ?autoBackupFiles.dayKeyOf(n)};
    final reportDays = {for (final n in mine.keys) ?debtReportFiles.dayKeyOf(n)};
    expect(backupDays, hasLength(3), reason: 'the backup keeps 3 days');
    expect(reportDays, hasLength(30), reason: 'the report keeps its 30');
    expect(mine, contains(backupName()));
    expect(mine, contains(backupName(today.subtract(const Duration(days: 2)))));
    expect(mine, isNot(contains(backupName(today.subtract(const Duration(days: 3))))));
    expect(mine, contains('souqi-backup-2026-01-02-1430.souqi'));
    expect(mine, contains('family photos.zip'));

    // The status: the report's files for "Share", the backup's date apart.
    final status = DebtReportStatus.fromJson(platform.status);
    expect(status.files, hasLength(2));
    expect(status.files.every((f) => !f.endsWith('.souqi')), isTrue);
    expect(status.lastBackupAt, isNotNull);
    // The staged copy of the backup is gone; the report's stay.
    expect(
      staging.listSync().map((f) => p.basename(f.path)),
      isNot(contains(backupName())),
    );

    // What was written is a real backup that opens with the password.
    final file = File(p.join(root.path, 'written.souqi'))
      ..writeAsBytesSync(mine[backupName()]!);
    final service = BackupService(
      factory: databaseFactoryFfi,
      keys: InMemoryKeyStore(),
      workDir: () async => Directory(p.join(root.path, 'check')),
    );
    final opened =
        await service.unlock(await service.inspect(file.path), password);
    expect(opened.manifest.counts.products, 1);
    expect(opened.manifest.counts.customers, 1);
  });

  test('the backup runs with the debt report off — and the ledger off',
      () async {
    await setPassword();
    await configure(report: false, backup: true, folderUri: null);
    final result = await job(featureOn: false).run(ReportTrigger.scheduled);
    expect(result.outcome, ReportOutcome.ok);
    expect(platform.folder(null).keys, [backupName()]);
    expect(platform.notices, isEmpty, reason: 'nothing to say when it worked');
  });

  test('a backup-only run that falls back to Downloads says so as a BACKUP',
      () async {
    await setPassword();
    await configure(report: false, backup: true);
    platform.folderOk = false;
    final result = await job().run(ReportTrigger.scheduled);
    expect(result.outcome, ReportOutcome.fallback);
    expect(platform.folder(null).keys, [backupName()]);
    expect(platform.notices.single.title, 'حُفظت النسخة اليومية في التنزيلات');
  });

  test('on, but no password on this phone: no backup, the report goes on',
      () async {
    await configure(report: true, backup: true);
    await job().run(ReportTrigger.scheduled);
    expect(platform.folder(folder).keys.where(autoBackupFiles.matches), isEmpty);
    expect(platform.folder(folder), contains(reportName('xlsx')));

    await configure(report: false, backup: true);
    expect((await job().run(ReportTrigger.scheduled)).skipped, isTrue);
  });

  test('"Create report now" makes the report only', () async {
    await setPassword();
    await configure(report: true, backup: true);
    await job().run(ReportTrigger.manual);
    expect(platform.folder(folder).keys.where(autoBackupFiles.matches), isEmpty);
    expect(platform.folder(folder), contains(reportName('pdf')));
  });

  test('app start: planned while the backup alone is on, dropped when off',
      () async {
    await setPassword();
    await configure(report: false, backup: true);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database),
      databaseFactoryProvider.overrideWithValue(databaseFactoryFfi),
      secretKeyStoreProvider.overrideWithValue(keys),
      backupWorkDirProvider.overrideWithValue(work),
      appVersionProvider.overrideWithValue(() async => '1.0.0+1'),
      reportPlatformProvider.overrideWithValue(platform),
      reportStagingDirProvider.overrideWithValue(() async => staging),
      reportFontsProvider.overrideWithValue(testReportFonts),
      clockProvider.overrideWithValue(DateTime.now),
    ]);
    addTearDown(container.dispose);
    // Due at midnight; turned on days ago: today's is owed.
    await SettingsRepository(database.db).setMany({
      ...const DebtReportSettings(minuteOfDay: 0).toMap(),
      ...AutoBackupSettings(
        enabled: true,
        keepDays: 7,
        enabledAt: DateTime.now().subtract(const Duration(days: 3)),
      ).toMap(),
    });
    await debtReportOnAppStart(container);
    expect(platform.schedules.single.minute, 0);
    expect(platform.folder(null).keys, [backupName()], reason: 'caught up');

    await keys.delete(autoBackupKeyName);
    container.invalidate(autoBackupHasKeyProvider);
    await debtReportOnAppStart(container);
    expect(platform.cancels, 1, reason: 'nothing left to make');
  });
}
