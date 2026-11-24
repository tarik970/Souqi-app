import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';
import 'product_form_screen.dart';
import 'products_providers.dart';

enum _KindFilter { all, goods, services }

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(productsFilterProvider);
    final products = ref.watch(productsListProvider);

    final kindFilter = switch (filter.kind) {
      null => _KindFilter.all,
      ProductKind.goods => _KindFilter.goods,
      ProductKind.service => _KindFilter.services,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navProducts),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              CheckedPopupMenuItem<void>(
                checked: filter.showInactive,
                child: Text(l10n.showInactive),
                onTap: () => ref
                    .read(productsFilterProvider.notifier)
                    .setShowInactive(!filter.showInactive),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchProductsHint,
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged:
                  ref.read(productsFilterProvider.notifier).setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_KindFilter>(
              segments: [
                ButtonSegment(
                    value: _KindFilter.all, label: Text(l10n.filterAll)),
                ButtonSegment(
                    value: _KindFilter.goods, label: Text(l10n.filterGoods)),
                ButtonSegment(
                    value: _KindFilter.services,
                    label: Text(l10n.filterServices)),
              ],
              selected: {kindFilter},
              onSelectionChanged: (selection) {
                ref.read(productsFilterProvider.notifier).setKind(
                      switch (selection.first) {
                        _KindFilter.all => null,
                        _KindFilter.goods => ProductKind.goods,
                        _KindFilter.services => ProductKind.service,
                      },
                    );
              },
            ),
          ),
          Expanded(
            child: products.when(
              data: (items) => items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: 0.5,
                            child: Image.asset(
                              'assets/branding/souqi_mark.png',
                              height: 80,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(l10n.noProducts),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _ProductTile(product: items[index]),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.addProduct),
      ),
    );
  }

  static void _openForm(BuildContext context, [Product? product]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final units = ref.watch(unitMapProvider).value ?? const <int, Unit>{};
    final currencies =
        ref.watch(currencyMapProvider).value ?? const <String, Currency>{};
    final theme = Theme.of(context);

    final currency = currencies[product.currencyCode];
    final price = currency == null
        ? product.currencyCode
        : formatMinor(
            product.priceMinor,
            decimals: currency.decimalPlaces,
            locale: locale,
            symbol:
                currency.symbol.isEmpty ? currency.code : currency.symbol,
          );
    final unit = product.unitId == null ? null : units[product.unitId];
    final details = [
      price,
      if (unit != null) unit.nameFor(locale),
      if (product.code != null) '#${product.code}',
    ].join(' · ');

    return ListTile(
      enabled: product.isActive,
      leading: Icon(product.kind == ProductKind.goods
          ? Icons.shopping_basket
          : Icons.sim_card),
      title: Row(
        children: [
          Flexible(child: Text(product.name)),
          if (!product.isActive) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(l10n.inactiveBadge),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: Text(details),
      onTap: () => ProductsScreen._openForm(context, product),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              product.isFavorite ? Icons.star : Icons.star_border,
              color: product.isFavorite ? theme.colorScheme.secondary : null,
            ),
            onPressed: () async {
              await ref
                  .read(productRepositoryProvider)
                  .setFavorite(product.id!, !product.isFavorite);
              ref.invalidate(productsListProvider);
            },
          ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                child: Text(l10n.edit),
                onTap: () => ProductsScreen._openForm(context, product),
              ),
              PopupMenuItem<void>(
                child: Text(l10n.delete),
                onTap: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteProductTitle),
        content: Text(l10n.deleteProductMessage(product.name)),
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
    final result =
        await ref.read(productRepositoryProvider).delete(product.id!);
    ref.invalidate(productsListProvider);
    if (result == ProductDeleteResult.deactivated) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.productDeactivatedMessage)),
      );
    }
  }
}
