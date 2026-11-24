import 'package:sqflite/sqflite.dart';

import '../../core/constants/settings_keys.dart';

/// Typed access to the `settings` key/value table.
class SettingsRepository {
  SettingsRepository(this._db);

  final DatabaseExecutor _db;

  /// Raw value, or null when the key is absent.
  Future<String?> getStringOrNull(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// Value with fallback to [SettingsKeys.defaults], then [fallback].
  Future<String> getString(String key, {String fallback = ''}) async {
    return await getStringOrNull(key) ??
        SettingsKeys.defaults[key] ??
        fallback;
  }

  Future<int> getInt(String key, {int fallback = 0}) async {
    final raw = await getString(key, fallback: '$fallback');
    return int.tryParse(raw) ?? fallback;
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final raw = await getString(key, fallback: fallback ? '1' : '0');
    return raw == '1' || raw == 'true';
  }

  Future<void> setString(String key, String value) async {
    await _db.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Every stored key with its raw value. Keys the user never changed are
  /// absent; callers layer [SettingsKeys.defaults] underneath.
  Future<Map<String, String>> getAll() async {
    final rows = await _db.query('settings', columns: ['key', 'value']);
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  /// Writes several keys in one batch.
  Future<void> setMany(Map<String, String> values) async {
    if (values.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final batch = _db.batch();
    for (final entry in values.entries) {
      batch.insert(
        'settings',
        {'key': entry.key, 'value': entry.value, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> setInt(String key, int value) => setString(key, '$value');

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? '1' : '0');

  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
