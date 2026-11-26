import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations/migration.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';
import 'migrations/migration_v6.dart';
import 'migrations/migration_v7.dart';
import 'migrations/migration_v8.dart';

/// Owns the sqflite [Database]: opening, PRAGMAs and versioned migrations.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;

  /// Where the file lives, for the housekeeping that measures it. In tests
  /// this is [inMemoryDatabasePath] (':memory:'), which is no file at all.
  final String path;

  static const String fileName = 'souqi.db';

  /// All migrations in ascending version order. Add new steps at the end;
  /// never edit or remove an existing one.
  static const List<Migration> migrations = [
    MigrationV1(),
    MigrationV2(),
    MigrationV3(),
    MigrationV4(),
    MigrationV5(),
    MigrationV6(),
    MigrationV7(),
    MigrationV8(),
  ];

  static int get schemaVersion => migrations.last.version;

  /// How long a statement waits for a lock held by another connection.
  static const int _busyTimeoutMs = 15000;

  /// Where the app's database file is on the phone.
  static Future<String> defaultPath({DatabaseFactory? factory}) async =>
      p.join(await (factory ?? databaseFactory).getDatabasesPath(), fileName);

  /// Opens (and creates/upgrades) the database.
  ///
  /// [factory] and [path] exist for tests (sqflite_common_ffi, in-memory).
  /// In the app, call with no arguments.
  ///
  /// [ownConnection] is for the BACKGROUND ENGINE (the daily job). sqflite's
  /// Android side keeps one connection per file for the whole PROCESS, not
  /// per Flutter engine: a second engine that opens the same file the
  /// ordinary way is handed the app's own connection, and closing it there
  /// closes it for the app too — every query of the open app then fails
  /// with "database_closed" until the app is killed. With [ownConnection]
  /// the caller gets a separate connection that it can close freely; SQLite
  /// itself arbitrates between the two (see [_busyTimeoutMs]).
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    bool ownConnection = false,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: !ownConnection,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // Another connection — the daily job's, while it copies the
          // database for the automatic backup — may hold the write lock for
          // a few seconds. Wait for it instead of failing a sale with
          // "database is locked" (Android's default gives up after 2.5 s).
          try {
            await db.rawQuery('PRAGMA busy_timeout = $_busyTimeoutMs');
          } on Object {
            // An engine that does not know the pragma keeps its default.
          }
        },
        onCreate: (db, version) async {
          for (final m in migrations) {
            if (m.version <= version) {
              await m.apply(db);
            }
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (final m in migrations) {
            if (m.version > oldVersion && m.version <= newVersion) {
              await m.apply(db);
            }
          }
        },
        // A database written by a NEWER version of the app (a restored
        // backup, or an older build installed over a newer one). Without
        // this sqflite would quietly stamp it with the older version number
        // and run old code on a schema it does not know.
        onDowngrade: (db, oldVersion, newVersion) =>
            throw NewerDatabaseException(oldVersion, newVersion),
      ),
    );
    return AppDatabase._(db, dbPath);
  }

  /// The schema version stored in the database file at [path], read without
  /// opening it as the app's database (no migration runs). 0 for an empty
  /// or new file.
  static Future<int> fileVersion(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await db.rawQuery('PRAGMA user_version');
      return (rows.first.values.first as int?) ?? 0;
    } finally {
      await db.close();
    }
  }

  Future<void> close() => db.close();
}

/// The database is from a newer version of the app than this one.
class NewerDatabaseException implements Exception {
  const NewerDatabaseException(this.fileVersion, this.appVersion);

  final int fileVersion;
  final int appVersion;

  @override
  String toString() =>
      'NewerDatabaseException(file: $fileVersion, app: $appVersion)';
}
