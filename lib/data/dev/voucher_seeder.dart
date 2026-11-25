/// DEBUG ONLY: fills the card stock with made-up codes, so selling cards,
/// low-stock warnings and the expired list can be tried on a phone without
/// typing a hundred codes. Nothing here runs in a release build.
library;

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/vouchers/code_import.dart';
import '../../domain/models/product.dart';
import '../../domain/models/voucher.dart';
import '../repositories/product_repository.dart';
import '../repositories/voucher_repository.dart';

/// The two test products, found again by name when seeding twice.
const String seedCardSmall = 'TEST بطاقة 5000';
const String seedCardLarge = 'TEST بطاقة 10000';

/// Creates (or reuses) two card products and loads [codesPerBatch] made-up
/// codes into each of four batches:
///
/// - small card: a batch with no expiry and a cost, a batch expiring in ten
///   days (so the "earliest expiry first" order is visible on the invoice);
/// - large card: a batch that expired yesterday (the expired list) and a
///   small fresh one under its low-stock threshold (the warning, the badge).
///
/// The codes go through the same parser, hash and cipher as real ones.
/// Returns how many codes were added; 0 in a release build.
Future<int> seedTestCards({
  required ProductRepository products,
  required VoucherRepository vouchers,
  required String currencyCode,
  int codesPerBatch = 20,
  DateTime? now,
}) async {
  if (!kDebugMode) return 0;
  final moment = now ?? DateTime.now();
  final today = DateTime(moment.year, moment.month, moment.day);
  // Different every run, so seeding twice adds new codes instead of
  // reporting them all as duplicates.
  final run = moment.millisecondsSinceEpoch % 100000000;

  Future<int> productFor(String name, int price, {int? threshold}) async {
    final existing = await products.findByName(name);
    if (existing != null) return existing.id!;
    return products.insert(Product(
      name: name,
      kind: ProductKind.service,
      priceMinor: price,
      currencyCode: currencyCode,
      isFavorite: true,
      soldFromCodeStock: true,
      lowStockThreshold: threshold,
    ));
  }

  String codes(int batch, int count) => [
        for (var i = 0; i < count; i++)
          // serial,code — a 16-digit code that prints as four groups.
          'T$batch-${i + 1},'
              '${(9000 + batch).toString()}'
              '${run.toString().padLeft(8, '0')}'
              '${i.toString().padLeft(4, '0')}',
      ].join('\n');

  Future<int> load(
    int productId,
    int batch,
    int count, {
    DateTime? lastDay,
    int? cost,
  }) async {
    final report = await vouchers.addBatch(
      productId: productId,
      parsed: parseCodeList(
        codes(batch, count),
        columns: CodeColumns.serialThenCode,
      ),
      expiryAt: lastDay == null ? null : expiryFromDate(lastDay),
      costPerCardMinor: cost,
      costCurrencyCode: cost == null ? null : currencyCode,
      source: 'seed',
      now: moment,
    );
    return report.added;
  }

  final small = await productFor(seedCardSmall, 5000, threshold: 5);
  final large = await productFor(seedCardLarge, 10000, threshold: 10);

  var added = 0;
  added += await load(small, 1, codesPerBatch, cost: 4500);
  added += await load(
    small,
    2,
    codesPerBatch,
    lastDay: today.add(const Duration(days: 10)),
    cost: 4600,
  );
  added += await load(
    large,
    3,
    codesPerBatch,
    lastDay: today.subtract(const Duration(days: 1)),
  );
  added += await load(large, 4, 3, cost: 9000);
  return added;
}
