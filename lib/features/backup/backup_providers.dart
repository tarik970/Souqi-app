import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/backup/backup_crypto.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../data/backup/backup_service.dart';
import '../customers/customers_providers.dart';
import '../debts/report/report_providers.dart';
import 'auto_backup.dart';

/// The app's own folder for a backup's temporary files: the snapshot being
/// packed, a backup being checked before a restore. Emptied on every start.
Future<Directory> appBackupWorkDir() async {
  final base = await getTemporaryDirectory();
  return Directory(p.join(base.path, 'backup-work'));
}

final backupWorkDirProvider = Provider<Future<Directory> Function()>(
  (ref) => appBackupWorkDir,
);

/// "1.0.0+1" — written into every backup's manifest.
Future<String> platformAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } on Object {
    return 'unknown';
  }
}

final appVersionProvider = Provider<Future<String> Function()>(
  (ref) => platformAppVersion,
);

/// PBKDF2 rounds for a new password. Tests make it small.
final backupIterationsProvider = Provider<int>((ref) => backupKdfIterations);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    factory: ref.watch(databaseFactoryProvider),
    keys: ref.watch(secretKeyStoreProvider),
    workDir: ref.watch(backupWorkDirProvider),
    clock: ref.watch(clockProvider),
  ),
);

class AutoBackupSettingsNotifier extends AsyncNotifier<AutoBackupSettings> {
  @override
  Future<AutoBackupSettings> build() async => AutoBackupSettings.fromMap(
        await ref.watch(settingsRepositoryProvider).getAll(),
      );

  Future<void> save(AutoBackupSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).setMany(next.toMap());
  }
}

final autoBackupSettingsProvider =
    AsyncNotifierProvider<AutoBackupSettingsNotifier, AutoBackupSettings>(
  AutoBackupSettingsNotifier.new,
);

/// The automatic backup's password is set on THIS phone (its key is in the
/// Keystore).
final autoBackupHasKeyProvider = FutureProvider<bool>((ref) async {
  try {
    final stored =
        await ref.watch(secretKeyStoreProvider).read(autoBackupKeyName);
    return BackupKey.fromStored(stored) != null;
  } on Object {
    return false;
  }
});

/// The newest backup this phone knows of: one made by hand (or restored),
/// kept in the settings, or the last daily one, kept in the job's status.
final lastBackupAtProvider = FutureProvider<DateTime?>((ref) async {
  final stored = await ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.backupLastAt);
  final ms = int.tryParse(stored) ?? 0;
  final manual =
      ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;
  final daily = (await ref.watch(debtReportStatusProvider.future)).lastBackupAt;
  if (manual == null) return daily;
  if (daily == null) return manual;
  return manual.isAfter(daily) ? manual : daily;
});

/// How long without a backup before the settings say so.
const Duration backupReminderAfter = Duration(days: 7);

/// True when the shop has something worth keeping and no backup is newer
/// than [backupReminderAfter].
final backupReminderProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider).db;
  final rows = await db.rawQuery(
    'SELECT EXISTS(SELECT 1 FROM invoices) OR EXISTS(SELECT 1 FROM products) '
    'OR EXISTS(SELECT 1 FROM customers) AS has_data',
  );
  if (rows.first['has_data'] != 1) return false;
  final last = await ref.watch(lastBackupAtProvider.future);
  if (last == null) return true;
  final now = ref.watch(clockProvider)();
  return now.difference(last) > backupReminderAfter;
});

/// After a backup, a restore, or a change to the automatic backup.
void refreshBackupState(ProviderContainer container) {
  container
    ..invalidate(autoBackupSettingsProvider)
    ..invalidate(autoBackupHasKeyProvider)
    ..invalidate(lastBackupAtProvider)
    ..invalidate(backupReminderProvider)
    ..invalidate(debtReportStatusProvider);
}
