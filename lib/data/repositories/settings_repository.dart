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

  Future<void> setInt(String key, int value) => setString(key, '$value');

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? '1' : '0');

  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
