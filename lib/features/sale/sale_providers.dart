import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';

/// Up to two extra currencies shown under the invoice total.
final extraTotalCurrenciesProvider = FutureProvider<List<String>>((ref) async {
  final raw = await ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.extraTotalCurrencies);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().take(2).toList();
  } on FormatException {
    return const [];
  }
});

/// Currency table + base code + extra display currencies, everything the cart
/// math needs. Rebuilt whenever a rate changes.
final currencyContextProvider = FutureProvider<CurrencyContext>((ref) async {
  final currencies = await ref.watch(currenciesProvider.future);
  final baseCode = await ref.watch(baseCurrencyCodeProvider.future);
  final extras = await ref.watch(extraTotalCurrenciesProvider.future);
  return CurrencyContext.of(currencies, baseCode: baseCode, extraCodes: extras);
});

/// Active currencies that can be picked as the invoice currency: the base
/// currency plus every active currency whose rate has been entered.
final sellableCurrenciesProvider = Provider<List<Currency>>((ref) {
  final ctx = ref.watch(currencyContextProvider).value;
  if (ctx == null) return const [];
  return [
    for (final c in ctx.byCode.values)
      if (c.isActive && ctx.hasUsableRate(c.code)) c,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  void add(CartLine line) => state = state.add(line);

  void replace(CartLine line) => state = state.replace(line);

  void setQuantity(int lineId, int qtyThousandths) =>
      state = state.setQuantity(lineId, qtyThousandths);

  void remove(int lineId) => state = state.remove(lineId);

  void clear() => state = state.clear();

  void setDiscount(Discount? discount) =>
      state = state.withDiscount(discountEnabled ? discount : null);

  void setInvoiceCurrency(String? code) =>
      state = state.withInvoiceCurrency(code);

  /// Starts a brand-new sale: no lines, no discount, invoice currency back to
  /// the base currency.
  void reset() => state = const Cart();
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

/// The computed cart. Null while the currency table is still loading.
final cartTotalsProvider = Provider<CartTotals?>((ref) {
  final ctx = ref.watch(currencyContextProvider).value;
  if (ctx == null) return null;
  return computeCartTotals(ref.watch(cartProvider), ctx);
});

/// Favorites for the top bar of the sale screen.
final favoriteProductsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(productRepositoryProvider).list(favoritesOnly: true),
);

class SaleSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final saleSearchProvider =
    NotifierProvider<SaleSearchNotifier, String>(SaleSearchNotifier.new);

/// Products matching the sale screen's search box. Empty query → no results
/// (the favorites bar and the cart stay visible instead).
final saleSearchResultsProvider = FutureProvider<List<Product>>((ref) async {
  final query = ref.watch(saleSearchProvider).trim();
  if (query.isEmpty) return const [];
  return ref.watch(productRepositoryProvider).list(query: query);
});

/// Units by id, for the unit name snapshot on each cart line.
final saleUnitsProvider = FutureProvider<Map<int, Unit>>((ref) async {
  final units = await ref.watch(unitsProvider.future);
  return {for (final u in units) u.id!: u};
});
