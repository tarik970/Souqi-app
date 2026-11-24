import 'package:sqflite/sqflite.dart';

import '../../../core/utils/normalize.dart';
import 'migration.dart';

/// Schema version 2: no table changes. Name normalization became stronger
/// (Arabic letter variants, diacritics, tatweel, the leading "ال"), so the
/// stored `name_norm` search columns are recomputed from the names — otherwise
/// products saved before the update would not be found by the new search or
/// recognised by the duplicate guard. The names themselves are not touched.
class MigrationV2 implements Migration {
  const MigrationV2();

  @override
  int get version => 2;

  @override
  Future<void> apply(DatabaseExecutor db) async {
    for (final table in const ['products', 'customers']) {
      final rows = await db.query(table, columns: ['id', 'name', 'name_norm']);
      for (final row in rows) {
        final normalized = normalizeName(row['name'] as String);
        if (normalized == row['name_norm']) continue;
        await db.update(
          table,
          {'name_norm': normalized},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }
}
