import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Housekeeping on the database FILE itself: how much room it takes and
/// reclaiming the space a big delete freed.
///
/// Deleting rows does not shrink an sqlite file: the freed pages stay in it,
/// ready to be reused. Only [vacuum] rewrites the file without them, so a
/// shop that clears a year of invoices sees the phone's storage figure drop.
class MaintenanceRepository {
  MaintenanceRepository(this._db, {required this.filePath});

  final Database _db;

  /// Path of the database file, or ':memory:' in tests (no file to measure).
  final String filePath;

  Future<int> invoiceCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM invoices'),
      ) ??
      0;

  /// Bytes the database occupies on disk: the file plus the `-wal` and `-shm`
  /// side files sqlite keeps beside it, because the phone's storage screen
  /// counts those too. 0 for an in-memory database.
  Future<int> databaseSizeBytes() async {
    if (filePath.isEmpty || filePath.startsWith(':')) return 0;
    var total = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$filePath$suffix');
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  // Deleting invoices themselves lives in ArchiveRepository: it owns the
  // filter criteria the archive screen shows, and a big delete has to go in
  // chunks (see ArchiveRepository.deleteMatchingChunk).

  /// Rewrites the database without its free pages, shrinking the file.
  ///
  /// Takes as long as it takes to copy the whole database and needs room for
  /// a second copy while it runs, so it is only worth doing after a large
  /// delete — see `vacuumInvoiceThreshold` — and never without telling the
  /// user something is happening.
  Future<void> vacuum() => _db.execute('VACUUM');
}
