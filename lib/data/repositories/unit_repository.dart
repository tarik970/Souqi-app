import 'package:sqflite/sqflite.dart';

import '../../domain/models/unit.dart';

/// Thrown when deleting a unit that products still reference.
class UnitInUseException implements Exception {
  const UnitInUseException(this.productCount);

  final int productCount;
}

class UnitRepository {
  UnitRepository(this._db);

  final DatabaseExecutor _db;

  Future<List<Unit>> list({bool includeInactive = false}) async {
    final rows = await _db.query(
      'units',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'is_preset DESC, sort_order ASC, id ASC',
    );
    return rows.map(Unit.fromMap).toList();
  }

  Future<Unit?> getById(int id) async {
    final rows =
        await _db.query('units', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Unit.fromMap(rows.first);
  }

  /// Adds a custom unit. Both localized names get the entered text.
  Future<int> insertCustom(String name) async {
    final next = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COALESCE(MAX(sort_order), -1) + 1 FROM units')) ??
        0;
    return _db.insert('units', {
      'name_ar': name.trim(),
      'name_en': name.trim(),
      'is_preset': 0,
      'is_active': 1,
      'sort_order': next,
    });
  }

  /// Renames a custom unit. Presets cannot be edited.
  Future<void> updateCustom(int id, String name) async {
    await _db.update(
      'units',
      {'name_ar': name.trim(), 'name_en': name.trim()},
      where: 'id = ? AND is_preset = 0',
      whereArgs: [id],
    );
  }

  Future<int> countProductsUsing(int unitId) async {
    return Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM products WHERE unit_id = ?',
          [unitId],
        )) ??
        0;
  }

  /// Deletes a custom unit. Throws [UnitInUseException] when any product
  /// (active or not) still uses it; presets are never deleted.
  Future<void> deleteCustom(int id) async {
    final used = await countProductsUsing(id);
    if (used > 0) {
      throw UnitInUseException(used);
    }
    await _db.delete('units', where: 'id = ? AND is_preset = 0',
        whereArgs: [id]);
  }
}
