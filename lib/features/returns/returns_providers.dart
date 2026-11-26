import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/invoice_correction_repository.dart';
import '../../domain/models/invoice_return.dart';
import '../archive/archive_providers.dart';
import '../customers/customers_providers.dart';
import '../debts/debt_providers.dart';
import '../products/products_providers.dart';
import '../sale/sale_providers.dart';
import '../security/audit_providers.dart';
import '../settings/storage_providers.dart';
import '../stats/stats_providers.dart';
import '../vouchers/voucher_providers.dart';

/// The return documents made from one invoice, oldest first — the "Returns"
/// block of the invoice screen.
final invoiceReturnsProvider = FutureProvider.family<List<InvoiceReturn>, int>(
  (ref, invoiceId) =>
      ref.watch(invoiceCorrectionRepositoryProvider).returnsOf(invoiceId),
);

/// One return document with its lines.
final returnDocumentProvider =
    FutureProvider.autoDispose.family<InvoiceReturn?, int>(
  (ref, id) => ref.watch(invoiceCorrectionRepositoryProvider).returnById(id),
);

/// The lines of an invoice with what is still returnable of each.
final returnableLinesProvider =
    FutureProvider.autoDispose.family<List<ReturnableLine>, int>(
  (ref, invoiceId) => ref
      .watch(invoiceCorrectionRepositoryProvider)
      .returnableLines(invoiceId),
);

/// The "void invoices up to N days old" setting; 0 = no limit.
final voidMaxAgeDaysProvider = FutureProvider<int>(
  (ref) => ref.watch(invoiceCorrectionRepositoryProvider).voidMaxAgeDays(),
);

/// How many return documents the archive's "Returns" list has loaded;
/// "Show more" raises it.
class ArchiveReturnsLimit extends Notifier<int> {
  @override
  int build() {
    // Another period or another search starts from the top again.
    ref.watch(archiveFilterProvider);
    return InvoiceCorrectionRepository.returnsPageSize;
  }

  void more() => state += InvoiceCorrectionRepository.returnsPageSize;
}

final archiveReturnsLimitProvider =
    NotifierProvider<ArchiveReturnsLimit, int>(ArchiveReturnsLimit.new);

/// The archive's "Returns" list: the return documents DATED in the archive's
/// period, newest first, narrowed by its search box.
final archiveReturnsProvider = FutureProvider<List<InvoiceReturn>>((ref) {
  final filter = ref.watch(archiveFilterProvider);
  final limit = ref.watch(archiveReturnsLimitProvider);
  return ref
      .watch(invoiceCorrectionRepositoryProvider)
      .returnsPage(filter, limit: limit);
});

/// How many returns that is and what they gave back — the line above the
/// list.
final archiveReturnsSummaryProvider = FutureProvider<ArchiveRangeSummary>(
  (ref) => ref
      .watch(invoiceCorrectionRepositoryProvider)
      .returnsSummary(ref.watch(archiveFilterProvider)),
);

/// AN INVOICE WAS VOIDED OR A RETURN WAS SAVED: everything that counts
/// invoices, money, debts, card stock or renewal dates is now stale — the
/// archive and the invoice on screen, the statistics, "most sold", the
/// customer's page and due dates, the ledger, the card stock and the audit
/// log.
///
/// Takes the container so it still runs when the screen that caused it has
/// already been closed.
void refreshAfterCorrection(ProviderContainer container) {
  container
    ..invalidate(archiveListProvider)
    ..invalidate(archiveRangeSummaryProvider)
    ..invalidate(archivedInvoiceProvider)
    ..invalidate(deleteSummaryProvider)
    ..invalidate(invoiceReturnsProvider)
    ..invalidate(returnDocumentProvider)
    ..invalidate(returnableLinesProvider)
    ..invalidate(archiveReturnsProvider)
    ..invalidate(archiveReturnsSummaryProvider)
    ..invalidate(storageStatsProvider)
    ..invalidate(statsReportProvider)
    ..invalidate(productsListProvider)
    ..invalidate(favoriteProductsProvider)
    ..invalidate(auditLogProvider);
  refreshCustomerData(container);
  refreshDebtData(container);
  refreshVoucherData(container);
}
