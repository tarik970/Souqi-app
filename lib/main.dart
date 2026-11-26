import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'app_root.dart';
import 'config/features.dart';
import 'core/platform/report_platform.dart';
import 'core/security/secure_key_store.dart';
import 'data/backup/backup_service.dart';
import 'data/backup/restore_journal.dart';
import 'data/db/app_database.dart';
import 'features/backup/auto_backup.dart';
import 'features/backup/backup_providers.dart';
import 'features/debts/report/daily_job.dart';
import 'features/debts/report/report_providers.dart';

Future<void> main() async {
  assert(featureFlagsConsistent,
      'accounts and debt feature flags require customersEnabled');
  WidgetsFlutterBinding.ensureInitialized();

  // A restore the app was killed in the middle of (battery, force stop) is
  // finished or undone BEFORE the database is opened: one of the two
  // complete databases, with its own card-code keys, is what opens.
  try {
    await RestoreJournal(
      dbPath: await AppDatabase.defaultPath(),
      keys: const SecureStorageKeyStore(),
    ).recover();
  } on Object {
    // Nothing to recover, or the Keystore did not answer: the next start
    // tries again (the marker stays until it succeeds).
  }

  final appDb = await AppDatabase.open();
  final start = await AppStart.load(appDb);

  // What an earlier backup or restore left in the temporary folder.
  unawaited(BackupService(
    factory: databaseFactory,
    keys: const SecureStorageKeyStore(),
    workDir: appBackupWorkDir,
  ).sweep());

  runApp(SouqiRoot(start: start));
}

/// THE DAILY JOB — the debt report and the automatic backup — run by
/// WorkManager in a Flutter engine of its own with no screen
/// (android/.../DebtReportWorker.kt starts it by this name).
///
/// It builds the outputs, writes them, rotates the old files, records the
/// status and posts the notification — [DailyReportJob], the same code the
/// app runs for a catch-up or "Create report now" — and then tells the
/// worker it may end. It only READS the database.
///
/// It takes the run lock BEFORE it opens the database, and stays away while
/// a restore is half-way: a restore in the app holds the same lock for its
/// swap, so the file is never replaced under this engine.
@pragma('vm:entry-point')
Future<void> debtReportWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannelReportPlatform();
  var locked = false;
  try {
    if (await RestoreJournal.pending(await AppDatabase.defaultPath())) return;
    if (!await platform.tryBeginRun()) return;
    locked = true;
    final appDb = await AppDatabase.open();
    try {
      await DailyReportJob(
        db: appDb.db,
        platform: platform,
        stagingDir: appReportStagingDir,
        loadFonts: loadBundledReportFonts,
        // The same switch as `debtFeatureProvider`, which this engine has
        // no ProviderScope for. PHASE 5b: also check the license here.
        featureOn: debtEnabled && customersEnabled,
        backupOutput: (stored) => autoBackupOutput(
          stored,
          keys: const SecureStorageKeyStore(),
          factory: databaseFactory,
          workDir: appBackupWorkDir,
          appVersion: platformAppVersion,
        ),
      ).run(ReportTrigger.scheduled, lockHeld: true);
    } finally {
      await appDb.close();
    }
  } on Object {
    // The worker records the failure when no status was written.
  } finally {
    if (locked) await platform.endRun();
    await platform.workerFinished();
  }
}
