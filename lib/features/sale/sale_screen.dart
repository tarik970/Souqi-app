import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';
import 'discount_sheet.dart';
import 'quantity_sheet.dart';
import 'quick_item_sheet.dart';
import 'rates_sheet.dart';
import 'sale_invoice_screen.dart';
import 'sale_providers.dart';

/// The sale screen: favorites bar, search, cart, live total, save.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _locale => ref.read(appLocaleProvider).languageCode;

  CurrencyContext? get _ctx => ref.read(currencyContextProvider).value;

  /// Builds a cart line from a saved product, snapshotting its unit name.
  /// Awaits the unit table so the snapshot is never silently empty on the
  /// first sale after launch.
  Future<CartLine> _lineFor(Product product,
      {int qtyThousandths = 1000}) async {
    final units = await ref.read(saleUnitsProvider.future);
    return CartLine(
      productId: product.id,
      name: product.name,
      code: product.code,
      kind: product.kind,
      unitName: product.unitId == null
          ? null
          : units[product.unitId]?.nameFor(_locale),
      unitPriceMinor: product.priceMinor,
      priceCurrencyCode: product.currencyCode,
      qtyThousandths: qtyThousandths,
    );
  }

  Future<void> _tapProduct(Product product) async {
    final draft = await _lineFor(product);
    if (!mounted) return;
    final line = await showQuantitySheet(context, line: draft);
    if (line == null) return;
    ref.read(cartProvider.notifier).add(line);
    _clearSearch();
  }

  Future<void> _editLine(CartLine line) async {
    final edited =
        await showQuantitySheet(context, line: line, isEdit: true);
    if (edited == null) return;
    ref.read(cartProvider.notifier).replace(edited);
  }

  void _clearSearch() {
    _search.clear();
    ref.read(saleSearchProvider.notifier).clear();
  }

  /// Enter on the search field: an exact code (or barcode) goes straight into
  /// the cart with quantity 1 — no sheet, no extra tap.
  Future<void> _submitSearch(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final product =
        await ref.read(productRepositoryProvider).getByExactCode(query);
    if (product == null) {
      final results = ref.read(saleSearchResultsProvider).value;
      if (results != null && results.length == 1) {
        await _tapProduct(results.first);
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.codeNotFound(query))),
      );
      return;
    }
    ref.read(cartProvider.notifier).add(await _lineFor(product));
    _clearSearch();
    _searchFocus.requestFocus();
  }

  Future<void> _addQuickItem() async {
    final line = await showQuickItemSheet(context);
    if (line == null) return;
    ref.read(cartProvider.notifier).add(line);
  }

  Future<void> _editDiscount() async {
    final result = await showDiscountSheet(context);
    if (result == null) return;
    ref.read(cartProvider.notifier).setDiscount(result.discount);
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCartTitle),
        content: Text(l10n.clearCartMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.clearCart),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(cartProvider.notifier).clear();
  }

  /// One optional extra currency shown under the total, persisted in the same
  /// setting the invoice settings screen will use (a JSON list, max 2).
  Future<void> _pickSecondaryTotal(List<Currency> currencies) async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(extraTotalCurrenciesProvider).value ?? const [];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.secondaryTotalTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(l10n.secondaryTotalNone),
          ),
          for (final currency in currencies)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(currency.code),
              child: Row(
                children: [
                  Expanded(child: Text('${currency.code} · '
                      '${currency.nameFor(_locale)}')),
                  if (current.contains(currency.code)) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(settingsRepositoryProvider).setString(
          SettingsKeys.extraTotalCurrencies,
          jsonEncode(picked.isEmpty ? <String>[] : [picked]),
        );
    ref.invalidate(extraTotalCurrenciesProvider);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || _saving) return;
    final ctx = await ref.read(currencyContextProvider.future);

    final totals = computeCartTotals(cart, ctx);
    if (totals.currenciesNeedingRate.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.rateNeeded(
          totals.currenciesNeedingRate.map((c) => c.code).join(', '),
        )),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await ref.read(invoiceRepositoryProvider).save(
            Invoice.fromCart(
              cart: cart,
              ctx: ctx,
              createdAt: DateTime.now().toUtc(),
            ),
          );
      ref.read(cartProvider.notifier).reset();
      if (!mounted) return;
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => SaleInvoiceScreen(invoice: saved),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final cart = ref.watch(cartProvider);
    final totals = ref.watch(cartTotalsProvider);
    final query = ref.watch(saleSearchProvider).trim();
    final sellable = ref.watch(sellableCurrenciesProvider);
    final allCurrencies = ref.watch(currenciesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSale),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: _addQuickItem,
                child: Text(l10n.quickItemTitle),
              ),
              PopupMenuItem<void>(
                onTap: () => _pickSecondaryTotal(sellable),
                child: Text(l10n.secondaryTotalTitle),
              ),
              if (cart.isNotEmpty)
                PopupMenuItem<void>(
                  onTap: _confirmClear,
                  child: Text(l10n.clearCart),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _FavoritesBar(onTap: _tapProduct),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.done,
              onChanged: ref.read(saleSearchProvider.notifier).set,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: l10n.saleSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _CartList(
                    totals: totals,
                    onEdit: _editLine,
                  )
                : _SearchResults(onTap: _tapProduct),
          ),
          _TotalsPanel(
            totals: totals,
            cart: cart,
            locale: locale,
            sellable: sellable,
            saving: _saving,
            onCurrencyChanged: (code) =>
                ref.read(cartProvider.notifier).setInvoiceCurrency(code),
            onUpdateRate: () async {
              final base = _ctx?.baseCode;
              if (base == null) return;
              await openRatesQuickAction(
                context,
                ref,
                baseCode: base,
                currencies: allCurrencies,
              );
            },
            onDiscount: _editDiscount,
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

/// Large one-tap buttons for favorite products.
class _FavoritesBar extends ConsumerWidget {
  const _FavoritesBar({required this.onTap});

  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final favorites = ref.watch(favoriteProductsProvider).value;
    final currencies = ref.watch(currencyContextProvider).value;

    if (favorites == null) {
      return const SizedBox(height: 96);
    }
    if (favorites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(Icons.star_border, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.saleFavoritesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final product = favorites[index];
          final currency = currencies?.lookup(product.currencyCode);
          return SizedBox(
            width: 132,
            child: FilledButton.tonal(
              onPressed: () => onTap(product),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (currency != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatMinor(
                        product.priceMinor,
                        decimals: currency.decimalPlaces,
                        locale: locale,
                        symbol: currency.symbol.isEmpty
                            ? currency.code
                            : currency.symbol,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.onTap});

  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final results = ref.watch(saleSearchResultsProvider);
    final ctx = ref.watch(currencyContextProvider).value;

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (products) {
        if (products.isEmpty) {
          return Center(child: Text(l10n.noMatchingProducts));
        }
        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final currency = ctx?.lookup(product.currencyCode);
            return ListTile(
              leading: Icon(product.kind == ProductKind.goods
                  ? Icons.shopping_basket
                  : Icons.sim_card),
              title: Text(product.name),
              subtitle: currency == null
                  ? null
                  : Text([
                      formatMinor(
                        product.priceMinor,
                        decimals: currency.decimalPlaces,
                        locale: locale,
                        symbol: currency.symbol.isEmpty
                            ? currency.code
                            : currency.symbol,
                      ),
                      if (product.code != null) '#${product.code}',
                    ].join(' · ')),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => onTap(product),
            );
          },
        );
      },
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.totals, required this.onEdit});

  final CartTotals? totals;
  final ValueChanged<CartLine> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final totals = this.totals;
    if (totals == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (totals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.cartEmpty, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.cartEmptyHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }

    final currency = totals.currency;
    final symbol = currency.symbol.isEmpty ? currency.code : currency.symbol;
    final ctx = ref.watch(currencyContextProvider).value;

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: totals.lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = totals.lines[index];
        final line = entry.line;
        final showOriginal = line.priceCurrencyCode != currency.code;
        return ListTile(
          onTap: () => onEdit(line),
          leading: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatQuantity(line.qtyThousandths, locale: locale),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (line.unitName != null)
                  Text(line.unitName!, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          title: Text(line.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${formatMinor(
                entry.unitPriceMinor,
                decimals: currency.decimalPlaces,
                locale: locale,
                symbol: symbol,
              )} × ${formatQuantity(line.qtyThousandths, locale: locale)}'),
              if (showOriginal)
                Text(
                  formatMinor(
                    line.unitPriceMinor,
                    decimals:
                        ctx?.lookup(line.priceCurrencyCode)?.decimalPlaces ?? 0,
                    locale: locale,
                    symbol: line.priceCurrencyCode,
                  ),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMinor(
                  entry.lineTotalMinor,
                  decimals: currency.decimalPlaces,
                  locale: locale,
                  symbol: symbol,
                ),
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                tooltip: l10n.removeLine,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(cartProvider.notifier).remove(line.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Invoice currency, rate shortcut, discount, the big total and Save.
class _TotalsPanel extends ConsumerWidget {
  const _TotalsPanel({
    required this.totals,
    required this.cart,
    required this.locale,
    required this.sellable,
    required this.saving,
    required this.onCurrencyChanged,
    required this.onUpdateRate,
    required this.onDiscount,
    required this.onSave,
  });

  final CartTotals? totals;
  final Cart cart;
  final String locale;
  final List<Currency> sellable;
  final bool saving;
  final ValueChanged<String?> onCurrencyChanged;
  final VoidCallback onUpdateRate;
  final VoidCallback onDiscount;
  final VoidCallback onSave;

  /// The currency whose rate the quick button talks about: the invoice
  /// currency when it is not the base one, otherwise the first non-base
  /// currency used in the cart, otherwise the first non-base currency.
  Currency? _rateFocus(CurrencyContext ctx, CartTotals totals) {
    if (totals.currency.code != ctx.baseCode) return totals.currency;
    for (final entry in totals.lines) {
      if (entry.line.priceCurrencyCode != ctx.baseCode) {
        return ctx.lookup(entry.line.priceCurrencyCode);
      }
    }
    for (final currency in sellable) {
      if (currency.code != ctx.baseCode) return currency;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ctx = ref.watch(currencyContextProvider).value;
    final totals = this.totals;
    if (totals == null || ctx == null) return const SizedBox.shrink();

    final currency = totals.currency;
    final symbol = currency.symbol.isEmpty ? currency.code : currency.symbol;
    String money(int minor) => formatMinor(
          minor,
          decimals: currency.decimalPlaces,
          locale: locale,
          symbol: symbol,
        );

    final focus = _rateFocus(ctx, totals);
    final needRate = totals.currenciesNeedingRate;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (sellable.length > 1)
                    DropdownButton<String>(
                      value: sellable.any((c) => c.code == currency.code)
                          ? currency.code
                          : null,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final option in sellable)
                          DropdownMenuItem(
                            value: option.code,
                            child: Text(option.code == ctx.baseCode
                                ? '${option.code} · ${l10n.baseBadge}'
                                : option.code),
                          ),
                      ],
                      onChanged: onCurrencyChanged,
                    )
                  else
                    Text('${l10n.invoiceCurrency}: ${currency.code}',
                        style: theme.textTheme.bodySmall),
                  const Spacer(),
                  if (focus != null)
                    TextButton.icon(
                      onPressed: onUpdateRate,
                      icon: const Icon(Icons.currency_exchange, size: 18),
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.rateDisplay(
                              focus.code,
                              formatRateValue(focus.rate, locale: locale),
                              ctx.baseCode,
                            ),
                            style: theme.textTheme.labelMedium,
                          ),
                          Text(
                            focus.rateUpdatedAt == null
                                ? l10n.rateNeverUpdated
                                : DateFormat.yMd(locale).add_jm().format(
                                    focus.rateUpdatedAt!.toLocal()),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: focus.rateUpdatedAt == null
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (totals.isNotEmpty) ...[
                const Divider(height: 12),
                Row(
                  children: [
                    Text(
                      l10n.itemsCount(totals.lines.length),
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (totals.discountMinor != 0)
                      Text(
                        '${l10n.subtotalLabel}: ${money(totals.subtotalMinor)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
              if (discountEnabled && totals.isNotEmpty)
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onDiscount,
                      icon: const Icon(Icons.percent, size: 18),
                      label: Text(totals.discountMinor == 0
                          ? l10n.discountTitle
                          : '${l10n.discountLabel} − '
                              '${money(totals.discountMinor)}'),
                    ),
                    if (totals.discountMinor != 0)
                      IconButton(
                        tooltip: l10n.discountNone,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            ref.read(cartProvider.notifier).setDiscount(null),
                      ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l10n.totalLabel, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      money(totals.totalMinor),
                      key: const ValueKey('cart-total'),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              for (final extra in totals.extraTotals)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '≈ ${formatMinor(
                      extra.totalMinor,
                      decimals: extra.currency.decimalPlaces,
                      locale: locale,
                      symbol: extra.currency.symbol.isEmpty
                          ? extra.currency.code
                          : extra.currency.symbol,
                    )}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              if (needRate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.rateNeeded(needRate.map((c) => c.code).join(', ')),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed:
                    cart.isEmpty || saving || needRate.isNotEmpty ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(l10n.save,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
