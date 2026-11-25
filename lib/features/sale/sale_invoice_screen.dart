import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/invoice.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
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
  const SaleInvoiceScreen({
    super.key,
    required this.invoice,
    this.packageOffer,
  });

  final Invoice invoice;

  /// Set when this sale renewed an account with a package other than the
  /// account's default one: the screen then offers to make it the default.
  final DefaultPackageOffer? packageOffer;

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
          if (packageOffer != null) ...[
            const SizedBox(height: 8),
            _PackageOfferCard(offer: packageOffer!),
          ],
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

/// "Make this the default package for this account": shown after a renewal
/// that sold a different package. An offer, not a question in the way — the
/// invoice is already saved and printable; one tap here changes what the
/// next "Renew" on that account starts with.
class _PackageOfferCard extends ConsumerStatefulWidget {
  const _PackageOfferCard({required this.offer});

  final DefaultPackageOffer offer;

  @override
  ConsumerState<_PackageOfferCard> createState() => _PackageOfferCardState();
}

class _PackageOfferCardState extends ConsumerState<_PackageOfferCard> {
  bool _saving = false;
  bool _done = false;

  Future<void> _accept() async {
    if (_saving || _done) return;
    final offer = widget.offer;
    // Finishes even if this screen is closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _saving = true);
    await container
        .read(customerRepositoryProvider)
        .setDefaultPackage(offer.accountId, offer.productId);
    refreshCustomerData(container);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('package-offer'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.packageChangedNotice(widget.offer.productName),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (_done)
              Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.defaultPackageUpdated,
                      key: const ValueKey('package-offer-done'),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton(
                key: const ValueKey('package-offer-accept'),
                onPressed: _saving ? null : _accept,
                child: Text(
                  l10n.makeDefaultPackage,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
