/// DEBUG-ONLY archive seeding, for testing the archive and the statistics
/// screens against the 50,000-invoice shop the brief asks them to stay smooth
/// on. Never reachable in a release build.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';

import '../../core/money/exchange.dart';
import '../../core/money/quantity.dart';
import '../../core/utils/normalize.dart';
import '../repositories/counter_repository.dart';

/// Item names the seeded invoices sell, so the "top products" tables have
/// something to group. The first few are deliberately Arabic variants of one
/// another ("السكر" / "سكر"), which is what proves the grouping is done on
/// the normalized name.
const List<String> seedItemNames = [
  'سكر',
  'السكر',
  'شاي',
  'رز',
  'زيت',
  'خبز',
  'ملح',
  'صابون',
  'قهوة',
  'انترنت 100 غيغا',
];

/// Writes [count] invoices spread evenly over the last [days] days and
/// returns how many it created.
///
/// Honest data: the invoice numbers come from the real counter, the totals
/// come from the real money module, every snapshot column (including the
/// normalized search columns) is filled, and one invoice in five is in a
/// second currency with its own rate snapshot — so a seeded archive
/// exercises the same code paths as a real one.
///
/// Returns 0 in a release build without touching the database.
Future<int> seedTestInvoices(
  Database db, {
  required int count,
  int days = 365,
  int linesPerInvoice = 3,
  DateTime? now,
}) async {
  if (!kDebugMode) return 0;
  if (count <= 0) return 0;

  final moment = now ?? DateTime.now();
  final currencies = await db.query(
    'currencies',
    columns: ['code', 'decimal_places', 'rate_num', 'rate_den'],
  );
  final baseRow = await db.query(
    'settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: ['base_currency_code'],
    limit: 1,
  );
  final baseCode =
      baseRow.isEmpty ? 'SYP' : baseRow.first['value'] as String;
  final base = currencies.firstWhere(
    (c) => c['code'] == baseCode,
    orElse: () => currencies.first,
  );
  final baseDecimals = base['decimal_places'] as int;

  // A currency that is not the base one, for the mixed-currency fifth.
  final other = currencies.where((c) => c['code'] != baseCode).firstOrNull;

  // Link the lines to real products where the shop already has them, so the
  // seeded data groups by product_id as well as by name.
  final products = await db.query('products', columns: ['id', 'name_norm']);
  final productIdByNorm = {
    for (final row in products) row['name_norm'] as String: row['id'] as int,
  };

  const counters = CounterRepository();
  var created = 0;

  // One transaction per 500 invoices: all-or-nothing per chunk, without
  // holding a single write lock for the whole of a 50,000-row seed.
  const chunk = 500;
  for (var start = 0; start < count; start += chunk) {
    final end = (start + chunk) < count ? start + chunk : count;
    await db.transaction((txn) async {
      for (var i = start; i < end; i++) {
        final invoiceNo =
            await counters.next(txn, CounterRepository.invoiceNo);
        final createdAt = moment.subtract(
          Duration(minutes: (i * days * 24 * 60) ~/ count),
        );
        final useOther = other != null && i % 5 == 0;
        final currency = useOther ? other : base;
        final code = currency['code'] as String;
        final decimals = currency['decimal_places'] as int;
        final rate = RateFraction(
          currency['rate_num'] as int,
          currency['rate_den'] as int,
        );

        final lines = <Map<String, Object?>>[];
        var subtotal = 0;
        for (var line = 0; line < linesPerInvoice; line++) {
          final name = seedItemNames[(i + line) % seedItemNames.length];
          final qty = 1000 + ((i + line) % 3) * 500;
          // A price that is sane in either currency's minor units.
          final price = decimals == 0 ? 500 + (i % 20) * 100 : 50 + (i % 20);
          final total =
              lineTotalMinor(unitPriceMinor: price, qtyThousandths: qty);
          subtotal += total;
          lines.add({
            'product_id': productIdByNorm[normalizeName(name)],
            'sort_order': line,
            'product_name': name,
            'product_name_norm': normalizeName(name),
            'kind': 'GOODS',
            'qty_thousandths': qty,
            'orig_unit_price_minor': price,
            'orig_currency_code': code,
            'orig_rate_num': rate.numerator,
            'orig_rate_den': rate.denominator,
            'unit_price_minor': price,
            'line_total_minor': total,
          });
        }
        // Every third invoice carries a discount, so the discount figure on
        // the statistics screen is not always zero.
        final discount = i % 3 == 0 ? subtotal ~/ 10 : 0;
        final total = subtotal - discount;

        final invoiceId = await txn.insert('invoices', {
          'invoice_no': invoiceNo,
          'created_at': createdAt.toUtc().millisecondsSinceEpoch,
          'currency_code': code,
          'base_currency_code': baseCode,
          'rate_num': rate.numerator,
          'rate_den': rate.denominator,
          'subtotal_minor': subtotal,
          'discount_type': discount > 0 ? 'AMOUNT' : null,
          'discount_value': discount > 0 ? discount : null,
          'discount_minor': discount,
          'total_minor': total,
          'total_base_minor': toBaseMinor(
            amountMinor: total,
            fromDecimals: decimals,
            fromRate: rate,
            baseDecimals: baseDecimals,
          ),
        });
        for (final line in lines) {
          await txn.insert('invoice_items', {
            ...line,
            'invoice_id': invoiceId,
          });
        }
        created++;
      }
    });
  }
  return created;
}
