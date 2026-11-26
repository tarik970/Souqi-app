import 'package:sqflite/sqflite.dart';

import '../../core/constants/settings_keys.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/debt_report.dart';
import 'debt_repository.dart';
import 'settings_repository.dart';

/// Reads everything the daily debt report shows, at one moment.
///
/// READ-ONLY: it runs in the background job too, in a second Flutter engine
/// next to the app's own, and writes nothing to the database. The figures
/// come from the same code as the debtors list and the statistics
/// ([DebtRepository.debtors], [DebtRepository.periodQuery]) so the report
/// can never disagree with the screens.
class DebtReportRepository {
  DebtReportRepository(this._db);

  final Database _db;

  static int _ms(DateTime moment) => moment.toUtc().millisecondsSinceEpoch;

  static DateTime? _date(Object? ms) => ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

  static String? _blankToNull(Object? text) {
    final value = (text as String?)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Every entry DATED today or WRITTEN today — a payment backdated to last
  /// week but typed in today is part of what changed today — in the order
  /// they were written, with the customer and the reversal links the
  /// ledger screens show.
  static const String movementsQuery =
      'SELECT t.*, c.name AS customer_name, c.phone AS customer_phone, '
      'r.id AS reversed_by_id, o.type AS rv_type, '
      'o.receipt_no AS rv_receipt_no, o.invoice_no AS rv_invoice_no '
      'FROM debt_transactions t '
      'JOIN customers c ON c.id = t.customer_id '
      'LEFT JOIN debt_transactions r ON r.reverses_id = t.id '
      'LEFT JOIN debt_transactions o ON o.id = t.reverses_id '
      'WHERE (t.created_at >= ? AND t.created_at < ?) '
      'OR (t.recorded_at >= ? AND t.recorded_at < ?) '
      'ORDER BY t.recorded_at ASC, t.id ASC';

  /// Every customer who has an account in the ledger, whatever its balance
  /// — zero and credit balances included.
  static const String balancesQuery =
      'SELECT c.name, c.name_norm, c.phone, c.is_active, '
      'c.credit_limit_base_minor, b.balance, b.last_payment_at '
      'FROM (SELECT t.customer_id, '
      '  SUM(t.amount_base_minor * t.direction) AS balance, '
      "  MAX(CASE WHEN t.type = 'PAYMENT' AND NOT EXISTS ("
      '    SELECT 1 FROM debt_transactions rv WHERE rv.reverses_id = t.id) '
      '    THEN t.created_at END) AS last_payment_at '
      '  FROM debt_transactions t GROUP BY t.customer_id) b '
      'JOIN customers c ON c.id = b.customer_id '
      'ORDER BY c.name_norm ASC, c.id ASC';

  Future<DebtReportData> build({required DateTime now}) async {
    final settings = SettingsRepository(_db);
    final language =
        await settings.getString(SettingsKeys.invoiceLanguage) == 'en'
            ? 'en'
            : 'ar';
    final shopName = (await settings.getString(SettingsKeys.shopName)).trim();
    final currency = await _baseCurrency(settings);

    final local = now.toLocal();
    final dayStart = DateTime(local.year, local.month, local.day);
    final dayEnd = DateTime(local.year, local.month, local.day + 1);

    final snapshot = await DebtRepository(_db).debtors(now: now);
    final today = (await _db.rawQuery(
      DebtRepository.periodQuery,
      [_ms(dayStart), _ms(dayEnd)],
    ))
        .first;

    final owing = [
      for (final d in snapshot.debtors)
        if (d.balanceBaseMinor > 0) d,
    ]..sort((a, b) {
        final byAmount = b.balanceBaseMinor.compareTo(a.balanceBaseMinor);
        return byAmount != 0 ? byAmount : a.nameNorm.compareTo(b.nameNorm);
      });

    final movementRows = await _db.rawQuery(movementsQuery, [
      _ms(dayStart),
      _ms(dayEnd),
      _ms(dayStart),
      _ms(dayEnd),
    ]);
    final balanceRows = await _db.rawQuery(balancesQuery);

    return DebtReportData(
      generatedAt: local,
      shopName: shopName,
      language: language,
      currency: currency,
      summary: DebtReportSummary(
        totalOutstandingBaseMinor: snapshot.totalOutstandingBaseMinor,
        totalCreditBaseMinor: snapshot.totalCreditBaseMinor,
        debtorsCount: snapshot.owingCount,
        overdueCount: snapshot.overdueCount,
        aging: snapshot.aging,
        collectedTodayBaseMinor: (today['collected'] as int?) ?? 0,
        newDebtTodayBaseMinor: (today['new_debt'] as int?) ?? 0,
      ),
      debtors: [
        for (final d in owing)
          DebtReportDebtor(
            name: d.name,
            phone: d.phone,
            balanceBaseMinor: d.balanceBaseMinor,
            creditLimitBaseMinor: d.creditLimitBaseMinor,
            oldestUnpaidAt: d.account.oldestUnpaidAt,
            lastPaymentAt: d.account.lastPaymentAt,
            overdue: d.account.isOverdue,
          ),
      ],
      movements: [
        for (final row in movementRows)
          DebtReportMovement(
            entry: DebtEntry.fromMap(row),
            customerName: row['customer_name'] as String,
            customerPhone: _blankToNull(row['customer_phone']),
          ),
      ],
      balances: [
        for (final row in balanceRows)
          DebtReportBalance(
            name: row['name'] as String,
            phone: _blankToNull(row['phone']),
            balanceBaseMinor: (row['balance'] as int?) ?? 0,
            creditLimitBaseMinor: row['credit_limit_base_minor'] as int?,
            lastPaymentAt: _date(row['last_payment_at']),
            isActive: row['is_active'] != 0,
          ),
      ],
    );
  }

  Future<ReportCurrency> _baseCurrency(SettingsRepository settings) async {
    final code = await settings.getString(SettingsKeys.baseCurrencyCode);
    final rows = await _db.query(
      'currencies',
      columns: ['symbol', 'decimal_places'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ReportCurrency(code: code, symbol: '', decimals: 0);
    }
    return ReportCurrency(
      code: code,
      symbol: (rows.first['symbol'] as String?) ?? '',
      decimals: (rows.first['decimal_places'] as int?) ?? 0,
    );
  }
}
