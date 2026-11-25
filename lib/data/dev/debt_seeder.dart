/// DEBUG-ONLY ledger seeding, for trying the debtors list, the aging summary
/// and the debt statistics against the 5,000 customers / 200,000 ledger
/// entries the brief asks them to stay fast with. Never reachable in a
/// release build.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';

import '../../core/utils/due_dates.dart';
import '../repositories/counter_repository.dart';

/// Writes [entries] ledger entries spread evenly over the customers that
/// exist, and returns how many it wrote (0 when there are no customers:
/// seed those first).
///
/// Honest data, in the shapes the real code writes:
/// - every customer gets a history that runs from about 400 days ago to
///   today, three debits for every two payments;
/// - one customer in five settles in full every time (their balance keeps
///   returning to zero), one in ten overpays (a credit balance), the rest
///   pay part, and one in six never pays at all — so the debtors list has
///   every kind of row and the FIFO aging has something in every bucket;
/// - one customer in seven starts with an opening balance;
/// - payments get sequential receipt numbers from the real counter;
/// - about one entry in a thousand is cancelled by a REVERSAL entry, so the
///   "not reversed" probes of the aggregates are exercised too.
///
/// The reversals come ON TOP of [entries].
///
/// [onProgress] is called after each chunk with the running total. Chunked
/// like the other seeders: one short transaction per 5,000 rows.
///
/// Returns 0 in a release build without touching the database.
Future<int> seedTestDebts(
  Database db, {
  required int entries,
  DateTime? now,
  void Function(int done)? onProgress,
}) async {
  if (!kDebugMode) return 0;
  if (entries <= 0) return 0;

  final customers = [
    for (final row in await db.query(
      'customers',
      columns: ['id'],
      where: 'is_active = 1',
      orderBy: 'id ASC',
    ))
      row['id'] as int,
  ];
  if (customers.isEmpty) return 0;

  final moment = now ?? DateTime.now();
  final recordedAt = moment.toUtc().millisecondsSinceEpoch;
  final n = customers.length;
  final rounds = (entries + n - 1) ~/ n;
  // The whole history spans about 400 days, whatever the number of rounds.
  final stepDays = (400 / rounds).clamp(0.05, 30.0);

  // Where each customer's balance stands as the history is written, so the
  // "settles in full" customers can pay exactly what they owe.
  final balance = List<int>.filled(n, 0);

  var written = 0;
  const chunk = 5000;
  for (var start = 0; start < entries; start += chunk) {
    final end = (start + chunk) < entries ? start + chunk : entries;
    await db.transaction((txn) async {
      var receiptNo = (await txn.query(
            'counters',
            columns: ['value'],
            where: 'name = ?',
            whereArgs: [CounterRepository.receiptNo],
            limit: 1,
          ))
              .firstOrNull?['value'] as int? ??
          0;
      final hadCounter = (await txn.query(
        'counters',
        columns: ['name'],
        where: 'name = ?',
        whereArgs: [CounterRepository.receiptNo],
        limit: 1,
      ))
          .isNotEmpty;

      final batch = txn.batch();
      // (position in this chunk, customer id, direction, amount) of the
      // rows that get a reversal.
      final toReverse = <(int, int, int, int)>[];
      for (var i = start; i < end; i++) {
        final c = i % n;
        final k = i ~/ n;
        final at = moment.subtract(Duration(
          minutes: ((rounds - k) * stepDays * 24 * 60).round() +
              (c * 37) % 600,
        ));
        final atMs = at.toUtc().millisecondsSinceEpoch;
        // One customer in six has stopped paying: their debts grow old.
        final wantsPayment = (k % 5 == 2 || k % 5 == 4) && c % 6 != 1;

        final Map<String, Object?> row;
        if (k == 0 && c % 7 == 0) {
          final amount = 10000 + (c % 50) * 1000;
          balance[c] += amount;
          row = {
            'type': 'OPENING_BALANCE',
            'direction': 1,
            'amount_base_minor': amount,
            'due_at': nextDueAfter(at, 30).toUtc().millisecondsSinceEpoch,
          };
        } else if (wantsPayment && balance[c] > 0) {
          final int amount;
          if (c % 5 == 0) {
            amount = balance[c]; // settles in full
          } else if (c % 10 == 3) {
            amount = balance[c] + 1000 + (k % 4) * 500; // overpays
          } else {
            final part = balance[c] * (30 + (c * 13 + k * 7) % 50) ~/ 100;
            amount = part < 500 ? 500 : part;
          }
          balance[c] -= amount;
          receiptNo++;
          row = {
            'type': 'PAYMENT',
            'direction': -1,
            'amount_base_minor': amount,
            'payment_method': const ['CASH', 'CASH', 'CASH', 'TRANSFER'][i % 4],
            'receipt_no': receiptNo,
            'balance_before_base_minor': balance[c] + amount,
          };
        } else {
          final amount = 2000 + ((c * 31 + k * 17) % 40) * 500;
          balance[c] += amount;
          final manual = c % 3 == 0;
          row = {
            'type': manual ? 'MANUAL_DEBT' : 'DEBT',
            'direction': 1,
            'amount_base_minor': amount,
            // The number of an invoice that is no longer in the archive.
            'invoice_no': manual ? null : 100000 + i,
            'due_at': nextDueAfter(at, 30).toUtc().millisecondsSinceEpoch,
          };
        }
        if (i % 997 == 500) {
          toReverse.add((
            i - start,
            customers[c],
            row['direction']! as int,
            row['amount_base_minor']! as int,
          ));
          balance[c] -=
              (row['direction']! as int) * (row['amount_base_minor']! as int);
        }
        batch.insert('debt_transactions', {
          'customer_id': customers[c],
          'created_at': atMs,
          'recorded_at': recordedAt,
          ...row,
        });
      }
      final ids = await batch.commit();
      for (final (position, customerId, direction, amount) in toReverse) {
        await txn.insert('debt_transactions', {
          'customer_id': customerId,
          'type': 'REVERSAL',
          'direction': -direction,
          'amount_base_minor': amount,
          'reverses_id': ids[position],
          'note': 'seed',
          'created_at': recordedAt,
          'recorded_at': recordedAt,
        });
      }
      if (hadCounter) {
        await txn.update(
          'counters',
          {'value': receiptNo},
          where: 'name = ?',
          whereArgs: [CounterRepository.receiptNo],
        );
      } else if (receiptNo > 0) {
        await txn.insert('counters', {
          'name': CounterRepository.receiptNo,
          'value': receiptNo,
        });
      }
      written += end - start;
    });
    onProgress?.call(written);
    // Hand the frame back so the progress dialog actually repaints.
    await Future<void>.delayed(Duration.zero);
  }
  return written;
}
