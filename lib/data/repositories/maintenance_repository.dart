import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Housekeeping on the archive and on the database file itself: how much
/// room it takes, dropping invoices by date, and reclaiming the space the
/// drops freed.
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

  /// Deletes the invoices created from [from] (inclusive) to [to]
  /// (exclusive) and returns how many went. Either bound may be left out to
  /// mean "no bound". Their items go with them through the invoice_items
  /// foreign key's ON DELETE CASCADE; payments and voucher sales keep their
  /// rows with a null invoice_id (ON DELETE SET NULL), so the money history
  /// survives the archive being trimmed.
  Future<int> deleteInvoicesCreatedBetween({DateTime? from, DateTime? to}) {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('created_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    return _db.delete(
      'invoices',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
  }

  /// Retention cleanup: deletes invoices older than [days] days and returns
  /// how many went. [days] of 0 or less is "keep everything" and deletes
  /// nothing. [now] exists for tests.
  Future<int> deleteOlderThan(int days, {DateTime? now}) {
    if (days <= 0) return Future.value(0);
    return deleteInvoicesCreatedBetween(
      to: (now ?? DateTime.now()).subtract(Duration(days: days)),
    );
  }

  /// Rewrites the database without its free pages, shrinking the file.
  ///
  /// Takes as long as it takes to copy the whole database and needs room for
  /// a second copy while it runs, so it is only worth doing after a large
  /// delete — see `vacuumInvoiceThreshold` — and never without telling the
  /// user something is happening.
  Future<void> vacuum() => _db.execute('VACUUM');
}
