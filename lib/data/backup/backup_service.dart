import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/backup/backup_crypto.dart';
import '../../core/backup/backup_file.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/security/code_cipher.dart';
import '../../domain/models/voucher.dart';
import '../db/app_database.dart';
import '../repositories/audit_repository.dart';
import 'database_snapshot.dart';
import 'restore_journal.dart';

/// Where the automatic backup's password key is kept: the Keystore, never
/// the database (a backup must not carry the key that opens it).
const String autoBackupKeyName = 'souqi.backup_key.v1';

/// The most PBKDF2 rounds a file may ask for: a crafted manifest must not
/// keep the phone busy for an hour.
const int backupKdfMaxIterations = 10000000;

/// A backup just written.
class CreatedBackup {
  const CreatedBackup({required this.path, required this.manifest});

  final String path;
  final BackupManifest manifest;

  String get name => p.basename(path);
}

/// A backup whose password was right: its manifest is signed by it, and its
/// card-code keys are open.
class UnlockedBackup {
  const UnlockedBackup({required this.extracted, required this.voucherKeys});

  final ExtractedBackup extracted;

  /// The Keystore entry of the phone that made it (base64 of AES ‖ HMAC), or
  /// null when that phone never had card codes.
  final String? voucherKeys;

  BackupManifest get manifest => extracted.manifest;
}

/// The restored database does not hold what the manifest says.
class RestoreCheckFailedException implements Exception {
  const RestoreCheckFailedException(this.detail);

  final String detail;

  @override
  String toString() => 'RestoreCheckFailedException($detail)';
}

/// "souqi-backup-2026-11-26-1430.souqi": a backup made by hand. Not the
/// daily pattern (`souqi-backup-YYYY-MM-DD.souqi`), so the daily backup's
/// keep-N never deletes it.
String manualBackupName(DateTime localNow) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'souqi-backup-${localNow.year.toString().padLeft(4, '0')}-'
      '${two(localNow.month)}-${two(localNow.day)}-'
      '${two(localNow.hour)}${two(localNow.minute)}.$backupExtension';
}

/// Making, opening and restoring backups. No Flutter, no platform: the same
/// code runs in the app, in the background engine (the daily backup) and in
/// the tests.
class BackupService {
  BackupService({
    required this.factory,
    required this.keys,
    required this.workDir,
    this.clock = DateTime.now,
  });

  final DatabaseFactory factory;
  final SecretKeyStore keys;

  /// A folder of the app's own for the temporary files.
  final Future<Directory> Function() workDir;
  final DateTime Function() clock;

  Future<Directory> _fresh(String what) async {
    final base = await workDir();
    final dir = Directory(p.join(
      base.path,
      '$what-${clock().microsecondsSinceEpoch}',
    ));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }

  // ---- Create --------------------------------------------------------

  /// Writes a complete backup of [db] to [outPath]: a snapshot of the whole
  /// database, the logo, and BOTH card-code keys sealed with [key].
  ///
  /// [db] is only read. Logging it is the caller's job (the background
  /// engine may not write to the database); see [logCreated].
  Future<CreatedBackup> create(
    Database db, {
    required BackupKey key,
    required String appVersion,
    required String outPath,
  }) async {
    final work = await _fresh('create');
    try {
      final dbFile = File(p.join(work.path, BackupEntry.database));
      final snapshot = await snapshotDatabase(db, dbFile.path, factory: factory);
      final files = <String, File>{BackupEntry.database: dbFile};

      if (snapshot.logoBase64.isNotEmpty) {
        try {
          final logo = File(p.join(work.path, BackupEntry.logo));
          await logo.writeAsBytes(base64Decode(snapshot.logoBase64), flush: true);
          files[BackupEntry.logo] = logo;
        } on FormatException {
          // A damaged logo setting: the database still carries it as it is.
        }
      }

      // The Keystore entry as a whole — AES and HMAC together (with only
      // the AES half the codes decrypt, but every lookup by hash fails).
      final voucherKeys = await keys.read(CodeCipher.keyName);
      final secrets = File(p.join(work.path, BackupEntry.secrets));
      await secrets.writeAsBytes(
        await key.seal(utf8.encode(jsonEncode({
          'format': 'souqi-secrets',
          'v': 1,
          'voucherKeys': voucherKeys,
        }))),
        flush: true,
      );
      files[BackupEntry.secrets] = secrets;

      final manifest = BackupManifest(
        appVersion: appVersion,
        schemaVersion: snapshot.schemaVersion,
        createdAt: clock().toUtc(),
        counts: snapshot.counts,
        files: [
          for (final entry in files.entries)
            await describeFile(entry.key, entry.value),
        ],
        kdf: BackupKdf(iterations: key.iterations, salt: key.salt),
      );
      final bytes = manifest.toBytes();
      await File(outPath).parent.create(recursive: true);
      await writeBackupZip(
        outPath,
        manifest: bytes,
        signature: key.sign(bytes),
        files: files,
      );
      return CreatedBackup(path: outPath, manifest: manifest);
    } finally {
      await _delete(work);
    }
  }

  /// The audit line and the "last backup" date of a backup made in the app.
  static Future<void> logCreated(Database db, CreatedBackup backup) async {
    await db.transaction((txn) async {
      await AuditRepository(txn).log(
        AuditAction.backupCreate,
        entityType: 'backup',
        details: {
          'file': backup.name,
          'invoices': backup.manifest.counts.invoices,
          'products': backup.manifest.counts.products,
        },
      );
      await txn.insert(
        'settings',
        {
          'key': SettingsKeys.backupLastAt,
          'value':
              '${backup.manifest.createdAt.toUtc().millisecondsSinceEpoch}',
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ---- Open ------------------------------------------------------------

  /// Takes the file apart and checks it — every file against the manifest's
  /// checksums, and the schema version against this app: a NEWER schema is
  /// refused here ([NewerBackupException]), before the password is asked.
  /// Throws [CorruptBackupException] for anything that is not a sound backup.
  Future<ExtractedBackup> inspect(String path) async {
    final extracted = await extractBackup(path, await _fresh('restore'));
    final manifest = extracted.manifest;
    if (manifest.schemaVersion > AppDatabase.schemaVersion) {
      await extracted.discard();
      throw NewerBackupException(
        backupSchema: manifest.schemaVersion,
        appSchema: AppDatabase.schemaVersion,
        appVersion: manifest.appVersion,
      );
    }
    final iterations = manifest.kdf.iterations;
    if (iterations < backupKdfMinIterations ||
        iterations > backupKdfMaxIterations ||
        manifest.kdf.salt.length < 8) {
      await extracted.discard();
      throw const CorruptBackupException('kdf parameters');
    }
    return extracted;
  }

  /// Opens [extracted] with [password]. A wrong password throws
  /// [WrongBackupPasswordException] and changes nothing — try again with the
  /// same [extracted]. A file altered after it was made fails the signature
  /// ([CorruptBackupException]).
  Future<UnlockedBackup> unlock(
    ExtractedBackup extracted,
    String password,
  ) async {
    final manifest = extracted.manifest;
    final key = await deriveBackupKey(
      password,
      salt: manifest.kdf.salt,
      iterations: manifest.kdf.iterations,
    );
    final payload = await key.open(await extracted.secrets.readAsBytes());
    if (!key.verify(extracted.manifestBytes, extracted.signature)) {
      throw const CorruptBackupException('signature');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(payload));
    } on FormatException {
      throw const CorruptBackupException('secrets');
    }
    if (json is! Map || json['format'] != 'souqi-secrets') {
      throw const CorruptBackupException('secrets');
    }
    final voucherKeys = json['voucherKeys'];
    if (voucherKeys != null) {
      if (voucherKeys is! String) throw const CorruptBackupException('keys');
      try {
        if (base64Decode(voucherKeys).length != 64) {
          throw const CorruptBackupException('keys');
        }
      } on FormatException {
        throw const CorruptBackupException('keys');
      }
    }
    return UnlockedBackup(
      extracted: extracted,
      voucherKeys: voucherKeys as String?,
    );
  }

  // ---- Restore ---------------------------------------------------------

  /// Replaces ALL of the shop's data with [backup], atomically.
  ///
  /// 1. The backup's database is copied next to the live one and opened
  ///    THERE: an older schema is migrated, and the result is checked
  ///    (integrity, foreign keys, every count of the manifest). The live
  ///    data is untouched; a failure here leaves the shop exactly as it was
  ///    and the live database open ([live] stays usable).
  /// 2. The swap ([RestoreJournal]): the live database is closed, the files
  ///    trade places, both card-code keys are written back to the Keystore,
  ///    and the restored database is opened. A failure there is rolled back
  ///    and [RestoreFailedException] carries the old database, reopened.
  ///
  /// Returns the restored database, open; the caller restarts the app on
  /// it. [closeLive] closes the live database (the caller's, since other
  /// code holds it). [fault] breaks the swap at a named step, for tests.
  Future<AppDatabase> restore(
    UnlockedBackup backup, {
    required AppDatabase live,
    required Future<void> Function() closeLive,
    void Function(String step)? fault,
  }) async {
    if (live.path == inMemoryDatabasePath) {
      throw StateError('an in-memory database cannot be restored over');
    }
    final journal = RestoreJournal(dbPath: live.path, keys: keys);
    final staged = journal.stagedPath;
    await RestoreJournal.deleteDatabaseFiles(staged);
    await backup.extracted.database.copy(staged);
    // THIS PHONE'S OWN LICENSE goes over to the restored data. The Keystore
    // holds a second copy and normally puts it back at the next start — but
    // on a phone whose Keystore entry is gone, the settings row is the only
    // copy left, and a restore (even of this phone's own backup) would
    // leave the shop unable to sell until the code is typed in again.
    final marks =
        List.filled(SettingsKeys.deviceBoundKeys.length, '?').join(', ');
    final ownRows = await live.db.query(
      'settings',
      where: 'key IN ($marks)',
      whereArgs: SettingsKeys.deviceBoundKeys,
    );
    try {
      await _prepare(staged, backup, deviceRows: ownRows);
      fault?.call('prepared');
    } on Object {
      await RestoreJournal.deleteDatabaseFiles(staged);
      rethrow;
    }

    final restored = await journal.swap<AppDatabase>(
      newKeys: backup.voucherKeys,
      close: closeLive,
      open: () => AppDatabase.open(factory: factory, path: live.path),
      closeOpened: (db) => db.close(),
      fault: fault,
    );
    await backup.extracted.discard();
    return restored;
  }

  /// Step 1 on the copy at [path].
  Future<void> _prepare(
    String path,
    UnlockedBackup backup, {
    List<Map<String, Object?>> deviceRows = const [],
  }) async {
    final manifest = backup.manifest;
    final int version;
    try {
      version = await AppDatabase.fileVersion(path, factory: factory);
    } on Object {
      throw const RestoreCheckFailedException('not a database');
    }
    if (version > AppDatabase.schemaVersion) {
      throw NewerBackupException(
        backupSchema: version,
        appSchema: AppDatabase.schemaVersion,
        appVersion: manifest.appVersion,
      );
    }
    if (version < 1 || version != manifest.schemaVersion) {
      throw RestoreCheckFailedException('schema version $version');
    }
    // Opening it as the app's database runs the migrations of a backup
    // made by an older version.
    final db = await AppDatabase.open(factory: factory, path: path);
    try {
      final integrity = await db.db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        throw const RestoreCheckFailedException('integrity');
      }
      if ((await db.db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const RestoreCheckFailedException('foreign keys');
      }
      final counts = await countRows(db.db);
      if (counts != manifest.counts) {
        throw RestoreCheckFailedException('counts $counts');
      }
      final autoKey = BackupKey.fromStored(await keys.read(autoBackupKeyName));
      await db.db.transaction((txn) async {
        // A LICENSE BELONGS TO THE DEVICE: whatever activation code a backup
        // might hold is dropped here. This phone's own license is written
        // back when the app starts over on the restored data
        // (`LicenseService.start`) — a phone that has none needs its own
        // activation, whoever made the backup.
        final marks =
            List.filled(SettingsKeys.deviceBoundKeys.length, '?').join(', ');
        await txn.delete(
          'settings',
          where: 'key IN ($marks)',
          whereArgs: SettingsKeys.deviceBoundKeys,
        );
        // …and this phone's own (see [restore]) is put in its place.
        for (final row in deviceRows) {
          await txn.insert(
            'settings',
            Map<String, Object?>.of(row),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        // The automatic backup's password lives in THIS phone's Keystore.
        // On another phone there is none yet: the daily backup stays off
        // until it is set here, instead of failing every night.
        if (autoKey == null) {
          await txn.insert(
            'settings',
            {
              'key': SettingsKeys.backupAutoEnabled,
              'value': '0',
              'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await AuditRepository(txn).log(
          AuditAction.backupRestore,
          entityType: 'backup',
          details: {
            'backup_at': manifest.createdAt.toUtc().millisecondsSinceEpoch,
            'invoices': manifest.counts.invoices,
            'products': manifest.counts.products,
          },
        );
      });
    } finally {
      await db.close();
    }
  }

  static Future<void> _delete(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // The app's own temporary folder.
    }
  }

  /// Removes what earlier runs left in the temporary folder — anything older
  /// than [olderThan], so neither a nightly backup the background engine is
  /// writing right now nor a file the share sheet is still reading is
  /// pulled away.
  Future<void> sweep({Duration olderThan = const Duration(hours: 1)}) async {
    try {
      final base = await workDir();
      if (!await base.exists()) return;
      final cutoff = clock().subtract(olderThan);
      await for (final entity in base.list()) {
        if (entity is! Directory) continue;
        if ((await entity.stat()).modified.isAfter(cutoff)) continue;
        await _delete(entity);
      }
    } on FileSystemException {
      // Next time.
    }
  }
}
