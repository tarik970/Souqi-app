import 'package:sqflite/sqflite.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/money/exchange.dart';
import '../../domain/models/currency.dart';
import 'settings_repository.dart';

/// Thrown when disabling or deleting would break the base currency.
class BaseCurrencyException implements Exception {
  const BaseCurrencyException();
}

/// Thrown when changing the base currency after invoices or debt
/// transactions exist (the setting is locked, no recalculation logic).
class BaseCurrencyLockedException implements Exception {
  const BaseCurrencyLockedException();
}

class CurrencyRepository {
  CurrencyRepository(this._db, this._settings);

  final DatabaseExecutor _db;
  final SettingsRepository _settings;

  Future<List<Currency>> list({bool includeInactive = false}) async {
    final rows = await _db.query(
      'currencies',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'sort_order ASC, code ASC',
    );
    return rows.map(Currency.fromMap).toList();
  }

  Future<Currency?> getByCode(String code) async {
    final rows = await _db
        .query('currencies', where: 'code = ?', whereArgs: [code], limit: 1);
    return rows.isEmpty ? null : Currency.fromMap(rows.first);
  }

  Future<String> baseCode() =>
      _settings.getString(SettingsKeys.baseCurrencyCode);

  Future<Currency> base() async => (await getByCode(await baseCode()))!;

  Future<bool> codeExists(String code) async =>
      await getByCode(code.toUpperCase()) != null;

  Future<void> insert(Currency currency) async {
    final next = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COALESCE(MAX(sort_order), -1) + 1 FROM currencies')) ??
        0;
    await _db.insert('currencies', {
      ...currency.toMap(),
      'code': currency.code.toUpperCase(),
      'sort_order': next,
    });
  }

  /// Updates names, symbol and decimal places (not the code, not the rate).
  Future<void> update(Currency currency) async {
    await _db.update(
      'currencies',
      {
        'name_ar': currency.nameAr,
        'name_en': currency.nameEn,
        'symbol': currency.symbol,
        'decimal_places': currency.decimalPlaces,
      },
      where: 'code = ?',
      whereArgs: [currency.code],
    );
  }

  Future<void> updateRate(String code, RateFraction rate) async {
    await _db.update(
      'currencies',
      {
        'rate_num': rate.numerator,
        'rate_den': rate.denominator,
        'rate_updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  /// The base currency can never be disabled.
  Future<void> setActive(String code, bool active) async {
    if (!active && code == await baseCode()) {
      throw const BaseCurrencyException();
    }
    await _db.update(
      'currencies',
      {'is_active': active ? 1 : 0},
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  /// True while no invoices and no debt transactions exist.
  Future<bool> canChangeBase() async {
    final locked = Sqflite.firstIntValue(await _db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM invoices UNION ALL '
      'SELECT 1 FROM debt_transactions)',
    ));
    return locked != 1;
  }

  /// Makes [code] the base currency: its rate becomes exactly 1/1 and every
  /// OTHER currency's rate is marked never-updated, forcing the user to
  /// re-enter rates against the new base. Old invoices are untouched because
  /// none may exist ([BaseCurrencyLockedException] otherwise).
  Future<void> setBase(String code) async {
    if (!await canChangeBase()) {
      throw const BaseCurrencyLockedException();
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'currencies',
      {'rate_num': 1, 'rate_den': 1, 'rate_updated_at': now},
      where: 'code = ?',
      whereArgs: [code],
    );
    await _db.update(
      'currencies',
      {'rate_updated_at': null},
      where: 'code != ?',
      whereArgs: [code],
    );
    await _settings.setString(SettingsKeys.baseCurrencyCode, code);
  }
}
