import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/load_error_view.dart';
import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../debts/debt_providers.dart';
import '../invoice/invoice_actions.dart';
import '../invoice/invoice_preview.dart';
import '../invoice/invoice_providers.dart';
import '../settings/storage_providers.dart';
import '../vouchers/code_widgets.dart';
import '../vouchers/voucher_providers.dart';
import 'archive_providers.dart';

/// One archived invoice: the receipt itself through [InvoicePaperPreview],
/// the full [InvoiceActions] bar, and Delete.
///
/// Everything that leaves this screen — a reprint, a shared image or PDF, a
/// WhatsApp send, a file saved to the phone — carries the "COPY / نسخة"
/// mark, so a reprint can never be passed off as a second sale.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final invoice = ref.watch(archivedInvoiceProvider(invoiceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navArchive),
        actions: [
          if (invoice.value != null)
            IconButton(
              key: const ValueKey('archive-delete-invoice'),
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref, invoice.value!),
            ),
        ],
      ),
      body: invoice.when(
        data: (data) => data == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(l10n.invoiceNotFound, textAlign: TextAlign.center),
                ),
              )
            : _Body(invoice: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) => LoadErrorView(e, stack),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Invoice invoice,
  ) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final number = formatMinor(invoice.invoiceNo, decimals: 0, locale: locale);
    // Taken before the dialog: the pop below tears this screen down, and a
    // confirmed delete must still land.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    // A debt is never deleted with its invoice: the dialog says so when
    // this invoice carries one.
    final carriesDebt = featureOn(Feature.debt) &&
        await container
            .read(archiveRepositoryProvider)
            .invoiceCarriesDebt(invoice.id!);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('delete-invoice-dialog'),
        scrollable: true,
        title: Text(l10n.deleteInvoiceTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteInvoiceMessage(number)),
            if (carriesDebt) ...[
              const SizedBox(height: 12),
              Text(
                l10n.deleteInvoiceCarriesDebt,
                key: const ValueKey('delete-invoice-debt-note'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await container.read(archiveRepositoryProvider).deleteInvoice(invoice.id!);
    container
      ..invalidate(archiveListProvider)
      ..invalidate(archiveRangeSummaryProvider)
      ..invalidate(storageStatsProvider)
      ..invalidate(archivedInvoiceProvider(invoice.id!))
      // The customer's page lists this invoice too.
      ..invalidate(customerHistoryProvider)
      ..invalidate(customerTotalsProvider);
    // The ledger entry stays; its link to the invoice is gone.
    refreshDebtData(container);
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.invoiceDeletedMessage(number))),
      );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final render = ref.watch(invoiceRenderContextProvider).value;
    final currencies = ref.watch(currenciesProvider).value;
    final currency =
        currencies?.where((c) => c.code == invoice.currencyCode).firstOrNull;
    // Masked: the preview never holds a code in the clear.
    final codes =
        ref.watch(invoicePreviewCodesProvider(invoice.id!)).value ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.invoiceNoLabel(
            formatMinor(invoice.invoiceNo, decimals: 0, locale: locale),
          ),
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat.yMd(locale).add_jm().format(invoice.createdAt.toLocal()),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          formatMinor(
            invoice.totalMinor,
            decimals: currency?.decimalPlaces ?? 0,
            locale: locale,
            symbol: currency == null || currency.symbol.isEmpty
                ? invoice.currencyCode
                : currency.symbol,
          ),
          key: const ValueKey('archive-invoice-total'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Said in words before anything is printed, because the mark on the
        // paper is only seen after the paper comes out.
        Row(
          children: [
            Icon(Icons.content_copy, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.invoiceCopyNotice,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InvoiceActions(invoice: invoice, copy: true),
        const SizedBox(height: 16),
        // The cards this invoice sold: masked, each with show / void /
        // return to stock behind the PIN.
        InvoiceCodesSection(invoiceId: invoice.id!),
        if (render != null)
          InvoicePaperPreview(
            key: const ValueKey('archive-invoice-view'),
            invoice: invoice,
            settings: render.settings,
            currencies: render.currencies,
            logo: render.logo,
            isCopy: true,
            codes: codes,
            maxWidth: 380,
          ),
      ],
    );
  }
}
