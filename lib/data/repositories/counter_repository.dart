import 'package:sqflite/sqflite.dart';

/// Persistent, never-reused sequential counters (invoice numbers).
class CounterRepository {
  const CounterRepository();

  static const invoiceNo = 'invoice_no';

  /// Increments [name] and returns the new value.
  ///
  /// MUST be called with the enclosing transaction's executor when the new
  /// number is written in the same unit of work (e.g. saving an invoice),
  /// so a rolled-back transaction does not leak a gap unnecessarily and two
  /// concurrent saves can never share a number.
  Future<int> next(DatabaseExecutor txn, String name) async {
    final updated = await txn.rawUpdate(
      'UPDATE counters SET value = value + 1 WHERE name = ?',
      [name],
    );
    if (updated == 0) {
      await txn.insert('counters', {'name': name, 'value': 1});
      return 1;
    }
    final rows = await txn.query(
      'counters',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return rows.first['value'] as int;
  }
}
