import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';

class ProductsFilter {
  const ProductsFilter({this.query = '', this.kind, this.showInactive = false});

  final String query;
  final ProductKind? kind;
  final bool showInactive;

  ProductsFilter copyWith({
    String? query,
    ProductKind? Function()? kind,
    bool? showInactive,
  }) {
    return ProductsFilter(
      query: query ?? this.query,
      kind: kind != null ? kind() : this.kind,
      showInactive: showInactive ?? this.showInactive,
    );
  }
}

class ProductsFilterNotifier extends Notifier<ProductsFilter> {
  @override
  ProductsFilter build() => const ProductsFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setKind(ProductKind? kind) => state = state.copyWith(kind: () => kind);

  void setShowInactive(bool show) => state = state.copyWith(showInactive: show);
}

final productsFilterProvider =
    NotifierProvider<ProductsFilterNotifier, ProductsFilter>(
        ProductsFilterNotifier.new);

final productsListProvider = FutureProvider<List<Product>>((ref) {
  final filter = ref.watch(productsFilterProvider);
  return ref.watch(productRepositoryProvider).list(
        query: filter.query,
        kind: filter.kind,
        includeInactive: filter.showInactive,
      );
});

final unitMapProvider = FutureProvider<Map<int, Unit>>((ref) async {
  final units = await ref.watch(unitsProvider.future);
  return {for (final u in units) u.id!: u};
});

final currencyMapProvider = FutureProvider<Map<String, Currency>>((ref) async {
  final currencies = await ref.watch(currenciesProvider.future);
  return {for (final c in currencies) c.code: c};
});
