import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/backup/backup_crypto.dart';
import '../../core/providers.dart';
import '../../data/backup/backup_service.dart';
import '../../data/backup/restore_journal.dart';
import '../../data/db/app_database.dart';
import '../customers/customers_providers.dart';
import '../debts/report/report_providers.dart';
import '../security/audit_providers.dart';
import 'backup_providers.dart';

/// The daily job (in the app or in the background engine) holds the run
/// lock: a restore must wait for it.
class BackupBusyException implements Exception {
  const BackupBusyException();
}

/// Makes a backup of the whole shop with [password] in the app's own
/// temporary folder, logs it, and returns it — for the share sheet, "Save
/// to phone" or the report folder to take from there.
///
/// With [record] false nothing is logged yet: the caller delivers the file
/// first and calls [recordBackupCreated] only when that worked. A backup
/// that reached nowhere must not show as "Last backup: today" and silence
/// the reminder.
Future<CreatedBackup> createBackupFile(
  ProviderContainer container, {
  required String password,
  bool record = true,
}) async {
  final database = container.read(databaseProvider);
  final service = container.read(backupServiceProvider);
  final iterations = container.read(backupIterationsProvider);
  final workDir = container.read(backupWorkDirProvider);
  final appVersion = container.read(appVersionProvider);
  final now = container.read(clockProvider)();

  final key = await newBackupKey(password, iterations: iterations);
  final out = Directory(
    p.join((await workDir()).path, 'out-${now.microsecondsSinceEpoch}'),
  );
  final created = await service.create(
    database.db,
    key: key,
    appVersion: await appVersion(),
    outPath: p.join(out.path, manualBackupName(now.toLocal())),
  );
  if (record) await recordBackupCreated(container, created);
  return created;
}

/// Writes the audit line and the "last backup" date of [created].
Future<void> recordBackupCreated(
  ProviderContainer container,
  CreatedBackup created,
) async {
  await BackupService.logCreated(container.read(databaseProvider).db, created);
  refreshBackupState(container);
  container.invalidate(auditLogProvider);
}

/// REPLACES ALL DATA with [backup] and starts the app over on it.
///
/// Holds the daily job's run lock throughout, so neither engine opens the
/// database while its file is swapped. When the swap fails, everything is
/// put back and the app starts over on its own data — [RestoreFailedException]
/// is rethrown for the record, but the screen that called this is gone by
/// then either way: the new start says how it went.
Future<void> restoreBackup(
  ProviderContainer container,
  UnlockedBackup backup, {
  void Function(String step)? fault,
}) async {
  final platform = container.read(reportPlatformProvider);
  final restart = container.read(appRestartProvider);
  final live = container.read(databaseProvider);
  final service = container.read(backupServiceProvider);

  bool locked;
  try {
    locked = await platform.tryBeginRun();
  } on Object {
    // No Android side (a test): nothing else can run.
    locked = true;
  }
  if (!locked) throw const BackupBusyException();
  try {
    final AppDatabase restored;
    try {
      restored = await service.restore(
        backup,
        live: live,
        closeLive: live.close,
        fault: fault,
      );
    } on RestoreFailedException<AppDatabase> catch (e) {
      await restart(e.database, AppRestartNotice.restoreFailed);
      rethrow;
    }
    await restart(restored, AppRestartNotice.restored);
  } finally {
    try {
      await platform.endRun();
    } on Object {
      // The lock goes stale after ten minutes anyway.
    }
  }
}
