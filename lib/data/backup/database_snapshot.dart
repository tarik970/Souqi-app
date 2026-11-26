import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/backup/backup_file.dart';
import '../../core/constants/settings_keys.dart';

/// What the snapshot read, inside the same transaction as the copy.
class SnapshotInfo {
  const SnapshotInfo({
    required this.schemaVersion,
    required this.counts,
    required this.logoBase64,
  });

  final int schemaVersion;
  final BackupCounts counts;

  /// The shop logo as stored in the settings ('' = none).
  final String logoBase64;
}

/// Copies the WHOLE database into a new file at [targetPath] — a consistent
/// snapshot, not a copy of a file that may be half-written.
///
/// How: the new file gets the exact schema of the live one (the `CREATE`
/// text of every table, index and trigger, and its `user_version`), is
/// ATTACHed to the live connection, and every table is copied with
/// `INSERT … SELECT` inside ONE transaction. SQLite does the copying itself,
/// so it is quick (no row passes through Dart), and the transaction is what
/// makes it a snapshot: a sale saved meanwhile waits for it, and lands
/// entirely before or entirely after.
///
/// Works on sqlite 3.9 (Android 7): no `VACUUM INTO` (3.27), no backup API.
/// The live database is only read.
///
/// ONE THING IS LEFT OUT: the settings that belong to the device and not to
/// the shop ([SettingsKeys.deviceBoundKeys] — the activation code). A
/// license is issued for one phone; a backup never carries it.
Future<SnapshotInfo> snapshotDatabase(
  Database source,
  String targetPath, {
  required DatabaseFactory factory,
}) async {
  final target = File(targetPath);
  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    final f = File('$targetPath$suffix');
    if (await f.exists()) await f.delete();
  }
  await target.parent.create(recursive: true);

  final version = (await source.rawQuery('PRAGMA user_version'))
          .first
          .values
          .first as int? ??
      0;
  final schema = await source.rawQuery(
    "SELECT type, name, sql FROM sqlite_master "
    "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
    // Android's own table (the locale): Android makes it again on open.
    "AND name != 'android_metadata' "
    "ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END, "
    "rowid",
  );
  final tables = [
    for (final row in schema)
      if (row['type'] == 'table') row['name'] as String,
  ];

  // 1. The empty file with the same schema.
  final empty = await factory.openDatabase(
    targetPath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    final existing = {
      for (final row in await empty
          .rawQuery('SELECT name FROM sqlite_master'))
        row['name'],
    };
    await empty.transaction((txn) async {
      for (final row in schema) {
        if (existing.contains(row['name'])) continue;
        await txn.execute(row['sql'] as String);
      }
    });
    await empty.execute('PRAGMA user_version = $version');
  } finally {
    await empty.close();
  }

  // 2. Every row, in one transaction on the live connection.
  await source.execute('ATTACH DATABASE ? AS snap', [targetPath]);
  try {
    return await source.transaction((txn) async {
      // The copy runs table by table; the foreign keys are checked once, at
      // the end, when every table is in.
      await txn.execute('PRAGMA defer_foreign_keys = ON');
      for (final table in tables) {
        final columns = [
          for (final c in await txn.rawQuery('PRAGMA main.table_info("$table")'))
            '"${c['name']}"',
        ].join(', ');
        await txn.execute(
          'INSERT INTO snap."$table" ($columns) SELECT $columns FROM main."$table"',
        );
      }
      // AUTOINCREMENT counters: an id handed out before (and deleted since)
      // must never be handed out again after a restore.
      final hasSequence = (await txn.rawQuery(
        "SELECT 1 FROM main.sqlite_master WHERE name = 'sqlite_sequence'",
      ))
          .isNotEmpty;
      if (hasSequence) {
        await txn.execute('DELETE FROM snap.sqlite_sequence');
        await txn.execute(
          'INSERT INTO snap.sqlite_sequence (name, seq) '
          'SELECT name, seq FROM main.sqlite_sequence',
        );
      }

      // The license stays on the phone it was issued for.
      if (tables.contains('settings')) {
        final marks =
            List.filled(SettingsKeys.deviceBoundKeys.length, '?').join(', ');
        await txn.rawDelete(
          'DELETE FROM snap.settings WHERE key IN ($marks)',
          SettingsKeys.deviceBoundKeys,
        );
      }

      Future<int> count(String table) async {
        if (!tables.contains(table)) return 0;
        return (await txn.rawQuery('SELECT COUNT(*) AS n FROM snap."$table"'))
            .first['n'] as int;
      }

      final logo = tables.contains('settings')
          ? await txn.rawQuery(
              'SELECT value FROM snap.settings WHERE key = ?',
              [SettingsKeys.shopLogoBase64],
            )
          : const <Map<String, Object?>>[];
      return SnapshotInfo(
        schemaVersion: version,
        counts: BackupCounts(
          invoices: await count('invoices'),
          customers: await count('customers'),
          products: await count('products'),
          codes: await count('voucher_codes'),
          debtEntries: await count('debt_transactions'),
        ),
        logoBase64: logo.isEmpty ? '' : (logo.first['value'] as String? ?? ''),
      );
    });
  } finally {
    await source.execute('DETACH DATABASE snap');
  }
}

/// The counts of a database as the restore checks them against the
/// manifest.
Future<BackupCounts> countRows(DatabaseExecutor db) async {
  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM "$table"')).first['n']
          as int;
  return BackupCounts(
    invoices: await count('invoices'),
    customers: await count('customers'),
    products: await count('products'),
    codes: await count('voucher_codes'),
    debtEntries: await count('debt_transactions'),
  );
}
