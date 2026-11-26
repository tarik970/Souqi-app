import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'app_root.dart';
import 'config/features.dart';
import 'core/licensing/license_service.dart';
import 'core/logging/error_log.dart';
import 'core/logging/error_reporting.dart';
import 'core/platform/license_platform.dart';
import 'core/platform/report_platform.dart';
import 'core/security/secure_key_store.dart';
import 'data/backup/backup_service.dart';
import 'data/backup/restore_journal.dart';
import 'data/db/app_database.dart';
import 'features/backup/auto_backup.dart';
import 'features/backup/backup_providers.dart';
import 'features/debts/report/report_providers.dart';
import 'features/license/background_license.dart';
import 'features/startup/startup_failure_app.dart';

Future<void> main() async {
  assert(featureFlagsConsistent,
      'accounts and debt feature flags require customersEnabled');
  WidgetsFlutterBinding.ensureInitialized();
  // From here on, an error nobody catches is written to the local error
  // log (Settings → About → "Share error log").
  await startErrorLog();
  await _startApp();
}

/// Opens the shop's data and shows the app — or, when that fails, a screen
/// that SAYS so (`StartupFailureApp`) instead of a white one: the data is
/// still on the phone, "Try again" runs this again, and the error log can
/// be sent to the developer from there.
Future<void> _startApp() async {
  try {
    // A restore the app was killed in the middle of (battery, force stop)
    // is finished or undone BEFORE the database is opened: one of the two
    // complete databases, with its own card-code keys, is what opens.
    try {
      await RestoreJournal(
        dbPath: await AppDatabase.defaultPath(),
        keys: const SecureStorageKeyStore(),
      ).recover();
    } on Object catch (error, stack) {
      // Nothing to recover, or the Keystore did not answer: the next start
      // tries again (the marker stays until it succeeds).
      reportError(error, stack, context: 'restore recovery');
    }

    final appDb = await AppDatabase.open();
    // The license of this phone is checked here, on every start, before
    // the first screen exists (`AppStart.load`).
    final start = await AppStart.load(appDb);

    // What an earlier backup or restore left in the temporary folder.
    unawaited(BackupService(
      factory: databaseFactory,
      keys: const SecureStorageKeyStore(),
      workDir: appBackupWorkDir,
    ).sweep());

    runApp(SouqiRoot(start: start));
  } on Object catch (error, stack) {
    reportError(error, stack, context: 'startup');
    runApp(StartupFailureApp(error: error, onRetry: _startApp));
  }
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
///
/// THE LICENSE IS CHECKED HERE TOO (`runDailyJobInBackground`): this engine
/// has no `ProviderScope` and never saw the app's own check, so it reads
/// the stored activation code itself, verifies it, and makes only what the
/// license allows.
@pragma('vm:entry-point')
Future<void> debtReportWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This engine has its own log file; "Share error log" sends both.
  await startErrorLog(engine: 'worker');
  const platform = MethodChannelReportPlatform();
  var locked = false;
  try {
    if (await RestoreJournal.pending(await AppDatabase.defaultPath())) return;
    if (!await platform.tryBeginRun()) return;
    locked = true;
    // A CONNECTION OF ITS OWN: the app may be open in this same process,
    // and the ordinary open would hand this engine the app's connection —
    // which the close below would then take away from the app.
    final appDb = await AppDatabase.open(ownConnection: true);
    try {
      await runDailyJobInBackground(
        db: appDb.db,
        platform: platform,
        license: LicenseService(
          db: appDb.db,
          keys: const SecureStorageKeyStore(),
          platform: const MethodChannelLicensePlatform(),
        ),
        stagingDir: appReportStagingDir,
        loadFonts: loadBundledReportFonts,
        backupOutput: (stored) => autoBackupOutput(
          stored,
          keys: const SecureStorageKeyStore(),
          factory: databaseFactory,
          workDir: appBackupWorkDir,
          appVersion: platformAppVersion,
        ),
      );
    } finally {
      await appDb.close();
    }
  } on Object catch (error, stack) {
    // The worker records the failure when no status was written.
    reportError(error, stack, context: 'daily job');
  } finally {
    // Nothing is written after the worker is told it may end the engine.
    await ErrorLog.instance.flush();
    if (locked) await platform.endRun();
    await platform.workerFinished();
  }
}
