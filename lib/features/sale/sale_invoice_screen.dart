import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice.dart';
import '../../l10n/generated/app_localizations.dart';
import 'sale_providers.dart';
import 'sale_screen.dart';

/// Shown right after an invoice is saved: what was stored, and what to do
/// next. Print and Share PDF are placeholders until the printing phase.
class SaleInvoiceScreen extends ConsumerWidget {
  const SaleInvoiceScreen({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final currencies = ref.watch(currencyContextProvider).value;
    final currency = currencies?.lookup(invoice.currencyCode);
    final decimals = currency?.decimalPlaces ?? 0;
    final symbol = currency == null
        ? invoice.currencyCode
        : (currency.symbol.isEmpty ? currency.code : currency.symbol);

    String money(int minor) => formatMinor(
          minor,
          decimals: decimals,
          locale: locale,
          symbol: symbol,
        );

    void comingSoon() => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.comingSoon)));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invoiceSavedTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.check_circle,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    l10n.invoiceNoLabel(
                      NumberFormat.decimalPattern(locale)
                          .format(invoice.invoiceNo),
                    ),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMd(locale)
                        .add_jm()
                        .format(invoice.createdAt.toLocal()),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    money(invoice.totalMinor),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  for (final extra in invoice.extraTotals)
                    Text(
                      '≈ ${formatMinor(
                        extra.totalMinor,
                        decimals: currencies
                                ?.lookup(extra.currencyCode)
                                ?.decimalPlaces ??
                            0,
                        locale: locale,
                        symbol: extra.currencyCode,
                      )}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.itemsCount(invoice.items.length),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (invoice.discountMinor != 0)
                    Text(
                      '${l10n.discountLabel} − ${money(invoice.discountMinor)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: comingSoon,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(l10n.printInvoice),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: comingSoon,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l10n.sharePdf),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const SaleScreen()),
            ),
            icon: const Icon(Icons.add_shopping_cart),
            label: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(l10n.newSale),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backToHome),
          ),
        ],
      ),
    );
  }
}
