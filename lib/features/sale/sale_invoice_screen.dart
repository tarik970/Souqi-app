import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_actions.dart';
import '../invoice/invoice_preview.dart';
import '../invoice/invoice_providers.dart';
import '../invoice/invoice_settings_screen.dart';
import 'sale_providers.dart';
import 'sale_screen.dart';

/// Shown right after an invoice is saved: a short summary in the app
/// language, the invoice exactly as it will be printed or shared, and the
/// output actions (primary button per the output mode, the rest under
/// "More").
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
    final render = ref.watch(invoiceRenderContextProvider).value;

    String money(int minor) => formatMinor(
          minor,
          decimals: decimals,
          locale: locale,
          symbol: symbol,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.invoiceSavedTitle),
        actions: [
          IconButton(
            tooltip: l10n.invoiceSettingsTitle,
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.check_circle,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 12),
                  Text(
                    money(invoice.totalMinor),
                    key: const ValueKey('saved-total'),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          InvoiceActions(invoice: invoice),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const SaleScreen()),
            ),
            icon: const Icon(Icons.add_shopping_cart),
            label: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(l10n.newSale),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backToHome),
          ),
          const SizedBox(height: 8),
          // The on-screen invoice view: the very widget that is printed and
          // shared, so what is seen here is what the customer gets.
          if (render != null)
            InvoicePaperPreview(
              key: const ValueKey('saved-invoice-view'),
              invoice: invoice,
              settings: render.settings,
              currencies: render.currencies,
              logo: render.logo,
              maxWidth: 380,
            ),
        ],
      ),
    );
  }
}
