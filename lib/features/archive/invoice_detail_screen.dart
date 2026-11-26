import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/licensing/license_status.dart';
import '../../core/widgets/load_error_view.dart';
import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_return.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../debts/debt_providers.dart';
import '../invoice/invoice_actions.dart';
import '../invoice/invoice_preview.dart';
import '../invoice/invoice_providers.dart';
import '../license/license_gate.dart';
import '../returns/return_items_screen.dart';
import '../returns/return_paper.dart';
import '../returns/return_screen.dart';
import '../returns/returns_providers.dart';
import '../returns/void_flow.dart';
import '../settings/storage_providers.dart';
import '../vouchers/code_widgets.dart';
import '../vouchers/voucher_providers.dart';
import 'archive_providers.dart';

/// One archived invoice: the receipt itself through [InvoicePaperPreview],
/// the full [InvoiceActions] bar, and what can be done to it — RETURN ITEMS,
/// VOID INVOICE, and Delete.
///
/// Everything that leaves this screen — a reprint, a shared image or PDF, a
/// WhatsApp send, a file saved to the phone — carries the "COPY / نسخة"
/// mark, so a reprint can never be passed off as a second sale.
///
/// A VOIDED invoice is still here, under a banner that says so (when, and
/// why), with its "VOID / ملغاة" stamp on the paper and on everything
/// printed or shared from it; it can be neither returned nor voided again.
/// The returns made from an invoice are listed under its actions, each
/// opening its own document.
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
        // A void or a return reloads the invoice: what is on screen stays
        // there while it does.
        skipLoadingOnReload: true,
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
    // Its return documents go with it (their ledger entries stay).
    final returns =
        (await container.read(invoiceReturnsProvider(invoice.id!).future))
            .length;
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
            if (returns > 0) ...[
              const SizedBox(height: 12),
              Text(
                l10n.deleteInvoiceHasReturns(returns),
                key: const ValueKey('delete-invoice-returns-note'),
              ),
            ],
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
      // Its returns went with it.
      ..invalidate(invoiceReturnsProvider)
      ..invalidate(archiveReturnsProvider)
      ..invalidate(archiveReturnsSummaryProvider)
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
    final returns =
        ref.watch(invoiceReturnsProvider(invoice.id!)).value ?? const [];
    final voided = invoice.isVoided;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (voided) ...[
          _VoidBanner(invoice: invoice),
          const SizedBox(height: 12),
        ],
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
            // A voided total is money that was not made.
            color: voided
                ? theme.colorScheme.outline
                : theme.colorScheme.primary,
            decoration: voided ? TextDecoration.lineThrough : null,
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
        // Correcting the sale without deleting it. A voided invoice is
        // final: it is neither returned nor voided again.
        if (!voided) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('invoice-return'),
            onPressed: () {
              // A return is blocked exactly where a sale is.
              if (!licenseAllows(context, LicensedAction.sell)) return;
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ReturnItemsScreen(invoiceId: invoice.id!),
              ));
            },
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(l10n.returnItems, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('invoice-void'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => voidInvoiceFlow(context, invoice),
            icon: const Icon(Icons.block),
            label: Text(l10n.voidInvoice, textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 16),
        if (returns.isNotEmpty) _ReturnsSection(returns: returns),
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

/// "VOID — voided on 26/11/2026 10:00 · Reason: duplicate": the first thing
/// on the screen of a voided invoice.
class _VoidBanner extends ConsumerWidget {
  const _VoidBanner({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final reason = invoice.voidReason?.trim() ?? '';
    final color = theme.colorScheme.onErrorContainer;
    return Card(
      key: const ValueKey('invoice-void-banner'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.invoiceVoidMark,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    l10n.invoiceVoidedOn(
                      DateFormat.yMd(locale)
                          .add_jm()
                          .format(invoice.voidedAt!.toLocal()),
                    ),
                    style: TextStyle(color: color),
                  ),
                  if (reason.isNotEmpty)
                    Text(
                      l10n.auditDetailReason(reason),
                      key: const ValueKey('invoice-void-reason'),
                      style: TextStyle(color: color),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The returns made from this invoice: number, date and how it was given
/// back, with the refund at the end. A tap opens the document (as a copy).
class _ReturnsSection extends ConsumerWidget {
  const _ReturnsSection({required this.returns});

  final List<InvoiceReturn> returns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('invoice-returns'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l10n.returnsTitle, style: theme.textTheme.titleSmall),
          ),
          for (final document in returns) ReturnTile(document: document),
        ],
      ),
    );
  }
}

/// One return document in a list — under its invoice, and in the archive's
/// "Returns" filter ([showInvoice] then names the invoice it came from).
///
/// A row of its own rather than a `ListTile`: a refund in the millions as a
/// tile's `trailing` takes the whole tile and asserts.
class ReturnTile extends ConsumerWidget {
  const ReturnTile({super.key, required this.document, this.showInvoice = false});

  final InvoiceReturn document;
  final bool showInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = invoiceMoney(ref, document.currencyCode);
    String number(int value) => formatMinor(value, decimals: 0, locale: locale);
    final customer = document.customerName?.trim() ?? '';
    final facts = [
      if (showInvoice) l10n.returnFromInvoice(number(document.invoiceNo)),
      DateFormat.yMd(locale).add_jm().format(document.createdAt.toLocal()),
      refundMethodLabel(l10n, document.method),
      if (showInvoice && customer.isNotEmpty) customer,
    ].join(' · ');

    return InkWell(
      key: ValueKey('return-tile-${document.returnNo}'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        // Opened again: every output is a copy.
        builder: (_) => ReturnScreen(returnId: document.id, copy: true),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.returnNoLabel(number(document.returnNo)),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    facts,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  money(document.refundMinor),
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
