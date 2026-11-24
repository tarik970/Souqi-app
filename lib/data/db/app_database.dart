import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations/migration.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';

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
  static const List<Migration> migrations = [MigrationV1(), MigrationV2()];

  static int get schemaVersion => migrations.last.version;

  /// Opens (and creates/upgrades) the database.
  ///
  /// [factory] and [path] exist for tests (sqflite_common_ffi, in-memory).
  /// In the app, call with no arguments.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
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
      ),
    );
    return AppDatabase._(db, dbPath);
  }

  Future<void> close() => db.close();
}
