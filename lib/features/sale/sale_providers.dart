import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../invoice/invoice_providers.dart';

/// Up to two extra currencies shown under the invoice total. One source of
/// truth: the invoice settings (edited there, or by the sale screen's
/// "secondary total" shortcut).
final extraTotalCurrenciesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(
    invoiceSettingsProvider.selectAsync((settings) => settings.extraCurrencies),
  ),
);

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

/// The "type-to-sell" switches from the Settings screen. All on by default.
class SaleSettings {
  const SaleSettings({
    this.saveNewItems = true,
    this.updatePrices = true,
    this.autoFavorites = true,
  });

  /// An item typed during a sale becomes a product when the invoice is saved.
  final bool saveNewItems;

  /// A unit price changed during a sale becomes the product's saved price.
  final bool updatePrices;

  /// The favorites bar is topped up with the best sellers of the last 30 days.
  final bool autoFavorites;

  SaleSettings copyWith({
    bool? saveNewItems,
    bool? updatePrices,
    bool? autoFavorites,
  }) =>
      SaleSettings(
        saveNewItems: saveNewItems ?? this.saveNewItems,
        updatePrices: updatePrices ?? this.updatePrices,
        autoFavorites: autoFavorites ?? this.autoFavorites,
      );
}

class SaleSettingsNotifier extends AsyncNotifier<SaleSettings> {
  @override
  Future<SaleSettings> build() async {
    final settings = ref.watch(settingsRepositoryProvider);
    return SaleSettings(
      saveNewItems:
          await settings.getBool(SettingsKeys.saveNewItemsAsProducts),
      updatePrices:
          await settings.getBool(SettingsKeys.updateProductPriceFromSales),
      autoFavorites: await settings.getBool(SettingsKeys.autoFavorites),
    );
  }

  /// Applies the change to the state first (the switch moves at once), then
  /// persists it.
  Future<void> change(SaleSettings Function(SaleSettings current) update) async {
    final next = update(await future);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).setMany({
      SettingsKeys.saveNewItemsAsProducts: next.saveNewItems ? '1' : '0',
      SettingsKeys.updateProductPriceFromSales: next.updatePrices ? '1' : '0',
      SettingsKeys.autoFavorites: next.autoFavorites ? '1' : '0',
    });
  }
}

final saleSettingsProvider =
    AsyncNotifierProvider<SaleSettingsNotifier, SaleSettings>(
  SaleSettingsNotifier.new,
);

/// The favorites bar: starred products first, then (unless switched off) the
/// most-sold products of the last 30 days, up to 12 buttons.
///
/// Auto-dispose, like the search results below: both are reloaded every time
/// the sale screen opens, so a product starred, renamed or just sold never
/// shows stale here.
final favoriteProductsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) async {
  final auto = await ref.watch(
    saleSettingsProvider.selectAsync((settings) => settings.autoFavorites),
  );
  return ref.watch(productRepositoryProvider).favoritesBar(includeAuto: auto);
});

/// The unit a new typed item starts with: the one used for the previous new
/// item, or the preset "piece" until there is one. Null = no unit.
final newItemUnitProvider = FutureProvider<Unit?>((ref) async {
  final units = await ref.watch(unitsProvider.future);
  final raw = await ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.lastNewItemUnitId);
  if (raw == '0') return null; // the last new item had no unit
  final id = int.tryParse(raw);
  for (final unit in units) {
    if (unit.id == id) return unit;
  }
  // Never chosen yet (or that unit is gone): the preset "piece".
  for (final unit in units) {
    if (unit.isPreset && unit.nameEn == 'piece') return unit;
  }
  return null;
});

class SaleSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final saleSearchProvider =
    NotifierProvider<SaleSearchNotifier, String>(SaleSearchNotifier.new);

/// What the sale screen shows for the typed text.
class SaleSearchResults {
  const SaleSearchResults({
    this.query = '',
    this.products = const [],
    this.exactMatch,
  });

  /// The typed text, trimmed, with runs of spaces collapsed — also the name
  /// a new item gets.
  final String query;

  /// Best match first (see [ProductRepository.list]).
  final List<Product> products;

  /// The product whose code, barcode or normalized name IS the typed text.
  final Product? exactMatch;

  /// "+ Add «typed text»" is offered whenever the text is not already a
  /// product — also when other products merely contain it, so "سكر خشن" can be
  /// added although "سكر" exists.
  bool get offersNewItem => query.isNotEmpty && exactMatch == null;
}

/// Runs the sale search. Shared by the results list and by Enter on the
/// search box, so both always agree on what the top row is.
Future<SaleSearchResults> searchForSale(
  ProductRepository repository,
  String rawQuery,
) async {
  final query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (query.isEmpty) return const SaleSearchResults();
  final products = await repository.list(query: query);
  final code = normalizeCode(query);
  final name = normalizeName(query);
  Product? exact;
  for (final product in products) {
    if (product.code == code ||
        product.barcode == code ||
        normalizeName(product.name) == name) {
      exact = product;
      break;
    }
  }
  return SaleSearchResults(query: query, products: products, exactMatch: exact);
}

/// Products matching the sale screen's search box. Empty query → no results
/// (the favorites bar and the cart stay visible instead).
final saleSearchResultsProvider =
    FutureProvider.autoDispose<SaleSearchResults>((ref) {
  final query = ref.watch(saleSearchProvider);
  return searchForSale(ref.watch(productRepositoryProvider), query);
});

/// Units by id, for the unit name snapshot on each cart line.
final saleUnitsProvider = FutureProvider<Map<int, Unit>>((ref) async {
  final units = await ref.watch(unitsProvider.future);
  return {for (final u in units) u.id!: u};
});
