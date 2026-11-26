import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../security/audit_providers.dart';
import '../stats/stats_providers.dart';

/// How many codes each card product can sell right now, by product id. A
/// product with none is absent. Empty when the feature is off.
///
/// One small query (see `idx_codes_status`) shared by every place that shows
/// a card product: the products list, the favorites bar, the sale search,
/// the quantity sheet and the cart.
final voucherAvailabilityProvider = FutureProvider<Map<int, int>>((ref) {
  if (!featureOn(Feature.vouchers)) return const <int, int>{};
  return ref.watch(voucherRepositoryProvider).availableByProduct();
});

/// Every card product with its available / sold / void / expired counts.
final stockOverviewProvider = FutureProvider<List<ProductStock>>(
  (ref) => ref.watch(voucherRepositoryProvider).stockOverview(),
);

/// Card products that are out of stock or at their threshold: the badge on
/// the home screen. Zero when the feature is off.
final lowStockCountProvider = FutureProvider<int>((ref) {
  if (!featureOn(Feature.vouchers)) return 0;
  return ref.watch(voucherRepositoryProvider).lowStockCount();
});

final productBatchesProvider =
    FutureProvider.family<List<VoucherBatch>, int>(
  (ref, productId) => ref.watch(voucherRepositoryProvider).batches(productId),
);

/// The codes of one batch, masked.
final batchCodesProvider =
    FutureProvider.autoDispose.family<List<VoucherCodeView>, int>(
  (ref, batchId) => ref.watch(voucherRepositoryProvider).codesOfBatch(batchId),
);

/// Unsold codes past their expiry, masked. `null` = every product.
final expiredCodesProvider =
    FutureProvider.autoDispose.family<List<VoucherCodeView>, int?>(
  (ref, productId) =>
      ref.watch(voucherRepositoryProvider).expiredCodes(productId: productId),
);

/// Every code an invoice sold, masked — for the "Card codes" section of the
/// invoice screens. Empty when the feature is off.
final invoiceCodesProvider =
    FutureProvider.family<List<VoucherCodeView>, int>((ref, invoiceId) {
  if (!featureOn(Feature.vouchers)) return const <VoucherCodeView>[];
  return ref.watch(voucherRepositoryProvider).codesOfInvoice(invoiceId);
});

/// The codes an invoice still carries (status SOLD), masked, in print order:
/// what the on-screen preview shows in place of the real thing.
final invoicePreviewCodesProvider =
    FutureProvider.family<List<InvoiceCode>, int>((ref, invoiceId) async {
  if (!featureOn(Feature.vouchers)) return const <InvoiceCode>[];
  // Depends on the list above so one invalidation refreshes both.
  await ref.watch(invoiceCodesProvider(invoiceId).future);
  final codes =
      await ref.watch(voucherRepositoryProvider).printableCodes(invoiceId);
  // The secret is dropped here, before anything reaches a widget.
  return [for (final code in codes) code.hidden];
});

/// Call after anything that changes card stock: a sale, a loaded batch, a
/// void, a return, a deleted batch. Goes through the container so it also
/// works after the screen that caused it is gone.
void refreshVoucherData(ProviderContainer container) {
  container
    ..invalidate(voucherAvailabilityProvider)
    ..invalidate(stockOverviewProvider)
    ..invalidate(lowStockCountProvider)
    ..invalidate(productBatchesProvider)
    ..invalidate(batchCodesProvider)
    ..invalidate(expiredCodesProvider)
    ..invalidate(invoiceCodesProvider)
    ..invalidate(invoicePreviewCodesProvider)
    ..invalidate(auditLogProvider)
    // "Cards sold" and its profit.
    ..invalidate(statsReportProvider);
}
