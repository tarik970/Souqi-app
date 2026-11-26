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

/// The decimal places of a currency that already has amounts stored in it
/// cannot change: every one of them would be read 10× or 100× off.
class CurrencyInUseException implements Exception {
  const CurrencyInUseException(this.code);

  final String code;

  @override
  String toString() => 'CurrencyInUseException($code)';
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

  /// Whether any amount is stored in [code]: a product's price, an invoice
  /// (as its currency, its base or an extra total), an invoice line, a
  /// ledger entry, a card batch's cost or the last bulk price change — and,
  /// for the base currency, any ledger entry or credit limit at all (those
  /// are always in the base).
  ///
  /// Amounts are INTEGER minor units with no decimals of their own: they
  /// mean what the currency's decimal places say today. That is why the
  /// decimal places are frozen while this is true.
  Future<bool> isInUse(String code) async {
    final isBase = code == await baseCode();
    final used = Sqflite.firstIntValue(await _db.rawQuery(
      'SELECT EXISTS('
      ' SELECT 1 FROM products WHERE currency_code = ?'
      ' UNION ALL SELECT 1 FROM invoices WHERE currency_code = ?'
      '   OR base_currency_code = ? OR extra1_currency_code = ?'
      '   OR extra2_currency_code = ?'
      ' UNION ALL SELECT 1 FROM debt_transactions WHERE orig_currency_code = ?'
      ' UNION ALL SELECT 1 FROM voucher_batches WHERE cost_currency_code = ?'
      ' UNION ALL SELECT 1 FROM price_change_items WHERE currency_code = ?'
      ' UNION ALL SELECT 1 FROM invoice_items WHERE orig_currency_code = ?'
      '${isBase ? ' UNION ALL SELECT 1 FROM debt_transactions'
          ' UNION ALL SELECT 1 FROM customers'
          ' WHERE credit_limit_base_minor IS NOT NULL' : ''}'
      ')',
      List<Object?>.filled(9, code),
    ));
    return used == 1;
  }

  /// Updates names, symbol and decimal places (not the code, not the rate).
  ///
  /// The decimal places only while nothing is stored in the currency
  /// ([isInUse]); otherwise [CurrencyInUseException] and nothing changes.
  Future<void> update(Currency currency) async {
    final stored = await _db.query(
      'currencies',
      columns: ['decimal_places'],
      where: 'code = ?',
      whereArgs: [currency.code],
      limit: 1,
    );
    if (stored.isNotEmpty &&
        stored.first['decimal_places'] != currency.decimalPlaces &&
        await isInUse(currency.code)) {
      throw CurrencyInUseException(currency.code);
    }
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

  /// True while no invoices, no debt transactions and no credit limits
  /// exist — everything that is stored as an amount of the base currency.
  Future<bool> canChangeBase() async {
    final locked = Sqflite.firstIntValue(await _db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM invoices UNION ALL '
      'SELECT 1 FROM debt_transactions UNION ALL '
      'SELECT 1 FROM customers WHERE credit_limit_base_minor IS NOT NULL)',
    ));
    return locked != 1;
  }

  /// Makes [code] the base currency: its rate becomes exactly 1/1 and every
  /// OTHER currency's rate is marked never-updated, forcing the user to
  /// re-enter rates against the new base. Old invoices are untouched because
  /// none may exist ([BaseCurrencyLockedException] otherwise).
  ///
  /// ONE transaction: the three writes land together or not at all. Half of
  /// them — the new currency at 1/1 with the old base still set — would sell
  /// that currency's products at "1 = 1". The new base is also made active:
  /// a disabled base could never be enabled again.
  Future<void> setBase(String code) async {
    final db = _db;
    if (db is Database) {
      await db.transaction(
        (txn) => CurrencyRepository(txn, SettingsRepository(txn)).setBase(code),
      );
      return;
    }
    if (!await canChangeBase()) {
      throw const BaseCurrencyLockedException();
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'currencies',
      {'rate_num': 1, 'rate_den': 1, 'rate_updated_at': now, 'is_active': 1},
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
