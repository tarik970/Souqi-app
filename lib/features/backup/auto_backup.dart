import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/backup/backup_crypto.dart';
import '../../core/backup/backup_file.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/security/code_cipher.dart';
import '../../data/backup/backup_service.dart';
import '../debts/report/daily_job.dart';
import '../debts/report/report_schedule.dart';

/// The daily automatic backup: `souqi-backup-YYYY-MM-DD.souqi`, one per day,
/// in the same folder as the daily debt report.
const autoBackupFiles = DatedFilePattern(
  prefix: 'souqi-backup',
  extensions: [backupExtension],
);

/// Settings → Backup → "Daily automatic backup". In the `settings` table;
/// the password key is in the Keystore ([autoBackupKeyName]).
class AutoBackupSettings {
  const AutoBackupSettings({
    this.enabled = false,
    this.keepDays = 7,
    this.enabledAt,
  });

  final bool enabled;

  /// How many days' backups stay in the folder — its own keep-N, apart from
  /// the debt report's.
  final int keepDays;
  final DateTime? enabledAt;

  static const List<int> keepChoices = [3, 7, 14, 30, 60];

  static AutoBackupSettings fromMap(Map<String, String> stored) {
    String get(String key) =>
        stored[key] ?? SettingsKeys.defaults[key] ?? '';
    final keep = int.tryParse(get(SettingsKeys.backupAutoKeepDays));
    final at = int.tryParse(get(SettingsKeys.backupAutoEnabledAt)) ?? 0;
    return AutoBackupSettings(
      enabled: get(SettingsKeys.backupAutoEnabled) == '1',
      keepDays: keep == null || keep < 1 ? 7 : keep,
      enabledAt: at <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }

  Map<String, String> toMap() => {
        SettingsKeys.backupAutoEnabled: enabled ? '1' : '0',
        SettingsKeys.backupAutoKeepDays: '$keepDays',
        SettingsKeys.backupAutoEnabledAt:
            '${enabledAt?.toUtc().millisecondsSinceEpoch ?? 0}',
      };

  AutoBackupSettings copyWith({
    bool? enabled,
    int? keepDays,
    DateTime? enabledAt,
  }) =>
      AutoBackupSettings(
        enabled: enabled ?? this.enabled,
        keepDays: keepDays ?? this.keepDays,
        enabledAt: enabledAt ?? this.enabledAt,
      );
}

/// THE BACKUP AS AN OUTPUT OF THE DAILY JOB. It writes the encrypted file
/// into the job's staging folder; the job copies it to the folder (or to
/// Downloads), applies [keepDays] to [autoBackupFiles] only, and records the
/// status. The staged copy is not offered to "Share" and is removed once
/// written.
class BackupOutput implements DailyOutput {
  BackupOutput({
    required this.settings,
    required this.service,
    required this.key,
    required this.appVersion,
  });

  final AutoBackupSettings settings;
  final BackupService service;
  final BackupKey key;
  final String appVersion;

  @override
  String get id => 'backup';

  @override
  DatedFilePattern get files => autoBackupFiles;

  @override
  int get keepDays => settings.keepDays;

  @override
  Future<List<StagedFile>> build(DailyJobContext context) async {
    final name = files.nameFor(context.now, backupExtension);
    final path = p.join(context.stagingDir.path, name);
    await service.create(
      context.db,
      key: key,
      appVersion: appVersion,
      outPath: path,
    );
    return [
      StagedFile(
        name: name,
        path: path,
        mimeType: backupMimeType,
        shareable: false,
      ),
    ];
  }
}

/// The backup output for tonight's run, or null when the daily backup is
/// off — or on but without a password on THIS phone (a database restored
/// from another phone), which the settings page points out.
Future<DailyOutput?> autoBackupOutput(
  Map<String, String> stored, {
  required SecretKeyStore keys,
  required DatabaseFactory factory,
  required Future<Directory> Function() workDir,
  required Future<String> Function() appVersion,
}) async {
  final settings = AutoBackupSettings.fromMap(stored);
  if (!settings.enabled) return null;
  final key = BackupKey.fromStored(await keys.read(autoBackupKeyName));
  if (key == null) return null;
  return BackupOutput(
    settings: settings,
    service: BackupService(factory: factory, keys: keys, workDir: workDir),
    key: key,
    appVersion: await appVersion(),
  );
}
