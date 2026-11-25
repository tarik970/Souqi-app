import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../security/pin_dialogs.dart';
import 'code_lookup_screen.dart';
import 'expired_codes_screen.dart';
import 'product_stock_screen.dart';
import 'voucher_providers.dart';

/// Card stock: every product sold from code stock with what is left of it.
/// Low-stock and out-of-stock warnings come first, then the expired codes
/// waiting for a decision, then the products.
class CardStockScreen extends ConsumerWidget {
  const CardStockScreen({super.key});

  Future<void> _openLookup(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    // Finding out whether a card was sold, and to whom, is itself guarded.
    if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;
    if (!navigator.mounted) return;
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const CodeLookupScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final overview = ref.watch(stockOverviewProvider);
    String count(int value) => formatMinor(value, decimals: 0, locale: locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCardStock),
        actions: [
          IconButton(
            key: const ValueKey('stock-lookup'),
            tooltip: l10n.cardStockLookup,
            icon: const Icon(Icons.manage_search),
            onPressed: () => _openLookup(context),
          ),
        ],
      ),
      body: overview.when(
        // No spinner: the counts are one small query, and a spinner would
        // keep a widget test waiting on its animation.
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('$e')),
        data: (stocks) {
          if (stocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.cardStockEmpty,
                  key: const ValueKey('stock-empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final warnings = [
            for (final stock in stocks)
              if (stock.needsAttention) stock,
          ];
          final expired =
              stocks.fold<int>(0, (sum, stock) => sum + stock.expired);

          return ListView(
            key: const ValueKey('stock-list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (warnings.isNotEmpty)
                Card(
                  key: const ValueKey('stock-warnings'),
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final stock in warnings)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 18,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    stock.isOut
                                        ? l10n.stockOutWarning(
                                            stock.product.name)
                                        : l10n.stockLowWarning(
                                            stock.product.name,
                                            count(stock.available),
                                          ),
                                    key: ValueKey(
                                        'stock-warning-${stock.product.id}'),
                                    style: TextStyle(
                                      color:
                                          theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (expired > 0)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: ListTile(
                    key: const ValueKey('stock-expired'),
                    leading: Icon(Icons.event_busy,
                        color: theme.colorScheme.error),
                    title: Text(l10n.expiredCodesTitle),
                    subtitle: Text(l10n.expiredCodesNotice(count(expired))),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ExpiredCodesScreen(),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              for (final stock in stocks) _StockCard(stock: stock),
            ],
          );
        },
      ),
    );
  }
}

class _StockCard extends ConsumerWidget {
  const _StockCard({required this.stock});

  final ProductStock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final product = stock.product;

    return Card(
      key: ValueKey('stock-product-${product.id}'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductStockScreen(productId: product.id!),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: product.isActive
                            ? null
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              StockCounts(
                locale: locale,
                available: stock.available,
                sold: stock.sold,
                voided: stock.voided,
                expired: stock.expired,
                highlightAvailable: stock.needsAttention,
                labels: l10n,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Available 12 · Sold 340 · Void 2" as a wrapping row of small figures.
/// A Wrap, so a large system font moves a figure to the next line instead of
/// overflowing the card.
class StockCounts extends StatelessWidget {
  const StockCounts({
    super.key,
    required this.locale,
    required this.available,
    required this.sold,
    required this.voided,
    required this.expired,
    required this.labels,
    this.highlightAvailable = false,
  });

  final String locale;
  final int available;
  final int sold;
  final int voided;
  final int expired;
  final AppLocalizations labels;

  /// The product is low or out: the available figure is drawn as a warning.
  final bool highlightAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget figure(String label, int value, {Color? color, String? id}) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatMinor(value, decimals: 0, locale: locale),
              key: id == null ? null : ValueKey(id),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        );

    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        figure(
          labels.stockAvailable,
          available,
          color: highlightAvailable
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
          id: 'count-available',
        ),
        figure(labels.stockSold, sold, id: 'count-sold'),
        figure(labels.stockVoid, voided, id: 'count-void'),
        if (expired > 0)
          figure(
            labels.stockExpired,
            expired,
            color: theme.colorScheme.error,
            id: 'count-expired',
          ),
      ],
    );
  }
}
