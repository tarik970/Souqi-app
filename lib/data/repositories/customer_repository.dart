import 'package:sqflite/sqflite.dart';

import '../../core/utils/due_dates.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/customer.dart';

/// One row of the Customers screen.
class CustomerListEntry {
  const CustomerListEntry({
    required this.customer,
    required this.nameNorm,
    required this.accountCount,
  });

  final Customer customer;

  /// The sort key, kept so the next page can start right after this row.
  final String nameNorm;

  /// Active cards / accounts.
  final int accountCount;
}

/// How many accounts each part of the due list holds.
class DueCounts {
  const DueCounts({this.overdue = 0, this.today = 0, this.soon = 0});

  final int overdue;
  final int today;
  final int soon;

  /// The home screen badge: everything on the "Due for renewal" screen.
  int get total => overdue + today + soon;
}

/// Customers, their cards / accounts, the quick search and the due list.
///
/// Takes a [DatabaseExecutor], so the invoice save can run
/// [recordRenewal] inside its own transaction.
///
/// Every list here is bounded by LIMIT and filtered in sqlite: this has to
/// stay instant with 5,000 customers and 10,000 accounts on a phone.
class CustomerRepository {
  CustomerRepository(this._db);

  final DatabaseExecutor _db;

  /// Rows the quick search shows. More than a screenful is noise: the seller
  /// types one more character instead of scrolling.
  static const int quickSearchLimit = 30;

  /// Rows per page of the Customers screen.
  static const int pageSize = 50;

  /// Rows the due list loads at a time.
  static const int duePageSize = 100;

  static const String _customerColumns =
      'c.id AS c_id, c.name AS c_name, c.phone AS c_phone, '
      'c.notes AS c_notes, c.is_active AS c_is_active, '
      'c.created_at AS c_created_at';

  static const String _accountColumns =
      'a.id AS a_id, a.customer_id AS a_customer_id, '
      'a.account_number AS a_account_number, a.label AS a_label, '
      'a.provider AS a_provider, '
      'a.default_product_id AS a_default_product_id, '
      'a.renewal_days AS a_renewal_days, '
      'a.last_renewal_at AS a_last_renewal_at, '
      'a.next_due_at AS a_next_due_at, a.notes AS a_notes, '
      'a.is_active AS a_is_active, a.created_at AS a_created_at';

  static const String _packageColumns =
      'p.name AS package_name, p.is_active AS package_active';

  /// `%`, `_` and the escape character typed by the user match themselves.
  /// Paired with `ESCAPE '!'` in every LIKE below.
  static String _escapeLike(String text) => text
      .replaceAll('!', '!!')
      .replaceAll('%', '!%')
      .replaceAll('_', '!_');

  static int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static int? _ms(DateTime? moment) => moment?.toUtc().millisecondsSinceEpoch;

  static String? _blankToNull(String? text) {
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static CustomerHit _hit(Map<String, Object?> row) => CustomerHit(
        customer: Customer.fromMap(row, prefix: 'c_'),
        account: row['a_id'] == null
            ? null
            : CustomerAccount.fromMap(row, prefix: 'a_'),
        packageName: row['package_name'] as String?,
        packageActive: row['package_active'] != 0,
      );

  // ---- Customers ---------------------------------------------------------

  /// The stored form of a customer (without `created_at`): the text as typed
  /// plus its normalized search columns. Public so the debug seeder writes
  /// rows through exactly the same normalization.
  static Map<String, Object?> customerRow(Customer customer) {
    final phone = _blankToNull(customer.phone);
    final phoneNorm = phone == null ? '' : normalizePhone(phone);
    return {
      'name': customer.name.trim(),
      'name_norm': normalizeName(customer.name),
      // Stored exactly as typed; the digits-only form is the search index.
      'phone': phone,
      'phone_norm': phoneNorm.isEmpty ? null : phoneNorm,
      'notes': _blankToNull(customer.notes),
      'is_active': customer.isActive ? 1 : 0,
    };
  }

  Future<int> insert(Customer customer) => _db.insert('customers', {
        ...customerRow(customer),
        'created_at': _now(),
      });

  /// Creates a customer and, when [account] is given, their first account —
  /// both or neither. The account's `customerId` is ignored.
  ///
  /// Returns the two new ids.
  Future<(int customerId, int? accountId)> insertWithAccount(
    Customer customer, {
    CustomerAccount? account,
  }) {
    Future<(int, int?)> run(CustomerRepository repository) async {
      final customerId = await repository.insert(customer);
      if (account == null) return (customerId, null);
      final accountId = await repository.insertAccount(
        account.copyWith(customerId: customerId),
      );
      return (customerId, accountId);
    }

    final db = _db;
    if (db is Database) {
      return db.transaction((txn) => run(CustomerRepository(txn)));
    }
    // Already inside someone else's transaction.
    return run(this);
  }

  Future<void> update(Customer customer) async {
    await _db.update(
      'customers',
      customerRow(customer),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  /// Customers are never hard-deleted: their invoices, accounts and (later)
  /// debts point at them. Deactivating hides them from the search.
  Future<void> setActive(int id, bool active) async {
    await _db.update(
      'customers',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Customer?> getById(int id) async {
    final rows = await _db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// One page of the Customers screen, by name. [query] matches the name or
  /// the phone number (partial, through the shared normalizers). Pass the
  /// last row of the previous page as [after].
  Future<List<CustomerListEntry>> list({
    String query = '',
    bool includeInactive = false,
    CustomerListEntry? after,
    int limit = pageSize,
    String countryCode = '963',
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeInactive) where.add('c.is_active = 1');

    final raw = query.trim();
    if (raw.isNotEmpty) {
      final clauses = <String>[];
      final name = normalizeName(raw);
      if (name.isNotEmpty) {
        clauses.add("c.name_norm LIKE ? ESCAPE '!'");
        args.add('%${_escapeLike(name)}%');
      }
      final phone = phoneSearchKey(raw, countryCode: countryCode);
      if (phone.isNotEmpty) {
        clauses.add("c.phone_norm LIKE ? ESCAPE '!'");
        args.add('%$phone%');
      }
      // Text that normalizes to nothing matches nobody, not everybody.
      where.add(clauses.isEmpty ? '0' : '(${clauses.join(' OR ')})');
    }
    if (after != null) {
      where.add('(c.name_norm > ? OR (c.name_norm = ? AND c.id > ?))');
      args.addAll([after.nameNorm, after.nameNorm, after.customer.id]);
    }

    final rows = await _db.rawQuery(
      'SELECT c.*, '
      '(SELECT COUNT(*) FROM customer_accounts a '
      ' WHERE a.customer_id = c.id AND a.is_active = 1) AS account_count '
      'FROM customers c '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
      'ORDER BY c.name_norm ASC, c.id ASC LIMIT ?',
      [...args, limit],
    );
    return [
      for (final row in rows)
        CustomerListEntry(
          customer: Customer.fromMap(row),
          nameNorm: row['name_norm'] as String,
          accountCount: (row['account_count'] as int?) ?? 0,
        ),
    ];
  }

  // ---- Accounts ----------------------------------------------------------

  /// The stored form of an account (without `created_at`).
  static Map<String, Object?> accountRow(CustomerAccount account) => {
        'customer_id': account.customerId,
        // Text, as typed: "0011-2233" keeps its zeros and its dash.
        'account_number': account.accountNumber.trim(),
        'account_number_norm': normalizeCode(account.accountNumber),
        'label': _blankToNull(account.label),
        'provider': _blankToNull(account.provider),
        'default_product_id': account.defaultProductId,
        'renewal_days': account.renewalDays,
        'last_renewal_at': _ms(account.lastRenewalAt),
        'next_due_at': _ms(account.nextDueAt),
        'notes': _blankToNull(account.notes),
        'is_active': account.isActive ? 1 : 0,
      };

  Future<int> insertAccount(CustomerAccount account) =>
      _db.insert('customer_accounts', {
        ...accountRow(account),
        'created_at': _now(),
      });

  Future<void> updateAccount(CustomerAccount account) async {
    await _db.update(
      'customer_accounts',
      accountRow(account),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<void> setAccountActive(int id, bool active) async {
    await _db.update(
      'customer_accounts',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<CustomerAccount?> getAccount(int id) async {
    final rows = await _db.query(
      'customer_accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CustomerAccount.fromMap(rows.first);
  }

  /// Every account of [customerId] with its default package: active ones
  /// first, the soonest due on top.
  Future<List<CustomerHit>> accountsOf(int customerId) async {
    final rows = await _db.rawQuery(
      'SELECT $_customerColumns, $_accountColumns, $_packageColumns '
      'FROM customer_accounts a '
      'JOIN customers c ON c.id = a.customer_id '
      'LEFT JOIN products p ON p.id = a.default_product_id '
      'WHERE a.customer_id = ? '
      'ORDER BY a.is_active DESC, a.next_due_at IS NULL, a.next_due_at ASC, '
      'a.id ASC',
      [customerId],
    );
    return rows.map(_hit).toList();
  }

  /// One account as a [CustomerHit] (customer, account, package).
  Future<CustomerHit?> hitForAccount(int accountId) async {
    final rows = await _db.rawQuery(
      'SELECT $_customerColumns, $_accountColumns, $_packageColumns '
      'FROM customer_accounts a '
      'JOIN customers c ON c.id = a.customer_id '
      'LEFT JOIN products p ON p.id = a.default_product_id '
      'WHERE a.id = ? LIMIT 1',
      [accountId],
    );
    return rows.isEmpty ? null : _hit(rows.first);
  }

  /// Accounts that already carry [accountNumber] for the same [provider] —
  /// the "this card is already registered" warning. Compared through the
  /// shared normalizers, so "0011-2233" is "٠٠١١ ٢٢٣٣" and "MTN" is "mtn".
  /// The same number under another provider is a different account.
  ///
  /// Only a warning: the caller may save anyway.
  Future<List<AccountDuplicate>> findDuplicateAccounts(
    String accountNumber, {
    String? provider,
    int? excludeId,
  }) async {
    final norm = normalizeCode(accountNumber);
    if (norm.isEmpty) return const [];
    final rows = await _db.rawQuery(
      'SELECT a.*, c.name AS customer_name '
      'FROM customer_accounts a '
      'JOIN customers c ON c.id = a.customer_id '
      'WHERE a.account_number_norm = ?'
      '${excludeId == null ? '' : ' AND a.id != ?'} '
      'ORDER BY a.id ASC',
      [norm, ?excludeId],
    );
    final wanted = normalizeName(provider ?? '');
    return [
      for (final row in rows)
        if (normalizeName((row['provider'] as String?) ?? '') == wanted)
          AccountDuplicate(
            account: CustomerAccount.fromMap(row),
            customerName: row['customer_name'] as String,
          ),
    ];
  }

  /// Providers typed before, the most used first — the suggestions under the
  /// provider field. Spellings that normalize to the same name are offered
  /// once, in their most common form.
  Future<List<String>> providerSuggestions({int limit = 50}) async {
    final rows = await _db.rawQuery(
      'SELECT provider, COUNT(*) AS n FROM customer_accounts '
      "WHERE provider IS NOT NULL AND TRIM(provider) != '' "
      'GROUP BY provider ORDER BY n DESC, provider ASC',
    );
    final seen = <String>{};
    final result = <String>[];
    for (final row in rows) {
      final provider = (row['provider'] as String).trim();
      if (seen.add(normalizeName(provider))) result.add(provider);
      if (result.length >= limit) break;
    }
    return result;
  }

  /// "Make this the default package for this account."
  Future<void> setDefaultPackage(int accountId, int? productId) async {
    await _db.update(
      'customer_accounts',
      {'default_product_id': productId},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  /// Marks [accountId] as renewed at [renewedAt]: that moment becomes the
  /// last renewal date, and the next due day is that day plus the account's
  /// renewal period. An account with no period has no schedule, so its due
  /// date is cleared rather than left pointing at the day just paid for.
  ///
  /// Called by the invoice save inside the invoice's own transaction — a
  /// sale that fails to save leaves both dates exactly as they were.
  Future<void> recordRenewal(int accountId, DateTime renewedAt) async {
    final rows = await _db.query(
      'customer_accounts',
      columns: ['renewal_days'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final days = rows.first['renewal_days'] as int?;
    await _db.update(
      'customer_accounts',
      {
        'last_renewal_at': _ms(renewedAt),
        'next_due_at':
            days == null ? null : _ms(nextDueAfter(renewedAt, days)),
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  // ---- Quick search ------------------------------------------------------

  /// The quick search as text, so a test can EXPLAIN exactly what runs.
  /// Null when [query] normalizes to nothing (no search at all).
  ///
  /// One box, three columns: the customer's name, their phone, or a card /
  /// account number — each compared through its own shared normalizer, so
  /// spaces, dashes and Arabic-Indic digits never matter, and letters in an
  /// account number are kept. Partial matches count everywhere.
  ///
  /// The plan is one pass over the customers, each joined to their accounts
  /// through `idx_accounts_customer` and to the package by primary key:
  /// linear in the number of rows, never customers × accounts.
  ///
  /// Best match first: an exact number or phone, an exact name, then names
  /// or numbers starting with the text, then the rest.
  (String, List<Object?>)? quickSearchQuery(
    String query, {
    int limit = quickSearchLimit,
    bool includeAccounts = true,
    String countryCode = '963',
  }) {
    final raw = query.trim();
    if (raw.isEmpty) return null;
    final name = normalizeName(raw);
    final code = includeAccounts ? normalizeCode(raw) : '';
    // Digits only when the text can be a phone number at all: "MTN-123"
    // must not match every phone containing 123.
    final phoneExact = looksLikePhone(raw) ? normalizePhone(raw) : '';
    final phoneKey = phoneSearchKey(raw, countryCode: countryCode);
    if (name.isEmpty && code.isEmpty && phoneKey.isEmpty) return null;

    final rank = StringBuffer('CASE');
    final rankArgs = <Object?>[];
    void when(String condition, int value, Object? arg) {
      rank.write(' WHEN $condition THEN $value');
      rankArgs.add(arg);
    }

    if (code.isNotEmpty) when('a.account_number_norm = ?', 0, code);
    if (phoneExact.isNotEmpty) when('c.phone_norm = ?', 0, phoneExact);
    if (name.isNotEmpty) {
      when('c.name_norm = ?', 1, name);
      when("c.name_norm LIKE ? ESCAPE '!'", 2, '${_escapeLike(name)}%');
    }
    if (code.isNotEmpty) {
      when(
        "a.account_number_norm LIKE ? ESCAPE '!'",
        2,
        '${_escapeLike(code)}%',
      );
    }
    if (phoneExact.isNotEmpty) when('c.phone_norm LIKE ?', 2, '$phoneExact%');
    rank.write(' ELSE 3 END');

    final match = <String>[];
    final matchArgs = <Object?>[];
    if (name.isNotEmpty) {
      match.add("c.name_norm LIKE ? ESCAPE '!'");
      matchArgs.add('%${_escapeLike(name)}%');
    }
    if (phoneKey.isNotEmpty) {
      match.add('c.phone_norm LIKE ?');
      matchArgs.add('%$phoneKey%');
    }
    if (code.isNotEmpty) {
      match.add("a.account_number_norm LIKE ? ESCAPE '!'");
      matchArgs.add('%${_escapeLike(code)}%');
    }

    final sql = includeAccounts
        ? 'SELECT $_customerColumns, $_accountColumns, $_packageColumns, '
            '$rank AS match_rank '
            'FROM customers c '
            'LEFT JOIN customer_accounts a '
            '  ON a.customer_id = c.id AND a.is_active = 1 '
            'LEFT JOIN products p ON p.id = a.default_product_id '
            'WHERE c.is_active = 1 AND (${match.join(' OR ')}) '
            'ORDER BY match_rank ASC, c.name_norm ASC, '
            'a.next_due_at IS NULL, a.next_due_at ASC, a.id ASC LIMIT ?'
        : 'SELECT $_customerColumns, NULL AS a_id, '
            'NULL AS package_name, 1 AS package_active, '
            '$rank AS match_rank '
            'FROM customers c '
            'WHERE c.is_active = 1 AND (${match.join(' OR ')}) '
            'ORDER BY match_rank ASC, c.name_norm ASC, c.id ASC LIMIT ?';
    return (sql, [...rankArgs, ...matchArgs, limit]);
  }

  /// Runs [quickSearchQuery]. An empty [query] finds nothing.
  Future<List<CustomerHit>> quickSearch(
    String query, {
    int limit = quickSearchLimit,
    bool includeAccounts = true,
    String countryCode = '963',
  }) async {
    final built = quickSearchQuery(
      query,
      limit: limit,
      includeAccounts: includeAccounts,
      countryCode: countryCode,
    );
    if (built == null) return const [];
    final (sql, args) = built;
    final rows = await _db.rawQuery(sql, args);
    return rows.map(_hit).toList();
  }

  // ---- Due for renewal ---------------------------------------------------

  static const String _dueWhere =
      'a.next_due_at IS NOT NULL AND a.next_due_at < ? '
      'AND a.is_active = 1 AND c.is_active = 1';

  /// The due list as text, so a test can EXPLAIN exactly what runs: a range
  /// read of `idx_accounts_due`, already in due-date order.
  ///
  /// `CROSS JOIN` pins the accounts as the outer loop — sqlite never
  /// reorders a cross join — so the index range is what bounds the query,
  /// whatever the planner's statistics say.
  (String, List<Object?>) dueListQuery({
    required DateTime now,
    required int soonDays,
    int limit = duePageSize,
  }) =>
      (
        'SELECT $_customerColumns, $_accountColumns, $_packageColumns '
            'FROM customer_accounts a '
            'CROSS JOIN customers c ON c.id = a.customer_id '
            'LEFT JOIN products p ON p.id = a.default_product_id '
            'WHERE $_dueWhere '
            'ORDER BY a.next_due_at ASC, a.id ASC LIMIT ?',
        [_ms(dueWindowEnd(now, soonDays)), limit],
      );

  /// Accounts that are overdue, due today or due within [soonDays] days as
  /// seen at [now], the longest overdue first. Deactivated accounts and the
  /// accounts of deactivated customers are left out.
  Future<List<CustomerHit>> dueList({
    required DateTime now,
    required int soonDays,
    int limit = duePageSize,
  }) async {
    final (sql, args) = dueListQuery(
      now: now,
      soonDays: soonDays,
      limit: limit,
    );
    final rows = await _db.rawQuery(sql, args);
    return rows.map(_hit).toList();
  }

  /// How many accounts each bucket of the due list holds — one aggregate
  /// over the same index range, for the section headers and the badge.
  Future<DueCounts> dueCounts({
    required DateTime now,
    required int soonDays,
  }) async {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final tomorrow = DateTime(local.year, local.month, local.day + 1);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, '
      'COALESCE(SUM(a.next_due_at < ?), 0) AS overdue, '
      'COALESCE(SUM(a.next_due_at >= ? AND a.next_due_at < ?), 0) AS today '
      'FROM customer_accounts a '
      'CROSS JOIN customers c ON c.id = a.customer_id '
      'WHERE $_dueWhere',
      [_ms(today), _ms(today), _ms(tomorrow), _ms(dueWindowEnd(now, soonDays))],
    );
    final row = rows.first;
    final total = (row['n'] as int?) ?? 0;
    final overdue = (row['overdue'] as int?) ?? 0;
    final dueToday = (row['today'] as int?) ?? 0;
    return DueCounts(
      overdue: overdue,
      today: dueToday,
      soon: total - overdue - dueToday,
    );
  }

  // ---- History -----------------------------------------------------------

  /// The customer's invoices, newest first, read through
  /// `idx_invoices_customer`. Only what is still in the archive: invoices
  /// removed by a delete or by the retention sweep are gone from here too.
  Future<List<CustomerInvoice>> history(
    int customerId, {
    int limit = 50,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT i.id, i.invoice_no, i.created_at, i.currency_code, '
      'i.total_minor, i.account_number, '
      '(SELECT COUNT(*) FROM invoice_items it WHERE it.invoice_id = i.id) '
      'AS item_count, '
      '(SELECT it.product_name FROM invoice_items it '
      ' WHERE it.invoice_id = i.id ORDER BY it.sort_order ASC, it.id ASC '
      ' LIMIT 1) AS first_item '
      'FROM invoices i WHERE i.customer_id = ? '
      'ORDER BY i.created_at DESC, i.id DESC LIMIT ?',
      [customerId, limit],
    );
    return rows.map(CustomerInvoice.fromRow).toList();
  }

  /// Count, base-currency total and date of the last purchase — from each
  /// invoice's stored `total_base_minor`, never from today's rates.
  Future<CustomerTotals> totals(int customerId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(i.total_base_minor), 0) AS total, '
      'MAX(i.created_at) AS last_at '
      'FROM invoices i WHERE i.customer_id = ?',
      [customerId],
    );
    final row = rows.first;
    final lastAt = row['last_at'] as int?;
    return CustomerTotals(
      invoiceCount: (row['n'] as int?) ?? 0,
      totalBaseMinor: (row['total'] as int?) ?? 0,
      lastPurchaseAt: lastAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAt, isUtc: true),
    );
  }
}
