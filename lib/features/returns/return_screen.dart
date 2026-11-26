import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/widgets/load_error_view.dart';
import '../../l10n/generated/app_localizations.dart';
import '../debts/debt_output.dart';
import '../invoice/invoice_providers.dart';
import 'return_paper.dart';
import 'returns_providers.dart';

/// A return document ("مرتجع رقم 12 — من فاتورة 152"): the paper exactly as
/// it prints, with Print / Share / WhatsApp / Save above it — the same
/// pipeline as an invoice and a receipt.
///
/// [copy] is false right after the return was saved — that output is the
/// original — and true when the document is opened again from the archive,
/// from its invoice or from the ledger: every output then carries the
/// "COPY / نسخة" mark.
class ReturnScreen extends ConsumerWidget {
  const ReturnScreen({super.key, required this.returnId, this.copy = false});

  final int returnId;
  final bool copy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final data = ref.watch(returnDocumentProvider(returnId));
    final render = ref.watch(invoiceRenderContextProvider).value;
    final currencies = ref.watch(currenciesProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.returnTitle)),
      body: data.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => LoadErrorView(e, stack),
        data: (document) {
          if (document == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.returnNotFound, textAlign: TextAlign.center),
              ),
            );
          }
          final paper = returnPaper(document);
          final currency = currencies
              ?.where((c) => c.code == document.currencyCode)
              .firstOrNull;
          String number(int value) =>
              formatMinor(value, decimals: 0, locale: locale);
          return ListView(
            key: const ValueKey('return-screen'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                l10n.returnNoLabel(number(document.returnNo)),
                key: const ValueKey('return-number'),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Text(
                l10n.returnFromInvoice(number(document.invoiceNo)),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // One line, scaled down: a refund in the millions at a large
              // system font is wider than a small phone.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatMinor(
                    document.refundMinor,
                    decimals: currency?.decimalPlaces ?? 0,
                    locale: locale,
                    symbol: currency == null || currency.symbol.isEmpty
                        ? document.currencyCode
                        : currency.symbol,
                  ),
                  key: const ValueKey('return-refund-total'),
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (copy) ...[
                Row(
                  children: [
                    Icon(
                      Icons.content_copy,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
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
              ],
              PaperActions(paper: paper, copy: copy),
              const SizedBox(height: 16),
              if (render != null)
                LedgerPaperPreview(
                  key: const ValueKey('return-preview'),
                  paper: paper,
                  context_: render,
                  copy: copy,
                ),
            ],
          );
        },
      ),
    );
  }
}
