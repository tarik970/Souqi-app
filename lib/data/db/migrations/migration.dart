import 'package:sqflite/sqflite.dart';

/// One versioned schema step. Migrations never drop user data.
abstract class Migration {
  /// The schema version this migration brings the database up to.
  int get version;

  Future<void> apply(DatabaseExecutor db);
}
