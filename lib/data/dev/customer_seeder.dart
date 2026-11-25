/// DEBUG-ONLY customer seeding, for trying the quick search and the due list
/// against the 5,000 customers / 10,000 accounts the brief asks them to stay
/// instant with. Never reachable in a release build.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';

import '../../core/utils/due_dates.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/customer.dart';
import '../repositories/customer_repository.dart';

const List<String> _firstNames = [
  'أحمد',
  'محمد',
  'علي',
  'خالد',
  'سامر',
  'فاطمة',
  'مريم',
  'يوسف',
  'عمر',
  'ليلى',
  'Omar',
  'Sara',
];

const List<String> _familyNames = [
  'الحسن',
  'العلي',
  'إبراهيم',
  'الخطيب',
  'حداد',
  'النجار',
  'سليمان',
  'Haddad',
];

/// Providers the seeded accounts cycle through — two spellings of one of
/// them on purpose, which is what the suggestions list has to fold together.
const List<String> seedProviders = [
  'Syriatel',
  'MTN',
  'السورية للاتصالات',
  'syriatel',
  'تراسل',
];

const List<String> _labels = ['internet card', 'ADSL', 'خط خليوي'];

/// The SERVICE/CARD packages created when the catalog has none, so the
/// seeded accounts have a default package to renew.
const List<(String name, int price)> seedPackages = [
  ('انترنت 100 غيغا', 50000),
  ('ADSL 4 Mbps', 35000),
  ('باقة شهرية', 25000),
];

/// Writes [customers] customers with [accountsPerCustomer] accounts each and
/// returns how many customers it created.
///
/// Honest data: every row goes through the repository's own row builders, so
/// the normalized search columns are filled exactly as for a customer typed
/// in by hand. Phones come in the spellings shops really use (plain, spaced,
/// with the country code, in Arabic-Indic digits), account numbers keep
/// their leading zeros and one in five has letters and a dash, and the due
/// dates are spread from two weeks overdue to a month ahead — so the due
/// list has something in every bucket.
///
/// [onProgress] is called after each chunk with the running total. Chunked
/// like the invoice seeder: one short transaction per 500 customers instead
/// of one write lock for the lot.
///
/// Returns 0 in a release build without touching the database.
Future<int> seedTestCustomers(
  Database db, {
  required int customers,
  int accountsPerCustomer = 2,
  DateTime? now,
  void Function(int done)? onProgress,
}) async {
  if (!kDebugMode) return 0;
  if (customers <= 0) return 0;

  final moment = now ?? DateTime.now();
  final createdAt = moment.toUtc().millisecondsSinceEpoch;

  // Numbering carries on from what is already there, so seeding twice does
  // not produce the same phones and account numbers again.
  final offset = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COALESCE(MAX(id), 0) FROM customers'),
      ) ??
      0;

  var packageIds = [
    for (final row in await db.query(
      'products',
      columns: ['id'],
      where: "kind = 'SERVICE' AND is_active = 1",
      orderBy: 'id ASC',
      limit: 5,
    ))
      row['id'] as int,
  ];
  if (packageIds.isEmpty && accountsPerCustomer > 0) {
    final base = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['base_currency_code'],
      limit: 1,
    );
    final baseCode = base.isEmpty ? 'SYP' : base.first['value'] as String;
    packageIds = [
      for (final (name, price) in seedPackages)
        await db.insert('products', {
          'name': name,
          'name_norm': normalizeName(name),
          'kind': 'SERVICE',
          'price_minor': price,
          'currency_code': baseCode,
          'created_at': createdAt,
          'updated_at': createdAt,
        }),
    ];
  }

  String phoneFor(int n) {
    final subscriber = (40000000 + n * 7919) % 100000000;
    final digits = subscriber.toString().padLeft(8, '0');
    return switch (n % 4) {
      0 => '09$digits',
      1 => '09${digits.substring(0, 2)} ${digits.substring(2, 5)} '
          '${digits.substring(5)}',
      2 => '+963 9$digits',
      // Arabic-Indic digits, as typed on an Arabic keyboard.
      _ => '09$digits'.split('').map((c) {
          final d = int.tryParse(c);
          return d == null ? c : String.fromCharCode(0x0660 + d);
        }).join(),
    };
  }

  String accountNumberFor(int n) {
    final digits = n.toString().padLeft(10, '0');
    // One in five is alphanumeric with a dash; the rest keep leading zeros.
    return n % 5 == 0 ? 'AB-${digits.substring(4)}' : digits;
  }

  var created = 0;
  const chunk = 500;
  for (var start = 0; start < customers; start += chunk) {
    final end = (start + chunk) < customers ? start + chunk : customers;
    await db.transaction((txn) async {
      final customerBatch = txn.batch();
      for (var i = start; i < end; i++) {
        final n = offset + i;
        final name = '${_firstNames[n % _firstNames.length]} '
            '${_familyNames[(n ~/ _firstNames.length) % _familyNames.length]} '
            '${n + 1}';
        customerBatch.insert('customers', {
          ...CustomerRepository.customerRow(Customer(
            name: name,
            // One customer in ten has no phone: it is optional.
            phone: n % 10 == 9 ? null : phoneFor(n),
          )),
          'created_at': createdAt,
        });
      }
      final ids = await customerBatch.commit();

      final accountBatch = txn.batch();
      for (var i = start; i < end; i++) {
        final customerId = ids[i - start] as int;
        for (var k = 0; k < accountsPerCustomer; k++) {
          final n = (offset + i) * accountsPerCustomer + k;
          // One account in six has no schedule at all.
          final days = n % 6 == 5 ? null : const [30, 30, 30, 7, 90][n % 5];
          final lastRenewal = moment.subtract(Duration(days: n % 45));
          accountBatch.insert('customer_accounts', {
            ...CustomerRepository.accountRow(CustomerAccount(
              customerId: customerId,
              accountNumber: accountNumberFor(n),
              label: _labels[n % _labels.length],
              provider: seedProviders[n % seedProviders.length],
              defaultProductId: packageIds.isEmpty
                  ? null
                  : packageIds[n % packageIds.length],
              renewalDays: days,
              lastRenewalAt: lastRenewal,
              nextDueAt: days == null ? null : nextDueAfter(lastRenewal, days),
            )),
            'created_at': createdAt,
          });
        }
      }
      await accountBatch.commit(noResult: true);
      created += end - start;
    });
    onProgress?.call(created);
    // Hand the frame back so the progress dialog actually repaints.
    await Future<void>.delayed(Duration.zero);
  }
  return created;
}
